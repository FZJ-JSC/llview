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
my $opt_outfile_ascii="./tmp/LMLDBupdate_stat_ASCII.dat";
my $opt_cntfile="./perm/stepcounter.dat";
my $opt_name="default";
my $opt_verbose=0;
my $opt_timings=0;
my $opt_dump=0;
usage($0) if( ! GetOptions( 
              'verbose'          => \$opt_verbose,
              'infile=s'         => \$opt_infile,
              'outfile=s'        => \$opt_outfile,
              'outfileascii=s'   => \$opt_outfile_ascii,
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
    $stat->{$name}->{level}=0;
    # print "TMPDEB2: ($a,$b,$c,$d,$e,$f,$g)\n";
    foreach my $k (keys(%{$dblist->{$a}})) {
      $dblist->{$a}->{$k}->{topstart}=$d;
      $dblist->{$a}->{$k}->{topend}=$e;
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
    $dbts->{$a}=$stat->{$name}->{end};
    $stat->{$name}->{startgroupnum}=3;
    $stat->{$name}->{nr}=$dbnr->{$a}++;
    $stat->{$name}->{cmplx}=$c;
    $stat->{$name}->{level}=1;
    $stat->{$name}->{topname}=lc($a);

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

# define order
my $num=0;
foreach my $step ( sort {&my_sort($a,$b)} (keys(%{$stat}))) {
    next if($stat->{$step}->{level}>0);
    $num++;
    $stat->{$step}->{order}=$num*100;
    $stat->{$step}->{ordercnt}=$num*100;
}

foreach my $step ( sort {&my_sort($a,$b)} (keys(%{$stat}))) {
    if($stat->{$step}->{level}==1) {
	my $top=$stat->{$step}->{topname};
	$stat->{$top}->{ordercnt}++;
	$stat->{$step}->{order}=$stat->{$top}->{ordercnt}++;
    }
}

# A fallback mechanism ensures a valid workflow start time is established 
# even if the initial log line was corrupted or omitted by concurrent processes.
if ($starttime == -1) { # If the workflow start time is missing...
  
  # We temporarily use 'time()' (now) simply as an extremely high starting value 
  # to compare against. (Any historical timestamp will mathematically be less than 'now').
  my $min_start = time(); 
  
  # Loop through every single recorded step in the log file
  foreach my $s (values %{$stat}) {
    # If the step has a valid timestamp, and it is older (smaller) than our current minimum...
    if (defined($s->{start}) && $s->{start} > 0 && $s->{start} < $min_start) {
      # ...we update the minimum to this step's timestamp.
      $min_start = $s->{start}; 
    }
  }
  
  # Once the loop finishes, $min_start holds the timestamp of the very first action 
  # that occurred in the past. We assign this to the workflow's start time!
  $starttime = $min_start; 
}

&write_steptimings_lml($opt_outfile,$opt_name,$starttime,$endtime,$stat);
&write_steptimings_ascii($opt_outfile_ascii,$opt_name,$starttime,$endtime,$stat);

# handle also stdout/stderr 
sub write_steptimings_lml {
  my($filename,$wf_name,$starttime,$endtime,$steprefs)=@_;
  my($count,%stepnr,$step);

  # print "write_steptimings_lml($filename,$wf_name,$starttime,$endtime,$steprefs)\n";
  
  open(OUT,"> $filename") || die "cannot open file $filename";
  printf(OUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");
  printf(OUT "<lml:lgui xmlns:lml=\"http://eclipse.org/ptp/lml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n");
  printf(OUT "	xsi:schemaLocation=\"http://eclipse.org/ptp/lml lgui.xsd\"\n");
  printf(OUT "	version=\"0.7\"\>\n");
  printf(OUT "<objects>\n");
  $count=0;

  # Object identifiers are prefixed with the workflow name and timestamp to guarantee 
  # global uniqueness, preventing primary key collisions in the database.
  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
    $count++; $stepnr{$step} = $count;
    printf(OUT "<object id=\"st_%s_%d_%04d\" name=\"%s\" type=\"steptime\"/>\n", $wf_name, $starttime, $count, $step);
  }

  printf(OUT "</objects>\n");
  printf(OUT "<information>\n");

  # Information nodes are linked using the corresponding unique identifiers.
  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
    printf(OUT "<info oid=\"st_%s_%d_%04d\" type=\"short\">\n", $wf_name, $starttime, $stepnr{$step});
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


# handle also stdout/stderr 
sub write_steptimings_ascii {
  my($filename,$wf_name,$starttime,$endtime,$steprefs)=@_;
  my($count,%stepnr,$step);

  # print "write_steptimings_lml($filename,$wf_name,$starttime,$endtime,$steprefs)\n";
  
  open(OUT,"> $filename") || die "cannot open file $filename";
  printf(OUT "%4s %3s %-50s %-15s %-15s %10s %10s %10s\n","ord","lvl","step","ts_start","ts_end","start_rel","end_rel","t_delta");
  print OUT "-"x122,"\n";
  $count=0;

  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
      printf(OUT "%04d %1d %-50s %15.4f %15.4f %10.4f %10.4f %10.4f\n",
	     $steprefs->{$step}->{order},
	     $steprefs->{$step}->{level},
	     $step,
	     $steprefs->{$step}->{start},
	     $steprefs->{$step}->{end},
	     $steprefs->{$step}->{start}-$starttime,
	     $steprefs->{$step}->{end}-$starttime,
	     $steprefs->{$step}->{end} - $steprefs->{$step}->{start});
  }
  
  close(OUT);
}


sub my_sort {
    my($a,$b)=@_;
    if($stat->{$a}->{start} != $stat->{$b}->{start}) {
	return( $stat->{$a}->{start} <=> $stat->{$b}->{start} );
    } else {
	return($a cmp $b);
    }
    
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
