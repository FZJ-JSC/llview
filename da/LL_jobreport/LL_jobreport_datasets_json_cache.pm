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
my($debug)=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_jobreport_datasets_constants;

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub process_data_query_and_save_json_cache {
  my $self = shift;
  my($dataset,$varsetref)=@_;

  #  required vars
  my $file=$dataset->{filepath};

  my $json_single_entry=0;
  if(exists($dataset->{json_type})) {
    $json_single_entry=1 if($dataset->{json_type} eq "single_entry");
  }
  
  # table cache
  my $table_cache="";
  if(exists($dataset->{table_cache})) {
    $table_cache=$dataset->{table_cache};
  } else {
    print STDERR "LLmonDB:    ERROR, table_cache not specified\n";
    return();
  }

  # pre-process column_convert
  my $col_convert_by_col;
  if(exists($dataset->{column_convert})) {
    $col_convert_by_col=$self->{LL_CONVERT}->init_column_convert_mapping($dataset->{column_convert});
  }
  
  # timevar
  my $selecttimevar="";
  if(exists($dataset->{selecttimevar})) {
    $selecttimevar=$dataset->{selecttimevar};
  }
  my $selecttimerange="";
  if(exists($dataset->{selecttimerange})) {
    $selecttimerange=$self->{DB}->replace_tsvars($dataset->{selecttimerange},$self->{CURRENTTS});
  }

  # checksum
  my $checksumvar=undef;
  my $checksum=0.0;
  my $checksumref;
  if(exists($dataset->{checksumvar})) {
    $checksumvar=$dataset->{checksumvar};
  }

  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file=~s/\$\{$key\}/$value/gs;	$file=~s/\$$key/$value/gs;
    $value=~s/^0+//gs; # remove leading zeros
    $selecttimerange=~s/\$\{$key\}/$value/gs;	$selecttimerange=~s/\$$key/$value/gs;
  }

  # eval expressions
  my($selecttimerange_begin,$selecttimerange_end)=(undef,undef);
  if($selecttimerange) {
    ($selecttimerange_begin,$selecttimerange_end)=split(/\s*,\s*/,$selecttimerange);
    $selecttimerange_begin=eval($selecttimerange_begin);
    $selecttimerange_end=eval($selecttimerange_end);
  }
  # print "process_data_query_and_save_json_cache: file=$file timerange=$selecttimerange ($selecttimerange_begin,$selecttimerange_end)\n";

  if(!exists($self->{TABLECACHE}->{$table_cache})) {
    $self->process_data_query_cache_table_json($table_cache,$dataset,$varsetref);
  }

  my $timevar=undef;
  if(exists($dataset->{selecttimevar})) {
    $timevar=$dataset->{selecttimevar};
  }

  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};
  
  my $max_entries=5000;
  if(exists($dataset->{max_entries})) {
    $max_entries=$dataset->{max_entries};
  } 

  # generate multiple files from one query?
  if(exists($dataset->{column_filemap})) {
    # printf("%s process_data_query_and_save_json_cache:  create multiple files=%s\n",$self->{INSTNAME},$file);

    # search for entries to be stored
    my $skeylistref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list};
    my $skey_to_filenameref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{skey_to_filename};
    my $dataref;

    if(1) {
      if(exists($dataset->{create_empty_files}) && ($dataset->{create_empty_files} eq "yes") ) {
        foreach my $k (keys(%{$skey_to_filenameref})) {
          my $file=$skey_to_filenameref->{$k};
          $dataref->{$file}=[];
          $checksumref->{$file}=0;
        }
      }
    }
    
    my $starttime=time();
    foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{dataset}}) {
      # check timevar
      if(defined($timevar)) {
        next if($ref->{$timevar}<$selecttimerange_begin);
        next if($ref->{$timevar}>=$selecttimerange_end);
      }

      # map entry to file
      my @skeys;
      foreach my $v (@{$skeylistref}) {
        push(@skeys,$ref->{$v});
      }
      if(!defined($skeys[0])) {
        print STDERR "process_data_query_and_save_json_cache ($dataset->{name} $table_cache): ERROR skey undefined\n";
        next;
      }
      my $skey=join(":",@skeys);
      
      if(exists($skey_to_filenameref->{$skey})) {
        my $file=$skey_to_filenameref->{$skey};
      
        push(@{$dataref->{$file}},$ref);
        
        # checksum
        $checksumref->{$file}=0 if(!exists($checksumref->{$file}));
        $checksumref->{$file}+=$ref->{$checksumvar} if(defined($checksumvar));
        $self->{COUNT_OP_WRITE_LINE}++;
      } else {
        # print STDERR "process_data_query_and_save_json_cache ($dataset->{name}): WARNING $skey not in known files, skipping entry\n";
      }
    }
    # printf("%s process_data_query_cache_table_json: check entries in %7.4fs (%d files)\n",
    #         $self->{INSTNAME},time()-$starttime, scalar keys(%{$dataref})
    #       );

    # write files
    while ( my ($file, $dataref_per_file) = each(%{$dataref}) ) {
      $self->register_data_for_file_json_cache( $table_cache,"$self->{OUTDIR}/$file",$ds,
                                                $dataref_per_file,$col_convert_by_col,
                                                $checksumvar,$checksumref->{$file},$max_entries,$dataset);
    }
  } else { # only a single file
    # search for entries to be stored
    my $starttime=time();
    my $dataref;
    foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{dataset}}) {
      if(defined($timevar)) {
        # printf("%s process_data_query_cache_table_json: single (%s(%d):%d .. %d )\n",$self->{INSTNAME},
        #         $timevar, $ref->{$timevar},, $selecttimerange_begin, $selecttimerange_end);
        next if($ref->{$timevar}<$selecttimerange_begin);
        next if($ref->{$timevar}>=$selecttimerange_end);
      }
      # checksum
      $checksum+=$ref->{$checksumvar} if(defined($checksumvar));

      push(@{$dataref},$ref);
      $self->{COUNT_OP_WRITE_LINE}++;
    }
    # printf("%s process_data_query_cache_table_json: single file, check entries in %7.4fs (%d entries) (%s:%d .. %d )\n",
    #         $self->{INSTNAME},time()-$starttime, scalar(@{$dataref}), $timevar, $selecttimerange_begin, $selecttimerange_end);
    
    $self->register_data_for_file_json_cache($table_cache,$file,$ds,$dataref,$col_convert_by_col,
                                              $checksumvar,$checksum,$max_entries,$dataset);
  }
}

