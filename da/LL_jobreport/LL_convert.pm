# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LL_convert;

my $VERSION='$Revision: 1.00 $';
my($debug)=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use FindBin;
use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( logmsg );

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  $self->{VERBOSE}     = shift;
  $self->{INSTNAME}    = shift;
  $self->{CURRENTTS}   = shift;
  $self->{SYSTEM_NAME} = shift;

  printf("\t LML_convert: new %s\n",ref($proto)) if($debug>=3);

  bless $self, $class;
  return $self;
}

sub init_column_convert_mapping {
  my $self = shift;
  my($list)=@_;

  $self->init_convert_functions() if(!exists($self->{CONVERT_FUNCTIONS}));
  
  # pre-process column_convert
  my $col_convert_by_col={};
  foreach my $rule (split(/\s*,\s*/,$list)) {
    if($rule=~/^\s*(.*)->(.*)\s*/) {
      my($c,$what)=($1,$2);
      if(exists($self->{CONVERT_FUNCTIONS}->{$what})) {
        $col_convert_by_col->{$c}=$self->{CONVERT_FUNCTIONS}->{$what};
      } else {
        printf(STDERR "%s[init_column_convert_mapping] ERROR: Unknown convert rule: %s\n;\n",$self->{INSTNAME},$rule);
      }
    }
  }
  return($col_convert_by_col);
}

sub get_column_convert_function {
  my $self = shift;
  my($what)=@_;

  $self->init_convert_functions() if(!exists($self->{CONVERT_FUNCTIONS}));
  
  # pre-process column_convert
  if(exists($self->{CONVERT_FUNCTIONS}->{$what})) {
    return($self->{CONVERT_FUNCTIONS}->{$what});
  } else {
    printf("%s get_column_convert_function: unknown convert rule: %s\n;\n",$self->{INSTNAME},$what);
  }
  return(undef);
}

sub init_convert_functions {
  my $self = shift;

  # pre-process column_convert
  $self->{CONVERT_FUNCTIONS} ={
                                "todate_1"           => \&sec_to_date_csv,
                                "todate_1_wo_time"   => \&sec_to_date_wo_time_csv,
                                "todate_fp"          => \&sec_to_date_fp_csv,
                                "todate_std_hhmmss_jufo" => \&sec_to_date_std_hhmmss_jufo,
                                "todate_std_hhmmss"  => \&sec_to_date_std_hhmmss,
                                "todate_std_hhmm"    => \&sec_to_date_std_hhmm,
                                "Bytes2MB"   => \&bytes_to_mbytes,
                                "Bytes2MiB"  => \&bytes_to_mbytes,
                                "cut6digits" => \&cut6digits,
                                "cut5digits" => \&cut5digits,
                                "cut4digits" => \&cut4digits,
                                "cut3digits" => \&cut3digits,
                                "cut2digits" => \&cut2digits,
                                "cut1digits" => \&cut1digits,
                                "days_sincenow"     => \&days_sincenow,
                                "jobdays_sincenow"  => \&jobdays_sincenow,
                                "hhmm_sincenow"     => \&hhmm_sincenow,
                                "hhmmss_sincenow"   => \&hhmmss_sincenow,
                                "hourfrac_sincenow" => \&hourfrac_sincenow,
                                "hhmm"       => \&hhmm,
                                "hhmm_short" => \&hhmm_short,
                                "hhmmss_short" => \&hhmmss_short,
                                "hhmmss"     => \&hhmmss,
                                "dayfrac" => \&dayfrac,
                                "hourfrac" => \&hourfrac,
                                "minutefrac" => \&minutefrac,
                                "MiBtoGiB" => \&mib_to_gib,
                                "KiBtoGiB" => \&kib_to_gib,
                                "MiBtoB"   => \&mib_to_b,
                                "BytestoGiB" => \&to_gib,
                                "Bytes2GiB"  => \&to_gib,
                                "toGiB"      => \&to_gib,
                                "toMiB"      => \&to_mib,
                                "to_ms"      => \&to_ms,
                                "MJouletoWh" => \&mjouletowh,
                                "toThousand" => \&to_thousand,
                                "toMillion"  => \&to_million,
                                "toBillion"  => \&to_billion,
                                "toPercent"  => \&to_percent,
                                "systemname" => \&systemname,
                                "wrapword10" => \&wrapword10,
                                "wrapcsword10" => \&wrapcsword10,
                                "wrapstr30"  => \&wrapstr30,
                                "wrapstr50"  => \&wrapstr50,
                                "wrapstr80"  => \&wrapstr80,
                                "wrapstr120" => \&wrapstr120,
                                "onlygtnull" => \&onlygtnull,
                                "as_array"   => \&as_array,
                                "corepattern" => \&corepattern,
                                "tolower"     => \&tolower,
                                "toupper"     => \&toupper,
                                "toupperfirst" => \&toupperfirst,
                                "null_if_empty" => \&null_if_empty
                              };
  return();
}

