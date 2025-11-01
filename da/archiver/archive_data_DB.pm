# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

#======================================
# DB files routines
#======================================

sub check_db_files {
  my($info)=@_;

  my @commands;
  
  # check local db directory
  my $dir=$info->{loc}->{db};
  my $locdata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    #	printf("$0: [DB] found file %-60s\n",$file);
    if($file=~/db\_(.*)\_date_(\d\d\d\d_w\d\d).csv(\.xz)?/) {
      my($dbtab,$yweek,$c)=($1,$2,$3);
      my $compress=0;
      $compress=1 if( defined($c));
      #	printf("$0: [DB] found dbtab %7s %2s %-s\n",$yweek,$compress?"xz":"  ",$dbtab);
      $locdata->{db}->{$yweek}->{$compress}->{$dbtab}=$file;
    }
    if($file=~/db_csv_(\d\d\d\d_w\d\d)_a1.tar/) {
      my($yweek)=($1);
      $locdata->{dbtar}->{$yweek}=$file;
    }
  }
  closedir($dh);
  
  return($locdata);
}

sub print_stat_db_files {
  my($info,$locdata)=@_;
  printf("$0: [DB] \n");
  printf("$0: [DB] Statistics DB files (currentweek $info->{currentweek})\n");
  foreach my $yweek (sort(keys(%{$locdata->{db}}))) {
    my $num_compressed  =scalar keys(%{$locdata->{db}->{$yweek}->{1}});
    my $num_uncompressed=scalar keys(%{$locdata->{db}->{$yweek}->{0}});
    printf("$0: [DB]  week %7s found %d files (%d not compressed)\n",$yweek,$num_compressed+$num_uncompressed,$num_uncompressed);
  }
}

sub check_compress_db_files {
  my($info,$locdata)=@_;

  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_compress=0;
  printf("$0: [DB] \n");
  printf("$0: [DB] compress DB files (currentweek $info->{currentweek})\n");
  foreach my $yweek (sort(keys(%{$locdata->{db}}))) {
    next if($yweek eq $info->{currentweek}); # not for current week files
    
    my $num_compressed  =scalar keys(%{$locdata->{db}->{$yweek}->{1}});
    my $num_uncompressed=scalar keys(%{$locdata->{db}->{$yweek}->{0}});
    my $num_tocompress=0;
    if($num_files_to_compress<$info->{opt}->{maxcompress}) {
      foreach my $dbtag (sort(keys(%{$locdata->{db}->{$yweek}->{0}}))) {
        # check if compression for this file is not ongoing
        if(!exists($locdata->{db}->{$yweek}->{1}->{$dbtag})) {
          my $cmd=sprintf("(cd %s; xz -3 %s)",$info->{loc}->{db},$locdata->{db}->{$yweek}->{0}->{$dbtag});
          push(@commands,$cmd);
          $num_files_to_compress++;
          $num_tocompress++;
          last if($num_files_to_compress>=$info->{opt}->{maxcompress});
        } else {
          printf("$0: [DB]  WARNING week %7s found another compress activity detected for %s, skipping\n",$yweek,$locdata->{db}->{$yweek}->{0}->{$dbtag});
        }
      }
    }
    if($num_tocompress>0) {
      printf("$0: [DB]  week %7s found %d files (%d not compressed, %d to compress)\n",$yweek,$num_compressed+$num_uncompressed,$num_uncompressed,$num_tocompress);
    }
  }

  # excecute compress actions
  my $pm = Parallel::ForkManager->new($info->{opt}->{maxpar});
  
  DATA_LOOP1:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP1;
    &mysystem($cmd);
    
    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;
  @commands=();
  
  # print Dumper($locdata);
  # my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($fn);
}

sub check_tar_db_files {
  my($info,$locdata)=@_;
  
  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_compress=0;
  printf("$0: [DB] \n");
  printf("$0: [DB] TAR DB files (currentweek $info->{currentweek})\n");
  foreach my $yweek (sort(keys(%{$locdata->{db}}))) {
    my $num_compressed  =scalar keys(%{$locdata->{db}->{$yweek}->{1}});
    my $num_uncompressed=scalar keys(%{$locdata->{db}->{$yweek}->{0}});
    
    if($num_uncompressed==0) {
      if(!exists($locdata->{dbtar}->{$yweek})) {
        my $tarfile=sprintf("db_csv_%s_a1.tar",$yweek);
        my @csvfiles=values(%{$locdata->{db}->{$yweek}->{1}});
        my $cmd=sprintf("(cd %s; tar cvf %s %s)",$info->{loc}->{db},$tarfile,join(" ",@csvfiles));
        push(@commands,$cmd);
        printf("$0: [DB]  week %7s create tar file %s)\n",$yweek,$tarfile);
      }
    }
  }
  
  # excecute compress actions
  my $pm = Parallel::ForkManager->new($info->{opt}->{maxpar});
  
  DATA_LOOP2:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP2;
    &mysystem($cmd);
    
    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;
  @commands=();
}