sub process_data_query_cache_table_json {
  my $self = shift;
  my($table_cache,$dataset,$varsetref)=@_;

  # create data structure
  $self->{TABLECACHE}->{$table_cache}->{dataset}=$dataset;
  my $tc=$self->{TABLECACHE}->{$table_cache};

  # replace variables in where attribute
  my $where="";
  if(exists($dataset->{sql_where})) {
    $where=$self->{DB}->replace_tsvars($dataset->{sql_where},$self->{CURRENTTS});
    while ( my ($key, $value) = each(%{$varsetref}) ) {
      $where=~s/\$\{$key\}/$value/gs;	$where=~s/\$$key/$value/gs;
    }
  }
  
  # check data tables and configure join if multiple tables are specified 
  my $from;
  my $joincol="";
  my @datatables=split(/\s*,\s*/,$dataset->{data_table});
  if($#datatables>0) {
    my @fromlist; my $c=0;
    if(!exists($dataset->{data_table_join_col})) {
      print STDERR "LLmonDB:    ERROR, attribute data_table_join_col missing for dataset $dataset->{name}\n";
      return();
    } else {
      $joincol=$dataset->{data_table_join_col};
    }
    foreach my $d (@datatables) {
      $c++;
      push(@fromlist,sprintf("%s D%d",$d,$c));
      if($c>1) {
        $where.=" AND " if($where);
        $where.=sprintf("D1.%s=D%d.%s",$joincol,$c,$joincol);
      }
    }
    $from = join(",",@fromlist);
  } else {
    $from = sprintf("%s D%d",$dataset->{data_table},1);
  }

  if(!exists($self->{TABLES}->{$dataset->{data_database}})) {
    printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database});
    $tc->{dataset}=undef;
    return;
  }
  foreach my $t (@datatables) {
    if(!exists($self->{TABLES}->{$dataset->{data_database}}->{$t})) {
      printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database},$t);
      $tc->{dataset}=undef;
      return;
    }
  }

  # check columns and make column names unique if they are used for join 
  my (@cols,$format,$tscol,$cnt);
  
  my $col_to_group=undef;
  if(exists($dataset->{column_groups})) {
    foreach my $g (keys(%{$dataset->{column_groups}})) {
      foreach my $col (split(/\s*,\s*/,$dataset->{column_groups}->{$g})) {
        my ($c,$as);
        if($col=~/^(.*)->(.*)$/) {
          $c=$1;$as=" as $2";
          $col_to_group->{$2}=$g;
        } else {
          $c=$col;$as="";
          $col_to_group->{$c}=$g;
        }
        push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
      }
    }
  } else {
    my $cn=0;
    foreach my $col (split(/\s*,\s*/,$dataset->{columns})) {
      my ($c,$as);
      if($col=~/^(.*)->(.*)$/) {
        $c=$1;$as=" as $2";
      } else {
        $c=$col;$as="";
      }
      $tc->{coltonum}->{$c}=$cn;
      push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
      $cn++;
    }
  }
  # print "TMPDEB:",Dumper($col_to_group);
  my (@order_cols);
  if(exists($dataset->{column_filemap})) {
    foreach my $c (@{$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list}}) {	
      push(@order_cols,($c eq $joincol)?"D1.$c":"$c");
    }
  }

  # Getting order for sorting
  my $orderby;
  my $ordertype;
  if(exists($dataset->{order})) {
    foreach my $c (split(/\s*,\s*/,$dataset->{order})) {
      $c =~ s/^\s+|\s+$//g;
      ($orderby, $ordertype) = split(' ', $c);
      $ordertype=$ordertype?$ordertype:"";
      push(@order_cols,($orderby eq $joincol)?"D1.$orderby $ordertype":"$orderby $ordertype");
    }
  }

  my $order="";
  if (@order_cols) {
    $order=sprintf("ORDER BY %s",join(",",@order_cols));
  }

  # build and call the query 
  my $sql=sprintf("SELECT %s FROM %s %s %s;",
                    join(",",@cols),
                    $from,
                    ($where)?"WHERE $where":"",
                    $order
                  );
  # printf("%s process_data_query_cache_table_json: sql=%s\n",$self->{INSTNAME},$sql);

  
  my $starttime=time();
  $tc->{dataset}=$self->{DB}->query($dataset->{data_database},$dataset->{data_table},
                                    {
                                      type => "get_arrayref_of_hashref",
                                      sql => $sql
                                    });
  printf("%s process_data_query_cache_table_json: pre-cache table in %7.4fs (%d entries)\n",
          $self->{INSTNAME},time()-$starttime,  scalar @{$tc->{dataset}}
        );

  return();
}

