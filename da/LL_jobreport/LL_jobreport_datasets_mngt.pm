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
use File::Spec;
use Parallel::ForkManager;
use LL_jobreport_datasets_constants;

use LML_da_util qw ( sec_to_date sec_to_date_dir_wo_hhmmss );

sub mngt_datasets {
  my $self = shift;
  my ($DB,$journalonly,$journaldir)=@_;
  my $config_ref=$DB->get_config();
  my $basename=$self->{BASENAME};

  $self->{JOURNALONLY}=$journalonly;
  $self->{JOURNALDIR}=$journaldir;
  
  # print Dumper($config_ref->{$basename});
  
  # init instantiated variables
  my $varsetref;
  if(exists($config_ref->{$basename}->{paths})) {
    foreach my $p (keys(%{$config_ref->{$basename}->{paths}})) {
      $varsetref->{$p}=$config_ref->{$basename}->{paths}->{$p};
    }
  }

  # find action types
  my $actions;
  foreach my $datamngtref (@{$config_ref->{$basename}->{datamngt}}) {
    my $subconfig_ref=$datamngtref->{action};
    if(exists($subconfig_ref->{name})) {
      $actions->{ $subconfig_ref->{name} }->{'definition'}=$subconfig_ref;
    }
  }
  
  # find datasets which require an mngt action
  foreach my $datasetref (@{$config_ref->{$basename}->{datafiles}}) {
    my $subconfig_ref=$datasetref->{dataset};
    if(exists($subconfig_ref->{mngt_actions})) {
      foreach my $action (split(/\s*,\s*/,$subconfig_ref->{mngt_actions})) {
        if(exists($actions->{$action})) { 
          push(@{$actions->{$action}->{datasets}},$subconfig_ref);
        } else {
          print STDERR "LLmonDB:    WARNING: no definition found for action $action in dataset definition $subconfig_ref->{name}, skipping...\n";
        }
      }
    }
  }

  # print Dumper($action_dataset_list);
  # print Dumper($actions);

  # run data mngt actions serial by type
  foreach my $datamngtref (@{$config_ref->{$basename}->{datamngt}}) {
    my $action=$datamngtref->{action}->{name};
    next if(!exists($actions->{$action}));
    
    my $action_ref=$actions->{$action};
    my $action_def=$action_ref->{definition};
    
    if(!exists($action_def->{type})) {
      print STDERR "LLmonDB:    WARNING: no type defined for action $action, skipping...\n";
      next;
    }
    $self->mngt_datasets_check($DB, $action_ref, $varsetref) if($action_def->{type} eq "archive");
    $self->mngt_datasets_check($DB, $action_ref, $varsetref) if($action_def->{type} eq "remove");
    $self->mngt_datasets_check_gz_gz($DB, $action_ref, $varsetref) if($action_def->{type} eq "compress");
    
    if(exists($action_ref->{datasets})) {
      $self->mngt_datasets_execute($DB, $action_ref, $varsetref, FACTION_COMPRESS) if($action_def->{type} eq "compress");
      $self->mngt_datasets_execute($DB, $action_ref, $varsetref, FACTION_ARCHIVE) if($action_def->{type} eq "archive");
      $self->mngt_datasets_execute($DB, $action_ref, $varsetref, FACTION_REMOVE) if($action_def->{type} eq "remove");
    }
  }
  
  return();
}

