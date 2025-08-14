# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LLmonDB;

my $VERSION='$Revision: 1.00 $';
my $debug=0;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time sleep );
use Parallel::ForkManager;
use POSIX ":sys_wait_h";


sub process_LMLdata {
  my($self) = shift;
  my($LMLdata,$MAX_PROCESSES)=@_;
  my($db,$table,$options,@DBs);
  my $cap=$LMLdata->{CAPABILITIES};
  my $capf=$LMLdata->{CAPABILITIES_FORCED};

  printf("$self->{INSTNAME} LLmonDB: start process_LMLdata\n") if($debug>=3);

  # define order of processing DBs, first DB with (LLgenDB: get_jobnodemap, get_jobtsmap)
  foreach $db (sort(keys(%{$self->{CONFIGDATA}->{databases}}))) {
    my $processDB=0;
    my $foundDBmapdata=0;
    my $map_data_required=0;
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      if(exists($tableref->{options})) {
        $options=$tableref->{options};
        if( exists($options->{update}) ) {
          if(exists($options->{update}->{LML})) {
            my $what=$options->{update}->{LML};
            if(exists($cap->{$what})) {
              $processDB=1;
            }
            if(exists($capf->{$what})) {
              $processDB=1;
            }
          }
          if(exists($options->{update}->{LLgenDB})) {
            my $what=$options->{update}->{LLgenDB};
            if( $what =~ /get_job(node|ts)map/ ) {
              $self->{DBcontains_map_data}=$db;
              $foundDBmapdata=1;
            }
            if( $what =~ /add_job(node|ts)map/ ) {
              $map_data_required=1;
            }
          }
        }
      }
    }
    if($processDB) {
      push(@DBs,$db) if(!$foundDBmapdata);
      $self->{MAP_DATA_REQUIRED}=1 if($map_data_required);
    }
  }

  printf("%-29s LLmonDB: start with job-DB:  %s\n",$self->{INSTNAME},defined($self->{DBcontains_map_data})?$self->{DBcontains_map_data}:"-none-") if($self->{VERBOSE});
  printf("%-29s LLmonDB: found other DBs:    %s\n",$self->{INSTNAME},join(", ",@DBs)) if($self->{VERBOSE});
  printf("%-29s LLmonDB: available cap.:     %s\n",$self->{INSTNAME},join(", ",sort(keys(%{$cap})))) if($self->{VERBOSE});

  my $stepnr=1;
  
  #  serial processing of job data DB
  if(defined($self->{DBcontains_map_data}) && $cap->{'jobs'}) {
    $self->process_LMLdata_DB($self->{DBcontains_map_data},$LMLdata,1,$stepnr++);
  }

  #  get mapping table from DB if not in LML
  if($self->{MAP_DATA_REQUIRED}) {
    $self->get_jobtsmap_from_DB() if(!$self->{JOBTSMAP_AVAIL}); 
    $self->get_jobnodemap_from_DB() if(!$self->{JOBNODEMAP_AVAIL}); 
  }
  
  #  process other DB serial or in parallel
  my $opt_parallel=0;
  my $opt_parwaitsec=40;
  
  if(exists($self->{CONFIGDATA}->{options})) {
    if(exists($self->{CONFIGDATA}->{options}->{parallel})) {
      $opt_parallel=1 if($self->{CONFIGDATA}->{options}->{parallel}=~/YES/i);
      $opt_parwaitsec=$self->{CONFIGDATA}->{options}->{parwaitsec} if($self->{CONFIGDATA}->{options}->{parwaitsec});
    }
  }
  
  # parallel processing
  $MAX_PROCESSES=0 if(!$opt_parallel);
  my $pm = Parallel::ForkManager->new($MAX_PROCESSES);

  my $starttime=time();
  
  DB_LOOP:
  foreach $db (@DBs) {
    $stepnr++;
    
    # Forks and returns the pid for the child: # my $pid = 
    $pm->start and next DB_LOOP;

    # set INSTNAME for messages
    my $in=uc($db);$in=~s/STATE//gs;
    $self->{INSTNAME}=sprintf("[%s][%s]",$self->{CALLER},$in);
    
    $self->process_LMLdata_DB($db,$LMLdata,2,$stepnr);
    $pm->finish; # Terminates the child process
  }
  printf("%-29s LLmonDB: wait for childs (%d) t=%6.3fs\n",$self->{INSTNAME},scalar $pm->running_procs(),time()-$starttime);
  $pm->wait_all_children;
  printf("%-29s LLmonDB: wait for childs ready (%d) t=%6.3fs\n",$self->{INSTNAME},scalar $pm->running_procs(),time()-$starttime);

  printf("%-29s LLmonDB: end process_LMLdata \n",$self->{INSTNAME}) if($debug>=3);
  return();
}

