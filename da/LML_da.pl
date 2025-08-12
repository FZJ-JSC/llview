#!/usr/bin/perl -w
# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

use Data::Dumper;
use Getopt::Long;
use Time::Local;
use Time::HiRes qw ( time );
# Use internal library
use FindBin;
use lib "$FindBin::RealBin/lib";
use LML_da_workflow_obj;
use LML_da_util qw( init_globalvar logmsg stacktrace check_folder );
use LML_da_step;
use LML_da_par_step;

use strict;
use warnings::unused;

my $version="1.1";
my $msg;

# time measurement
my ($tstart,$tdiff);

# option handling
my $opt_configfile="./LML_da_workflow.conf";
my $opt_verbose=0;
my $opt_dump=0;
my $opt_parallel=0;
my $opt_maxproc=8;
my $opt_do_stepfiles=1;
my $opt_sleepusec=1000000;
usage($0) if( ! GetOptions( 
              'verbose'          => \$opt_verbose,
              'configfile=s'     => \$opt_configfile,
              'stepfiles!'       => \$opt_do_stepfiles,
              'parallel!'        => \$opt_parallel,
              'maxprocesses=i'   => \$opt_maxproc,
              'sleepusec=i'      => \$opt_sleepusec,
              'dump'             => \$opt_dump
              ) );
my $date=`date`;
chomp($date);
my $date_=$date;$date_=~s/\s/_/gs;

my $hostname = `hostname`;
chomp($hostname);

my $confshort=$opt_configfile;$confshort=~s/.*\///gs;$confshort=~s/.conf$//gs;$confshort=~s/LML_da_//gs;

$msg=sprintf("%s\n","-"x90); logmsg($msg);
$msg=sprintf("  LML Data Access Workflow Manager $version, starting at ($date) [$confshort]\n"); logmsg($msg);

# read config file
$msg=$opt_verbose ? sprintf("$0: configfile=$opt_configfile\n") : ""; logmsg($msg);
$tstart=time;
my $workflow_obj = LML_da_workflow_obj->new($opt_verbose,0);
$workflow_obj->read_xml_fast($opt_configfile);
my $confxml=$workflow_obj->{DATA};
$tdiff=time-$tstart;
$msg=$opt_verbose ? sprintf("$0: parsing XML configfile in %6.4f sec\n",$tdiff) : ""; logmsg($msg);

# init global vars
my $vardefs=$confxml->{'vardefs'}->[0];
my $globalvarref;
my $pwd=`pwd`; chomp($pwd);
$globalvarref->{instdir} = $FindBin::RealBin;
$globalvarref->{pwd}     = $pwd;
$globalvarref->{permdir} = "./perm_default";
$globalvarref->{tmpdir}  = "./tmp_default";
$globalvarref->{logdir}  = "./log_default";
$globalvarref->{verbose} = $opt_verbose;
$globalvarref->{do_stepfiles} = $opt_do_stepfiles;
$globalvarref->{executehostpattern} = ".*";
$globalvarref->{date} = $date_;
$globalvarref->{sleepusec} = $opt_sleepusec;

# replace ENV vars 
foreach my $k (keys(%ENV)) {
    if($k=~/^LLVIEW_/) {
	$globalvarref->{$k} = $ENV{$k};
    }
}

# replacing default values with the ones read from configfile
init_globalvar($vardefs,$globalvarref); 

# substitute vars in steps
my $stepdefs=$confxml->{'step'};
#&LML_da_util::substitute_recursive($stepdefs,$globalvarref); 

if($opt_dump) {
  print STDERR Dumper($confxml);
  exit(1);
}

# check permament, temporary and log directories
my $permdir=$globalvarref->{permdir};
my $tmpdir=$globalvarref->{tmpdir};
my $logdir=$globalvarref->{logdir};
# Checking folders
&check_folder($permdir.'/');
&check_folder($tmpdir.'/');
&check_folder($logdir.'/');

# Getting filename to be used as a signal that the process is running
my $signalfilename="RUNNING";
$signalfilename=$globalvarref->{signalfilename} if exists($globalvarref->{signalfilename});

# check if another LML_da.pl is running via signal file
my $help=$globalvarref->{executehostpattern};
my $rc = 0;
if ($hostname !~/$help/) {
  $msg=sprintf("[LML_da.pl] LML_da.pl not desired to run on host $hostname (should match $help)\n"); logmsg($msg,\*STDERR);
} elsif (-f "$permdir/$signalfilename") {
  open(RUNNING,"< $permdir/$signalfilename");
  my $pid = <RUNNING>;
  close(RUNNING);
  chomp($pid);
  if (-d "/proc/$pid") {
    $msg=sprintf("[LML_da.pl] another LML_da.pl process may be running [PID: $pid]! Exiting, please remove $permdir/$signalfilename if error persists.\n"); logmsg($msg,\*STDERR);
    exit(1);
  } else {
    unlink("$permdir/$signalfilename") or &mydie("[LML_da.pl] Can't delete $permdir/$signalfilename: $!\n");
    $msg=sprintf("[LML_da.pl] LML_da.pl process ID $pid is not running. $permdir/$signalfilename was automatically removed\n"); logmsg($msg,\*STDERR);
  }
} else {
  # touch RUNNING stamp
  open(RUNNING,"> $permdir/$signalfilename");
  print RUNNING "$$\n";
  close(RUNNING);

  # processing steps
  my $stepobj=LML_da_step->new($stepdefs,$globalvarref);
  $rc = $stepobj->process() if(!$opt_parallel);
  $rc = $stepobj->parprocess($globalvarref,$opt_maxproc) if($opt_parallel);

  unlink("$permdir/$signalfilename");
  exit($rc) if ($rc);
}

$date=`date`;
chomp($date);
my $trun=sprintf("%4.2f",time()-$tstart);
$msg=sprintf("  LML Data Access Workflow Manager $version, ending at   ($date) [$confshort] after $trun sec\n"); logmsg($msg);

sub mydie {
  my ($message)=@_;
  unlink("$permdir/$signalfilename");
  die "$message".stacktrace();
}

sub usage {
  die "Usage: $_[0] <options> 
        -configfile <configfile> : configfile (default: ./LML_da_workflow.conf)
        -verbose                 : verbose mode to log more information
        -stepfiles               : activate stepfiles (default: true)
        -parallel                : activate parallel processing (default: false)
        -maxprocesses            : max number of processes when -parallel is used (default: 8)
        -dump                    : only dump configuration to stderr, does not run (default: false)

";
}
