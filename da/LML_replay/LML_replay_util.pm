##################################################################################################################
####  Replay utils ###############################################################################################
##################################################################################################################

sub read_config {
    my($configfile,$verbose) =@_;
    my $config=LLmonDB_config->new($configfile,0); # 0 -> no verbose
    $config->load_config();
    printf(" read configfile=%s\n",$configfile) if($verbose);
    return($config);
}

sub read_or_init_replay_status {
    my($configdata,$verbose) =@_;
    my $status_file=$configdata->{"LML_replay"}->{"config"}->{"status_file"};
    my $status;
    if(-f $status_file) {
	my $status_obj=LLmonDB_config->new($status_file,0); # 0 -> no verbose
	$status_obj->load_config();
	$status=$status_obj->get_contents();
#	print Dumper($status);

	printf(" read status_file=%s\n",$status_file) if($verbose);
    } else {
	
	$status->{"LML_replay"}->{"sync_from_date"}="01_01_01";
	$status->{"LML_replay"}->{"sync_from_ts"}=&replay_date_to_sec_day($status->{"LML_replay"}->{"sync_from_date"});

	$status->{"LML_replay"}->{"sync_until_date"}="01_01_01";
	$status->{"LML_replay"}->{"sync_until_ts"}=&replay_date_to_sec_day($status->{"LML_replay"}->{"sync_until_date"});
		
	$status->{"LML_replay"}->{"sim_status"}="before_init";
	printf(" write status_file=%s\n",$status_file);
 	YAML::DumpFile($status_file,$status);
	
    }
	
    return($status);
}


sub check_update_config {
    my($configdata,$verbose) =@_;
    my $okay=1;
    
    # main level
    foreach my $topl ("LML_replay") {
	if(!exists($configdata->{$topl})) {
	    printf(" check config top level %s missing, exiting\n",$topl);
	    $okay=0;
	}

    }

    # category level
    my $p=$configdata->{"LML_replay"};
    foreach my $topl ("simulation", "config", "initdb") {
	if(!exists($p->{$topl})) {
	    printf(" check config category level %s missing, exiting\n",$topl);
	    $okay=0;
	}
	
    }

    # check/add directory info
    $p=$configdata->{"LML_replay"}->{"config"};
    if(!exists($p->{"LMLdir"})) {
	$p->{"LMLdir"}="./data/input";
	printf(" check config setting config->LMLdir to %s\n",$p->{"LMLdir"});
    }
    
    # check/add date info
    $p=$configdata->{"LML_replay"}->{"simulation"};
    if(exists($p->{"end_date"})) {
	if($p->{"end_date"} eq "today") {
	    $p->{"end_date"}=&replay_sec_to_date_yymmdd(time());
	}
	$p->{"end_ts"}=&replay_date_to_sec_day($p->{"end_date"});
    }
    if(exists($p->{"start_date"})) {
	$p->{"start_ts"}=&replay_date_to_sec_day($p->{"start_date"});
    } else {
	printf(" check config setting simulate->startdate to end-date - 30days\n");
	$p->{"start_ts"}=$p->{"end_ts"}-30*24*3600;
	$p->{"start_date"}=&replay_sec_to_date_yymmdd($p->{"start_ts"});
    }
    
    printf(" check config file: check=%d\n",$okay) if($verbose);
    
    return($okay);
}


sub check_dirs {
    my($configdata,$verbose) =@_;


    my $p=$configdata->{"LML_replay"}->{"config"};
    
    foreach my $dir ("LMLdir", "DBdir", "reportdir", "logdir", "tmpdir", "archdbdir", "archjrdir" ) {
	if(! -d $p->{$dir} ) {
	    printf(" create directory %s \n",$p->{$dir});
	    my $cmd=sprintf("mkdir -p %s",$p->{$dir});
	    &mysystem($cmd,$verbose);
	}
    }
    
    return($okay);
}

sub replay_sec_to_date_yymmdd {
  my ($lsec)=@_;
  my($date);
  my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
  $year=sprintf("%02d",$year % 100);
  $mon++;
  $date=sprintf("%02d_%02d_%02d",$year,$mon,$mday);
  return($date);
}


sub replay_date_to_sec_day {
  my ($ldate)=@_;
  my ($year,$mon,$mday)=split(/[ \.:\/\-\_\.]/,$ldate);
  my($sec,$min,$hours)=(0,0,0);
  $mon--;
  my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
  return($timesec);
}


sub date_to_sec {
    my ($ldate)=@_;
#    my ($mday,$mon,$year,$hours,$min,$sec)=split(/[ \.:\/\-\_\.]/,$ldate);
    my ($year,$mon,$mday,$hours,$min,$sec)=split(/[ \.:\/\-\_\.]/,$ldate);
#    print "date_to_sec: ($mday,$mon,$year,$hours,$min,$sec) $ldate\n";
    $mon--;
    my $timesec=timelocal($sec,$min,$hours,$mday,$mon,$year);
    return($timesec);
}

sub sec_to_date {
    my ($lsec)=@_;
    my($date);
    my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
    $year=sprintf("%02d",$year % 100);
    $mon++;
    $date=sprintf("%02d/%02d/%02d-%02d:%02d:%02d",$mon,$mday,$year,$hours,$min,$sec);
    return($date);
}

sub sec_to_day_month {
    my ($lsec)=@_;
    my($date);
    my ($sec,$min,$hours,$mday,$mon,$year,$rest)=localtime($lsec);
    $year=sprintf("%02d",$year % 100);
    $mon++;
    $date=sprintf("%02d.%02d",$mday,$mon);
    return($date);
}

sub _max {
  my ( $a, $b ) = @_;
  if ( not defined $a ) { return $b; }
  if ( not defined $b ) { return $a; }
  if ( not defined $a and not defined $b ) { return; }

  if   ( $a >= $b ) { return $a; }
  else              { return $b; }

  return;
}

sub _min {
  my ( $a, $b ) = @_;
  if ( not defined $a ) { return $b; }
  if ( not defined $b ) { return $a; }
  if ( not defined $a and not defined $b ) { return; }

  if   ( $a <= $b ) { return $a; }
  else              { return $b; }

  return;
}


sub mysystem {
    my($call,$verbose)=@_;

    printf(STDERR "  --> exec: %s\n",$call) if($verbose);
    system($call);
    printf(STDERR "           rc=%d\n",$?) if($verbose);
}

1;
