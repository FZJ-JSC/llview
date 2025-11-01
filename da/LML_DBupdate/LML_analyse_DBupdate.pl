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
use Getopt::Long;
use Data::Dumper;

use FindBin;
use lib "$FindBin::RealBin/";
use lib "$FindBin::RealBin/../lib";

my $patint="([\\+\\-\\d]+)";   # Pattern for Integer number
my $patintk="([\\+\\-\\d,]+)";   # Pattern for Integer number, with ','
my $patfp ="([\\+\\-\\d.E]+)"; # Pattern for Floating Point number
my $patwrd="([\^\\s]+)";       # Pattern for Work (all noblank characters)
my $patbl ="\\s+";             # Pattern for blank space (variable length)

#####################################################################
# get user info / check system 
#####################################################################
my $UserID = getpwuid($<);
my $Hostname = `hostname`;
my $verbose=1;
my ($filename);
my $caller=$0;$caller=~s/^.*\/([^\/]+)$/$1/gs;

#####################################################################
# get command line parameter
#####################################################################

# option handling
my $opt_infile="./tmp/steplogs/LMLDBupdate_last.log";
my $opt_outfile="./tmp/LMLDBupdate_stat_LML.xml";
my $opt_cntfile="./perm/stepcounter.dat";
my $opt_name="default";
my $opt_verbose=0;
my $opt_timings=0;
my $opt_dump=0;
usage($0) if( ! GetOptions( 
              'verbose'          => \$opt_verbose,
              'infile=s'         => \$opt_infile,
              'outfile=s'        => \$opt_outfile,
              'cntfile=s'        => \$opt_cntfile,
              'name=s'           => \$opt_name,
              ) );

my $current_cnt=0;
if (-f $opt_cntfile ) {
  $current_cnt=`cat $opt_cntfile`;
}

if($opt_verbose) {
  printf("infile   = %s\n",$opt_infile);
  printf("outfile  = %s\n",$opt_outfile);
  printf("cntfile  = %s (%d)\n",$opt_cntfile,$current_cnt);
  printf("name     = %s\n",$opt_name);
}

my $stat;
my $dbts;
my $dbnr;
my $dblist;
my($starttime,$endtime)=(-1,-1);
open(IN, $opt_infile) or die "[${caller}] Cannot open $opt_infile";
while(my $line=<IN>) {
  if($line=~/\[LML_DBupdate.pl\]\[PRIMARY\s*\]\s*starttime_ts $patint/) {
    $starttime=$1;
  }
  if($line=~/\[LML_DBupdate.pl\]\[PRIMARY\s*\]\s*endtime_ts $patint/) {
    $endtime=$1;
  }
  if($line=~/\[LML_DBupdate.pl\]\[PRIMARY\s*\]\s+$patwrd\s+in \s*$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\)/) {
    my($a,$b,$c,$d,$e,$f)=($1,$2,$3,$4,$5,$6);
    # print "TMPDEB1: ($a,$b,$c,$d,$e,$f)\n";
    my $name=sprintf("%s",$a);
    $stat->{$name}->{start}=$c;
    $stat->{$name}->{end}=$d;
    $stat->{$name}->{startgroupnum}=$e;
    $stat->{$name}->{nr}=$f;
    $stat->{$name}->{level}=0;
  }
  if($line=~/\[LML_DBupdate.pl\]\[$patwrd\s*\]\s+LLmonDB: DB \s*$patwrd\s* ready in\s+$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\)/) {
    my($a,$b,$c,$d,$e,$f,$g)=($1,$2,$3,$4,$5,$6,$7);
    my $name=sprintf("%s",lc($a));
    $stat->{$name}->{start}=$d;
    $stat->{$name}->{end}=$e;
    $stat->{$name}->{startgroupnum}=$f;
    $stat->{$name}->{nr}=$g;
    # print "TMPDEB2: ($a,$b,$c,$d,$e,$f,$g)\n";
    foreach my $k (keys(%{$dblist->{$a}})) {
      $dblist->{$a}->{$k}->{start}+=$d;
      $dblist->{$a}->{$k}->{end}+=$d;
    }
    
  }
  if($line=~/\[LML_DBupdate.pl\]\[$patwrd\s*\]\s+LLmonDB:\s+(trg_upd\.|upd\.|add\.)\s+$patint\s+entries (in|to) table\s+$patwrd\/$patwrd\s+in\s+$patfp[s]/) {
    my($a,$b,$c,$d,$e,$f,$g)=($1,$2,$3,$4,$5,$6,$7);
    my $name=sprintf("_%s_%s",lc($a),lc($f));
    if(exists($dbts->{$a})) {
      $stat->{$name}->{start}=$dbts->{$a};
    } else {
      $stat->{$name}->{start}=0;
    }
    $stat->{$name}->{end}=$stat->{$name}->{start}+$g;
    $dbts->{$b}=$stat->{$name}->{end};
    $stat->{$name}->{startgroupnum}=3;
    $stat->{$name}->{nr}=$dbnr->{$a}++;
    $stat->{$name}->{cmplx}=$c;

    $dblist->{$a}->{$name}=$stat->{$name};
    # print "TMPDEB3: ($a,$b,$c,$d,$e,$f,$g) -> $stat->{$name}->{start}, $stat->{$name}->{end} $stat->{$name}->{startgroupnum} $stat->{$name}->{nr}\n";
  }
  if($line=~/\[LML_DBupdate.pl\]\[$patwrd\s*\]\s+LLmonDB:\s+$patwrd\.\s*$patint entries.*in\s+$patfp[s]/) {
    my($a,$b,$c,$d)=($1,$2,$3,$4);
    my $name=sprintf("%s",lc($a));
    $stat->{$name}->{cmplx}+=$c;
  }
}
close(IN);
#print Dumper($stat);
#exit;