sub process_LMLdata_DB {
  my($self) = shift;
  my($db,$LMLdata,$grpnr,$stepnr)=@_;
  
  my($table,$options,$columns);
  printf("%-29s LLmonDB: start process_LMLdata_DB ($db) \n",$self->{INSTNAME}) if($debug>=3);
  my $starttime=time();
  printf("\n%-29s LLmonDB: DB $db\n",$self->{INSTNAME}) if($self->{VERBOSE});
  # check tables from config
  foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
    my $tableref=$t->{table};
    $table=$tableref->{name};
    $columns=$tableref->{columns};
    if(exists($tableref->{options})) {
      $options=$tableref->{options};
      
      if( exists($options->{update}) ) {
        if(exists($options->{update}->{LML})) {
          printf("%-29s LLmonDB:  -> check TABLE $db/$table (LML)\n",$self->{INSTNAME}) if($self->{VERBOSE});
          $self->process_LMLdata_from_LML($db,$table,$columns,$options,$LMLdata);
        }
          
        if(exists($options->{update}->{LLgenDB})) {
          printf("%-29s LLmonDB:  -> check TABLE $db/$table (LLgenDB)\n",$self->{INSTNAME}) if($self->{VERBOSE});
          $self->process_LMLdata_LLgenDB($db,$table,$options,$LMLdata);
        }
      }
    }
  }
  # close db (if opened)
  $self->close_db($db);
  my $endtime=time();
#  printf("$self->{INSTNAME} LLmonDB: DB %20s ready in                 %8.5fs (ts=%.5f,%.5f,l=%d,nr=%d)\n",$db,$endtime-$starttime,$starttime,$endtime,$grpnr,$stepnr); # if($self->{VERBOSE});
  printf("%-29s LLmonDB: DB %20s ready in                 %8.5fs (ts=%.5f,%.5f,l=%d,nr=%d)\n",$self->{INSTNAME},$db,$endtime-$starttime,$starttime,$endtime,$grpnr,$stepnr); # if($self->{VERBOSE});
  
  printf("$self->{INSTNAME} LLmonDB: end process_LMLdata_DB ($db) \n") if($debug>=3);
}


