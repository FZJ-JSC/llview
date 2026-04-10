# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_jobreport;

my $VERSION='$Revision: 1.00 $';

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_jobreport_datasets_constants;

# SQL help:
# restore wrong file in database:
#    delete from datasetstat_csv where ukey in (select ukey from datasetstat_csv group by ukey having count(*)>1) and status=0;
# split stat-table:
#    insert into datasetstat_node_dat (dataset,name,ukey,lastts_saved,status,checksum) SELECT dataset,name,ukey,lastts_saved,status,checksum from datasetstat where(name='fabric_node_dat') ;  
sub solve_datasets {
  my $self = shift;
  my ($DB, $force) = @_;
  my $basename = $self->{BASENAME};

  my $config_ref = $DB->get_config();

  my $varsetref;
  if (exists($config_ref->{$basename}->{paths})) {
    foreach my $p (keys(%{$config_ref->{$basename}->{paths}})) {
      $varsetref->{$p} = $config_ref->{$basename}->{paths}->{$p};
    }
  }

  my $fl = $self->get_filelist($varsetref->{outputdir});

  foreach my $datasetref (@{$config_ref->{$basename}->{datafiles}}) {
    my $dataset = $datasetref->{dataset};
    
    next if($dataset->{name} !~ /(chippower|fabric|loadmem|GPU|fsusage)_/);
    next if (!exists($dataset->{stat_table}));

    my $filepath = $dataset->{filepath};
    my $pattern = ".*";
    my $filepath_fn = $filepath;
    $filepath_fn =~ s/.*\///gs;
    if ($filepath_fn =~ /\$\{J\}/) {
      $pattern = $filepath_fn;
      $pattern =~ s/\$\{J\}/\(\.\*\)/s;
      $pattern .= "(.gz)?";
    }
    
    printf("%s work now on dataset %s (%s)\n", $self->{INSTNAME}, $dataset->{name}, $filepath);
    
    $self->get_datasetstat_from_DB($dataset->{stat_database}, $dataset->{stat_table});
    my $ds = $self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};
    
    my $cnt_not_on_FS = 0;
    my $cnt_fn_inconsistence = 0;
    my $cnt_bad_status = 0;
    my $needs_save = 0;
    
    # Check existent states in DB vs File System
    if (1) {
      while ( my ($file, $ref) = each(%{$ds}) ) {
        
        # use $file (the hash key) as the source of truth for the filename, because
        # get_datasetstat_from_DB does not include 'dataset' in the hash_value
        my $actual_dataset_name = defined($ref->{dataset}) ? $ref->{dataset} : $file;

        if ($file ne $actual_dataset_name) {
          $cnt_fn_inconsistence++;
          printf("%s[%05d] fn inconsistence: [st=%d] %s vs %s\n", $self->{INSTNAME},
                  $cnt_fn_inconsistence, $ref->{status}, $file, $actual_dataset_name);
        }
        
        # Fix leftover files from the .gz.gz bug using $file
        if ($file =~ /\.gz$/ && $ref->{status} == FSTATUS_EXISTS) {
          $cnt_bad_status++;
          printf("%s[%05d] bad status fixed: %s was %d, now %d (FSTATUS_COMPRESSED)\n", 
                 $self->{INSTNAME}, $cnt_bad_status, $file, $ref->{status}, FSTATUS_COMPRESSED);
          
          $ref->{status} = FSTATUS_COMPRESSED;
          $ref->{dataset} = $file; # Populate this so save_datasetstat_in_DB doesn't crash
          $needs_save = 1;
        }

        next if ($ref->{status} == FSTATUS_NOT_EXISTS);
        
        my $realfile = sprintf("%s/%s", $self->{OUTDIR}, $file);
        if (!exists($fl->{$realfile})) {
          $cnt_not_on_FS++;
          # printf("%s[%05d] not_on_FS: [st=%d] %s\n", $self->{INSTNAME}, $cnt_not_on_FS, $ref->{status}, $realfile);
        }
      }
    }
    
    my $cnt_not_in_DB = 0;
    if (1) {
      while ( my ($fn, $val) = each(%{$fl}) ) {
        if ($fn =~ /$pattern/) {
          my $ukey = $1;
          my $shortfile = $fn; 
          $shortfile =~ s/$self->{OUTDIR}\///s;
          
          if (!exists($ds->{$shortfile})) {
            $cnt_not_in_DB++;
            my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($fn);
            
            $ds->{$shortfile}->{dataset} = $shortfile;
            $ds->{$shortfile}->{name} = $dataset->{name};
            
            if ($shortfile =~ /\.gz$/) {
              $ds->{$shortfile}->{status} = FSTATUS_COMPRESSED;
            } else {
              $ds->{$shortfile}->{status} = FSTATUS_EXISTS;
            }
            
            $ds->{$shortfile}->{lastts_saved} = $mtime;
            $ds->{$shortfile}->{checksum} = 0;
            $ds->{$shortfile}->{ukey} = $ukey;
            $needs_save = 1;

            printf("%s[%05d] not_in_DB: [%s,%s,%s,%s] %s %s\n", $self->{INSTNAME}, $cnt_not_in_DB,
                    $ds->{$shortfile}->{status},
                    $ds->{$shortfile}->{lastts_saved},
                    (defined($ds->{$shortfile}->{checksum}) ? $ds->{$shortfile}->{checksum} : "?"),
                    (defined($ds->{$shortfile}->{ukey}) ? $ds->{$shortfile}->{ukey} : "?"),
                    &sec_to_date($ds->{$shortfile}->{lastts_saved}),
                    $shortfile);
          }
        }
      }
    }
    
    if ($force) {
      if ($needs_save) {
        # Make sure every memory record has 'dataset' defined before saving,
        # otherwise save_datasetstat_in_DB will skip the row entirely.
        foreach my $k (keys %$ds) {
          $ds->{$k}->{dataset} = $k if (!defined($ds->{$k}->{dataset}));
        }

        $self->save_datasetstat_in_DB($dataset->{stat_database}, $dataset->{stat_table});
        printf("%s saved datasetstat for %s (fixed %d bad statuses, inserted %d new)\n", 
               $self->{INSTNAME}, $dataset->{name}, $cnt_bad_status, $cnt_not_in_DB);
      }
    }
  }

  return();
}

sub get_filelist {
  my $self = shift;
  my ($filepath)=@_;

  my ($fl,$cnt);
  my $starttime=time();
  
  printf("%s scan filepath %s ...\n",$self->{INSTNAME},$filepath);
  open(FL,"find $filepath -type f |");
  $cnt=0;
  while(my $fn=<FL>) {
    chomp($fn);
    $fl->{$fn}=1;
    $cnt++;
  }
  close(FL);
  printf("%s scan filepath %s ... ready, found %d files in %7.4fs\n",$self->{INSTNAME},$filepath,$cnt,time()-$starttime);
  return($fl);
}

1;