sub sec_to_date {
  my ($lsec)=@_;
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%02d",$year % 100);
  $mon++;
  $date=sprintf("%02d/%02d/%02d-%02d:%02d:%02d",$year,$mon,$mday,$hours,$min,$sec);
  # print "TMPDEB: sec_to_date $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n";
  return($date);
}

sub sec_to_date4 {
  my ($lsec)=@_;
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $mon++;
  $date=sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year+1900,$mon,$mday,$hours,$min,$sec);
  # print "TMPDEB: sec_to_date4 $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n";
  return($date);
}

sub sec_to_date_csv {
  my ($arg)=@_;
  return("-") if(!$arg);
  my $lsec; if($arg=~/:/) { $lsec=&date_to_sec($arg);} else { $lsec=$arg;    }
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%04d",$year+1900);
  $mon++;
  $date=sprintf("%04d/%02d/%02d %02d:%02d:%02d",$year,$mon,$mday,$hours,$min,$sec);
  # print "TMPDEB: sec_to_date_csv $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n";
  return($date);
}

sub sec_to_date_wo_time_csv {
    my ($arg)=@_;
    my $lsec; if($arg=~/:/) { $lsec=&date_to_sec($arg);} else        { $lsec=$arg;    }
    my($date);
    my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
    $year=sprintf("%04d",$year+1900);
    $mon++;
    $date=sprintf("%04d/%02d/%02d",$year,$mon,$mday);
    return($date);
}

sub sec_to_date_fp_csv {
  my ($arg)=@_;
  my $lsec; if($arg=~/:/) { $lsec=&date_to_sec($arg);} else { $lsec=$arg;    }
  my ($date);
  my $usec=$lsec-int($lsec);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%04d",$year+1900);
  $mon++;
  $date=sprintf("%04d/%02d/%02d %02d:%02d:%02.6f",$year,$mon,$mday,$hours,$min,$sec+$usec);
  # print "TMPDEB: sec_to_date_fp_csv $lsec -> usec=$usec,sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n";
  return($date);
}

sub sec_to_date_std_hhmmss {
  my ($arg)=@_;
  my $lsec; if($arg=~/:/) { $lsec=&date_to_sec($arg);} else { $lsec=$arg;    }
  return("-") if($lsec<=0);
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%04d",$year+1900);
  $mon++;
  $date=sprintf("%04d-%02d-%02d %02d:%02d:%02d",$year,$mon,$mday,$hours,$min,$sec);
  return($date);
}

sub sec_to_date_std_hhmmss_jufo {
  my ($arg)=@_;
  my $lsec; if($arg=~/:/) { $lsec=&date_to_sec($arg);} else { $lsec=$arg;    }
  return("-") if($lsec<=0);
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year-=100;
  $mon++;
  $date=sprintf("%02d/%02d/%02d-%02d:%02d:%02d",$mon,$mday,$year,$hours,$min,$sec);
  return($date);
}

