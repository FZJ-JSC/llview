# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

#!/usr/bin/perl -w
use strict;
use Carp;
use Time::HiRes qw ( time );
use Time::Local;
use POSIX qw(strftime);
use Parallel::ForkManager;

use FindBin;
use lib "$FindBin::RealBin";

my $patint="([\\+\\-\\d]+)";    # Pattern for Integer number
my $patfp ="([\\+\\-\\d.Ee]+)"; # Pattern for Floating Point number
my $patwrd="([\^\\s]+)";        # Pattern for Work (all noblank characters)
my $patnint="[\\+\\-\\d]+";     # Pattern for Integer number, no () 
my $patnfp ="[\\+\\-\\d.Ee]+";  # Pattern for Floating Point number, no () 
my $patnwrd="[\^\\s]+";         # Pattern for Work (all noblank characters), no () 
my $patbl ="\\s+";              # Pattern for blank space (variable length)

use Getopt::Long qw(:config no_ignore_case);
use Data::Dumper;
use archive_data_LML;
use archive_data_DB;
use archive_data_jobreport;

my $opt_verbose=1;
my $opt_dry=0;
my $opt_remove=0;
my $opt_maxpar=8;
my $opt_maxcompress=16;
my $opt_maxremove=4;
#my $opt_system="JUWELS_BOOSTER_DEMO";
my $opt_system="unknown";

usage($0) if( ! GetOptions( 
                            'verbose'            => \$opt_verbose,
                            'dry'                => \$opt_dry,
                            'remove'             => \$opt_remove,
                            'system=s'           => \$opt_system,
                            'maxpar=i'           => \$opt_maxpar,
                            'maxcompress=i'      => \$opt_maxcompress,
                            'maxremove=i'        => \$opt_maxremove,
                            ) );
my $date=`date`;
chomp($date);
my $fdate=`date +%y_%m_%d`;
chomp($fdate);

my $nowts=time();
my $currentweek=&sec_to_date_week_fn($nowts);
my $currentmonth=&sec_to_date_month_fn($nowts);
my $currentday=&sec_to_date_day_fn($nowts);

my $info;

$info->{opt}->{maxpar}=$opt_maxpar;
$info->{opt}->{maxcompress}=$opt_maxcompress;
$info->{opt}->{maxremove}=$opt_maxremove;
$info->{opt}->{remove}=$opt_remove;
$info->{currentmonth}=$currentmonth;
$info->{currentweek}=$currentweek;
$info->{currentday}=$currentday;
$info->{nowts}=$nowts;

for my $loc ("loc", "arch", "data") {
  for my $kind ("db", "LMLall", "LML_llgen", "jobreport") {
    my $envvar=sprintf("LLVIEW_ARCHIVER_%s_%s",uc($loc),uc($kind));
    if(exists($ENV{$envvar})) {
      $info->{$loc}->{$kind} = $ENV{$envvar};
    } else {
      printf( "$0: ERROR: env var $envvar not defined, please set, ... exiting\n");
      exit;
    }
  }
}

my $signalfilename=sprintf("%s/.archive_data_%s.pid",$ENV{HOME},$opt_system);

if (-f "$signalfilename") {
  open(RUNNING,"< $signalfilename");
  my $pid = <RUNNING>;
  close(RUNNING);
  chomp($pid);
  if (-d "/proc/$pid") {
    printf( "$0: another archive_data.pl process is running... exiting, please remove $signalfilename\n");
    exit(1);
  } else {
    unlink("$signalfilename") or die "$0: Can't delete $signalfilename: $!\n";
    printf( "$0: process ID $pid is not running. $signalfilename was automatically removed\n");
  }
} else {
  # touch RUNNING stamp
  open(RUNNING,"> $signalfilename");
  print RUNNING "$$\n";
  close(RUNNING);
}

print "$0: started at $date --> $fdate\n";
print "$0: -verbose      = $opt_verbose\n"; 
print "$0: -dry          = $opt_dry\n"; 
print "$0: -remove       = $opt_remove\n"; 
print "$0: -system       = $opt_system\n"; 
print "$0: -maxpar       = $opt_maxpar\n"; 
print "$0: -maxcompress  = $opt_maxcompress\n"; 
print "$0: -maxremove    = $opt_maxremove\n"; 