sub mngt_datasets_execute {
  my $self = shift;
  my ($DB,$action_ref,$varsetref,$action_type)=@_;
  my $action_def=$action_ref->{definition};
  my $parallel_level=1; # serial
  my $compress_tool="gzip";
  my $limit_sec=0;
  my $limit_ts=$self->{CURRENTTS};
  my $limit_pattern_ts=undef;
  my $files_to_process;
  my $tmptardir="/tmp/jobreport/dir";
  my $tarfileprefix="job_";
  
  if(exists($action_def->{options})) {
    if(exists($action_def->{options}->{limit})) {
      $limit_sec=$DB->timeexpr_to_sec($action_def->{options}->{limit});
      $limit_ts-=$limit_sec if($limit_sec>0);
    }
    if(exists($action_def->{options}->{limit_pattern})) {
      foreach my $pair (split(/\),?\(/,$action_def->{options}->{limit_pattern})) {
        $pair=~s/^\(//s;$pair=~s/\)$//s;
        if($pair=~/^\'(.*)\'\,(.*)$/) {
          my($pat,$l)=($1,$2);
          my $l_sec=$DB->timeexpr_to_sec($l);
          print "TMPDEB: found pattern: $pat,$l, $l_sec\n";
          $limit_pattern_ts->{$pat}=$self->{CURRENTTS}-$l_sec;
        }
      }
    }
    if(exists($action_def->{options}->{parallel_level})) {
      $parallel_level=$action_def->{options}->{parallel_level};
    }
    if(exists($action_def->{options}->{compress_tool})) {
      $compress_tool=$action_def->{options}->{compress_tool};
    }
    if(exists($action_def->{options}->{tmptardir})) {
      $tmptardir=$action_def->{options}->{tmptardir};
    }
    if(exists($action_def->{options}->{tarfileprefix})) {
      $tarfileprefix=$action_def->{options}->{tarfileprefix};
    }
  }
  
  # get status of datasets from DB
  my $stat_tables;
  my $num_stat_tables=0;
  my $num_files_found=0;
  my $starttime=time();
  my $where="(lastts_saved <= $limit_ts)";
  if(defined($limit_pattern_ts)) {
    while ( my ($pat, $l_ts) = each(%{$limit_pattern_ts}) ) {
      $where.=" OR (dataset like '%$pat%' AND lastts_saved <= $l_ts)";
    }
  }
  print "TMPDEB: where=$where\n";
  
  if($action_type==1) { 	# compress
    $where.=" AND (status = ".FSTATUS_EXISTS.")"; # file exists and is created, but not compressed
  }
  if($action_type==2) {
    $where.=" AND ( (status = ".FSTATUS_EXISTS.") OR (status = ".FSTATUS_COMPRESSED.") )"; # all files which exists, compressed or not
  }
  
  foreach my $dataset (@{$action_ref->{datasets}}) {
    # read info about files into memory
    if(!exists($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}})) {
      $self->get_datasetstat_from_DB($dataset->{stat_database},$dataset->{stat_table},$where);
    }
    # print Dumper($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}}) if($dataset->{name} eq "loadmem_csv");
    
    # manage pointer to memory table
    $stat_tables->{$num_stat_tables}->{ds}=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};
    $stat_tables->{$num_stat_tables}->{modified}=0;
    $stat_tables->{$num_stat_tables}->{stat_database}=$dataset->{stat_database};
    $stat_tables->{$num_stat_tables}->{stat_table}=$dataset->{stat_table};
    $stat_tables->{$num_stat_tables}->{name}=$dataset->{name};
    my $st=$stat_tables->{$num_stat_tables};
    $num_stat_tables++;

    # scan for matching files
    my $count;
    ($files_to_process,$count)= $self->scan_for_files_by_name_limit($st,
                                                                    $files_to_process,$dataset->{name},
                                                                    $limit_ts,$limit_pattern_ts,
                                                                    $action_type);
    $num_files_found+=$count;

    printf("%s scan datasetstat(%s,%s) for files older than %5.2fh (%s,%s) found %d [%s]\n",$self->{INSTNAME},
            $dataset->{stat_database},$dataset->{stat_table},($limit_sec)/3600.0,
            &sec_to_date($self->{CURRENTTS}),&sec_to_date($limit_ts),
            $count,$dataset->{name});
  }

  # printf("%s get  datasetstat [%s] in %4.3fs\n",$self->{INSTNAME}, $action_type,time()-$starttime);

  # scan for oldest files (limited by option max_files)
  $starttime=time();
  my ($count_ukey_tbc,$count_tbc)=$self->scan_for_files_to_be_processed($files_to_process,
                                                                        $action_def->{options}->{max_files},
                                                                        $action_type);
  # printf("%s scan datasetstat [%s] in %4.3fs\n",$self->{INSTNAME}, $action_type,time()-$starttime);

  # process files
  $starttime=time();
  my $count_processed=0;
  $count_processed=$self->compress_files($files_to_process,$parallel_level,$compress_tool) if($action_type==FACTION_COMPRESS);
  $count_processed=$self->archive_files($files_to_process,
                                        $parallel_level,
                                        $compress_tool,
                                        $varsetref,
                                        $tmptardir,
                                        $tarfileprefix) if($action_type==FACTION_ARCHIVE);
  $count_processed=$self->remove_files($files_to_process,$parallel_level,
                                        $compress_tool) if($action_type==FACTION_REMOVE);

  # printf("%s process files    [%s] in %4.3fs\n",$self->{INSTNAME}, $action_type,time()-$starttime);

  $starttime=time();
  while ( my ($num, $st) = each(%{$stat_tables}) ) {
    if($st->{modified}) {
      # write updated data back to DB
      my $tstarttime=time();
      $self->cleanup_datasetstat($st->{stat_database},$st->{stat_table});
      $self->save_datasetstat_in_DB($st->{stat_database},$st->{stat_table},$where);
      $st->{modified}=0; # reset if stat table used in multiple datasets
      printf("%s in %4.3fs saved datasetstat(%s,%s) [%s] \n",$self->{INSTNAME},time()-$tstarttime,
              $st->{stat_database},$st->{stat_table},$st->{name})
    }
    delete($self->{DATASETSTAT}->{$st->{stat_database}}->{$st->{stat_table}}); # remove in-memory version
  }
  # printf("%s save datasetstat [%s] in %4.3fs\n",$self->{INSTNAME}, $action_type,time()-$starttime);
  
  printf("%s scan dataset for files older than %6.2fh found in total %d files (%d ukeys (%d files) to be processed)  (%d processed)\n",
          $self->{INSTNAME}, ($limit_sec)/3600.0, $num_files_found,$count_ukey_tbc,$count_tbc,$count_processed);
}

