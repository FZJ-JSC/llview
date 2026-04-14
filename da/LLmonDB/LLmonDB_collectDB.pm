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
my $debug=3;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time sleep );
use POSIX ":sys_wait_h";

#my $patint="([\\+\\-\\d]+)";   # Pattern for Integer number
#my $patfp ="([\\+\\-\\d.E]+)"; # Pattern for Floating Point number
my $patwrd="([\^\\s]+)";       # Pattern for Work (all noblank characters)
#my $patbl ="\\s+";             # Pattern for blank space (variable length)


sub process_collectDB_update {
  my($self) = shift;
  my($action) = shift;
  my($scan_db) = shift;
  my($db,$table,$options,$known_tables);

  printf("$self->{INSTNAME} LLmonDB: start process_collectDB_update\n") if($debug>=3);

  # scan for known tables
  foreach $db (sort(keys(%{$self->{CONFIGDATA}->{databases}}))) {
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      $known_tables->{$db}->{$table}=1;
    }
  }
  
  # find table which need collectDB_update
  foreach $db (sort(keys(%{$self->{CONFIGDATA}->{databases}}))) {
    if(defined($scan_db)) {
      next if($db ne $scan_db);
    }
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      $known_tables->{$db}->{$table}=1;
      if(exists($tableref->{options})) {
        $options=$tableref->{options};
        if( exists($options->{update}) ) {
          if($action=~/LLjobreport/) {
            my $what=undef;
            if(exists($options->{update}->{LLjobreport})) {
              $what=$options->{update}->{LLjobreport};
            }
            if(exists($options->{update}->{LLreport})) {
              $what=$options->{update}->{LLreport};
            }
            if(defined($what)) {
              if( $what =~ /update_from_other_db\($patwrd,$patwrd,$patwrd\)/ ) {
                my($ukey,$stab,$ktab)=($1,$2,$3);
                
                printf("$self->{INSTNAME} LLmonDB:     update_from_other_db(%s,%s,%s) for %s/%s\n",$ukey,$stab,$ktab,$db,$table) if($self->{VERBOSE});
                my $keepoldentries=1;
                $self->process_collectDB_update_from_other_DB($db,$table,$tableref,$ukey,$stab,$ktab,$keepoldentries,$known_tables);
                
                if( exists($options->{update_trigger}) && (ref($options->{update_trigger}) eq "ARRAY") ) {
                  printf("$self->{INSTNAME} LLmonDB:     trigger update of %s\n",join(", ",@{$options->{update_trigger}})) if($self->{VERBOSE});
                  foreach my $up_table (@{$options->{update_trigger}}) {
                    my $dbobj=$self->get_db_handle($db);
                    $self->update_table($dbobj,$db,$up_table,undef,undef);
                  }
                }
                # close the DB
                $self->close_db($db);
              }
            }
          }
          if($action=~/LMLstat/) {
            if(exists($options->{update}->{LMLstat})) {
              my $what=$options->{update}->{LMLstat};
              if( $what =~ /update_from_other_db\($patwrd,$patwrd,$patwrd\)/ ) {
                my($ukey,$stab,$ktab)=($1,$2,$3);

                # my $cnt1=$self->remove_contents($db,$ktab);
                # my $cnt2=$self->remove_contents($db,$table);
                # printf("$self->{INSTNAME} LLmonDB:     remove_contents() for %s/%s (%d,%d) rows\n",$db,$table,$cnt1,$cnt2) if($self->{VERBOSE});
                
                printf("$self->{INSTNAME} LLmonDB:     update_from_other_db(%s,%s,%s) for %s/%s\n",$ukey,$stab,$ktab,$db,$table) if($self->{VERBOSE});
                my $keepoldentries=0;
                $self->process_collectDB_update_from_other_DB($db,$table,$tableref,$ukey,$stab,$ktab,$keepoldentries,$known_tables);

                if( exists($options->{update_trigger}) && (ref($options->{update_trigger}) eq "ARRAY") ) {
                  printf("$self->{INSTNAME} LLmonDB:     trigger update of %s\n",join(", ",@{$options->{update_trigger}})) if($self->{VERBOSE});
                  foreach my $up_table (@{$options->{update_trigger}}) {
                    my $dbobj=$self->get_db_handle($db);
                    $self->update_table($dbobj,$db,$up_table,undef,undef);
                  }
                }
                # close the DB
                $self->close_db($db);
              }
            }
          }
        }
      }
    }
  }

  printf("$self->{INSTNAME} LLmonDB: end process_collectDB_update \n") if($debug>=3);
  return();
}

