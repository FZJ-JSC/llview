# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_da_util;
use Time::Local;
use Time::Piece; # For the timezone
my $debug=0;
use Data::Dumper;
use File::Spec;
use Exporter 'import';
our @EXPORT_OK = qw( init_globalvar substitute_recursive
                    logmsg system_call check_folder
                    stacktrace get_date _max _min remove_old_logs
                    sec_to_date sec_to_date_dir_wo_hhmmss sec_to_date_yymmdd
                    );

# SUPPORT FUNCTIONS
###################
sub init_globalvar {
  my($vardefsref,$varhashref)=@_;
  my($pairref,$key,$value);
  
  foreach $pairref (@{$vardefsref->{var}}) {
    $key=$pairref->{key};
    $value=$pairref->{value};
    &substitute(\$value,$varhashref);
    $msg=($debug==1) ? sprintf("[init_globalvar]\t $key -> $value\n") : ""; logmsg($msg);
    $varhashref->{$key}=$value;
  }
  
  return(1);
}

sub substitute_recursive {
  my($ds,$varhashref)=@_;
  my($i);
  # $msg=sprintf("[substitute_recursive] ".ref($ds)."\n"); logmsg($msg);
  # $msg=sprintf("[substitute_recursive] ".Dumper($ds)."\n"); logmsg($msg);
  
  if(ref($ds) eq "HASH") {
    foreach $key (keys(%{$ds})) {
      # $msg=sprintf("[substitute_recursive] HASH -> $key\n"); logmsg($msg);
      if(ref($ds->{$key})) {
        &substitute_recursive($ds->{$key},$varhashref);
      } else {
        &substitute(\$ds->{$key},$varhashref);
      }
    }
  } elsif(ref($ds) eq "ARRAY") {
    for($i=0;$i<=$#{$ds};$i++) {
      # $msg=sprintf("[substitute_recursive] ARRAY\n"); logmsg($msg);
      if(ref($ds->[$i])) {
        &substitute_recursive($ds->[$i],$varhashref);
      } else {
        &substitute(\$ds->[$i],$varhashref);
      }
    }
  } else {
    $msg=sprintf("[substitute_recursive] Unknown type ".ref($ds)."\n"); logmsg($msg,\*STDERR);
  }
  return(1);
}

