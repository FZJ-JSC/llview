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
# JOBREPORT files routines
#======================================

sub check_jobreport_files {
  my($info)=@_;

  my @commands;
  
  # check local jobreport directory
  my $dir=$info->{loc}->{jobreport};
  my $locdata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    #	printf("$0: [JOBREPORT] found file %-60s\n",$file);
    if($file=~/^(\d\d\d\d_\d\d)_(\d\d)$/) {
      my($ym,$dd)=($1,$2);
      $locdata->{jobreport}->{$ym}->{dir}->{$dd}=$file;
    }
    if($file=~/(\d\d\d\d_\d\d)_(\d\d)\.lst/) {
      my($ym,$dd)=($1,$2);
      $locdata->{jobreport}->{$ym}->{lst}->{$dd}=$file;
    }
    if($file=~/(\d\d\d\d_\d\d)_(\d\d).tar/) {
      my($ym,$dd)=($1,$2);
      $locdata->{jobreport}->{$ym}->{dtar}->{$dd}=$file;
    }
    if($file=~/(\d\d\d\d_\d\d).tar/) {
      my($ym)=($1);
      $locdata->{jobreport}->{$ym}->{mtar}=$file;
    }
  }
  closedir($dh);
  
  return($locdata);
}

sub print_stat_jobreport_files {
  my($info,$locdata)=@_;
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] Statistics JOBreport files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{jobreport}}))) {
    my $num_dirs  = scalar keys(%{$locdata->{jobreport}->{$ym}->{dir}});
    my $num_lsts  = scalar keys(%{$locdata->{jobreport}->{$ym}->{lst}});
    my $num_dtars = scalar keys(%{$locdata->{jobreport}->{$ym}->{dtar}});
    my $num_mtar  = 0;
    $num_mtar = 1 if(exists($locdata->{jobreport}->{$ym}->{mtar}));
    printf("$0: [JOBREPORT]  month %7s found %2d dirs, %2d lst files, %2d day-tar files %d mon-tar file\n",
            $ym,$num_dirs,$num_lsts,$num_dtars,$num_mtar);
  }
}

sub check_tar_jobreport_files {
  my($info,$locdata)=@_;
  
  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_tar=0;
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] TAR DIR files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{jobreport}}))) {
    foreach my $dd (sort(keys(%{$locdata->{jobreport}->{$ym}->{dir}}))) {
      next if(&day_diff($ym,$dd,$info->{nowts})<22);
      if(!exists($locdata->{jobreport}->{$ym}->{dtar}->{$dd})) {
        my $tarfile=sprintf("%s_%02d.tar",$ym,$dd);
        my $cmd=sprintf("(cd %s; tar cf %s %s %s)",$info->{loc}->{jobreport},$tarfile,$locdata->{jobreport}->{$ym}->{dir}->{$dd},$locdata->{jobreport}->{$ym}->{lst}->{$dd});
        push(@commands,$cmd);
        printf("$0: [JOBREPORT]  day %5s %dd create tar file %s)\n",$ym,$dd,$tarfile);
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

sub check_remove_jobreport_dirs {
  my($info,$locdata)=@_;
  
  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_remove=0;
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] REMOVE DIR files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{jobreport}}))) {
    foreach my $dd (sort(keys(%{$locdata->{jobreport}->{$ym}->{dir}}))) {
      next if(&day_diff($ym,$dd,$info->{nowts})<22);
      
      if(exists($locdata->{jobreport}->{$ym}->{dtar}->{$dd})) {
        my $tarfile=sprintf("%s/%s_%02d.tar",$info->{loc}->{jobreport},$ym,$dd);
        my $tarfiles;
        my $foundlst=0;
        open(TAR, "tar tvf $tarfile|");
        while(my $line=<TAR>) {
          chomp($line);
          if($line=~/(JOB_\d+\.tar)$/) {
            $tarfiles->{$1}=1;
          }
          $foundlst=1 if($line=~/(\d\d\d\d_\d\d\_\d\d\.lst)$/);
        }
        close(TAR);
        my $countwrong=0;
        open(LST, "ls $info->{loc}->{jobreport}/$locdata->{jobreport}->{$ym}->{dir}->{$dd}|");
        while(my $f=<LST>) {
          chomp($f);
          if(exists($tarfiles->{$f})) {
            delete($tarfiles->{$f});
          } else {
            print "$0: [JOBREPORT] check TAR file, NOT FOUND tarfiles->{$f}\n";
            $countwrong++;
          }
        }
        close(LST);
        my $numleft=scalar (keys(%{$tarfiles}));

        if( ($countwrong==0) && ($numleft==0) && ($foundlst==1) ) {
          if($info->{opt}->{remove}) {
            if($num_files_to_remove<$info->{opt}->{maxremove}) {
              my $cmd=sprintf("(cd %s; rm -r %s %s)",$info->{loc}->{jobreport},
                                $locdata->{jobreport}->{$ym}->{dir}->{$dd},
                                $locdata->{jobreport}->{$ym}->{lst}->{$dd});
              push(@commands,$cmd);
              $num_files_to_remove++;
              printf("$0: [JOBREPORT] day %5s %2d REMOVE DIR and LST ($countwrong, $numleft, $foundlst)\n",$ym,$dd);
            } else {
              printf("$0: [JOBREPORT] day %5s %2d REMOVE DIR and LST (max limit reached $num_files_to_remove>=$info->{opt}->{maxremove}, skipping)\n",$ym,$dd);
            }
          } else {
            printf("$0: [JOBREPORT] day %5s %2d REMOVE DIR and LST (disabled, please use option --remove)\n",$ym,$dd);
          }
        } else {
          printf("$0: [JOBREPORT] day %5s %2d REMOVE DIR and LST WARNING tar file not consistent !!! ($countwrong, $numleft, $foundlst)\n",$ym,$dd);
        }
      }
      last if($num_files_to_remove>=$info->{opt}->{maxremove});
    }
    last if($num_files_to_remove>=$info->{opt}->{maxremove});
  }
  
  # excecute compress actions
  my $pm = Parallel::ForkManager->new(1);
  
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

