##################################################################################################################
####  Replay sync ###############################################################################################
##################################################################################################################


sub init_db {
    my($configdata,$replay_status,$verbose) =@_;


    my $p=$configdata->{"LML_replay"}->{"initdb"};
    
    if(exists($configdata->{"LML_replay"}->{"config"}->{"DBdir"})) {
	my $dbdir=$configdata->{"LML_replay"}->{"config"}->{"DBdir"};
	my $cmd=sprintf("rm  %s/*.sqlite",$dbdir);
	&mysystem($cmd,$verbose);
#	printf("WF: old db files removed in %s\n",$dbdir);

	if(exists($p->{"update_db_cmd"})) {
	    my $cmd=$p->{"update_db_cmd"};
	    &mysystem($cmd,$verbose);
	    printf("WF: newd db files generated in %s\n",$dbdir);
	}

	# reset simulation start
	$replay_status->{"LML_replay"}->{"sim_lastts"}=$configdata->{"LML_replay"}->{"simulation"}->{"start_ts"};
    }
        
    return();
}

sub update_db {
    my($configdata,$replay_status,$verbose) =@_;


    my $p=$configdata->{"LML_replay"}->{"initdb"};
    
    if(exists($configdata->{"LML_replay"}->{"config"}->{"DBdir"})) {
	my $dbdir=$configdata->{"LML_replay"}->{"config"}->{"DBdir"};
	if(exists($p->{"update_db_cmd"})) {
	    my $cmd=$p->{"update_db_cmd"};
	    &mysystem($cmd,$verbose);
#	    printf("WF: newd db files generated in %s\n",$dbdir);
	}
    }
        
    return();
}


1;