sub process_data_query_drop_table_json {
  my $self = shift;
  my($table_cache,$dataset,$varsetref)=@_;

  # delete data structure
  delete($self->{TABLECACHE}->{$table_cache});
}

# The JSON file operation is queued into the caching engine for parallel execution.
#
# Arguments:
#   $self               - (Object) The LML_jobreport instance
#   $table_cache        - (String) Name of the memory cache pool
#   $file               - (String) Target output file path
#   $ds                 - (HashRef) Database status reference
#   $dataref            - (ArrayRef) Rows assigned to this file
#   $col_convert_by_col - (HashRef) Conversion functions to apply to columns
#   $checksumvar        - (String|Undef) The column used for checksum calculation
#   $checksum           - (Float) The calculated checksum integer for this file
#   $max_entries        - (Integer) Maximum number of rows allowed per file
#   $dataset            - (HashRef) Original dataset configuration definitions
#
# Returns:
#   (Void)
sub register_data_for_file_json_cache {
  my $self = shift;
  my ($table_cache, $file, $ds, $dataref, $col_convert_by_col, $checksumvar, $checksum, $max_entries, $dataset) = @_;

  my $shortfile = $file;
  $shortfile =~ s/$self->{OUTDIR}\///s;

  my $process_file = 1;  
  if (defined($checksumvar)) {
    if (!defined($checksum)) {
      printf(STDERR "%s [ERROR] No checksum evaluated for %s. Database may be corrupt.\n", $self->{INSTNAME}, $shortfile);
      $checksum = 0;
    }
    if (!exists($ds->{$shortfile}->{checksum})) {
      printf(STDERR "%s [WARNING] Missing checksum tracking for %s. Initializing to zero.\n", $self->{INSTNAME}, $shortfile);
      $ds->{$shortfile}->{checksum} = 0;
    }
    if ($checksum != $ds->{$shortfile}->{checksum}) {
      $ds->{$shortfile}->{checksum} = $checksum;
    } else {
      $process_file = 0;	    
    }
  } else {
    $ds->{$shortfile}->{checksum} = 0;
  }

  # Files that do not physically exist must bypass the checksum optimization to ensure initial creation.
  if (!exists($ds->{$shortfile}->{status}) || $ds->{$shortfile}->{status} == FSTATUS_NOT_EXISTS) {
    $process_file = 1;
  }

  if ($process_file) {
    $ds->{$shortfile}->{dataset} = $shortfile;
    $ds->{$shortfile}->{status} = FSTATUS_EXISTS;
    $ds->{$shortfile}->{name} = $dataset->{name} if (!exists($ds->{$shortfile}->{name}));
    $ds->{$shortfile}->{lastts_saved} = $self->{CURRENTTS}; 
    $ds->{$shortfile}->{mts} = $self->{CURRENTTS}; 
    $self->{COUNT_OP_NEW_FILE}++;

    $self->{TABLECACHE}->{$table_cache}->{con_convert}->{$file} = $col_convert_by_col;
    $self->{TABLECACHE}->{$table_cache}->{fileop}->{$file} = $dataref;
    $self->{TABLECACHE}->{$table_cache}->{max_entries}->{$file} = $max_entries;
  }
}