sub check_tar_monthly_jobreport_files {
  my($info,$locdata)=@_;
  
  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_tar=0;
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] TAR DIR files (currentmonth $info->{currentmonth})\n");
  my @ym_list=(sort(keys(%{$locdata->{jobreport}})));
  pop(@ym_list); # remove last month

  
  foreach my $ym (@ym_list) {
  
    if(!exists($locdata->{jobreport}->{$ym}->{mtar})) {
      my @dtarfiles=(sort(values(%{$locdata->{jobreport}->{$ym}->{dtar}})));
      my $tarfile=sprintf("%s.tar",$ym);
      my $cmd=sprintf("(cd %s; tar cf %s %s)",$info->{loc}->{jobreport},$tarfile,join(" ",@dtarfiles));
      push(@commands,$cmd);
      printf("$0: [JOBREPORT]  month %5s create tar file %s)\n",$ym,$tarfile);
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


sub check_remote_jobreport_files {
  my($info,$fs)=@_;

  my @commands;
  
  # check remote jobreport directory
  my $dir=$info->{$fs}->{jobreport};
  my $remotedata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    if($file=~/(\d\d\d\d_\d\d).tar/) {
      my($ym)=($1);
      $remotedata->{jobtar}->{$ym}=$file;
    }
  }
  closedir($dh);
  
  return($remotedata);
}

sub print_stat_jobreport_tar_files {
  my($info,$locdata,$remotedata)=@_;
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] Statistics JOBREPORT tar files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{jobreport}}))) {
    next if(!exists($locdata->{jobreport}->{$ym}->{mtar}));
    printf("$0: [JOBREPORT]  month %5s found %s\n",$ym,$locdata->{jobreport}->{$ym}->{mtar});
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{jobtar}->{$ym})) {
        printf("$0: [JOBREPORT]     file exists on fs %s\n",$fs);
      }
    }
  }
}

sub check_cp_tar_jobreport_files {
  my($info,$locdata,$remotedata)=@_;
  
  my @commands;
  my $num_files_to_remove=0;

  # check required actions
  printf("$0: [JOBREPORT] \n");
  printf("$0: [JOBREPORT] CHECK and COPY tar JOBREPORT files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{jobreport}}))) {
    next if(!exists($locdata->{jobreport}->{$ym}->{mtar}));
    printf("$0: [JOBREPORT]  month %5s found %s\n",$ym,$locdata->{jobreport}->{$ym}->{mtar});
    my $count_remote=0;
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{jobtar}->{$ym})) {
        printf("$0: [JOBREPORT]  month %5s file exist on fs %s\n",$ym,$fs);
        $count_remote++;
      } else {
        my $cmd=sprintf("(cd %s; cp -p %s %s/)",$info->{loc}->{jobreport},$locdata->{jobreport}->{$ym}->{mtar},$info->{$fs}->{jobreport});
        push(@commands,$cmd);
        printf("$0: [JOBREPORT]  month %5s cp tar file %s to fs %s)\n",$ym,$locdata->{jobreport}->{$ym}->{mtar},$fs);
      }
      if($count_remote==2) {
        # check file size
        my($Lsize,$Lmtime)=&get_file_info($info->{loc}->{jobreport}."/".$locdata->{jobreport}->{$ym}->{mtar});
        my($Asize,$Amtime)=&get_file_info($info->{arch}->{jobreport}."/".$locdata->{jobreport}->{$ym}->{mtar});
        my($Dsize,$Dmtime)=&get_file_info($info->{data}->{jobreport}."/".$locdata->{jobreport}->{$ym}->{mtar});
        printf("$0: [JOBREPORT]  week %7s consistency check, Size (L/A/D): %d=%d=%d Mtime (L/A/D): %d=%d=%d\n",$ym,$Lsize,$Asize,$Dsize,$Lmtime,$Amtime,$Dmtime);

        if ( ($Lsize==$Asize) &&  ($Lsize==$Dsize) && ($Lmtime<=$Amtime) &&  ($Lmtime<=$Dmtime) ) {
          printf("$0: [JOBREPORT]  month %5s consistency check, files are identical\n",$ym);
          
          if( $Lmtime < ($info->{nowts}-48*3600) ) {
            if($info->{opt}->{remove}) {
              if($num_files_to_remove<$info->{opt}->{maxremove}) {
                my $tarfile=sprintf("%s.tar",$ym);
                my @dtarfiles=values(%{$locdata->{jobreport}->{$ym}->{dtar}});
                my $cmd=sprintf("(cd %s; rm %s %s)",$info->{loc}->{jobreport},$tarfile,join(" ",@dtarfiles));
                push(@commands,$cmd);
                printf("$0: [JOBREPORT]  month %5s remove now local csv files and local tar file\n",$ym);
                $num_files_to_remove++;
              } else {
                printf("$0: [JOBREPORT]  month %5s remove now local csv files and local tar file (max limit reached $num_files_to_remove>=$info->{opt}->{maxremove}, skipping)\n",$ym);
                last;
              }
            } else {
              printf("$0: [JOBREPORT]  month %5s remove now local csv files and local tar file (disabled, please use option --remove)\n",$ym);
            }
          } else {
            printf("$0: [JOBREPORT]  month %5s consistency check, but files exists not more 2 days on remote file systems\n",$ym);
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