sub sec_to_date_std_hhmm {
  my ($arg)=@_;
  return("-") if(!$arg || $arg eq "-" || $arg eq "Unknown");
  # print STDERR "TMPDEB: error no arg\n",caller(),"\n" if(!$arg);
  my $lsec; 
  if($arg=~/:/) { 
    $lsec=&date_to_sec($arg);
  } else {
    $lsec=$arg;
  }
  return("-") if($lsec<=0);

  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  if(!defined($year)) {
    print STDERR "[sec_to_date_std_hhmm] error in timestamp: $lsec (called by ",caller(),")\n";
    return(undef);
  }
  $year=sprintf("%04d",$year+1900);
  $mon++;
  $date=sprintf("%04d-%02d-%02d %02d:%02d",$year,$mon,$mday,$hours,$min);
  return($date);
}

sub sec_to_date_fn {
  my ($lsec)=@_;
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%02d",$year % 100);
  $mon++;
  $date=sprintf("%02d%02d%02d_%02d%02d%02d",$year,$mon,$mday,$hours,$min,$sec);
  return($date);
}

sub date_to_sec {
  my ($ldate)=@_;
  my ($year,$mon,$mday,$hours,$min,$sec)=split(/[ :\/\-\_\.]/,$ldate);
  $mon--;
  $sec=0 if(!defined($sec));
  # print "TMPDEB: date_to_sec $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year\n";
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  return($timesec);
}

sub hourfrac_to_hour_minute_sec {
  my ($hoursfrac)=@_;
  my ($hours,$min,$sec,$rest,$ret);
  $hours=int($hoursfrac); $rest=$hoursfrac-$hours;
  $min=int($rest*60); $rest=$rest*60-$min; 
  $sec=int($rest*60); $rest=$rest*60-$sec; 

  $ret=sprintf("%02d:%02d:%02d",$hours,$min,$sec);

  return($ret);
}

sub hourfrac_to_hour_minute_short {
  my ($hoursfrac)=@_;
  my ($days,$hours,$min,$rest,$ret);

  $hoursfrac=int($hoursfrac*60*2+1)/(60*2);
  $days=int($hoursfrac/24); $rest=$hoursfrac-($days*24);
  $hours=int($rest); $rest=$rest-$hours;
  $min=int($rest*60);  

  if($days>0) {
    $ret=sprintf("%dd%02dh%02dm",$days,$hours,$min);
  } elsif($hours>0) {
    $ret=sprintf("%dh%02dm",$hours,$min);
  } else {
    $ret=sprintf("%2dm",$min);
  }
  return($ret);
}

sub hourfrac_to_hour_minute_sec_short {
  my ($hoursfrac)=@_;
  my ($days,$hours,$min,$sec,$rest,$ret);

  $hoursfrac=int($hoursfrac*60*2+1)/(60*2);
  $days=int($hoursfrac/24); $rest=$hoursfrac-($days*24);
  $hours=int($rest); $rest=$rest-$hours;
  $min=int($rest*60); $rest=$rest-($min/60);
  $sec=int($rest*3600); 

  if($days>0) {
    $ret=sprintf("%dd%02dh%02dm%02ds",$days,$hours,$min,$sec);
  } elsif($hours>0) {
    $ret=sprintf("%dh%02dm%02ds",$hours,$min,$sec);
  } elsif($min>0) {
    $ret=sprintf("%2dm%02ds",$min,$sec);
  } else {
    $ret=sprintf("%2ds",$sec);
  }
  return($ret);
}

sub hourfrac_to_hour_minute {
  my ($hoursfrac)=@_;

  my ($hours,$min,$sec,$rest,$ret);
  $hours=int($hoursfrac); $rest=$hoursfrac-$hours;
  $min=int($rest*60); $rest=$rest*60-$min; 
  $sec=int($rest*60); $rest=$rest*60-$sec; 

  $ret=sprintf("%02d:%02d",$hours,$min);

  return($ret);
}

sub bytes_to_mbytes {
  my ($bytes)=@_;
  return($bytes/1024.0/1024.0);
}

sub cut6digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*1000000)/1000000.0);
}

sub cut5digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*100000)/100000.0);
}

sub cut4digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*10000)/10000.0);
}

sub cut3digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*1000)/1000.0);
}

sub cut2digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*100)/100.0);
}
sub cut1digits {
  my ($number)=@_;
  if($number!~/^[0-9\.]+$/) {
    return($number); 
  }
  return(int($number*10)/10.0);
}