sub write_data_to_file_json_cache {
  my $self = shift;
  my($table_cache,$part,$parlevel)=@_;

  my $starttime=time();
  my @filelist=(sort(keys(%{$self->{TABLECACHE}->{$table_cache}->{fileop}})));
  my $numfiles=scalar @filelist;
  my $fcount=0;
  my $lcount=0;
  for(my $fnum=0;$fnum<$numfiles; $fnum++) {
    # do only the files for this part 
    next if(($fnum%$parlevel) != $part);
    $fcount++;
    
    my $file=$filelist[$fnum];
    my $fstarttime=time();
    
    # convert values
    my $ds_converted=[];
    my $col_convert_by_col=$self->{TABLECACHE}->{$table_cache}->{con_convert}->{$file};
    # The dataset row reference is safely initialized to an empty array if undefined.
    my $dataset=$self->{TABLECACHE}->{$table_cache}->{fileop}->{$file} || [];
    my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;
    my $max_entries=$self->{TABLECACHE}->{$table_cache}->{max_entries}->{$file};
    printf("%s write_data_to_file_json_cache: max_entries=%d ($table_cache,$file)\n", $self->{INSTNAME},$max_entries) if($max_entries>5000);
    
    my $numentries=0;
    foreach my $ref (@{$dataset}) {
      # copy dataset
      my $nref;
      while ( my ($col, $val) = each(%{$ref}) ) {
        $nref->{$col}=$val;
      }
    
      # convert data
      while ( my ($col, $func) = each(%{$col_convert_by_col}) ) {
        if(!exists($ref->{$col})) {
          print STDERR "TMPDEB: column $col does not exist\n";
          next;
        }
        if(!defined($ref->{$col})) {
          # print STDERR "TMPDEB: value for column $col not defined\n";
          next;
        }
        if($ref->{$col}=~/^\s*$/) {
          print STDERR "TMPDEB: no val for column $col\n" if($debug);
        } else {
          $nref->{$col}=&{$func}($nref->{$col},$self);
        }
      }
      $lcount++;
      push(@{$ds_converted},$nref);
      $numentries++;
      if($numentries>=$max_entries) {
        printf("%s write_data_to_file_json_cache: WARNING: too many entries in file %s (%d), skipping > $max_entries\n",
                $self->{INSTNAME}, $file, scalar @{$dataset});
        last;
      }
    }
    my $conv_time=time()-$fstarttime;
    # write data to file

    my $estarttime=time();
    my $jsondata=$self->encode_JSON($ds_converted);
    my $enc_time=time()-$estarttime;

    my $fh = IO::File->new();
    my $openparm;
    if($file=~/\.gz$/) {
      $openparm="| gzip -c > $file";
    } else {
      $openparm="> $file";
    }
    &check_folder("$file");
    if (!($fh->open($openparm))) {
      printf(STDERR "%s write_data_to_file_json_cache:    WARNING: cannot open %s/%s, skipping...\n",$self->{INSTNAME},$self->{OUTDIR},$file);
      return();
    }
    
    $fh->print($jsondata);
    $fh->close();

    # printf("%s write_data_to_file_json_cache: write data in %7.4fs (convert in %7.4fs) (encode in %7.4fs) (%4d entries) $file\n",
    #         $self->{INSTNAME},time()-$fstarttime, $conv_time, $enc_time, scalar @{$ds_converted});
    # printf("%s process_data_query_cache_table_json:  created file=%s\n",$self->{INSTNAME},$file);
  }
  printf("%s write_data_to_file_json_cache: %10s  write files %3d of %4d in %7.4fs (%5d lines)\n",
          $self->{INSTNAME},  $table_cache, $fcount, $numfiles, time()-$starttime, $lcount 
  );
  
  return();
}

1;