sub check_remote_db_files {
  my($info,$fs)=@_;

  my @commands;
  
  # check remote db directory
  my $dir=$info->{$fs}->{db};
  my $remotedata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    if($file=~/db_csv_(\d\d\d\d_w\d\d)_a1.tar/) {
      my($yweek)=($1);
      $remotedata->{dbtar}->{$yweek}=$file;
    }
  }
  closedir($dh);
  
  return($remotedata);
}

sub print_stat_db_tar_files {
  my($info,$locdata,$remotedata)=@_;
  printf("$0: [DB] \n");
  printf("$0: [DB] Statistics DB tar files (currentweek $info->{currentweek})\n");
  foreach my $yweek (sort(keys(%{$locdata->{dbtar}}))) {
    printf("$0: [DB]  week %7s found %s\n",$yweek,$locdata->{dbtar}->{$yweek});
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{dbtar}->{$yweek})) {
        printf("$0: [DB]     file exists on fs %s\n",$fs);
      }
    }
  }
}

sub check_cp_tar_db_files {
  my($info,$locdata,$remotedata)=@_;
  
  my @commands;
  my $num_files_to_remove=0;

  # check required actions
  printf("$0: [DB] \n");
  printf("$0: [DB] CHECK and COPY tar DB files (currentweek $info->{currentweek})\n");
  foreach my $yweek (sort(keys(%{$locdata->{dbtar}}))) {
    printf("$0: [DB]  week %7s found %s\n",$yweek,$locdata->{dbtar}->{$yweek});
    my $count_remote=0;
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{dbtar}->{$yweek})) {
        printf("$0: [DB]  week %7s file exist on fs %s\n",$yweek,$fs);
        $count_remote++;
      } else {
        my $cmd=sprintf("(cd %s; cp -p %s %s/)",$info->{loc}->{db},$locdata->{dbtar}->{$yweek},$info->{$fs}->{db});
        push(@commands,$cmd);
        printf("$0: [DB]  week %7s cp tar file %s to fs %s)\n",$yweek,$locdata->{dbtar}->{$yweek},$fs);
      }
      if($count_remote==2) {
        # check file size
        my($Lsize,$Lmtime)=&get_file_info($info->{loc}->{db}."/".$locdata->{dbtar}->{$yweek});
        my($Asize,$Amtime)=&get_file_info($info->{arch}->{db}."/".$locdata->{dbtar}->{$yweek});
        my($Dsize,$Dmtime)=&get_file_info($info->{data}->{db}."/".$locdata->{dbtar}->{$yweek});
        printf("$0: [DB]  week %7s consistency check, Size (L/A/D): %d=%d=%d Mtime (L/A/D): %d=%d=%d\n",$yweek,$Lsize,$Asize,$Dsize,$Lmtime,$Amtime,$Dmtime);

        if ( ($Lsize==$Asize) &&  ($Lsize==$Dsize) && ($Lmtime<=$Amtime) &&  ($Lmtime<=$Dmtime) ) {
          printf("$0: [DB]  week %7s consistency check, files are identical\n",$yweek);
          
          if( $Lmtime < ($info->{nowts}-48*3600) ) {
            if($info->{opt}->{remove}) {
              if($num_files_to_remove<$info->{opt}->{maxremove}) {
                my $tarfile=sprintf("db_csv_%s_a1.tar",$yweek);
                my @csvfiles=values(%{$locdata->{db}->{$yweek}->{1}});
                my $cmd=sprintf("(cd %s; rm %s %s)",$info->{loc}->{db},$tarfile,join(" ",@csvfiles));
                push(@commands,$cmd);
                printf("$0: [DB]  week %7s remove now local csv files and local tar file\n",$yweek);
                $num_files_to_remove++;
              } else {
                printf("$0: [DB]  week %7s remove now local csv files and local tar file (max limit reached $num_files_to_remove>=$info->{opt}->{maxremove}, skipping)\n",$yweek);
              }
            } else {
              printf("$0: [DB]  week %7s remove now local csv files and local tar file (disabled, please use option --remove)\n",$yweek);
            }
          } else {
            printf("$0: [DB]  week %7s consistency check, but files exists not more 2 days on remote file systems\n",$yweek);
          }
        }
      }
    }
  }
  
  # excecute compress actions
  my $pm = Parallel::ForkManager->new(2);
  
  DATA_LOOP2:
  foreach my $cmd (@commands) {
    # Forks and returns the pid for the child:
    my $pid = $pm->start and next DATA_LOOP2;
    &mysystem($cmd);
    
    $pm->finish; # Terminates the child process
  }
  $pm->wait_all_children;
  @commands=();
  
}

1;