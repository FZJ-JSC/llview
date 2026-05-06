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

use strict;
#use warnings::unused -global;
use Getopt::Long;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use FindBin;
use lib "$FindBin::RealBin/";
use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder logmsg );

use lib "$FindBin::RealBin/../LLmonDB";
use LLmonDB;

use LML_DBupdate_file;
use LML_DBupdate_CSV_file;

#####################################################################
# get command line parameter
#####################################################################

# option handling
my $opt_verbose=0;
my $opt_timings=0;
my $opt_dump=0;
my $opt_demo=0;
my $opt_only_system=0;
my $opt_maxproc=8;
my $opt_config=undef;
my $opt_dbdir=undef;
my $opt_systemname=undef;
my $opt_currentts=undef;
my $opt_currenttsfile=undef;
my $opt_updatealways=undef;
my $caller=$0;$caller=~s/^.*\/([^\/]+)$/$1/gs;
my $instname="[${caller}][PRIMARY]";
my $msg;

usage($0) if( ! GetOptions( 
            'verbose'          => \$opt_verbose,
            'timings'          => \$opt_timings,
            'config=s'         => \$opt_config,
            'dbdir=s'          => \$opt_dbdir,
            'maxprocesses=i'   => \$opt_maxproc,
            'systemname=s'     => \$opt_systemname,
            'currentts=i'      => \$opt_currentts,
            'currenttsfile=s'  => \$opt_currenttsfile,
            'updatealways=s'    => \$opt_updatealways,
            'dump'             => \$opt_dump,
            'demo'             => \$opt_demo
            ) );

if ($#ARGV < 0) {
  &usage($0);
}

if((!defined $opt_config)||(! -f $opt_config)) {
  $msg=sprintf("$instname Config file '$opt_config' does not exist, exiting...\n"); logmsg($msg,\*STDERR);
  usage($0);
  exit;
}

if ( ($opt_demo==1) || $ENV{"LML_DBUPDATE_DEMO"} || $ENV{"LLVIEW_DEMO_MODE"} ) {
  $opt_demo=1;
  $msg=sprintf("$instname DEMO MODE trigger found --> switching to DEMO mode...\n"); logmsg($msg);
}

my $currentts=time();
if (defined($opt_currenttsfile)) {
  if(-f $opt_currenttsfile) {
    open(IN,$opt_currenttsfile) or die "cannot open $opt_currenttsfile";
    $currentts=<IN>;chomp($currentts);
    close(IN);
  }
} elsif(defined($opt_currentts)) {
  $currentts=$opt_currentts;
}

my $DB;

my $starttime=time();
$msg=sprintf("%s starttime_ts %d\n",$instname,$starttime); logmsg($msg);

&check_folder($opt_dbdir.'/');

$DB = LLmonDB->new($opt_config,$opt_dbdir,undef,$opt_verbose,$opt_systemname,$currentts);
$DB->init();
my $fileobj=LML_DBupdate_file->new($opt_verbose, $opt_dbdir, $opt_demo);
my $endtime=time();
$msg=sprintf("%s openDB                                          in %7.4fs (ts=%.5f,%.5f,l=0,nr=1)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);
my ($count_lml,$count_csv)=(0,0);
$starttime=time();
foreach my $filename (@ARGV) {
  if (!-f $filename) {
    $msg=sprintf("$instname ERROR: File $filename does not exist!\n"); logmsg($msg,\*STDERR);
    next;
  }
  if($filename=~/\.csv(.xz)?$/) {
    $msg=$opt_verbose ? sprintf("$instname reading CSV file: $filename...\n") : ""; logmsg($msg);
    my $fstarttime=time();
    $fileobj->read_CSV($filename);
    printf("%s reading CSV input file (%-30s) in %7.4fs\n",$instname,$filename,time()-$fstarttime);
    $count_csv++;
  } else {
    $msg=$opt_verbose ? sprintf("$instname reading LML file: $filename...\n") : ""; logmsg($msg);
    my $fstarttime=time();
    $fileobj->read_LML($filename);
    printf("%s reading LML input file (%-30s) in %7.4fs\n",$instname,$filename,time()-$fstarttime);
    $count_lml++;
  }
}
$endtime=time();
$msg=sprintf("%s readingInput                                    in %7.4fs (ts=%.5f,%.5f,l=0,nr=2)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);

$starttime=time();
my $checklmldata=($count_lml>0);
my $LMLmon_input_data=$fileobj->get_data($checklmldata,$opt_updatealways);
$endtime=time();
$msg=sprintf("%s getdata                                         in %7.4fs (ts=%.5f,%.5f,l=0,nr=2)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);

if($opt_dump) {
    $starttime=time();
    &check_folder("./dump/");
    $fileobj->dump_entries_by_cap("./dump/");
    $endtime=time();
    $msg=sprintf("%s dumpdata                                        in %7.4fs (ts=%.5f,%.5f,l=0,nr=2)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);
}

$starttime=time();
$DB->process_LMLdata($LMLmon_input_data,$opt_maxproc);  
$endtime=time();
$msg=sprintf("%s processLML                                      in %7.4fs (ts=%.5f,%.5f,l=0,nr=3)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);

$starttime=time();
$DB->close();  
$endtime=time();
$msg=sprintf("%s closeDB                                         in %7.4fs (ts=%.5f,%.5f,l=0,nr=4)\n",$instname,$endtime-$starttime,$starttime,$endtime); logmsg($msg);
$msg=sprintf("%s endtime_ts %d\n",$instname,time()); logmsg($msg);

sub usage {
  die "Usage: $_[0] <options> <filenames> 
                --config <file>                  : YAML config file
                --updatealways <type, type, ...> : update DB of these type always (also if no data in input files) 
                --demo                           : run in demo mode (e.g. name mangling)
                --dbdir <dir>                    : directory containing database
                --systemname <name>              : name of monitored system
                --currentts <ts>                 : current timestamp (if running in replay mode) 
                --currenttsfile <file>           : file containng current timestamp (if running in replay mode) 
                --timings                        : print additional timing info
                --verbose                        : verbose
";
}