&write_steptimings_lml($opt_outfile,$opt_name,$starttime,$endtime,$stat);

# handle also stdout/stderr 
sub write_steptimings_lml {
  my($filename,$wf_name,$starttime,$endtime,$steprefs)=@_;
  my($count,%stepnr,$step);

  print "write_steptimings_lml($filename,$wf_name,$starttime,$endtime,$steprefs)\n";
  
  open(OUT,"> $filename") || die "cannot open file $filename";
  printf(OUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  printf(OUT "<lml:lgui xmlns:lml=\"http://eclipse.org/ptp/lml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n");
  printf(OUT "	xsi:schemaLocation=\"http://eclipse.org/ptp/lml lgui.xsd\"\n");
  printf(OUT "	version=\"0.7\"\>\n");
  printf(OUT "<objects>\n");
  $count=0;
  foreach $step (sort {$steprefs->{$a}->{start} <=> $steprefs->{$b}->{start}} (keys(%{$steprefs}))) {
    $count++;$stepnr{$step}=$count;
    printf(OUT "<object id=\"fb%06d\" name=\"%s\" type=\"steptime\"/>\n",$count,$step);
  }

  printf(OUT "</objects>\n");
  printf(OUT "<information>\n");

  foreach $step (sort {$steprefs->{$a}->{start} <=> $steprefs->{$b}->{start}} (keys(%{$steprefs}))) {
    printf(OUT "<info oid=\"fb%06d\" type=\"short\">\n",$stepnr{$step});
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_name\"", $wf_name);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"name\"", $step);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"wf_startts\"", $starttime);
    printf(OUT " <data %-20s value=\"%s\"/>\n","key=\"nr\"", $stepnr{$step});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"start_ts\"", $steprefs->{$step}->{start});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"end_ts\"", $steprefs->{$step}->{end});
    printf(OUT " <data %-20s value=\"%.6f\"/>\n","key=\"dt\"", $steprefs->{$step}->{end} - $steprefs->{$step}->{start});
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"cmplx\"", (defined($steprefs->{$step}->{cmplx}))?$steprefs->{$step}->{cmplx}:0);
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"group\"", $steprefs->{$step}->{startgroupnum});
    printf(OUT " <data %-20s value=\"%d\"/>\n","key=\"wf_cnt\"", $current_cnt);
    printf(OUT "</info>\n");
  }
  
  printf(OUT "</information>\n");
  printf(OUT "</lml:lgui>\n");
  close(OUT);
}

sub modint {
  my($number)=@_;
  $number=~s/\,//gs;
  return($number);
}

sub usage {
    die "Usage: $_[0] <options> <filenames> 
                -verbose                 : verbose
                -infile <file>           : input filename (transferlog)
                -outfile <file>          : LML output filename

";
}