#======================================
# DB files
#======================================
if(1) {
  my $locdbdata=&check_db_files($info); 
  &print_stat_db_files($info,$locdbdata);
  
  &check_compress_db_files($info,$locdbdata);
  
  $locdbdata=&check_db_files($info); 
  &print_stat_db_files($info,$locdbdata);
  
  &check_tar_db_files($info,$locdbdata);
  
  $locdbdata=&check_db_files($info); 
  &print_stat_db_files($info,$locdbdata);
  
  my $remotedata;
  for my $fs ("arch","data") {
    $remotedata->{$fs}=&check_remote_db_files($info,$fs);
  }
  
  &print_stat_db_tar_files($info,$locdbdata,$remotedata);
  &check_cp_tar_db_files($info,$locdbdata,$remotedata);
}

#======================================
# LML files
#======================================
if(1) {
  for my $kind ("LMLall","LML_llgen") {
    my $locLMLdata=&check_LML_files($info,$kind); 
    &print_stat_LML_files($info,$kind,$locLMLdata);
    &check_tar_LML_files($info,$kind,$locLMLdata);

    my $remotedata;
    for my $fs ("arch","data") {
      $remotedata->{$fs}=&check_remote_LML_files($info,$kind,$fs);
    }
    &print_stat_LML_tar_files($info,$locLMLdata,$kind,$remotedata);
    &check_cp_tar_LML_files($info,$locLMLdata,$kind,$remotedata);

    my $remotecurrent=&check_remote_LML_current_files($info,$kind,"data");
    &print_stat_LML_tar_current_files($info,$locLMLdata,$kind,$remotecurrent);
    &check_cp_tar_LML_current_files($info,$locLMLdata,$kind,$remotecurrent,"data");
  }
}

#======================================
# Jobreport files
#======================================
if(1) {
  my $locjobdata=&check_jobreport_files($info); 
  &print_stat_jobreport_files($info,$locjobdata);
  
  &check_tar_jobreport_files($info,$locjobdata);

  &check_remove_jobreport_dirs($info,$locjobdata);

  $locjobdata=&check_jobreport_files($info); 
  &print_stat_jobreport_files($info,$locjobdata);
  
  &check_tar_monthly_jobreport_files($info,$locjobdata);

  $locjobdata=&check_jobreport_files($info); 
  &print_stat_jobreport_files($info,$locjobdata);
  
  my $remotedata;
  for my $fs ("arch","data") {
    $remotedata->{$fs}=&check_remote_jobreport_files($info,$fs);
  }
  
  $locjobdata=&check_jobreport_files($info); 
  &print_stat_jobreport_tar_files($info,$locjobdata,$remotedata);
  &check_cp_tar_jobreport_files($info,$locjobdata,$remotedata);
}

unlink("$signalfilename");
print "$0: ended at $date --> $fdate\n";

sub get_file_info {
  my($file)=@_;
  my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size, $atime,$mtime,$ctime,$blksize,$blocks) = stat($file);
  return($size,$mtime);
}

sub mysystem {
  my($call)=@_;
  printf("  --> exec: START  %s %s\n",$call,($opt_dry?"DRY-RUN":"")) if($opt_verbose);
  system($call) if(!$opt_dry);
  printf("      exev: rc=%3d %s \n",$?,$call) if($opt_verbose);
  return($?)
}

sub sec_to_date_week_fn {
  my ($lsec)=@_;
  my($date);
  my @t=localtime($lsec);
  $date=strftime('%Y_w%U',@t);
  return($date);
}

sub sec_to_date_month_fn {
  my ($lsec)=@_;
  my($date);
  my @t=localtime($lsec);
  $date=strftime('%y_%m',@t);
  return($date);
}

sub sec_to_date_day_fn {
  my ($lsec)=@_;
  my($date);
  my @t=localtime($lsec);
  $date=strftime('%d',@t);
  return($date);
}

sub day_diff {
  my ($ym,$dd,$nowts)=@_;
  $ym=~/(\d\d\d\d)_(\d\d)/;
  my ($mon,$mday,$year,$hours,$min,$sec)=($2,$dd,$1,0,0,0);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  my $ddiff=($nowts-$timesec)/3600.0/24.0;
  # print "TMPDEB: day_diff $ym,$dd,$nowts -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec -> $ddiff\n";
  return($ddiff);
}

