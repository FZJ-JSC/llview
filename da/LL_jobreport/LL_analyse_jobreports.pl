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
# get command line parameter
#####################################################################

# option handling
my $opt_infile="./tmp/steplogs/jobreport_last.log";
my $opt_outfile="./tmp/LL_jobreports_stat_LML.xml";
my $opt_outfile_ascii="./tmp/LL_jobreports_stat_ASCII.dat";
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
my @collecteditems=();
my $collected_cmplx=0;
my $collecteditems_per_level;
my $collecteditems_per_par;
my $collected_cmplx_per_level;

my($starttime,$endtime)=(-1,-1);
my $lastts=0;
my $lastnr=0;
open(IN, $opt_infile) or die "cannot open $opt_infile";
while(my $line=<IN>) {
  if($line=~/\[LL_create_jobreports.pl\]\[PRIMARY\s*\] starttime_ts $patint/) {
    $starttime=$1;
    $lastts=$starttime;
    next;
  }
  if($line=~/\[LL_create_jobreports.pl\]\[PRIMARY\s*\] endtime_ts $patint/) {
    $endtime=$1;
    next;
  }
  if($line=~/\[LL_create_jobreports.pl\]\[PRIMARY\s*\]\s+$patwrd\s+in\s+$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\)/) {
    my($a,$b,$c,$d,$e,$f)=($1,$2,$3,$4,$5,$6);
#    print "TMPDEB1: $line";
#    print "         (a=$a,b=$b,c=$c,d=$d,e=$e,f=$f)\n";
    my $name=sprintf("%s",$a);
    $stat->{$name}->{start}=$c;
    $stat->{$name}->{end}=$d;
    $lastts=$d;
    $lastnr=0;
    $stat->{$name}->{startgroupnum}=1; # not used anymore
    my $level=$e;
    $stat->{$name}->{nr}=$f;
    $stat->{$name}->{level}=$level-1;
    $stat->{$name}->{cmplx}=$collected_cmplx_per_level->[$level];
    $collected_cmplx_per_level->[$level]=0;
    while (my $subname = shift @{$collecteditems_per_level->[$level]}) {
	$stat->{$subname}->{topname}=$name;
	push(@{$stat->{$name}->{subelems}},$subname);
	
    }
    push(@{$collecteditems_per_level->[$level-1]},$name) if($level>1);
    next;
  }
  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\]\s+LLmonDB: table \s*$patwrd\s* ready \(\s*$patint entries\)\s+in\s+$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\)/) {
    my($a,$b,$c,$d,$e,$f,$g,$h)=($1,$2,$3,$4,$5,$6,$7,$8);
#    print "TMPDEB2: $line";
#    print "         (a=$a,b=$b,c=$c,d=$d,e=$e,f=$f,g=$g)\n";
    my $name=sprintf("%s",lc($b));
    $stat->{$name}->{start}=$e;
    $stat->{$name}->{end}=$f;
    $stat->{$name}->{startgroupnum}=2;
    $stat->{$name}->{nr}=$h;
    $collected_cmplx+=$c;
    $stat->{$name}->{level}=1;
    push(@{$collecteditems_per_level->[1]},$name);
    next;
  }
  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\]\s+LLmonDB:\s+(trg_upd\.|upd\.|add\.)\s+$patint\s+entries (in|to) table\s+$patwrd\/$patwrd\s+in\s+$patfp[s]/) {
    my($a,$b,$c,$d,$e,$f,$g)=($1,$2,$3,$4,$5,$6,$7);
    my $name=sprintf("_%s_%s",lc($a),lc($f));
    $stat->{$name}->{start}=$lastts;
    $lastts+=$g;
    $stat->{$name}->{end}=$lastts;
    $stat->{$name}->{startgroupnum}=2;
    $stat->{$name}->{nr}=$lastnr++;
    $stat->{$name}->{cmplx}=$c;
    $stat->{$name}->{level}=1;
    $stat->{$name}->{topname}=lc($a);

    push(@{$collecteditems_per_level->[1]},$name);
#    print "TMPDEB3: $line";
#    print "         (a=$a,b=$b,c=$c,d=$d,e=$e,f=$f,g=$g) -> $stat->{$name}->{start}, $stat->{$name}->{end} $stat->{$name}->{startgroupnum} $stat->{$name}->{nr}\n";
    next;
  }
  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\] (S\d\d\d) .* FINISHED process_dataset: $patwrd\s+in\s+$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\)/) {
    my($a,$b,$c,$d,$e,$f,$g,$h)=($1,$2,$3,$4,$5,$6,$7,$8);
#    print "TMPDEB4: $line";
#    print "         (a=$a,b=$b,c=$c,d=$d,e=$e,f=$f,g=$g,h=$h)\n";
    my $name=sprintf("%s",lc($a));
    $stat->{$name}->{start}=$e;
    $stat->{$name}->{end}=$f;
    $stat->{$name}->{startgroupnum}=$g;
    $stat->{$name}->{nr}=$h;
    $stat->{$name}->{level}=3;
    while (my $subname = shift @{$collecteditems_per_par->{$a}}) {
	$stat->{$subname}->{topname}=$name;
	push(@{$stat->{$name}->{subelems}},$subname);
	
    }
    push(@{$collecteditems_per_level->[2]},$name);
    next;
  }

  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\] process_dataset_.*:\s*end work \(\#files created:\s*$patint, \#files appended:\s*$patint: #lines=\s*$patint\)\s+in\s+$patfp[s] \(ts=$patfp,$patfp,l=$patint,nr=$patint\) on $patwrd/) {
    my($a,$b,$c,$d,$e,$f,$g,$h,$i,$j)=($1,$2,$3,$4,$5,$6,$7,$8,$9,$10);
    print "TMPDEB5: $line";
    print "         (a=$a,b=$b,c=$c,d=$d,e=$e,f=$f,g=$g,h=$h,j=$j)\n";
    my $name=sprintf("%s_%s",lc($a),lc($j));
    $stat->{$name}->{start}=$f;
    $stat->{$name}->{end}=$g;
    $stat->{$name}->{nr}=$i;
    $stat->{$name}->{level}=4;
    $stat->{$name}->{startgroupnum}=4; # not used anymore
    $stat->{$name}->{cmplx}+=$b+$c+$d;
    push(@{$collecteditems_per_par->{$a}},$name);
    $collected_cmplx+=$b+$c+$d;
  }

  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\] LLmonDB:\s+\-\-\> updated\s+$patint entries in DB/) {
      next;
    my($a,$b,$c,$d)=($1,$2);
    # print "TMPDEB: ($a,$b)\n";
    $collected_cmplx+=$b;
  }


  if($line=~/\[LL_create_jobreports.pl\]\[$patwrd\s*\] write_data_to_file_json_cache:\s+$patwrd\s+write files\s+$patint of\s+$patint in\s+$patfp[s] \(\s*$patint lines\)/) {
      next;
    my($a,$b,$c,$d,$e,$f)=($1,$2,$3,$4,$5,$6);
    # print "TMPDEB: ($a,$b,$c,$d)\n";
    my $name=sprintf("%s",lc($a));
    $stat->{$name}->{cmplx}+=$f;
    $collected_cmplx+=$f;
  }
}
if(0) {
    close(IN);
    open(TT, "> Test.dat");
    print TT Dumper($stat);
    close(TT);
    exit;
}