sub mngt_datasets_check {
  my $self = shift;
  my ($DB,$action_ref,$varsetref)=@_;
  my $action_def=$action_ref->{definition};
  my $parallel_level=1; # serial
  my $compress_tool="gzip";
  my $limit_sec=0;
  my $limit_ts=$self->{CURRENTTS};
  my $files_to_process;
  my $tmptardir="/tmp/jobreport/dir";
  my $tarfileprefix="job_";
  
  if(exists($action_def->{options})) {
    if(exists($action_def->{options}->{limit})) {
      $limit_sec=$DB->timeexpr_to_sec($action_def->{options}->{limit});
      $limit_ts-=$limit_sec if($limit_sec>0);
    }
  }

  # get status of datasets from DB
  my $stat_tables;
  my $num_stat_tables=0;
  my $num_files_found=0;
  my $starttime=time();
  
  my $total_count_fixed=0;
  foreach my $dataset (@{$action_ref->{datasets}}) {
    next if($dataset->{format} eq "registerfile");
    # printf("%s check_file_state_with_file_system: check dataset $dataset->{name}\n",$self->{INSTNAME});
    
    my $where="(lastts_saved <= $limit_ts) AND (status = ".FSTATUS_NOT_EXISTS.") and (name = \"$dataset->{name}\")";

    # read info about files into memory
    if(!exists($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}})) {
      $self->get_datasetstat_from_DB($dataset->{stat_database},$dataset->{stat_table},$where);
    }
    my @removed_files;
    my $count_fixed=0;
    my $count_fixed_exists=0;
    while ( my ($file, $ref) = each(%{$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}}}) ) {
      next if($ref->{name} ne $dataset->{name});	
      my $realfile=sprintf("%s/%s",$self->{OUTDIR},$ref->{dataset});

      if( -f $realfile ) {
        my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($realfile);
        print "check: $realfile -> ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks)\n";
        $ref->{status}=FSTATUS_EXISTS;
        $ref->{lastts_saved}=$mtime;
        $ref->{checksum}=0;
        printf("%s check_file_state_with_file_system: check status=$ref->{status} lastts=$ref->{lastts_saved} -> $realfile --> exists\n",$self->{INSTNAME});
        $count_fixed_exists++;
      } else {
        push(@removed_files,$file);
        # printf("%s check_file_state_with_file_system: check status=$ref->{status} lastts=$ref->{lastts_saved} -> $realfile --> not exist\n",$self->{INSTNAME});
      }
      $count_fixed++;
    
      last if($count_fixed>=10000);
    }
    foreach my $file (@removed_files) {
      delete($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}}->{$file});
    }

    $total_count_fixed+=$count_fixed;
    
    if($count_fixed>0) {
      my $tstarttime=time();
      $self->save_datasetstat_in_DB($dataset->{stat_database},$dataset->{stat_table},$where);
      printf("%s check dataset for files: saved datasetstat for $dataset->{name} #%d files exists not on fs, removed from DB, %d files exists, status adapted\n",
              $self->{INSTNAME},$count_fixed-$count_fixed_exists,$count_fixed_exists);
    }
    delete($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}});
  }

  printf("%s check dataset for files: %d file changed\n", $self->{INSTNAME}, $total_count_fixed);
}


