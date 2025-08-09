##################################################################################################################
####  Replay sync ###############################################################################################
##################################################################################################################


sub sync_LML_files {
    my($configdata,$replay_status,$verbose) =@_;


    my $p=$configdata->{"LML_replay"}->{"simulation"};
    my $start_ts=$p->{"start_ts"};
    my $end_ts=$p->{"end_ts"};
    
    my $local_dir=$configdata->{"LML_replay"}->{"config"}->{"LMLdir"};

    $p=$configdata->{"LML_replay"}->{"sync"};

    for($ts=$start_ts;$ts<=$end_ts;$ts+=24*3600) {
	my $file_date=&replay_sec_to_date_yymmdd($ts);
	
	my $localfn=sprintf("%s/LML_data_%s.tar",$local_dir,$file_date);
	if(! -f $localfn) {
	    my $cmd=sprintf("scp -C %s:%s/LML_data_%s.tar %s",$p->{"host"},$p->{"remote_path"},$file_date,$localfn);
	    &mysystem($cmd,$verbose);
	} else {
	    printf("WF: check %s is there\n",$localfn);
	}

	$localfn=sprintf("%s/%s.dat",$local_dir,$file_date);
	if(! -f $localfn) {
	    my $cmd=sprintf("scp -C %s:%s/%s.dat %s",$p->{"host"},$p->{"remote_path"},$file_date,$localfn);
	    &mysystem($cmd,$verbose);
	} else {
	    printf("WF: check %s is there\n",$localfn);
	}


	if($ts < $replay_status->{"LML_replay"}->{"sync_from_ts"}) {
	    $replay_status->{"LML_replay"}->{"sync_from_ts"}=$ts; 
	    $replay_status->{"LML_replay"}->{"sync_from_date"}=&replay_sec_to_date_yymmdd($ts); 
	}
	
	
	printf("WF: sync_until_date  %d > %d\n",$ts, $replay_status->{"LML_replay"}->{"sync_until_ts"});
	if($ts > $replay_status->{"LML_replay"}->{"sync_until_ts"}) {
	    $replay_status->{"LML_replay"}->{"sync_until_ts"}=$ts; 
	    $replay_status->{"LML_replay"}->{"sync_until_date"}=&replay_sec_to_date_yymmdd($ts);
	    printf("WF: set sync_until_date to  %s\n",$replay_status->{"LML_replay"}->{"sync_until_date"});
	}

#	last;
	
    }
    
    return($okay);
}

1;
