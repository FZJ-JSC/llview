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
# LML files routines
#======================================

sub check_LML_files {
  my($info,$kind)=@_;

  my @commands;
  
  # check local LML directory
  my $dir=$info->{loc}->{$kind};
  my $locdata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    #	printf("$0: [LML] found file %-60s\n",$file);
    if($file=~/^(\d\d)\_(\d\d)\_(\d\d).dat$/) {
      my($yy,$mm,$dd)=($1,$2,$3);
      my $ym=sprintf("%2d_%02d",$yy,$mm);
      # printf("$0: [LML] found dat file %5s %02d\n",$ym,$dd);
      $locdata->{LML}->{$kind}->{$ym}->{ddat}->{$dd}=$file;
    }
    if($file=~/^(\d\d)\_(\d\d).dat$/) {
      my($yy,$mm)=($1,$2,$3);
      my $ym=sprintf("%2d_%02d",$yy,$mm);
      #	printf("$0: [LML] found dat file %5s\n",$ym);
      $locdata->{LML}->{$kind}->{$ym}->{mdat}=$file;
    }
    if($file=~/^LML_data_(\d\d)\_(\d\d)\_(\d\d).tar$/) {
      my($yy,$mm,$dd)=($1,$2,$3);
      my $ym=sprintf("%2d_%02d",$yy,$mm);
      # printf("$0: [LML] found tar file %5s %02d\n",$ym,$dd);
      $locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd}=$file;
    }
    if($file=~/LML_(\d\d_\d\d).tar/) {
      my($ym)=($1);
      $locdata->{LML}->{$kind}->{$ym}->{mtar}=$file;
    }
  }
  closedir($dh);
  
  return($locdata);
}

sub print_stat_LML_files {
  my($info,$kind,$locdata)=@_;
  printf("$0: [LML] \n");
  printf("$0: [LML] Statistics LML files (kind=$kind, currentmonth=$info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{LML}->{$kind}}))) {
    my ($num_ddat,$num_mdat,$num_tar,$num_mtar)=(0,0,0,0);
    if(exists($locdata->{LML}->{$kind}->{$ym}->{ddat})) {
      $num_ddat = scalar keys(%{$locdata->{LML}->{$kind}->{$ym}->{ddat}});
    }
    if(exists($locdata->{LML}->{$kind}->{$ym}->{mdat})) {
      $num_mdat = 1;
    }
    if(exists($locdata->{LML}->{$kind}->{$ym}->{tar})) {
      $num_tar = scalar keys(%{$locdata->{LML}->{$kind}->{$ym}->{tar}});
    }
    if(exists($locdata->{LML}->{$kind}->{$ym}->{mtar})) {
      $num_mtar = 1;
    }
    printf("$0: [LML]  kind=%s month %5s found %2d tar files and %2d dat files%s\n",
            $kind,$ym,$num_tar,$num_ddat+$num_mdat,
            ($num_mtar)?" [monthly tar file exists]":""
          );
  }
}

sub check_tar_LML_files {
  my($info,$kind,$locdata)=@_;
  
  my @commands;
  
  # print statistics and check required actions
  my $num_files_to_compress=0;
  printf("$0: [LML] \n");
  printf("$0: [LML] TAR LML files (currentmonth $info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{LML}->{$kind}}))) {
    next if($ym eq $info->{currentmonth}); # not for current month files
    my @files;
    if(exists($locdata->{LML}->{$kind}->{$ym}->{ddat})) {
      foreach my $dd (sort(keys(%{$locdata->{LML}->{$kind}->{$ym}->{ddat}}))) {
        push(@files,$locdata->{LML}->{$kind}->{$ym}->{ddat}->{$dd});
      }
    }
    if(exists($locdata->{LML}->{$kind}->{$ym}->{mdat})) {
      push(@files,$locdata->{LML}->{$kind}->{$ym}->{mdat});
    }
    if(exists($locdata->{LML}->{$kind}->{$ym}->{tar})) {
      foreach my $dd (sort(keys(%{$locdata->{LML}->{$kind}->{$ym}->{tar}}))) {
        push(@files,$locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd});
      }
    }
    
    if( (scalar @files) > 0) {
      if(!exists($locdata->{LML}->{$kind}->{$ym}->{mtar})) {
        my $tarfile=sprintf("LML_%s.tar",$ym);
        my $cmd=sprintf("(cd %s; tar cvf %s %s)",$info->{loc}->{$kind},$tarfile,join(" ",@files));
        push(@commands,$cmd);
        printf("$0: [LML]  month %5s create tar file %s)\n",$ym,$tarfile);
      }
    }
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

sub check_remote_LML_files {
  my($info,$kind,$fs)=@_;
  my @commands;
  
  # check remote tar directory
  my $dir=$info->{$fs}->{$kind};
  my $remotedata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    if($file=~/LML_(\d\d_\d\d).tar/) {
      my($ym)=($1);
      $remotedata->{LMLtar}->{$kind}->{$ym}=$file;
    }
  }
  closedir($dh);

  return($remotedata);
}