sub mngt_datasets_check_gz_gz {
  my $self = shift;
  my ($DB,$action_ref,$varsetref)=@_;
  my $action_def=$action_ref->{definition};
  my $parallel_level=1; # serial
  my $compress_tool="gzip";
  my $limit_sec=0;
  my $limit_ts=$self->{CURRENTTS};
  my $files_to_process;
  my $tmptardir="/tmp/jobreport/dir";
  my $tarfileprefix="job_";
  
  # get status of datasets from DB
  my $stat_tables;
  my $num_stat_tables=0;
  my $num_files_found=0;
  my $starttime=time();
  
  my $total_count_fixed=0;
  foreach my $dataset (@{$action_ref->{datasets}}) {
    next if($dataset->{format} eq "registerfile");
    # printf("%s check_file_state_with_file_system: check dataset $dataset->{name}\n",$self->{INSTNAME});
    
    my $where="(lastts_saved <= $limit_ts) and (name = \"$dataset->{name}\")";

    # read info about files into memory
    if(!exists($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}})) {
      $self->get_datasetstat_from_DB($dataset->{stat_database},$dataset->{stat_table},$where);
    }
    my @removed_files;
    my $count_fixed=0;
    while ( my ($file, $ref) = each(%{$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}}}) ) {
      next if($ref->{name} ne $dataset->{name});	
      my $realfile=sprintf("%s/%s",$self->{OUTDIR},$ref->{dataset});

      if($file=~/\.gz\.gz$/) {
	  printf(STDERR "LLmonDB:    WARNING: compress file found with .gz.gz end %-20s (%-20s) ... deleting\n",
		 get_status_desc($ref->{status}),$file);
	  $ref->{status}=FSTATUS_TOBEDELETED;
	  push(@removed_files,$file);
	  $count_fixed++;
	  last if($count_fixed>=10000);
      }
    }
    foreach my $file (@removed_files) {
      delete($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}}->{$file});
    }

    $total_count_fixed+=$count_fixed;
    
    if($count_fixed>0) {
      my $tstarttime=time();
      $self->save_datasetstat_in_DB($dataset->{stat_database},$dataset->{stat_table},$where);
      printf("%-40s check dataset for files .gz.gz: saved datasetstat for #%d files deleted, status adapted\n",
	     $dataset->{name},$count_fixed);
    }
    delete($self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}});
  }

  printf("%s check dataset for files .gz.gz: %d file changed\n", $self->{INSTNAME}, $total_count_fixed);
}

