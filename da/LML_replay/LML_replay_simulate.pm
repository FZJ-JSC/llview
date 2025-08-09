##################################################################################################################
####  Replay sync ###############################################################################################
##################################################################################################################


sub simulate {
    my($configdata,$replay_status,$nsteps,$verbose) =@_;

    my $p=$configdata->{"LML_replay"}->{"simulation"};
    my $input_start_ts=$p->{"start_ts"};
    my $input_end_ts=$p->{"end_ts"};
    my $local_dir=$configdata->{"LML_replay"}->{"config"}->{"LMLdir"};
    my $tmp_dir=$configdata->{"LML_replay"}->{"config"}->{"tmpdir"};
    my $log_dir=$configdata->{"LML_replay"}->{"config"}->{"logdir"};
    my $runworkflow=$p->{"runworkflow"};

    
    # check lastts
    if(! exists($replay_status->{"LML_replay"}->{"sim_lastts"})) {
	$replay_status->{"LML_replay"}->{"sim_lastts"}=$p->{"start_ts"};
    }
    my $sim_lastts=$replay_status->{"LML_replay"}->{"sim_lastts"};

    printf(" simulate: last simulated ts of data:     %12d (%s)\n",$sim_lastts,&sec_to_date($sim_lastts));

    my $timeline=&read_timestamps($local_dir,$sim_lastts,$input_start_ts,$input_end_ts,$nsteps);
    &write_timestamp_log($timeline,$configdata->{"LML_replay"}->{"config"}->{"logdir"});


    my $rc=&simulate_timeline($timeline, $runworkflow, $local_dir, $tmp_dir, $log_dir, $nsteps);

    if($rc>0) {
	$replay_status->{"LML_replay"}->{"sim_lastts"}=$rc;
    }

    return();
}




# read timestamps
sub read_timestamps {
    my($local_dir,$last_ts, $input_start_ts, $input_end_ts, $nsteps)=@_;
    my($timeline, $numsteps);

    my $sim_startts=$last_ts + 1;
    my $sim_endts=0;
    $numsteps=0;
    
    for($ts=$last_ts;$ts<=$input_end_ts;$ts+=24*3600) {
	
	my $file_date=&replay_sec_to_date_yymmdd($ts);
	$localfn=sprintf("%s/%s.dat",$local_dir,$file_date);
	open(IN,$localfn) or die "cannot find input file $localfn";
	
	while(my $line=<IN>) {
	    my $event;
	    my ($nr,$ldate)=split(/\s+/,$line);
	    my  $ts=&date_to_sec($ldate) - $sim_startts;
	    $sim_endts=&date_to_sec($ldate);
	    
	    # new entry found?
	    next if ($ts<0);
	    
	    $numsteps++;
	    last if($numsteps>$nsteps);

	    # store entry
	    $event->{fnr}=$nr+1;   # nr in .dat file is wrong (offset of 1)
	    $event->{date}=$ldate;
	    $event->{filedate}=$file_date;
	    $event->{ts}=$ts;
	    push(@{$timeline->{$ts}},$event); 
	}
	close(IN);
	last if($numsteps>$nsteps);
    }

#    print Dumper($timeline);
    
    printf(" read_timestamps:  %4d timestamps found: %12d (%s) to %12d (%s)\n",$numsteps-1,
	   $sim_startts,&sec_to_date($sim_startts),
	   $sim_endts,&sec_to_date($sim_endts),
	);
    return($timeline);
}


# read timestamps
sub simulate_timeline {
    my( $timeline, $runworkflow, $local_dir, $tmp_dir, $log_dir, $nsteps)=@_;

    my $numsteps=0;
    my $sim_endts=0;
    
    foreach $ts (sort {$a <=> $b} keys(%{$timeline})) {
	foreach $event (@{$timeline->{$ts}}) {
	    
	    $numsteps++;

 	    { my $asave=$|;$|=1;
	      printf(" simulate: [%4d] (%4d, %s) tar: ",$numsteps, $event->{fnr},$event->{date});
	      $|=$asave;
	    }

	    # extract data
	    my $starttime=time();
	    my $cmd=sprintf("(cd %s; rm -f replay_LML.xml; tar xf %s/LML_data_%s.tar %06d.xml.gz; mv %06d.xml.gz replay_LML.xml.gz; gunzip replay_LML.xml.gz) 2>> %s/tar.log",
			    $tmp_dir,$local_dir,$event->{filedate},$event->{fnr},
			    $event->{fnr},
			    $log_dir);
#	    print "WF >$cmd<\n";
	    &mysystem($cmd);
	    my $tartime=time()-$starttime;
 	    { my $asave=$|;$|=1;
	      printf(" %6.3fs run: ",$tartime);
	      $|=$asave;
	    }
	    

	    # run workflow
	    $starttime=time();
	    $cmd=sprintf("%s >> %s/replay_%s_stdout.log 2>> %s/replay_%s_stderr.log",
			    $runworkflow,
			    $log_dir,$event->{filedate},
			    $log_dir,$event->{filedate});
#	    print "WF >$cmd<\n";
	    &mysystem($cmd);
	    my $runtime=time()-$starttime;

	    
 	    { my $asave=$|;$|=1;
	      printf(" %6.3fs ready\n",$runtime);
	      $|=$asave;
	    }
    
	    $sim_endts=&date_to_sec($event->{date});
	}
    }
    return($sim_endts);
}


sub write_timestamp_log() {
    my($timeline,$logdir)=@_;
    
    my($event);
    open(LOG,"> $logdir/timestamps.log");
    foreach my $ts (sort {$a <=> $b} keys(%{$timeline})) {
	foreach my $event (@{$timeline->{$ts}}) {
	    printf(LOG "%15d: fnr=%s date=%-16s filedate=%-16s ts=%15d\n",
		   $ts,$event->{fnr},$event->{date},$event->{filedate},$event->{ts});
	}
    }
    close(LOG);
}

1;
