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
use lib "$FindBin::RealBin/../LLmonDB";
use LLmonDB;
use LL_jobreport;
use LML_da_util qw ( sec_to_date );

my $caller=$0;$caller=~s/^.*\/([^\/]+)$/$1/gs;
my $instname="[${caller}][PRIMARY]";

#####################################################################
# get command line parameter
#####################################################################

# option handling
my $opt_verbose=0;
my $opt_timings=0;
my $opt_dump=0;
my $opt_demo=0;
my $opt_only_system=0;
my $opt_config=undef;
my $opt_dbdir=undef;
my $opt_updateconfig=0;
my $opt_archdir=undef;
my $opt_outdir=undef;
my $opt_tmpdir=undef;
my $opt_dblist=undef;
my $opt_journalonly=0;
my $opt_journaldir=undef;
my $opt_currentts=undef;
my $opt_currenttsfile=undef;
my $opt_systemname=undef;
my $opt_solvestat=0;
my $opt_statstat=0;
my $opt_migratestat=0;
my $opt_force=0;
my $opt_changedfileslog="changedfiles.log";

usage($0) if( ! GetOptions( 
                'verbose'          => \$opt_verbose,
                'timings'          => \$opt_timings,
                'config=s'         => \$opt_config,
                'updateconfig!'    => \$opt_updateconfig,
                'archdir=s'        => \$opt_archdir,
                'dblist=s'         => \$opt_dblist,
                'dbdir=s'          => \$opt_dbdir,
                'outdir=s'         => \$opt_outdir,
                'tmpdir=s'         => \$opt_tmpdir,
                'solvestat'        => \$opt_solvestat,
                'statstat'         => \$opt_statstat,
                'migratestat'      => \$opt_migratestat,
                'force'            => \$opt_force,
                'journalonly'      => \$opt_journalonly,
                'journaldir=s'     => \$opt_journaldir,
                'systemname=s'     => \$opt_systemname,
                'currentts=i'      => \$opt_currentts,
                'currenttsfile=s'  => \$opt_currenttsfile,
                'dump'             => \$opt_dump,
                'demo'             => \$opt_demo,
                'changedfilelog=s' => \$opt_changedfileslog,
                ) );


if(! -f $opt_config) {
  print STDERR "$instname Config-file $opt_config does not exist, leaving...\n";
  usage($0);
  exit;
}

my $currentts=time();
if (defined($opt_currenttsfile)) {
  if(-f $opt_currenttsfile) {
  open(IN,$opt_currenttsfile) or die "$instname Cannot open $opt_currenttsfile";
  $currentts=<IN>;chomp($currentts);
  close(IN);
  }
  
} elsif(defined($opt_currentts)) {
  $currentts=$opt_currentts;
}

if ($opt_verbose) {
  printf("%s Parameters:\n",$instname);
  printf("%s  verbose            = %d\n",$instname,$opt_verbose);
  printf("%s  demo               = %d\n",$instname,$opt_demo);
  printf("%s  config             = %s\n",$instname,$opt_config);
  printf("%s  db-dir             = %s\n",$instname,$opt_dbdir);
  printf("%s  outdir             = %s\n",$instname,$opt_outdir);
  printf("%s  solvestat          = %s\n",$instname,$opt_solvestat);
  printf("%s  tmpdir             = %s\n",$instname,$opt_tmpdir);
  printf("%s  archdir            = %s\n",$instname,$opt_archdir);
  printf("%s  journalonly        = %s\n",$instname,$opt_journalonly);
  printf("%s  journaldir         = %s\n",$instname,$opt_journaldir) if(defined($opt_journaldir));; 
  printf("%s  systemname         = %s\n",$instname,$opt_systemname);
  printf("%s  opt_currentts      = %s\n",$instname,$opt_currentts) if(defined($opt_currentts));
  printf("%s  opt_currenttsfile  = %s\n",$instname,$opt_currenttsfile) if(defined($opt_currenttsfile));
  printf("%s  currenttime        = %s\n",$instname,&sec_to_date($currentts));
  printf("%s  opt_changedfileslog= %s\n",$instname,$opt_changedfileslog) if(defined($opt_changedfileslog));
}

# set umask
umask 0022;

my $jobreport=LML_jobreport->new($opt_verbose,$instname,$caller,$opt_outdir,$opt_updateconfig,$currentts,$opt_systemname);

my $DB;
my $starttime=time();
$DB = LLmonDB->new($opt_config,$opt_dbdir,$opt_archdir,$opt_verbose,$opt_systemname);
$DB->init();
$jobreport->update_global_vars_in_config($DB,$opt_outdir,$opt_archdir);  

printf("%s open DB                                         in %7.4fs\n",$instname,time()-$starttime);

my $done=0;
if($opt_solvestat) {
    $starttime=time();
    $jobreport->solve_datasets($DB,$opt_force);  
    printf("%s solve datasets                                  in %7.4fs\n",$jobreport->{INSTNAME},time()-$starttime);
    $done=1;
}

if($opt_statstat) {
    $starttime=time();
    $jobreport->stat_datasets($DB,$opt_force);  
    printf("%s stat datasets                                  in %7.4fs\n",$jobreport->{INSTNAME},time()-$starttime);
    $done=1;
}

if(!$done) {
    $starttime=time();
    $jobreport->mngt_datasets($DB,$opt_journalonly,$opt_journaldir);  
    printf("%s managed datasets                                in %7.4fs\n",$jobreport->{INSTNAME},time()-$starttime);

    $starttime=time();
    my($changed_files)=$jobreport->mngt_scan_datasets($DB,$opt_journalonly,$opt_journaldir);  
    printf("%s scan  datasets                                   in %7.4fs\n",$jobreport->{INSTNAME},time()-$starttime);

    $starttime=time();
    open(OUT,"> $opt_changedfileslog") or die "cannot open $opt_changedfileslog";
    foreach my $dataset (sort(keys(%{$changed_files}))) {
	print OUT "$dataset\n";
    }
    close(OUT);
    printf("%s wrote changed files log                          in %7.4fs (%s)\n",$jobreport->{INSTNAME},time()-$starttime,$opt_changedfileslog);
}

  
$DB->close();  

sub usage {
  die "Usage: $_[0] <options> <filenames> 
                -config <file>           : YAML config file
                -verbose                 : verbose
";
}