sub scan_for_files_by_name_limit {
  my $self = shift;
  my ($st,$files_found,$name,$limit_ts,$limit_pattern_ts,$action_type)=@_;
  my $count=0;

  while ( my ($file, $ref) = each(%{$st->{ds}}) ) {
    next if($ref->{name} ne $name);	
    next if($ref->{status} == FSTATUS_NOT_EXISTS); # file not created
    next if($ref->{status} == FSTATUS_TOBEDELETED); # file already marked to be deleted from DB
    if($action_type == FACTION_COMPRESS) {
      next if($ref->{status} == FSTATUS_COMPRESSED); # already compressed
      next if($ref->{status} == FSTATUS_TOBECOMPRESSED); # already marked to be compressed
    }
    my $found=0;
    
    $found=1 if($ref->{lastts_saved}<=$limit_ts);
    
    if(defined($limit_pattern_ts)) {
      while ( my ($pat, $l_ts) = each(%{$limit_pattern_ts}) ) {
        if($file=~/$pat/) {
          $found=1 if($ref->{lastts_saved}<=$l_ts);
        }
      }
    }
    
    if($action_type == FACTION_COMPRESS) {
	if($file=~/\.gz\.gz$/) {
	    printf(STDERR "LLmonDB:    WARNING: compress action planed for filename with .gz.gz ending %-20s (%-20s) ... skipping\n",
		   get_status_desc($ref->{status}),$file);
	    $found=0;
	} elsif($file=~/.gz$/) {
	    printf(STDERR "LLmonDB:    WARNING: compress action planed for filename with .gz ending %-20s (%-20s) ... skipping\n",
		   get_status_desc($ref->{status}),$file);
	    $found=0;
	}
    }

    next if(!$found);
    
    # file found
    $count++;
    if(!exists($files_found->{$ref->{ukey}})) {
      $files_found->{$ref->{ukey}}->{ts}=0;
    }

    push(@{$files_found->{ $ref->{ukey} }->{files}},$ref);
    
    if( $ref->{lastts_saved} > $files_found->{$ref->{ukey}}->{ts} ) {
      $files_found->{ $ref->{ukey} }->{ts}=$ref->{lastts_saved};
    }
    $files_found->{$ref->{ukey}}->{datasets}->{$name}=$st;
  }
  return($files_found,$count);
}


sub scan_for_files_to_be_processed {
  my $self = shift;
  my ($files_found,$max_num, $action_type)=@_;
  my $count_ukey=0;
  my $count=0;
  
  foreach my $ukey (sort {$files_found->{$a}->{ts} <=>  $files_found->{$b}->{ts}} (keys(%{$files_found}))) {
    if( $count_ukey >= $max_num ) {
      # remove file from list if limit reached
      delete($files_found->{$ukey});
    } else {
      $count_ukey++; # count ukeys instead of files 
      $count += scalar @{$files_found->{$ukey}->{files}};
    }
  }
  return($count_ukey,$count);
}

sub compress_files {
  my $self = shift;
  my ($files_found,$parallel_level,$compress_tool)=@_;
  my $count=0;
  my (@commands,$compress_call,$compress_suffix);
  
  if( $compress_tool eq "gzip" ) {
    $compress_call="gzip";
    $compress_suffix="gz";
  } elsif( $compress_tool eq "xz" ) {
    $compress_call="xz";
    $compress_suffix="xz";
  } else {
    print STDERR "LLmonDB:    WARNING: unknown compress_tool $compress_tool, skipping action...\n";
    return(0);
  }

  while ( my ($ukey, $ref) = each(%{$files_found}) ) {
    my @files;
    foreach my $dsentry (@{$ref->{files}}) {
      my $realfile=sprintf("%s/%s",$self->{OUTDIR},$dsentry->{dataset});
      if(-f $realfile) {
	  push(@files,$realfile);
        $dsentry->{dataset}.=".$compress_suffix";
        $dsentry->{status}=FSTATUS_TOBECOMPRESSED;
        $count++;
        # printf("compress_files: %s -> %s\n",$ukey,$dsentry->{dataset});
      } else {
	  printf("compress_files: %s -> %s (set state to FSTATUS_NOT_EXISTS) (.gz)\n",$ukey,$dsentry->{dataset});
	  $dsentry->{status}=FSTATUS_NOT_EXISTS;
      }
    }
    if(scalar @files > 0) {
      push(@commands,"$compress_call ".join(" ",@files));
    }
    
    while ( my ($name, $st) = each(%{$ref->{datasets}}) ) {
      $st->{modified}=1;
    }
  }

  if(defined($self->{JOURNALDIR})) {
    if(scalar @commands > 0 ) {
      if(! -d $self->{JOURNALDIR}) {
        my $cmd="mkdir -p $self->{JOURNALDIR}";
        $self->mysystem($cmd);
      }
    
      my $journaldatfile=sprintf("%s/mngt_actions_compress_%d.dat",$self->{JOURNALDIR},$self->{CURRENTTS});
      open(DAT, ">$journaldatfile") or die "cannot open $journaldatfile";
      foreach my $cmd (@commands) {
        print DAT $cmd,"\n";
      }
      close(DAT);

      my $journalsignalfile=sprintf("%s/mngt_actions_compress_lastts.dat",$self->{JOURNALDIR});
      open(SIG, ">$journalsignalfile") or die "cannot open $journalsignalfile";
      print SIG $self->{CURRENTTS};
      close(SIG);
    }
  }
  if($self->{JOURNALONLY}) {
    return($count);
  }
  
  my $pm = Parallel::ForkManager->new($parallel_level);
  
  DATA_LOOP:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP;
    $self->mysystem($cmd);
    
    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;

  return($count);
}