# define order
my $num=0;
foreach my $step ( sort {&my_sort($a,$b)} (keys(%{$stat}))) {
    &enum_order($step,\$num) if($stat->{$step}->{level}==0);
}

sub enum_order {
    my ($step,$cntref)=@_;
    $$cntref++;
    $stat->{$step}->{order}=$$cntref;
    foreach my $substep ( sort {&my_sort($a,$b)} (@{$stat->{$step}->{subelems}}) ) {
	&enum_order($substep,$cntref);
    }
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
  foreach $step (keys(%{$steprefs})) {
    if (!defined($steprefs->{$step}->{order})) {
      print STDERR "[LL_analyse_jobreports.pl] [$step] does not include 'start'. Skipping... \n";
      delete ($steprefs->{$step});
    }
  }

  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
    $count++;$stepnr{$step}=$count;
    printf(OUT "<object id=\"fb%06d\" name=\"%s\" type=\"steptime\"/>\n",$count,$step);
  }

  printf(OUT "</objects>\n");
  printf(OUT "<information>\n");

  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
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

# handle also stdout/stderr 
sub write_steptimings_ascii {
  my($filename,$wf_name,$starttime,$endtime,$steprefs)=@_;
  my($count,%stepnr,$step);

  # print "write_steptimings_lml($filename,$wf_name,$starttime,$endtime,$steprefs)\n";
  
  open(OUT,"> $filename") || die "cannot open file $filename";
  printf(OUT "%14s %3s %-50s %-15s %-15s %10s %10s %10s\n","ord","lvl","step","ts_start","ts_end","start_rel","end_rel","t_delta");
  print OUT "-"x122,"\n";
  $count=0;

  foreach $step (sort {$steprefs->{$a}->{order} <=> $steprefs->{$b}->{order}} (keys(%{$steprefs}))) {
      printf(OUT "%014d %1d %-50s %15.4f %15.4f %10.4f %10.4f %10.4f\n",
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