sub substitute {
  my($strref,$hashref)=@_;
  my($found,$c,@varlist1,@varlist2,$var);
  my($SUBSTITUTE_NOTFOUND);
  $c=0;
  $found=0;

  return(0) if($$strref eq "");

  # search normal variables
  @varlist1=($$strref=~/\$([^\{\[\$\\\s\.\,\*\/\+\-\\\`\(\)\'\?\:\;\}]+)/g);
  foreach $var (sort {length($b) <=> length($a)} (@varlist1)) {
    if(exists($hashref->{$var})) {
      my $val=$hashref->{$var};
      $$strref=~s/\$$var/$val/egs;
      $msg=($debug==1) ? sprintf("[substitute]    var1: %s = %s\n",$var,$val) : ""; logmsg($msg);
      $found=1;
    }
  }

  # search variables in following form: ${name}
  @varlist2=($$strref=~/\$\{([^\{\[\$\\\s\.\,\*\/\+\-\\\`\(\)\'\?\:\;\}]+)\}/g);
  foreach $var (sort {length($b) <=> length($a)} (@varlist2)) {
    if(exists($hashref->{$var})) {
      my $val=$hashref->{$var};
      $$strref=~s/\$\{$var\}/$val/egs;
      $msg=($debug==1) ? sprintf("[substitute]    var2: %s = %s\n",$var,$val) : ""; logmsg($msg);
      $found=1;
    } 
  }

  # search eval strings (`...`)
  while($$strref=~/^(.*)(\`(.*?)\`)(.*)$/) {
    my ($before,$evalall,$evalstr,$after)=($1,$2,$3,$4);
    my($val,$executeval);
    $val=undef;

    if($evalstr=~/^\s*getstdout\((.*)\)\s*$/) {
      $executeval=$1;
      eval("{\$val=`$executeval`}");
      $val=~s/\n/ /gs;
    } 
    if(!defined($val)) {
      eval("{\$val=$evalstr;}");
    }
    if(!defined($val)) {
      $val=eval("{$evalstr;}");
    }
    $val="" if(!defined($val));
    if($val ne "") {
      $$strref=$before.$val.$after;
    } else {
      last;
    }
    $msg=($debug==1) ? sprintf("[substitute]    eval %s -> %s >%s<\n",$val,$$strref,$evalall) : ""; logmsg($msg);
  }

  # search for variables which could not be substitute
  @varlist1=($$strref=~/\$([^\{\[\$\\\s\.\,\*\/\+\-\\\`\(\)\'\?\:\;\}]+)/g);
  @varlist2=($$strref=~/\$\{([^\{\[\$\\\s\.\,\*\/\+\-\\\`\(\)\'\?\:\;\}]+)\}/g);
  if ( (@varlist1) || (@varlist2) ) {
    $SUBSTITUTE_NOTFOUND=join(',',@varlist1,@varlist2);
    $found=-1;
    $msg=sprintf("[substitute]    Unknown vars in %s: %s\n",$$strref,$SUBSTITUTE_NOTFOUND); logmsg($msg,\*STDERR);
  }
  return($found);
}

# just a replacement if perl module function is missing
sub mask_to_regexp {
  my($mask)=@_;
  my($regexp);
  my($pat,$repl);
  $regexp=$mask;
  # substitution typical patterns

  # %d
  $regexp=~s/%d/\\s*\([-+]?\\d+(?:_\\d+)*\)/gs;

  # %03d
  $regexp=~s/\%(\d+)d/\\s*\([-+]?\\d{$1}(?:_\\d+)*\)/gs;

  # %s
  $regexp=~s/\%s/\\s*\(\\S*\)/gs;

  $regexp=~s/\%(\d+)s/\\s*\(\\S\{0,$1\}\)/gs;

  return($regexp);
}

# UTILITY FUNCTIONS
###################

sub cp_file {
  my($from,$to,$verbose)=@_;
  my $cmd="/bin/cp $from $to";
  $msg=$verbose ? sprintf("[cp_file] Executing: %s\n",$cmd) : ""; logmsg($msg);
  system($cmd);$rc=$?;
  if($rc) {
    $msg=sprintf("[cp_file] rc=%d: Failed executing: %s\n",$rc,$cmd); logmsg($msg,\*STDERR);
    exit(-1);
  }
  return($rc);
}

sub sec_to_date {
  my ($lsec)=@_;
  my($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%02d",$year % 100);
  $mon++;
  $date=sprintf("%02d/%02d/%02d-%02d:%02d:%02d",$mon,$mday,$year,$hours,$min,$sec);
  # $msg=sprintf("[sec_to_date] TMPDEB: $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n"); logmsg($msg,\*STDERR);
  return($date);
}

# Transform from seconds (timestamp) to date format ISO 8601 format
sub sec_to_date_yymmdd {
  my ($lsec) = @_;

  # Create a Time::Piece object from the epoch seconds.
  # This object correctly understands the server's local time and DST.
  my $time = Time::Piece->new($lsec);

  # Get the timezone offset string (e.g., "+0100" or "+0200").
  # The '%z' specifier does this automatically.
  my $offset = $time->strftime('%z');
  
  # Add the required colon for the ISO 8601 standard (e.g., "+01:00").
  $offset =~ s/(\d{2})$/:$1/;

  # Format the date and time, and append the corrected offset.
  # The object-oriented style is very clear.
  return $time->strftime('%Y-%m-%dT%H:%M:%S') . $offset;
}


sub sec_to_date_ger {
  my ($lsec)=@_;
  my($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%04d",2000 + $year % 100);
  $mon++;
  $date=sprintf("%02d.%02d.%02d-%02d:%02d:%02d",$mday,$mon,$year,$hours,$min,$sec);
  # print "TMPDEB: sec_to_date $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n";
  return($date);
}

sub date_to_sec_ger {
  my ($ldate)=@_;
  my ($mday,$mon,$year,$hours,$min,$sec)=split(/[ \.:\/\-\_\.T]/,$ldate);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  return($timesec);
}

sub date_to_sec_res {
  my ($ldate)=@_;
  my ($year,$mon,$mday,$hours,$min,$sec)=split(/[ :\/\-\_\.T]/,$ldate);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # print "TMPDEB: date_to_sec_res $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n";
  return($timesec);
}

sub sec_to_date2 {
  my ($lsec)=@_;
  my($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $mon++;
  $year+=1900;
  $date=sprintf("%02d.%02d.%4d",$mday,$mon,$year);
  # $msg=sprintf("[sec_to_date2] TMPDEB: $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $date\n"); logmsg($msg,\*STDERR);
  return($date);
}

sub sec_to_day {
  my ($lsec)=@_;
  my($wdaystr);
  my ($sec,$min,$hours,$mday,$mon,$year,$wday,$rest)=localtime($lsec);
  $wdaystr=("Su","Mo","Tu","We","Th","Fr","Sa")[$wday];
  # $msg=sprintf("[sec_to_day] TMPDEB: $lsec -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> wday=$wday wdaystr=$wdaystr\n"); logmsg($msg,\*STDERR);
  return($wday);
}

sub sec_to_month {
  my ($lsec)=@_;
  my ($sec,$min,$hours,$mday,$mon,$year,$wday,$rest)=localtime($lsec);
  return($mon);
}

sub timediff {
  my ($date1,$date2)=@_;
  # $msg=sprintf("[timediff] TMPDEB: $date1 $date2\n"); logmsg($msg,\*STDERR);
  my $timesec1=&date_to_sec($date1);
  my $timesec2=&date_to_sec($date2);
  return($timesec1-$timesec2);
}

sub date_to_secj {
  my ($ldate)=@_;
  my ($year,$mon,$mday,$hours,$min,$sec)=split(/[ \.:\/\-\_\.]/,$ldate);
  $mon--;
  # $msg=sprintf("[date_to_secj] TMPDEB: ".caller()."\n"); logmsg($msg,\*STDERR);
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # $msg=sprintf("[date_to_secj] TMPDEB: $date -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub date_to_sec_slurm {
  my ($ldate)=@_;
  my ($year,$mon,$mday,$hours,$min,$sec)=split(/[ \.:\/\-\_\.T]/,$ldate);
  $mon--;
  # $msg=sprintf("[date_to_sec_slurm] TMPDEB: ".caller()."\n"); logmsg($msg,\*STDERR);
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # $msg=sprintf("[date_to_sec_slurm] TMPDEB: $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec -> ".sec_to_date($timesec)."\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub sec_to_date_dir_wo_hhmmss {
    my ($lsec)=@_;
    my($date);
    my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
    $year=sprintf("%04d",$year+1900);
    $mon++;
    $date=sprintf("%04d_%02d_%02d",$year,$mon,$mday);
    return($date);
}

sub time_to_sec_slurm {
  my ($ldate)=@_;
  my $timesec=-1;
  if ($ldate=~/(\d+)\-(\d\d):(\d\d):(\d\d)/) {
    my ($days,$hours,$min,$sec)=($1,$2,$3,$4);
    $timesec=$days*24*3600+$hours*3600+$min*60+$sec;
  } elsif ($ldate=~/(\d\d):(\d\d):(\d\d)/) {
    my ($hours,$min,$sec)=($1,$2,$3);
    $timesec=$hours*3600+$min*60+$sec;
  }
  # $msg=sprintf("[time_to_sec_slurm] TMPDEB: $ldate -> $timesec -> ".($timesec/3600)."\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub date_to_sec3 {
  my ($ldate)=@_;
  my ($mday,$mon,$year,$hours,$min,$sec)=split(/[ \.:\/\-\_\.]/,$ldate);
  $hours=$min=$sec=0;
  $mon--;
  # $msg=sprintf("[date_to_sec3] TMPDEB: ".caller()."\n"); logmsg($msg,\*STDERR);
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # $msg=sprintf("[date_to_sec3] TMPDEB: $date -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub date_to_sec {
  my ($ldate)=@_;
  my ($mon,$mday,$year,$hours,$min,$sec)=split(/[ :\/\-\_\.]/,$ldate);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # $msg=sprintf("[date_to_sec] TMPDEB: $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub date_to_sec_job {
  my ($ldate)=@_;
  my ($mday,$mon,$year,$hours,$min,$sec)=split(/[ :\/\-\_\.]/,$ldate);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  # $msg=sprintf("[date_to_sec_job] TMPDEB: $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

sub date_to_sec2 {
  my ($ldate)=@_;
  my ($mday,$mon,$year)=split(/[ :\/\-\.\_]/,$ldate);
  $mon--;
  if($mon<0) {  
    $mon=0;$year=0;$mday=1;
    # $msg=sprintf("[date_to_sec2] TMPDEB: >$ldate< -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
    # $msg=sprintf("[date_to_sec2] TMPDEB: ".caller()."\n"); logmsg($msg,\*STDERR);
  }
  my $timesec=timelocal(0,0,0,$mday,$mon,$year);
  # $msg=sprintf("[date_to_sec2] TMPDEB: $ldate -> sec=$sec,min=$min,hours=$hours,mday=$mday,mon=$mon,year=$year -> $timesec\n"); logmsg($msg,\*STDERR);
  return($timesec);
}

# $dpm Tage pro Monat
sub timediff_md {
  my ($timesec1,$timesec2)=@_;
  my @days=(31,28,31,30,31,30,31,31,30,31,30,31);
  my($diffm,$difft);
  my ($sec1,$min1,$hours1,$mday1,$mon1,$year1,$wday1,$rest1)=localtime($timesec1);
  my ($sec2,$min2,$hours2,$mday2,$mon2,$year2,$wday2,$rest2)=localtime($timesec2);
  my($m1,$m2)=($mon1+12*$year1,$mon2+12*$year2);
  if($m1==$m2) {
    $diffm=0;
    $difft=($mday2-$mday1+1) * $dpm/$days[$mon1];
  } else {
    $diffm=$m2-$m1+1;
    if($mday1!=1) {
      $difft=-($mday1) * $dpm/$days[$mon1];
      # $msg=sprintf("[timediff_md] TMPDEB: mday1 $difft\n"); logmsg($msg,\*STDERR);
    } else {$difft=0}

    if($mday2!=$days[$mon2]) {
      $difft+= -($days[$mon2]-$mday2+1) * $dpm/$days[$mon2];
      # $msg=sprintf("[timediff_md] TMPDEB: mday2 $difft\n"); logmsg($msg,\*STDERR);
    }
    if($difft<0) {
      $diffm+=int($difft/$dpm-1);
      $difft+= -$dpm*int($difft/$dpm-1);
    }
  }
  # $msg=sprintf("[timediff_md] TMPDEB: timediff_md: $m1,$m2 $year1,$year2 $mday1,$mday2 ($diffm,$difft)\n"); logmsg($msg,\*STDERR);
  return($diffm,$difft);
}

sub date_to_absmonth {
  my ($ldate)=@_;
  my $absmonth=-1;
  my ($mday,$mon,$year);
  if($ldate) {
    ($mday,$mon,$year)=split(/[ :\/\-\.\_]/,$ldate);
    $absmonth=$mon-1;
    $year-=2000 if($year>=2000);
    $absmonth+=(12*$year);
  }
  return($absmonth);
}

sub absmonth_to_date {
  my ($absmonth)=@_;
  my($ldate,$mday,$mon,$year);
  $year=int($absmonth/12);
  $mon=$absmonth-$year*12 + 1;
  $year+=2000;
  $mday=01;
  $ldate=sprintf("%02d.%02d.%4d",$mday,$mon,$year);
  return($ldate);
}

sub absmonth_to_mname {
  my ($absmonth)=@_;
  my($mname,$mon,$year);
  $year=int($absmonth/12);
  $mon=$absmonth-$year*12 + 1;
  $mname=("","Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec")[$mon];
  $mname.=sprintf("%02d",$year);
  return($mname);
}

sub unify_string {
  my($lineref)=@_;
  my $data=$$lineref;
  $data=~s/\xe1/a/gs;
  $data=~s/\xe4/ae/gs;
  $data=~s/\xfc/ue/gs;
  $data=~s/\xf6/oe/gs;
  $data=~s/\xf3/o/gs;
  $data=~s/\xc1/A/gs;
  $data=~s/\xd6/Oe/gs;
  $data=~s/\xdf/ss/gs;
  # print "unify_line: '$$lineref' -> '$data'\n" if($data=~/Ir/);
  $$lineref=$data;
}

sub unescape_special_characters {
  my($str)=@_;
  my $newstr=$str;
  $newstr=~s/\&eq;/=/gs;
  $newstr=~s/\&ne;/!=/gs;
  $newstr=~s/\&lt;/</gs;
  $newstr=~s/\&le;/<=/gs;
  $newstr=~s/\&gt;/>/gs;
  $newstr=~s/\&ge;/>=/gs;
  return($newstr);
}

sub escape_special_characters {
  my($str)=@_;
  my $newstr=$str;
  $newstr=~s/"="/"&eq;"/gs;
  $newstr=~s/"!="/"&ne;"/gs;
  $newstr=~s/"<"/"&lt;"/gs;
  $newstr=~s/"<="/"&le;"/gs;
  $newstr=~s/">"/"&gt;"/gs;
  $newstr=~s/">="/"&ge;"/gs;
  return($newstr);
}

# This subroutine does a system call with the argument 'string' as the command 
# and returns the output removing trailing new lines at the end
sub system_call {
  my ($string) = @_;
  # Local trap for SIGCHLD to avoid being catch by the main one defined above
  local $SIG{'CHLD'} = 'DEFAULT';
  my $output = `$string`;
  chomp($output);
  return ($output);
}

# This subroutine logs $msg into the file $llogfile 
# adding a current timestamp to the message. $llogfile can be
# STDERR, STDOUT, or a file. When empty, it defaults to STDOUT.
sub logmsg {
  my ($msg,$llogfile)=@_;
  return if (!$msg);
  # Local trap for SIGCHLD to avoid being catch by the main one defined above
  local $SIG{'CHLD'} = 'DEFAULT';
  my $pwd=`pwd`; chomp($pwd);
  if ((!defined $llogfile)||($llogfile eq \*STDOUT)) {
    open(LOG, '>&', \*STDOUT) or die "Cannot open STDOUT for writing from $pwd, aborting...\n".&stacktrace();
  } elsif (($llogfile eq STDERR)||($llogfile eq \*STDERR)) {
    open(LOG, '>&', \*STDERR) or die "Cannot open STDERR for writing from $pwd, aborting...\n".&stacktrace();
  } else {
    open(LOG, '>>', $llogfile) or die "Cannot open $llogfile for writing from $pwd, aborting...\n".&stacktrace();
  }
  print LOG sprintf("[%s] %s",get_time(),$msg);
  close(LOG);
}

# This is useful for debugging, used to print all callers (i.e., the stack trace)
sub stacktrace {
  my $i = 1;
  print STDERR "Stack Trace:\n";
  while ( (my @call_details = (caller($i++))) ){
      print STDERR $call_details[1].":".$call_details[2]." in function ".$call_details[3]."\n";
  }
  return "End Stack Trace\n";
}

# Returns current date in the format ".%Y.%m.%d" (e.g., .2023.12.31)
# An integer argument $daysago can be given to get date from '$daysago'
# days ago (default is 0, i.e., today)
# (Used for the log files)
sub get_date {
  my ($daysago) = @_;
  $daysago = $daysago ? $daysago : 0;
  # Local trap for SIGCHLD to avoid being catch by the main one defined above
  local $SIG{'CHLD'} = 'DEFAULT';
  my $currentdate = `date -d \"${daysago} day ago\" +%Y.%m.%d`; chomp($currentdate);
  return $currentdate;
}

# Returns current time
sub get_time {
  my ($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime();
  $year=sprintf("%02d",$year % 100);
  $mon++;
  $date=sprintf("%02d/%02d/%02d-%02d:%02d:%02d",$mon,$mday,$year,$hours,$min,$sec);
  return($date);
}

# This subroutine checks all log and errlog files in a giving folder
# and removes files older than $logdays. Uses $logfile to log messages
sub remove_old_logs {
  my ($folder,$logdays,$logfile)=@_;
  # Getting last date to keep files (older than this, it should be deleted)
  my $olddate = &get_date($logdays);
  my $filedate;
  # Looping over logs and error files
  for my $type ("log", "errlog") {
    # Getting all logs and errlog files from $folder
    my @files = <"$folder/*.$type">;
    # Looping over all the files
    foreach my $filename (@files) {
      # Getting date of file
      if ($filename =~ /.([0-9]{4}.[0-9]{2}.[0-9]{2}).$type/) {
        $filedate = $1;
        # If filename is older than last date to keep files, delete it
        if ($filedate lt $olddate) {
          logmsg("Date $filedate is older than $olddate, removing older log file: $filename\n",$logfile);
          unlink $filename;
        }
      };
    }
  }
  return;
}

# Check if a folder exists, and if not, creates it
sub check_folder {
  my ($path) = @_;
  my ($vol,$folder,$file) = File::Spec->splitpath($path);
  # Checking if folder exist, and if not, creates it
  if(! -d $folder) {
    # Getting filename of function that called this one
    my ($package, $filename, $line) = caller;
    my ($callervol,$callerfolder,$callerfile) = File::Spec->splitpath($filename);
    # Creating the folder
    $msg=sprintf("[$callerfile] Folder not found, creating new directory '$folder'...\n"); logmsg($msg);
    system("mkdir -p $folder") == 0 or die "[$callerfile] Could not create '$folder': $!\n".&stacktrace();
  }
}

# Get maximum value between 2 variables
# (when they are defined, otherwise, return what is defined)
sub _max {
  my ($a, $b) = @_;
  if (not defined $a) { 
    return $b; 
  } elsif (not defined $b) { 
    return $a; 
  } elsif (not defined $a and not defined $b) { 
    return; 
  }

  if ($a >= $b) { 
    return $a; 
  } else { 
    return $b; 
  }

  return;
}

# Get minimum value between 2 variables
# (when they are defined, otherwise, return what is defined)
sub _min {
  my ($a, $b) = @_;
  if (not defined $a) { 
    return $b; 
  } elsif (not defined $b) { 
    return $a; 
  } elsif (not defined $a and not defined $b) { 
    return; 
  }

  if ($a <= $b) { 
    return $a; 
  } else {
    return $b;
  }

  return;
}


1;