sub archive_files {
  my $self = shift;
  my ($files_found,$parallel_level,$compress_tool,$varsetref,$tmptardir,$tarfileprefix)=@_;
  my $count=0;
  my (@commands,$tardirs,$tarlistfiles,$compress_call,$compress_suffix);
  
  if( $compress_tool eq "gzip" ) {
    $compress_call="gzip";
    $compress_suffix="gz";
  } elsif( $compress_tool eq "xz" ) {
    $compress_call="xz";
    $compress_suffix="xz";
  } else {
    print STDERR "LLmonDB:    WARNING: unknown compress_tool $compress_tool, skipping action...\n";
    return(0);
  }

  my $archdir=File::Spec->rel2abs($varsetref->{"archdir"});

  while ( my ($ukey, $ref) = each(%{$files_found}) ) {
    my @filelist;

    foreach my $dsentry (@{$ref->{files}}) {
      my $realfile=sprintf("%s/%s",$self->{OUTDIR},$dsentry->{dataset});
      if(-f $realfile) {
        push(@filelist,$realfile);
        $dsentry->{status}=FSTATUS_TOBEDELETED; # mark to delete from DB after archiving it
        $count++;
      } else {
        $dsentry->{status}=FSTATUS_TOBEDELETED; # mark also to delete from DB after archiving it
      }
      printf("archive_files: %s -> %s\n",$ukey,$dsentry->{dataset});
    }
    while ( my ($name, $st) = each(%{$ref->{datasets}}) ) {
      $st->{modified}=1;
    }

    if(@filelist) {
      # construct tar cmd
      my $tardir = $archdir."/".&sec_to_date_dir_wo_hhmmss($ref->{ts});
      my $tarlistfile = $archdir."/".&sec_to_date_dir_wo_hhmmss($ref->{ts}).".lst";
      $tardirs->{$tardir}=1;
      my $cmd="mkdir $tmptardir/$ukey;"; 
      $cmd.="mv ".( join(" ",@filelist))." $tmptardir/$ukey;";
      $cmd.="(cd $tmptardir;tar uf $tardir/$tarfileprefix$ukey.tar $ukey);";
      $cmd.="rm -r $tmptardir/$ukey;";
      $cmd.="echo \"$tarfileprefix$ukey.tar: ".(join(",",@filelist))."\" >> $tarlistfile;";
      push(@commands,$cmd);
    }
  }
  
  # check tmp and archive dirs
  foreach my $tardir ($tmptardir,keys(%{$tardirs})) {
    if(! -d $tardir) {
      my $cmd="mkdir -p $tardir";
      unshift(@commands,$cmd);
    }
  }

  
  if(defined($self->{JOURNALDIR})) {
    if(scalar @commands > 0 ) {
      if(! -d $self->{JOURNALDIR}) {
        my $cmd="mkdir -p $self->{JOURNALDIR}";
        $self->mysystem($cmd);
      }
    
      my $journaldatfile=sprintf("%s/mngt_actions_tar_%d.dat",$self->{JOURNALDIR},$self->{CURRENTTS});
      open(DAT, ">$journaldatfile") or die "cannot open $journaldatfile";
      foreach my $cmd (@commands) {
        print DAT $cmd,"\n";
      }
      close(DAT);

      my $journalsignalfile=sprintf("%s/mngt_actions_tar_lastts.dat",$self->{JOURNALDIR});
      open(SIG, ">$journalsignalfile") or die "cannot open $journalsignalfile";
      print SIG $self->{CURRENTTS};
      close(SIG);
    }
  
  }
  if($self->{JOURNALONLY}) {
    return($count);
  }

  my $pm = Parallel::ForkManager->new($parallel_level);
  
  DATA_LOOP:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP;
    $self->mysystem($cmd);
    
    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;

  return($count);
}