sub process_collectDB_update_from_other_DB {
  my($self) = shift;
  my($db,$table,$tableref,$ukey,$stab,$ktab,$keepoldentries,$known_tables)=@_;
  
  printf("$self->{INSTNAME} LLmonDB: start process_collectDB_update_from_other_DB ($db,$table) \n") if($debug>=3);
  my $starttime=time();

  printf("$self->{INSTNAME} LLmonDB:  -> check TABLE $db/$table (LML)\n") if($self->{VERBOSE});

  # my $dbobj=$self->get_db_handle($db);

  # get status info
  my $status_hash=$self->query($db,$stab,
                {
                  type => 'hash_values',
                  hash_keys => 'tabspec',
                  hash_value => 'lasttscol,lastts',
                });
  # print Dumper($status_hash);

  # collect DBs and columns
  my ($colsref,$colsdef,$allcolnames,$DBqueries,@qDBs,$mapDBs);
  my $columns=$tableref->{columns};
  
  foreach my $colref (@{$columns}) {
    my $name=$colref->{name};
    push(@{$colsref},$name);
    
    # print "TMPDEB: $name\n", Dumper($colref);
    if(exists($colref->{LLDB_from})) {
      my $DBfrom=$colref->{LLDB_from};
      my($qdb,$qtab,$qcol)=split("/",$DBfrom);	
      $qcol=$name if(!defined($qcol)); # identical column names
      my $qfrom="$qdb/$qtab";
      if($name ne $ukey) { # don't store unique key (e.g. jobid)
        push(@qDBs,$qfrom) if(!exists($DBqueries->{$qfrom}));
        push(@{$DBqueries->{$qfrom}->{cols}},$name);
        $DBqueries->{$qfrom}->{colmap}->{$qcol}=$name;
        push(@{$DBqueries->{$qfrom}->{qcols}},$qcol);
        push(@{$allcolnames},$name);
      }
      my $DBdefault=exists($colref->{LL_default})?$colref->{LL_default}:"-1";
      $colsdef->{$name}=$DBdefault;
      if(exists($colref->{LLDB_from_filter})) {
        push(@{$DBqueries->{$qfrom}->{where}},"$name=\"".$colref->{LLDB_from_filter}."\"" );
      }
      if(exists($colref->{LLDB_from_lastts})) {
        if($colref->{LLDB_from_lastts} eq "yes") {
          $DBqueries->{$qfrom}->{lasttscol}=$qcol;
          if(exists($status_hash->{$qfrom})) {
            push(@{$DBqueries->{$qfrom}->{where}},"$qcol > ".$status_hash->{$qfrom}->{lastts} );
          } else {
            $status_hash->{$qfrom}->{tabspec}=$qfrom;
            $status_hash->{$qfrom}->{lastts}=-1;
            $status_hash->{$qfrom}->{lasttscol}=$qcol;
          }
        }
      }
    }
    
    if(exists($colref->{LLDB_map})) {
      if($colref->{LLDB_map}=~/lookup\(([^\)]+)\)/) {
        my $parms=$1;
        my($from,$qcmpcol,$cmpcol)=split(/\s*,\s*/,$parms);
        # print "TMPDEB: ($from,$cmpcol)\n";
        my($qdb,$qtab,$qcol)=split("/",$from);
        my $qfrom="$qdb/$qtab";
        $mapDBs->{$qfrom}->{$name}->{qcol}=$qcol;
        $mapDBs->{$qfrom}->{$name}->{qcmpcol}=$qcmpcol;
        $mapDBs->{$qfrom}->{$name}->{cmpcol}=$cmpcol;
        $mapDBs->{$qfrom}->{$name}->{default}=$colref->{LL_default};
      }
    }
  }
  if($self->{VERBOSE}) {
    for(my $d=0;$d< scalar @qDBs; $d++) {
      if($d%4==0) {
        print("\n") if($d>0);
        printf("$self->{INSTNAME} query DBs: %s", $qDBs[$d]);
      } else {
        printf(",%s", $qDBs[$d]);
      }
    }
    print("\n");
  }

  # do the queries to other DBs
  my $newkeys;
  my ($db_opened);
  foreach my $dbspec (@qDBs) {
    my ($qdb,$qtab)=split("/",$dbspec);

    if(!exists($known_tables->{$qdb})) {
      printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping attributes from that database\n",$qdb);
      next;
    }
    if(!exists($known_tables->{$qdb}->{$qtab})) {
      printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping attributes from that table\n",$qdb,$qtab);
      next;
    }
    $db_opened->{$qdb}++;
    # get new data from other DBs
    my $qstarttime=time();
    my $qdata=$self->query($qdb,$qtab,
              {
              type => 'hash_values',
              hash_keys => $ukey,
              hash_value => join(",",@{$DBqueries->{$dbspec}->{qcols}}),
              where => exists($DBqueries->{$dbspec}->{where})?
                join(" AND ",@{$DBqueries->{$dbspec}->{where}}):undef
              });
    
    $DBqueries->{$dbspec}->{data}=$qdata;
    $DBqueries->{$dbspec}->{colmap}->{$ukey}=$ukey;

    foreach my $key (keys(%{$qdata})) {
      $newkeys->{$key}=1;
      if(exists($status_hash->{$dbspec})) {
        if(exists($status_hash->{$dbspec}->{lasttscol})) {
          if ($qdata->{$key}->{$status_hash->{$dbspec}->{lasttscol}} > $status_hash->{$dbspec}->{lastts} ) {
            $status_hash->{$dbspec}->{lastts} = $qdata->{$key}->{$status_hash->{$dbspec}->{lasttscol}};
          }
        }
      }
    }
    # print "TMPDEB: qdata $dbspec:",Dumper($qdata->{10868782}),"\n";
    # print "TMPDEB: qdata where:",exists($DBqueries->{$dbspec}->{where})?
    # 			       join(" AND ",@{$DBqueries->{$dbspec}->{where}}):"-","\n";
    printf("$self->{INSTNAME}  --> got %4d new/updated entries from table %22s/%-26s  in  %8.5fs\n",
            scalar keys(%{$qdata}),$qdb,$qtab, time()-$qstarttime) if($self->{VERBOSE});
  }

  # close all other DBs
  foreach my $qdb (keys(%{$db_opened})) {
    $self->close_db($qdb);
  }

  # do the queries to mapping DBs
  # print "TMPDEB: ",Dumper(\$mapDBs),"\n";
  foreach my $dbspec (keys(%{$mapDBs})) {
    my ($qdb,$qtab)=split("/",$dbspec);
    foreach my $col (keys(%{$mapDBs->{$dbspec}})) {
      my $qref=$mapDBs->{$dbspec}->{$col};
      my $qstarttime=time();
      my $qdata=$self->query($qdb,$qtab,
                {
                  type => 'hash_values',
                  hash_keys => $qref->{qcmpcol},
                  hash_value => $qref->{qcol},
                  where => undef
                });
      $qref->{data}=$qdata;
      printf("$self->{INSTNAME}  --> got %4d lookup      entries from table %22s/%-26s  in  %8.5fs (%s)\n",
              scalar keys(%{$qdata}),$qdb,$qtab, time()-$qstarttime, $col) if($self->{VERBOSE});
      # print "TMPDEB: ",Dumper(\$qdata),"\n";
    }
  }
  
  # query data of existing jobs (where new data is found)
  my $estarttime=time();
  my $existdata=$self->query($db,$table,
                  {
                  type => 'hash_values',
                  hash_keys => $ukey,
                  hash_value => join(",",@{$allcolnames}),
                  where => "$ukey in (\"".join("\",\"",(keys(%{$newkeys})))."\")"
                  });

  # init new entries in existdata in memory
  my $updated_keys;
  foreach my $key (keys(%{$newkeys})) {
    if(exists($existdata->{$key})) {
      $updated_keys->{$key}=1;
    } else {
      foreach my $k (keys(%{$colsdef})) {
        $existdata->{$key}->{$k}=$colsdef->{$k};
      }
    }
  }
  
  # insert new data in existdata in memory
  foreach my $dbspec (keys(%{$DBqueries})) {
    my $qdata=$DBqueries->{$dbspec}->{data};
    my $qcolmap=$DBqueries->{$dbspec}->{colmap};
    foreach my $key (keys(%{$qdata})) {
      foreach my $k (keys(%{$qdata->{$key}})) {
        print STDERR "TMPDEB: ERROR: $key $k<\n" if (!defined($qdata->{$key}->{$k}));
        $existdata->{$key}->{$qcolmap->{$k}}=$qdata->{$key}->{$k};
      }
    }
  }

  # map value from mapDBs
  foreach my $dbspec (keys(%{$mapDBs})) {
    foreach my $col (keys(%{$mapDBs->{$dbspec}})) {
      my $qref=$mapDBs->{$dbspec}->{$col};
      my $qdata=$qref->{data};
      foreach my $key (keys(%{$existdata})) {
        my $lkey=$existdata->{$key}->{$qref->{cmpcol}};
        if(exists($qdata->{$lkey})) {
          $existdata->{$key}->{$col}=$qdata->{$lkey}->{$qref->{qcol}};
        } else {
          # print "TMPDEB: existdata->{$key}->{$col}=$existdata->{$key}->{$col}=qdata->{$lkey}->{$qref->{qcol}}\n";
          $existdata->{$key}->{$col}=$qref->{default};
        }
      }
    }
  }
  printf("$self->{INSTNAME} LLmonDB:  --> updated %4d entries in memory %s in  %8.5fs\n",
          scalar keys(%{$existdata}), " "x50,time()-$estarttime) if($self->{VERBOSE});
  
  # remove existing data from DB table
  my $sstarttime=time();
  if($keepoldentries) {
    if(scalar keys(%{$updated_keys})) {
      $self->delete($db,$table,
              {
                type => 'some_rows',
                where => "$ukey in (\"".join("\",\"",(keys(%{$updated_keys})))."\")"
              });
    }
  } else {
    # remove all records (if new data is there)
    if(scalar keys(%{$existdata})) {
      $self->remove_contents($db,$table);
    }
  }
  # add new and updated data to DB table
  my $seq=$self->start_insert_sequence($db,$table,$colsref);
  foreach my $key (keys(%{$existdata})) {
    my @data;
    foreach my $k ( @{$colsref} ) {
      push(@data,$existdata->{$key}->{$k});
    }
    $self->insert_sequence($db,$table,$seq,\@data  );
  }
  $self->end_insert_sequence($db,$table,$seq);

  # remove tabstat info about queried tables
  $self->delete($db,$stab,
          {
            type => 'some_rows',
            where => "tabspec in (\"".join("\",\"",(keys(%{$DBqueries})))."\")"
          });
  
  # add new tabstat to DB table
  my @tabstatcolsref=("tabspec","lasttscol","lastts");
  $seq=$self->start_insert_sequence($db,$stab,\@tabstatcolsref);
  foreach my $key (keys(%{$status_hash})) {
    my @data= ( $status_hash->{$key}->{"tabspec"},
                $status_hash->{$key}->{"lasttscol"},
                $status_hash->{$key}->{"lastts"});
    $self->insert_sequence($db,$stab,$seq,\@data  );
  }
  $self->end_insert_sequence($db,$stab,$seq);

  # remove info about updated entries
  $self->delete($db,$ktab,
                {
                  type => 'all_rows'
                });
  
  # add info about recently updated entries to DB table
  my @updatetabcolref=($ukey);
  $seq=$self->start_insert_sequence($db,$ktab,\@updatetabcolref);
  foreach my $key ((keys(%{$newkeys}))) {
    my @data= ($key);
    $self->insert_sequence($db,$ktab,$seq,\@data  );
  }
  $self->end_insert_sequence($db,$ktab,$seq);

  printf("$self->{INSTNAME} LLmonDB:  --> updated %4d entries in DB %s in  %8.5fs\n",
          scalar keys(%{$newkeys}), " "x54,time()-$sstarttime) if($self->{VERBOSE});

  
  my $endtime=time();
  printf("$self->{INSTNAME} LLmonDB: table %25s/%-20s ready (%6d entries)   in  %8.5fs (ts=%.5f,%.5f,l=1,nr=1)\n",
          $db,$table,scalar keys(%{$newkeys}),
	 $endtime-$starttime,
	 $starttime,$endtime
       ) if($self->{VERBOSE});

  printf("$self->{INSTNAME} LLmonDB: end process_LMLdata_DB ($db) \n") if($debug>=3);
}

1;
