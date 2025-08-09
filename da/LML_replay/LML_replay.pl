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

use strict 'vars';
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
use LLmonDB_config;
use YAML qw(DumpFile);

use LML_da_util qw ( substitute_recursive ) ;
use LML_replay_util;
use LML_replay_sync;
use LML_replay_initdb;
use LML_replay_simulate;


#####################################################################
# get command line parameter
#####################################################################

# option handling
my $opt_verbose=0;
my $opt_timings=0;
my $opt_dump=0;
my $opt_demo=0;
my $opt_maxproc=8;
my $opt_config=undef;
my $opt_systemname=undef;
my $opt_currentts=undef;
my $opt_currenttsfile=undef;
my $caller=$0;$caller=~s/^.*\/([^\/]+)$/$1/gs;
my $instname="[${caller}][PRIMARY]";
my $msg;
my $opt_steps="sync,simulate";
my $opt_nsteps=1;

usage($0) if( ! GetOptions( 
            'verbose'          => \$opt_verbose,
            'timings'          => \$opt_timings,
            'config=s'         => \$opt_config,
            'systemname=s'     => \$opt_systemname,
            'steps=s'          => \$opt_steps,
            'nsteps=i'         => \$opt_nsteps,
            'currentts=i'      => \$opt_currentts,
            'currenttsfile=s'  => \$opt_currenttsfile,
            'dump'             => \$opt_dump,
            'demo'             => \$opt_demo
            ) );

printf("$0: options:\n");
printf("  verbose:   %d\n",$opt_verbose);
printf("  config:    %s\n",$opt_config);
printf("  nsteps:    %d\n",$opt_nsteps);
printf("  steps:     %s\n",$opt_steps);
printf(" \n");


if (! exists($ENV{LLVIEW_DATA})) {
  $msg=sprintf("$instname please source rc file before call of this script (. llview_server_rc], exiting...\n"); logmsg($msg,\*STDERR);
  usage($0);
  exit;
}

if((!defined $opt_config)||(! -f $opt_config)) {
  $msg=sprintf("$instname Config file '$opt_config' does not exist, exiting...\n"); logmsg($msg,\*STDERR);
  usage($0);
  exit;
}

my $steps;
foreach my $step (split(/\s?,\s?/,$opt_steps))  {
    if($step !~ /(sync|initdb|updatedb|sim|simulate)/) {
	$msg=sprintf("$instname unknown step $step, exiting...\n"); logmsg($msg,\*STDERR);
	usage($0);
	exit;
    }
    $steps->{$step}=1;
}

my $config_obj=&read_config($opt_config, $opt_verbose);
if(!defined $config_obj) {
    $msg=sprintf("$instname Config file '$opt_config' could not be read, exiting...\n"); logmsg($msg,\*STDERR);
    usage($0);
    exit;
}

my $configdata=$config_obj->get_contents();

# apply env vars to config 
my $subvars;
for my $v ( qw ( LLVIEW_HOME LLVIEW_DATA LLVIEW_SYSTEMNAME LLVIEW_CONF ) ) {
    $subvars->{$v}=$ENV{$v};
}

&substitute_recursive($configdata,$subvars);


my $okay=&check_update_config($configdata, $opt_verbose);
exit if (!$okay);

#print Dumper($configdata) if($opt_dump);

&check_dirs($configdata,$opt_verbose);

my $replay_status=&read_or_init_replay_status($configdata,$opt_verbose);
#print Dumper($replay_status);


if(exists $steps->{"sync"}) {
    printf("\n");
    printf("STEP: sync\n");
    &sync_LML_files($configdata,$replay_status,$opt_verbose);
}

if(exists $steps->{"initdb"}) {
    printf("\n");
    printf("STEP: initdb\n");
    &init_db($configdata,$replay_status,$opt_verbose);
}
if(exists $steps->{"updatedb"}) {
    printf("\n");
    printf("STEP: updatedb\n");
    &update_db($configdata,$replay_status,$opt_verbose);
}


if((exists $steps->{"sim"}) || ((exists $steps->{"simulate"}))) {
    printf("\n");
    printf("STEP: simulate\n");
    &simulate($configdata,$replay_status,$opt_nsteps,$opt_verbose);
}


my $status_file=$configdata->{"LML_replay"}->{"config"}->{"status_file"};
YAML::DumpFile($status_file,$replay_status);


sub usage {
  die "Usage: . llview_server_rc; $_[0] <options>
                --config <file>                  : YAML config file
		--steps <step1, step2, ...>      : execution of one or more steps, valid steps are
                                                   sync, initdb, updatedb, sim[ulate]
		--nsteps <n>  			 : run simulation with <i> update steps, default 1	   
                --currentts <ts>                 : current timestamp (if running in replay mode) 
                --currenttsfile <file>           : file containng current timestamp (if running in replay mode) 
                --timings                        : print additional timing info
                --verbose                        : verbose
";
}