sub remove_files {
  my $self = shift;
  my ($files_found,$parallel_level,$compress_tool)=@_;
  my $count=0;
  my (@commands,$compress_call,$compress_suffix);

  while ( my ($ukey, $ref) = each(%{$files_found}) ) {
    my @files;
    foreach my $dsentry (@{$ref->{files}}) {
      my $realfile=sprintf("%s/%s",$self->{OUTDIR},$dsentry->{dataset});
      if(-f $realfile) {
        push(@files,$realfile);
        $dsentry->{status}=FSTATUS_TOBEDELETED;
        $count++;
        printf("remove_files: %s -> %s\n",$ukey,$dsentry->{dataset});
      } else {
        $dsentry->{status}=FSTATUS_NOT_EXISTS;
      }
    }
    if(scalar @files > 0) {
      push(@commands,"rm ".join(" ",@files));
    }

    while ( my ($name, $st) = each(%{$ref->{datasets}}) ) {
      $st->{modified}=1;
    }
  }

  if(defined($self->{JOURNALDIR})) {
    if(scalar @commands > 0 ) {
      if(! -d $self->{JOURNALDIR}) {
        my $cmd="mkdir -p $self->{JOURNALDIR}";
        $self->mysystem($cmd);
      }

      my $journaldatfile=sprintf("%s/mngt_actions_delete_%d.dat",$self->{JOURNALDIR},$self->{CURRENTTS});
      open(DAT, ">$journaldatfile") or die "cannot open $journaldatfile";
      foreach my $cmd (@commands) {
        print DAT $cmd,"\n";
      }
      close(DAT);

      my $journalsignalfile=sprintf("%s/mngt_actions_delete_lastts.dat",$self->{JOURNALDIR});
      open(SIG, ">$journalsignalfile") or die "cannot open $journalsignalfile";
      print SIG $self->{CURRENTTS};
      close(SIG);
    }
  }

  if($self->{JOURNALONLY}) {
    return($count);
  }

  my $pm = Parallel::ForkManager->new($parallel_level);

  DATA_LOOP:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP;
    $self->mysystem($cmd);

    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;

  return($count);
}