sub process_LMLdata_from_LML {
  my($self) = shift;
  my($db,$table,$columns,$options,$LMLdata)=@_;
  my $what=$options->{update}->{LML};
  my $listref=undef;
  my $starttime;

  my $cap=$LMLdata->{CAPABILITIES};
  my $changed=0;

  my $forceupdate=0;
  if(exists($LMLdata->{ENTRIES_BY_CAP_FORCED}->{$what})) {
    $forceupdate=1;
  }

  #  check if file contains input data for that table
  if((!exists($cap->{$what})) && (!$forceupdate) ) {
    printf("%-29s LLmonDB:     Input has no data for %s for table %s, skipping table ...\n",$self->{INSTNAME}, $what, $table) if($self->{VERBOSE});
    return($changed);
  }

  if(exists($LMLdata->{ENTRIES_BY_CAP}->{$what})) {
    $listref=$LMLdata->{ENTRIES_BY_CAP}->{$what};
    printf("%-29s LLmonDB:     found capability '%s' in input data, processing table\n",$self->{INSTNAME}, $what); # if($self->{VERBOSE});
  } elsif($forceupdate) {
    $listref=[];
    printf("%-29s LLmonDB: force update category %s for table %s \n",$self->{INSTNAME},$what, $table) if($self->{VERBOSE});
  } else {
    printf(STDERR "%-29s LLmonDB: ERROR: unknown LML update category %s for table %s \n",$self->{INSTNAME}, $what, $table);
    return($changed);
  }

  if ( ( $#{$listref} < 0)  && (!$forceupdate) )  { # no entries 
    printf("%-29s LLmonDB: WARNING no entries found for %s in table %s \n",$self->{INSTNAME},$what, $table);
    return($changed);
  }
  
  my $dbobj=$self->get_db_handle($db);

  if( exists($options->{update}->{mode}) ) {
    if($options->{update}->{mode} eq "replace") {
      $starttime=time();
      my $cnt=$dbobj->remove_contents($table);
      $changed=($cnt>0);
      printf("%-29s LLmonDB: removed contents (%d rows) of table %s \n",$self->{INSTNAME},$cnt,$table) if($self->{VERBOSE});
    }
  }

  my  ($cnt,$LMLminlastinsert,$LMLmaxlastinsert);
  if ( $#{$listref} >= 0 )  { 
    $starttime=time();
    ($cnt,$LMLminlastinsert,$LMLmaxlastinsert)=$self->add_to_table($dbobj,$table,$columns,$listref);
    $changed=1;
    printf("%-29s LLmonDB:     add.     %6d entries to table %15s/%-35s in %8.5fs\n",$self->{INSTNAME},$cnt,$db,$table,time()-$starttime);
  }

  #  check for LLgenDB some update which have to be performed before update of trigerred tables
  if( exists($options->{update}->{LLgenDB}) ) {
    $what=$options->{update}->{LLgenDB};
    if( ($what =~ "set_node2nid") ) {
      $self->set_node2nid($db,$table,$what,$LMLdata);
    }
  }
  
  if( exists($options->{update_trigger}) ) {
    if( ref $options->{update_trigger} eq 'ARRAY' ) {
      printf("%-29s LLmonDB:     trigger update of %s\n",$self->{INSTNAME},join(", ",@{$options->{update_trigger}})) if($self->{VERBOSE});
      foreach my $up_table (@{$options->{update_trigger}}) {
        $self->update_table($dbobj,$db,$up_table,$LMLminlastinsert,$LMLmaxlastinsert);
      }
    }
  }
  return($changed);
}

sub process_LMLdata_LLgenDB {
  my($self) = shift;
  my($db,$table,$options,$LMLdata)=@_;
  my $starttime;

  my $what=$options->{update}->{LLgenDB};

  my $cap=$LMLdata->{CAPABILITIES};

  #  check if file contains input data for that table
  if(
      ( ($what =~ "get_jobnodemap") || ($what =~ "get_jobtsmap") )
      && (!exists($cap->{'jobs'}))
      ) {
    printf("%-29s LLmonDB:     Input has no data for %s, skipping mapping tables ...\n",$self->{INSTNAME},'jobs') if($self->{VERBOSE});
    return(undef);
  } else {
    if( ($what =~ "get_jobnodemap") && ( $#{$LMLdata->{JOBS_RUNNING_ENTRIES}} >= 0 ) ) {
      $self->get_jobnodemap_from_LML($LMLdata->{JOBS_RUNNING_ENTRIES}, $LMLdata->{NODES_BY_NODEID});
      printf("%-29s LLmonDB:     got jobnodemap from %s/%s (LML)\n",$self->{INSTNAME},$db,$table) if($self->{VERBOSE});
    }
    if( ($what =~ "get_jobtsmap") && ( $#{$LMLdata->{JOBS_RUNNING_ENTRIES}} >= 0 ) ) {
      $self->get_jobtsmap_from_LML($LMLdata->{JOBS_RUNNING_ENTRIES}, $LMLdata->{NODES_BY_NODEID});
      printf("%-29s LLmonDB:     got jobtsmap from %s/%s (LML)\n",$self->{INSTNAME},$db,$table) if($self->{VERBOSE});
    }
  }
  
  # change mapping tables only if data was added in other tables in DB
  if( ($what =~ "add_jobtsmap") ) {
    my $dbobj=$self->get_db_handle($db);
    $starttime=time();
    my $cnt=$self->add_to_jobtsmap($dbobj,$table);
    printf("%-29s LLmonDB:     upd.     %6d entries in table %15s/%-35s in %8.5fs\n",$self->{INSTNAME},$cnt,$db,$table,time()-$starttime);
  }
  if( ($what =~ "add_jobnodemap") ) {
    my $dbobj=$self->get_db_handle($db);
    $starttime=time();
    my $cnt=$self->add_to_jobnodemap($dbobj,$table);
    printf("%-29s LLmonDB:     upd.     %6d entries in table %15s/%-35s in %8.5fs\n",$self->{INSTNAME},$cnt,$db,$table,time()-$starttime);
  }
  
  return();
}

sub add_to_table {
  my($self) = shift;
  my($dbobj,$table,$columns,$entries)=@_;
  my($colref,$colsref,$LMLcolsref,$LMLcolsdefault,$LMLminlastinsert,$LMLmaxlastinsert);
  my ($cnt,$rc,$numerrors,$LML_minlastinsert_vals,$LML_maxlastinsert_vals);

  # get config of table and mapping of attributes from config file
  my @replacelist=("-"); 
  foreach $colref (@{$columns}) {
    my $name=$colref->{name};
    if(exists($colref->{LML_from})) {
      my $from=$colref->{LML_from};
      my $default=$colref->{LML_default};
      push(@{$colsref},$name);
      push(@{$LMLcolsref},$from);
      push(@{$LMLcolsdefault},$default);
      
      if(exists($colref->{LML_minlastinsert})) {
        push(@{$LMLminlastinsert},$colref->{LML_minlastinsert});
        $LML_minlastinsert_vals->{$colref->{LML_minlastinsert}}=1e20;
      } else {
        push(@{$LMLminlastinsert},undef);
      }
      if(exists($colref->{LML_maxlastinsert})) {
        push(@{$LMLmaxlastinsert},$colref->{LML_maxlastinsert});
        $LML_maxlastinsert_vals->{$colref->{LML_maxlastinsert}}=0;
      } else {
        push(@{$LMLmaxlastinsert},undef);
      }
      
    } elsif(exists($colref->{LML_valuelist})) {
      my @help=@replacelist;
      @replacelist=();
      foreach my $repentry (@help) {
        foreach my $val (split(/\s*,\s*/,$colref->{LML_valuelist})) {
          push(@replacelist,"$repentry;$name=$val");
        }
      }
      push(@{$colsref},$name);
      push(@{$LMLcolsref},undef);
      push(@{$LMLcolsdefault},undef);
      push(@{$LMLminlastinsert},undef);
      push(@{$LMLmaxlastinsert},undef);
    }
  }
  
  my $seq=$dbobj->start_insert_sequence($table,$colsref);

  $cnt=0;$numerrors=0;
  foreach my $entry (@{$entries}) {
    foreach my $repentry (@replacelist) {
      my $data;
      for(my $c=0;$c<=$#{$colsref};$c++) {
        if(defined($LMLcolsref->[$c])) {
          my $from=$LMLcolsref->[$c];
          # replace vars in $from
          foreach my $rep (split(";",$repentry)) {
            if($rep=~/(.*)=(.*)/) {
              my($f,$t)=($1,$2);
              $from=~s/\$$f/$t/gs;
            }
          }	
          $data->[$c]=( exists($entry->{$from} ) ? $entry->{$from} : $LMLcolsdefault->[$c]);
        } else {
          # check value for var
          foreach my $rep (split(";",$repentry)) {
            if($rep=~/(.*)=(.*)/) {
              my(undef,$t)=($1,$2);
              $data->[$c]=$t;
            }
          }
          $data->[$c]=$LMLcolsdefault->[$c] if(!defined($data->[$c]));
        }

        if(defined($LMLminlastinsert->[$c])) {
          if(!defined($data->[$c])) {
            print "TMPDEB: LMLminlastinsert data->[$c] not found\n";
            next;
          }
          if($data->[$c]!~/\d+/) {
            printf("WARNING: $LMLminlastinsert->[$c] not defined: %s\n",join(",",@{$data}));
          }
          if($data->[$c]<$LML_minlastinsert_vals->{$LMLminlastinsert->[$c]}) {
            $LML_minlastinsert_vals->{$LMLminlastinsert->[$c]}=$data->[$c];
            printf("%-29s LLmonDB:     new value for %s: '%s'\n",$self->{INSTNAME},$LMLminlastinsert->[$c],$data->[$c]) if($debug>=1);
          }
        }
        if(defined($LMLmaxlastinsert->[$c])) {
          $LML_maxlastinsert_vals->{$LMLmaxlastinsert->[$c]}=$data->[$c] if($data->[$c]>$LML_maxlastinsert_vals->{$LMLmaxlastinsert->[$c]});
        }
      }
      $rc=$dbobj->insert_sequence($seq,$data);
      $cnt++;
      $numerrors++ if($rc != 1); # inserted on row
      # print "insert(",join(",",@{$data}),")\n";
    }
  }
  
  $dbobj->end_insert_sequence($seq);
  printf("$self->{INSTNAME} LLmonDB: end add_to_table (add $cnt entries to $table, #errors=$numerrors)\n") if($debug>=3);
  
  return($cnt,$LML_minlastinsert_vals);
  
  $self->{A}=0;  #dummy statement to avoid unused warning
}

sub update_table {
  my($self) = shift;
  my($dbobj,$db,$table,$LMLminlastinsert,$LMLmaxlastinsert)=@_;
  my($options,@trig_tables);
  my $cnt=0;

  printf("$self->{INSTNAME} LLmonDB: update_table: $db, $table\n") if($debug>=3);

  printf("$self->{INSTNAME} LLmonDB:  -> check TABLE $db/$table (triggered)\n") if($self->{VERBOSE});
  foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
    my $tableref=$t->{table};
    next if($tableref->{name} ne $table);
    if(exists($tableref->{options})) {
      $options=$tableref->{options};
    
      if(exists($options->{update}->{sql_update_contents})) {
        my $starttime=time();

        if(exists($options->{update}->{sql_update_contents}->{sql})) {
          my $sqldebug=0;
          $sqldebug=$options->{update}->{sql_update_contents}->{sqldebug} if(exists($options->{update}->{sql_update_contents}->{sqldebug}));
          my $sql=$options->{update}->{sql_update_contents}->{sql};
          if(exists($options->{update}->{sql_update_contents}->{vars})) {
            foreach my $varpattern (split(/\s*,\s*/,$options->{update}->{sql_update_contents}->{vars})) {
              if($varpattern=~/^\s*(.*)\s*\=\s*(.*)\s*$/) {
                my($var,$val)=($1,$2);
                $sql=~s/$var/$val/gs;
              } else {
                my $var=$varpattern;
                if(exists($LMLminlastinsert->{$var})) {
                  my $val=$LMLminlastinsert->{$var};
                  $sql=~s/$var/$val/gs;
                }
                if(exists($LMLmaxlastinsert->{$var})) {
                  my $val=$LMLmaxlastinsert->{$var};
                  $sql=~s/$var/$val/gs;
                }
              }
            }
          }
          foreach my $subsql (split(/\s*;\s*/,$self->replace_vars($sql))) {
            my $stime=time();
            my $rc=$dbobj->execute_sql($subsql);
            $cnt=$rc; # count only last operation
            if($sqldebug) {
              printf("%-29s LLmonDB:     call sql_update_contents on %s: lines changed=%4d %4.2fs SQL: %s\n",$self->{INSTNAME},$table,$rc,time()-$stime,$subsql);
            }
          }
          if(exists($options->{update}->{sql_update_contents}->{aggr_by_time_resolutions})) {
            $self->update_table_aggr_by_time($dbobj,$table,$tableref,$LMLminlastinsert);
          }
        }
        
        if( exists($options->{update_trigger}) ) {
          foreach my $up_table (@{$options->{update_trigger}}) {
            push(@trig_tables,$up_table);
          }
        }
        printf("%-29s LLmonDB:     trg_upd. %6d entries in table %15s/%-35s in %8.5fs\n",$self->{INSTNAME},$cnt,$db,$table,time()-$starttime);
      }
    }
  }
  
  foreach my $up_table (@trig_tables) {
    next if($up_table eq $table); # avoid infinite loop if a table has input + triggered update methods
    $self->update_table($dbobj,$db,$up_table,$LMLminlastinsert,$LMLmaxlastinsert);
  }
  
  return($cnt);
  
  $self->{A}=0;  #dummy statement to avoid unused warning
}

sub update_table_aggr_by_time {
  my($self) = shift;
  my($dbobj,$table,$tableref,$LMLminlastinsert)=@_;
  my $opt=$tableref->{options}->{update}->{sql_update_contents};

  # printf("$self->{INSTNAME} update_table_aggr_by_time: missing option: aggr_by_time_resolutions\n"),return(-1) if(!exists($opt->{aggr_by_time_resolutions}));
  my @resultions=(@{$opt->{aggr_by_time_resolutions}});
  my $base_res= shift @resultions;
  # printf("$self->{INSTNAME} update_table_aggr_by_time: missing option: aggr_by_time_mintsvar\n"),return(-1) if(!exists($opt->{aggr_by_time_mintsvar}));
  my $mintsval=0;
  if(exists($opt->{aggr_by_time_mintsvar})) {
    my $mintsvar=$opt->{aggr_by_time_mintsvar};
    $mintsval=$LMLminlastinsert->{$mintsvar} if(exists($LMLminlastinsert->{$mintsvar}));
  } elsif(exists($opt->{aggr_by_time_mintslimit})) {
    $mintsval=$self->replace_vars("(TS_NOW - 60.0*".$opt->{aggr_by_time_mintslimit}.")");
  }

  my $sqldebug=$opt->{sqldebug} if(exists($opt->{sqldebug}));
        
  # print "$self->{INSTNAME} update_table_aggr_by_time: table   = $table\n";
  # print "$self->{INSTNAME} update_table_aggr_by_time: mintsvar= $mintsvar ($mintsval)\n";
  # print "$self->{INSTNAME} update_table_aggr_by_time: base_res= $base_res\n";
  my(@keyvars,@aggrvars1,@aggrvars2,$tsvar);
  foreach my $colref (@{$tableref->{columns}}) {
    my $name=$colref->{name};
    if(exists($colref->{time_aggr})) {
      my $val=$colref->{time_aggr};
      $tsvar=$name if($val eq "TS");
      push(@keyvars, $name) if($val eq "KEY");
      if($val=~/(AVG|SUM|MIN|MAX|COUNT)/) {
        push(@aggrvars1, $name);
        push(@aggrvars2, "$val\($name\)");
      }
    }
  }
  foreach my $res (@resultions) {
    my $sql_del="DELETE FROM $table WHERE (_time_res=$res) AND ($tsvar >=  CAST($mintsval/($res*60) AS INT) * ($res*60) );";
    # print "$self->{INSTNAME} update_table_aggr_by_time: res=$res sql_del=$sql_del\n";
    my $rc=$dbobj->execute_sql($sql_del);
    if($sqldebug) {
      printf("$self->{INSTNAME} LLmonDB:     call sql_update_contents on %s: lines changed=%4d SQL: %s\n",$table,$rc,$sql_del);
    }
    my $sql_ins;
    if(@keyvars) {
      $sql_ins="INSERT INTO $table (_time_res,_time_cnt,$tsvar, ".
                join(",",@keyvars).",".
                join(",",@aggrvars1).")".
                " SELECT $res, COUNT($tsvar),".
                "(CAST($tsvar/($res*60.0) AS INT) * ($res*60.0) ) res,".join(",",@keyvars).",".
                join(",",@aggrvars2).
                " FROM $table".
                            " WHERE (_time_res=$base_res) AND ($tsvar >= CAST($mintsval/($res*60.0) AS INT) * ($res*60.0) )".
                " GROUP BY ".join(",",@keyvars).",res";
    } else {
      $sql_ins="INSERT INTO $table (_time_res,_time_cnt,$tsvar, ".
                join(",",@aggrvars1).")".
                " SELECT $res, COUNT($tsvar),".
                "(CAST($tsvar/($res*60.0) AS INT) * ($res*60.0) ) res,".join(",",@aggrvars2).
                " FROM $table".
                            " WHERE (_time_res=$base_res) AND ($tsvar >= CAST($mintsval/($res*60.0) AS INT) * ($res*60.0) )".
                " GROUP BY res";
    }
    # print "$self->{INSTNAME} update_table_aggr_by_time: res=$res sql_ins=$sql_ins\n"; 
    $rc=$dbobj->execute_sql($sql_ins);
    if($sqldebug) {
      printf("$self->{INSTNAME} LLmonDB:     call sql_update_contents on %s: lines changed=%4d SQL: %s\n",$table,$rc,$sql_ins);
    }
  }
  return();
}


sub set_node2nid {
  my($self) = shift;
  my($db,$table,$what,$LMLdata)=@_;
  my($col,$desttab,$destcol1,$destcol2,$nodeid);
  my $cnt=0;
  
  printf("$self->{INSTNAME} LLmonDB:     set_node2nid: $db, $table, $what\n") if($debug>=3);

  # parse what option
  if($what=~/^set_node2nid\((.*)\)$/) {
    my $optlist=$1;
    ($col,$desttab,$destcol1,$destcol2)=split(/\s*,\s*/,$optlist);
  } else {
    printf("$self->{INSTNAME} LLmonDB:     set_node2nid: wrong parameter list: %s\n",$what);
    return(-1);
  }
  
  # get list of known nodeids,nid
  my $node2nid_hash=$self->query($db,$desttab,
                                {
                                  type => 'hash_values',
                                  hash_keys => 'nodeid',
                                  hash_value => 'nid',
                                });

  # compute max_nid from existing mapping
  my $max_nid=-1;
  foreach $nodeid (keys(%{$node2nid_hash})) {
    $max_nid=$node2nid_hash->{$nodeid}->{nid} if($node2nid_hash->{$nodeid}->{nid}>$max_nid);
  }

  # check for new nodes 
  my $nodesinLML=$LMLdata->{NODES_BY_NODEID};
  my %newnodes;
  foreach $nodeid (keys(%{$nodesinLML})) {
    if(!exists($node2nid_hash->{$nodeid})) {
      $newnodes{$nodeid}=++$max_nid;
    }
  }

  #  insert into data base
  if(keys(%newnodes) > 0) {
    my($colsref,$data,$numerrors,$rc);
    push(@{$colsref},"nodeid");push(@{$colsref},"nid");
    
    my $dbobj=$self->get_db_handle($db);
    my $seq=$dbobj->start_insert_sequence($desttab,$colsref);
    $cnt=0;$numerrors=0;
    foreach $nodeid (keys(%newnodes)) {
      $data->[0]=$nodeid;
      $data->[1]=$newnodes{$nodeid};
      $rc=$dbobj->insert_sequence($seq,$data);
      $numerrors++ if($rc != 1); # inserted on row
      $cnt++;
    }
    $dbobj->end_insert_sequence($seq);
    printf("$self->{INSTNAME} LLmonDB:     set_node2nid  (add %d entries to %s, #errors=%d)\n",$cnt,$desttab,$numerrors)  if($self->{VERBOSE});
  }
  
  # print Dumper($node2nid_hash);
  
  return($cnt);
  
  $self->{A}=0;  #dummy statement to avoid unused warning
}

1;