sub hourfrac_sincenow {
  my ($ts,$self)=@_;
  return(&cut3digits(($self->{CURRENTTS}-$ts)/3600.0));
}

sub hhmmss_sincenow {
  my ($ts,$self)=@_;
  return(&hourfrac_to_hour_minute_sec(($self->{CURRENTTS}-$ts)/3600.0));
}

sub hhmm_sincenow {
  my ($ts,$self)=@_;
  return(&hourfrac_to_hour_minute(($self->{CURRENTTS}-$ts)/3600.0));
}

sub days_sincenow {
  my ($ts,$self)=@_;
  my (undef,undef,undef,$mday,$mon,$year)=localtime($self->{CURRENTTS});
  my $ts_startoftoday=timelocal(0,0,0,$mday,$mon,$year);
  if($ts>=$ts_startoftoday) {
    return(0) ;
  } else {
    return( int( ($ts_startoftoday-$ts) / (24.0*3600.0) ) );
  }
}

sub jobdays_sincenow {
  my ($ts,$self)=@_;
  my (undef,undef,undef,$mday,$mon,$year)=localtime($self->{CURRENTTS});
  my $ts_startoftoday=timelocal(0,0,0,$mday,$mon,$year);
  if($ts>=$self->{CURRENTTS}-120) {
    return(-1); 		# running
  } elsif($ts>=$ts_startoftoday) {
    return(0) ;             # finished today
  } else {
    return( int( ($ts_startoftoday-$ts) / (24.0*3600.0) ) + 1 );
  }
}

sub dayfrac {
  my ($ts,$self)=@_;
  return(0) if(!$ts);
  if($ts!~/^[0-9\.]+$/) {
    return($ts); 
  }
  return(&cut3digits(($ts)/3600.0/24.0));
}

sub hourfrac {
  my ($ts,$self)=@_;
  return(0) if(!$ts);
  if($ts!~/^[0-9\.]+$/) {
    return($ts); 
  }
  return(&cut3digits(($ts)/3600.0));
}

sub minutefrac {
  my ($ts,$self)=@_;
  return(0) if(!$ts);
  if($ts!~/^[0-9\.]+$/) {
    return($ts); 
  }
  return(&cut3digits(($ts)/60.0));
}