sub mngt_scan_datasets {
  my $self = shift;
  my ($DB)=@_;
  my $basename=$self->{BASENAME};
  my $config_ref=$DB->get_config();
  my $limit_ts=$self->{CURRENTTS};

  # init instantiated variables
  my $varsetref;
  if(exists($config_ref->{$basename}->{paths})) {
    foreach my $p (keys(%{$config_ref->{$basename}->{paths}})) {
      $varsetref->{$p}=$config_ref->{$basename}->{paths}->{$p};
    }
  }

  # find datasets which could have updated files
  my $ds;
  foreach my $datasetref (@{$config_ref->{$basename}->{datafiles}}) {
    my $subconfig_ref=$datasetref->{dataset};
    $ds->{$subconfig_ref->{stat_database}}->{$subconfig_ref->{stat_table}}=$subconfig_ref;
  }
  foreach my $datasetref (@{$config_ref->{$basename}->{footerfiles}}) {
    my $subconfig_ref=$datasetref->{footer};
    $ds->{$subconfig_ref->{stat_database}}->{$subconfig_ref->{stat_table}}=$subconfig_ref;
  }
  foreach my $datasetref (@{$config_ref->{$basename}->{graphpages}}) {
    my $subconfig_ref=$datasetref->{graphpage};
    $ds->{$subconfig_ref->{stat_database}}->{$subconfig_ref->{stat_table}}=$subconfig_ref;
  }
  foreach my $datasetref (@{$config_ref->{$basename}->{views}}) {
    my $subconfig_ref=$datasetref->{view};
    $ds->{$subconfig_ref->{stat_database}}->{$subconfig_ref->{stat_table}}=$subconfig_ref;
  }

  # find datasets which require an mngt action
  my $changed_files;
  my $stat;
  my $where="(mts >= ($limit_ts) OR (status=".FSTATUS_TOBEDELETED.") OR (status=".FSTATUS_TOBECOMPRESSED.") OR (status=".FSTATUS_DELETED."))";
  foreach my $ds_db (sort(keys(%{$ds}))) {
    foreach my $ds_tab (sort(keys(%{$ds->{$ds_db}}))) {
      my $subconfig_ref=$ds->{$ds_db}->{$ds_tab};
      my $count_ds_changed=0;
      
      # remove old in memory if available (maybe different where)
      if(exists($self->{DATASETSTAT}->{$ds_db}->{$ds_tab})) {
        delete($self->{DATASETSTAT}->{$ds_db}->{$ds_tab}); # remove in-memory version
      }
      
      # read info about files into memory
      $self->get_datasetstat_from_DB($ds_db,$ds_tab,$where);
      
      while ( my ($file, $ref) = each(%{$self->{DATASETSTAT}->{$ds_db}->{$ds_tab}}) ) {
	$stat->{$ref->{status}}++;
	  

        if($ref->{status}==FSTATUS_EXISTS) {
          # updated of regular files
          $changed_files->{$ref->{dataset}}++ if($ref->{status} != FSTATUS_NOT_EXISTS);
          printf ("%s/%s: [%d] changed %s\n",$ds_db,$ds_tab,$ref->{status},$ref->{dataset}) if($self->{VERBOSE}>=1);
        } elsif($ref->{status}==FSTATUS_TOBECOMPRESSED) {
          my $realfile=sprintf("%s/%s",$self->{OUTDIR},$ref->{dataset});
          if( -f $realfile ) {
            # file is already compressed
            $count_ds_changed++;
            $ref->{status}=FSTATUS_COMPRESSED;
            # mark dataset with and w/o suffix as changed
            my $help=$ref->{dataset}; $changed_files->{$help}++;
            $help=~s/\.(gz|xz)$//gs;  $changed_files->{$help}++;
            printf ("%s/%s: [%d] compressed %s\n",$ds_db,$ds_tab,$ref->{status},$ref->{dataset}) if($self->{VERBOSE}>=1);
          }
        } elsif($ref->{status}==FSTATUS_TOBEDELETED) {
          my $realfile=sprintf("%s/%s",$self->{OUTDIR},$ref->{dataset});
          if( ! -f $realfile ) {
            # file is already deleted
            $count_ds_changed++;
            $ref->{status}=FSTATUS_DELETED;
            $changed_files->{$ref->{dataset}}++;
            printf ("%s/%s: [%d] deleted %s\n",$ds_db,$ds_tab,$ref->{status},$ref->{dataset}) if($self->{VERBOSE}>=1);
          }
        }
      }

      if($count_ds_changed>0) {
        $self->cleanup_datasetstat($ds_db,$ds_tab);
        $self->save_datasetstat_in_DB($ds_db,$ds_tab,$where);
      }
      delete($self->{DATASETSTAT}->{$ds_db}->{$ds_tab}); # remove in-memory version
    }
  }
  foreach my $st (sort(keys(%{$stat}))) {
    printf("mngt_scan_datasets: status=%d -> %6d files\n",$st,$stat->{$st});
  }

  return($changed_files);
  }

sub cleanup_datasetstat {
  my $self = shift;
  my($stat_db,$stat_table)=@_;
  my $cnt=0;
  my $ds=$self->{DATASETSTAT}->{$stat_db}->{$stat_table};
  foreach my $key (keys(%{$ds})) {
    # remove entries which are marked to be removed (already archived)
    if($ds->{$key}->{"status"} == FSTATUS_DELETED) {
      delete($ds->{$key});
      $cnt++;
    }
  }
  printf ("%s/%s: deleted %d entries\n",$stat_db,$stat_table, $cnt) if($self->{VERBOSE}>=1);
}

sub mysystem {
  my $self = shift;
  my($call)=@_;

  printf("  --> exec: %s\n",$call) if($self->{VERBOSE}>=1);
  system($call);
  my $rc = $?;
  if ($rc) {
    printf(STDERR "  ERROR --> exec: %s\n",$call);
    printf(STDERR "  ERROR --> rc=%d\n",$rc);
  } else {
    printf("           rc=%d\n",$rc) if($self->{VERBOSE}>=2);
  }
  return($?)
}

1;