sub print_stat_LML_tar_files {
  my($info,$locdata,$kind,$remotedata)=@_;
  printf("$0: [LML] \n");
  printf("$0: [LML] Statistics LML tar files (kind=$kind, currentmonth=$info->{currentmonth})\n");
  foreach my $ym (sort(keys(%{$locdata->{LML}->{$kind}}))) {
    next if(!exists($locdata->{LML}->{$kind}->{$ym}->{mtar}));
    
    printf("$0: [LML]  month %5s found %s\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{mtar});
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{LMLtar}->{$kind}->{$ym})) {
        printf("$0: [LML]     file exists on fs %s\n",$fs);
      } else {
        printf("$0: [LML]     file NOT exists on fs %s\n",$fs);
      }
    }
  }
}

sub check_cp_tar_LML_files {
  my($info,$locdata,$kind,$remotedata)=@_;
  
  my @commands;
  my $num_files_to_remove=0;

  # check required actions
  printf("$0: [LML] \n");
  printf("$0: [LML] CHECK and COPY tar LML files (currentmonth $info->{currentmonth} kind=$kind)\n");
  foreach my $ym (sort(keys(%{$locdata->{LML}->{$kind}}))) {
    next if(!exists($locdata->{LML}->{$kind}->{$ym}->{mtar}));
    next if($ym eq $info->{currentmonth}); # not for current month files
    
    printf("$0: [LML]  month %5s found %s\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{mtar});
    my $count_remote=0;
    for my $fs ("arch","data") {
      if(exists($remotedata->{$fs}->{LMLtar}->{$kind}->{$ym})) {
        printf("$0: [LML]  month %5s file exist on fs %s\n",$ym,$fs);
        $count_remote++;
      } else {
        my $cmd=sprintf("(cd %s; cp -p %s %s/)",$info->{loc}->{$kind},$locdata->{LML}->{$kind}->{$ym}->{mtar},$info->{$fs}->{$kind});
        push(@commands,$cmd);
        printf("$0: [LML]  month %5s cp tar file %s to fs %s)\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{mtar},$fs);
      }
      if($count_remote==2) {
        # check file size
        my($Lsize,$Lmtime)=&get_file_info($info->{loc}->{$kind}."/".$locdata->{LML}->{$kind}->{$ym}->{mtar});
        my($Asize,$Amtime)=&get_file_info($info->{arch}->{$kind}."/".$locdata->{LML}->{$kind}->{$ym}->{mtar});
        my($Dsize,$Dmtime)=&get_file_info($info->{data}->{$kind}."/".$locdata->{LML}->{$kind}->{$ym}->{mtar});
        printf("$0: [LML]  month %5s consistency check, Size (L/A/D): %d=%d=%d Mtime (L/A/D): %d=%d=%d\n",$ym,$Lsize,$Asize,$Dsize,$Lmtime,$Amtime,$Dmtime);

        if ( ($Lsize==$Asize) &&  ($Lsize==$Dsize) && ($Lmtime<=$Amtime) &&  ($Lmtime<=$Dmtime) ) {
          printf("$0: [LML]  month %5s consistency check, files are identical\n",$ym);
          
          if( $Lmtime < ($info->{nowts}-48*3600) ) {
            if($info->{opt}->{remove}) {
              if($num_files_to_remove<$info->{opt}->{maxremove}) {
                my $mtarfile=sprintf("LML_%s.tar",$ym);
                my @tarfiles=values(%{$locdata->{LML}->{$kind}->{$ym}->{tar}});
                my @datfiles=values(%{$locdata->{LML}->{$kind}->{$ym}->{ddat}});
                if(exists($locdata->{LML}->{$kind}->{$ym}->{mdat})) {
                  push(@datfiles,$locdata->{LML}->{$kind}->{$ym}->{mdat});
                }
                my $cmd=sprintf("(cd %s; rm %s %s %s)",$info->{loc}->{$kind},
                                  $mtarfile,
                                  join(" ",@tarfiles),
                                  join(" ",@datfiles)
                                );
                push(@commands,$cmd);
                printf("$0: [LML]  month %5s remove now local tar files and local daily tar file\n",$ym);
                $num_files_to_remove++;
              } else {
                printf("$0: [LML]  month %5s remove now local tar files and local daily tar file (max limit reached $num_files_to_remove>=$info->{opt}->{maxremove}, skipping)\n",$ym);
              }
            } else {
              printf("$0: [LML]  month %5s remove now local tar files and local daily tar file (disabled, please use option --remove)\n",$ym);
            }
          } else {
            printf("$0: [LML]  month %5s consistency check, but files exists not more 2 days on remote file systems\n",$ym);
          }
        } else {
          printf("$0: [LML]  month %5s consistency check FAILED, size of files different PLEASE CHECK!!!\n",$ym);
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


sub check_remote_LML_current_files {
  my($info,$kind,$fs)=@_;
  my @commands;
  
  # check remote current tar directory
  my $dir=$info->{$fs}->{$kind}. "/current";
  my $remotedata;
  opendir(my $dh, $dir) || die "Can't open $dir: $!";
  while (my $file = readdir $dh) {
    if($file=~/LML_data_(\d\d_\d\d)_(\d\d).tar/) {
      my($ym,$dd)=($1,$2);
      $remotedata->{LMLcurrenttar}->{$kind}->{$ym}->{$dd}=$file;
    }
    if($file=~/(\d\d_\d\d)_(\d\d).dat/) {
      my($ym,$dd)=($1,$2);
      $remotedata->{LMLcurrentdat}->{$kind}->{$ym}->{$dd}=$file;
    }
  }
  closedir($dh);

  return($remotedata);
}


sub print_stat_LML_tar_current_files {
  my($info,$locdata,$kind,$remotedata)=@_;
  printf("$0: [LML] \n");
  printf("$0: [LML] Statistics LML current tar files (kind=$kind, currentmonth=$info->{currentmonth})\n");
  my $ym=$info->{currentmonth};
  foreach my $dd (sort(keys(%{$locdata->{LML}->{$kind}->{$ym}->{tar}}))) {
    printf("$0: [LML]   %5s current file found %s\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd});
    if(exists($remotedata->{LMLcurrenttar}->{$kind}->{$ym}->{$dd})) {
      printf("$0: [LML]     file exists on remote current dir\n");
    } else {
      printf("$0: [LML]     file NOT exists on remote current dir\n");
    }
  }
}

sub check_cp_tar_LML_current_files {
  my($info,$locdata,$kind,$remotedata,$fs)=@_;
  my @commands;
  my $num_files_to_remove=0;

  # check required actions
  printf("$0: [LML] \n");
  printf("$0: [LML] CHECK and COPY tar LML files (currentmonth $info->{currentmonth})\n");
  my $ym=$info->{currentmonth};
  foreach my $dd (sort(keys(%{$locdata->{LML}->{$kind}->{$ym}->{tar}}))) {
    next if($dd == $info->{currentday});
    
    printf("$0: [LML]  currentmonth %5s found %s\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd});
    my $count_remote=0;
    if(exists($remotedata->{LMLcurrenttar}->{$kind}->{$ym}->{$dd})) {
      $count_remote++;
    } else {
      my $cmd=sprintf("(cd %s; cp -p %s %s/current/)",$info->{loc}->{$kind},
                      $locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd},
                      $info->{$fs}->{$kind});
      push(@commands,$cmd);
      printf("$0: [LML]  month %5s cp tar file %s to fs %s)\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{tar}->{$dd},$fs);
    }
    if(exists($remotedata->{LMLcurrentdat}->{$kind}->{$ym}->{$dd})) {
      $count_remote++;
    } else {
      my $cmd=sprintf("(cd %s; cp -p %s %s/current/)",$info->{loc}->{$kind},
                      $locdata->{LML}->{$kind}->{$ym}->{ddat}->{$dd},
                      $info->{$fs}->{$kind});
      push(@commands,$cmd);
      printf("$0: [LML]  month %5s cp dat file %s to fs %s)\n",$ym,$locdata->{LML}->{$kind}->{$ym}->{ddat}->{$dd},$fs);
    }
  }

  # remove current files from recent month
  foreach my $ym (sort(keys(%{$remotedata->{LMLcurrenttar}->{$kind}}))) {
    next if($ym eq $info->{currentmonth}); # not for current month files

    if(exists($remotedata->{"arch"}->{LMLtar}->{$kind}->{$ym})) {
      if($info->{opt}->{remove}) {
        if($num_files_to_remove<$info->{opt}->{maxremove}) {
          my @files=values(%{$remotedata->{LMLcurrenttar}->{$kind}->{$ym}});
          my $cmd=sprintf("(cd %s/current/; rm %s)",$info->{$fs}->{$kind},
                            join(" ",@files)
                          );
          push(@commands,$cmd);
          printf("$0: [LML]  month %5s now old remote current files\n",$ym);
          $num_files_to_remove++;
        } else {
          printf("$0: [LML]  month %5s remove now old remote current files (max limit reached $num_files_to_remove>=$info->{opt}->{maxremove}, skipping)\n",$ym);
        }
      } else {
        printf("$0: [LML]  month %5s remove now old remote current files (disabled, please use option --remove)\n",$ym);
      }
    } else {
      printf("$0: [LML]  month %5s remote mothly tar file does not exists, skipping\n",$ym);
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