sub wrapword10 {
  my ($text,$self)=@_;
  return($text) if(!$text);
  my @words=split(/\s+/,$text);
  my $newtext;
  for(my $w=0;$w<=$#words;$w++) {
    $newtext.=" " if($newtext);
    $newtext.=$words[$w];
    $newtext.="<br>" if($w%10==9);
  }
  
  return($newtext);
}
sub wrapcsword10 {
  my ($text,$self)=@_;
  return($text) if(!$text);
  my @words=split(/\s*,\s*/,$text);
  my $newtext;
  for(my $w=0;$w<=$#words;$w++) {
    $newtext.=$words[$w];
    $newtext.="," if($w<$#words);
    $newtext.="<br>" if($w%10==9);
  }
  
  return($newtext);
}

sub wrapstr120 {
  my ($text,$self)=@_;
  return(&wrapstr($text,120,$self));
}

sub wrapstr80 {
  my ($text,$self)=@_;
  return(&wrapstr($text,80,$self));
}

sub wrapstr50 {
  my ($text,$self)=@_;
  return(&wrapstr($text,50,$self));
}

sub wrapstr30 {
  my ($text,$self)=@_;
  return(&wrapstr($text,30,$self));
}

sub wrapstr {
  my ($text,$width,$self)=@_;
  return($text) if(!$text);
  my $newtext="";
  while($text) {
    if(length($text)>$width) {
      $newtext.=substr($text,0,$width);
      $text=substr($text,$width);
      $newtext.="<br>";
    } else {
      $newtext.=$text;
      $text="";
    }
  }
  return($newtext);
}

sub corepattern {
    my ($text,$self)=@_;
    return($text) if(!$text);
    my $lh=int(length($text)/2);
    my @first  = split(//, substr($text,0,$lh));
    my @second = split(//, substr($text,$lh));
    my $newtext="";
    for(my $i=0;$i<=$#first;$i++) {
	$newtext.="&#xc".$first[$i].$second[$i].";";
    }
    return($newtext);
}

sub hhmmss {
  my ($ts,$self)=@_;
  if($ts!~/^[0-9\.]+$/) {
    my $msg = "$self->{INSTNAME}\[".(caller(1))[3]."\]\[".(caller(0))[3]."\] ERROR: wrong argument: $ts\n"; logmsg($msg,\*STDERR);
    return($ts); 
  }

  return(&hourfrac_to_hour_minute_sec(($ts)/3600.0));
}

sub hhmm {
  my ($ts,$self)=@_;
  if($ts!~/^[0-9\.]+$/) {
    my $msg = "$self->{INSTNAME}\[".(caller(1))[3]."\]\[".(caller(0))[3]."\] ERROR: wrong argument: $ts\n"; logmsg($msg,\*STDERR);
    return($ts); 
  }

  return(&hourfrac_to_hour_minute(($ts)/3600.0));
}

sub hhmm_short {
  my ($ts,$self)=@_;
  if($ts!~/^[0-9\.]+$/) {
    # my $msg = "$self->{INSTNAME}\[".(caller(1))[3]."\]\[".(caller(0))[3]."\] ERROR: wrong argument: $ts\n"; logmsg($msg,\*STDERR);
    return($ts); 
  }
  
  return(&hourfrac_to_hour_minute_short(($ts)/3600.0));
}

sub hhmmss_short {
  my ($ts,$self)=@_;
  if($ts!~/^[0-9\.]+$/) {
    # my $msg = "$self->{INSTNAME}\[".(caller(1))[3]."\]\[".(caller(0))[3]."\] ERROR: wrong argument: $ts\n"; logmsg($msg,\*STDERR);
    return($ts); 
  }

  return(&hourfrac_to_hour_minute_sec_short(($ts)/3600.0));
}

sub mib_to_gib {
  my ($mib,$self)=@_;
  return($mib/1024.0);
}

sub kib_to_gib {
  my ($kib,$self)=@_;
  return($kib/1024.0/1024.0);
}

sub mib_to_b {
  my ($mib,$self)=@_;
  return($mib*1024.0*1024.0);
}

sub to_mib {
  my ($b,$self)=@_;
  return($b/1024.0/1024.0);
}

sub to_gib {
  my ($b,$self)=@_;
  return($b/1024.0/1024.0/1024.0);
}

sub to_ms {
  my ($num,$self)=@_;
  return($num*1000.0);
}

sub mjouletowh {
  my ($num,$self)=@_;
  return($num*277.77777778);
}

sub to_thousand {
  my ($num,$self)=@_;
  return($num/1000.0);
}

sub to_million {
  my ($num,$self)=@_;    
  return($num/1000.0/1000.0);
}

sub to_billion {
    my ($num,$self)=@_;
    return($num/1000.0/1000.0/1000.0);
}

sub to_percent {
  my ($num,$self)=@_;    
  return($num*100.0);
}

sub onlygtnull {
  my ($number)=@_;
  if($number>0) {
    return($number);
  } else {
    return("");
  }
}

sub toupper {
  my ($text)=@_;
  if(!defined($text)) {
    return("");
  } else {
    return(uc($text));
  }
}

sub toupperfirst {
  my ($text)=@_;
  if(!defined($text)) {
    return("");
  } else {
    return(ucfirst($text));
  }
}

sub tolower {
  my ($text)=@_;
  if(!defined($text)) {
    return("");
  } else {
    return(lc($text));
  }
}

sub as_array {
  my ($string)=@_;
  my @list;
  if($string) {
    @list = split(/\s*[,; ]\s*/,$string);
  } 
  return(\@list);
}

sub null_if_empty {
  my ($number)=@_;
  if(!defined($number)) {
    return(0);
  } elsif($number eq "" ) {
    return(0);
  } else {
    return($number);
  }
}

sub systemname {
  my ($num,$self)=@_;
  return($self->{SYSTEM_NAME});
}

1;
