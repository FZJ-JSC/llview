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

########################
####  Replay initdb ####
########################

sub init_db {
  my($configdata,$replay_status,$verbose) =@_;

  my $p=$configdata->{"LML_replay"}->{"initdb"};
  
  if(exists($configdata->{"LML_replay"}->{"config"}->{"DBdir"})) {
    my $dbdir=$configdata->{"LML_replay"}->{"config"}->{"DBdir"};
    my $cmd=sprintf("rm  %s/*.sqlite",$dbdir);
    &mysystem($cmd,$verbose);
    #	printf("TMPDEB: old db files removed in %s\n",$dbdir);

    if(exists($p->{"update_db_cmd"})) {
      my $cmd=$p->{"update_db_cmd"};
      &mysystem($cmd,$verbose);
      # printf("TMPDEB: newd db files generated in %s\n",$dbdir);
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
      # printf("TMPDEB: newd db files generated in %s\n",$dbdir);
    }
  }
    
  return();
}

1;