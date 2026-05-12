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
#
# This script compares the modification time of $filename and $cmpfilename
# and copies the first to $destfilename when it is newer, or it copies
# $emptyfile when it is older

use strict;
use Time::HiRes qw ( time usleep );
use FindBin;
use Getopt::Long;
use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( sec_to_date );

my $opt_verbose=0;
my $opt_debug=0;
my $opt_lockfile = "lockfile.dat";
my $opt_timeout = 60;    # in seconds
my $opt_rejecttimeout  = 120;    # in seconds
my $opt_waitstep  = 200000;    # in u-seconds

my $current_ts=time();

usage($0) if( ! GetOptions( 
                'verbose'            => \$opt_verbose,
                'debug'              => \$opt_debug,
                'lockfile=s'         => \$opt_lockfile,
                'timeout=i'          => \$opt_timeout,
                'rejecttimeout=i'    => \$opt_rejecttimeout
                ) );

usage($0) if(scalar @ARGV !=1);

my $action  = $ARGV[0];  # 'set' 'release' 'clear'

printf("$0: [%s] lock %s ...\n",$opt_lockfile,$action);

#check state of lock file
my ($lock_ts,$lock_age)=(-1,-1);
if(-f $opt_lockfile) {
  $lock_ts=(stat($opt_lockfile))[9];
  $lock_age=$current_ts-$lock_ts;
  printf("$0: [%s] lock files exists age=%d sec\n",$opt_lockfile,$lock_age) if($opt_verbose);
}

if( lc($action) eq "set" ) {
  if($lock_age>$opt_rejecttimeout) {
  &remove_lockfile($opt_lockfile);
  printf("$0:    old lock file removed age=%ds > %ds\n",$lock_age,$opt_rejecttimeout) if($opt_verbose);
  }
  if($lock_age>0) {
  my $loopstarttime=time();
  printf("$0:    wait for lock has been removed max %ds\n",$opt_timeout) if($opt_verbose);
  while(1) {
    usleep(200000);
    my $waittime=(time()-$loopstarttime); 
    printf("$0:    wait %d us total wait time %5.2fs \n",$opt_waitstep,$waittime) if($opt_debug);
    if (!-f $opt_lockfile) {
    $lock_ts=-1; $lock_age=-1;
    last;
    }
    if ( $waittime > $opt_timeout ) {
    printf("$0:    timeout (%ds) reached, exiting\n",$opt_timeout) if($opt_verbose);
    exit(-1);
    }
  }
  }
  $current_ts=time();
  &create_lockfile($opt_lockfile,$current_ts);
  printf("$0:    lock created at %d (%s)\n",$current_ts,&sec_to_date($current_ts)) if($opt_verbose);
}

if( lc($action) eq "release" || lc($action) eq "clear" ) {
  if(-f $opt_lockfile) {
  $lock_ts=(stat($opt_lockfile))[9];
  $lock_age=$current_ts-$lock_ts;
  printf("$0: [%s] lock files exists age=%d sec\n",$opt_lockfile,$lock_age) if($opt_verbose);
  
  &remove_lockfile($opt_lockfile);
  printf("$0:    lock file removed\n") if($opt_verbose);
  } else {
  printf("$0:    no lock file found\n") if($opt_verbose);
  }
}

exit;

sub remove_lockfile {
  my($file)=@_;
  unlink($file);
}

sub create_lockfile {
  my($file,$current_ts)=@_;
  open(OUT, "> $file") or die "cannot open $file for writing";
  printf(OUT "%d (%s)\n",$current_ts,&sec_to_date($current_ts));
  close(OUT);
}


sub usage {
  die "Usage: $_[0] <options> [--] <action>
        -lockfile <file>           : lock filenam,e
        -rejecttimeout <sec>       : remove older lock if it is older than <sec>, default 120sec
        -timeout <sec>             : wait only for that time, after that time lock scripts return with error code
    -waitstep <usec>           : waittime in wait loop step (in us), default 200000us
        -verbose                   : verbose messages
        -debug                     : debug messages

    action: 'set', 'release', or 'clear'
";
}
