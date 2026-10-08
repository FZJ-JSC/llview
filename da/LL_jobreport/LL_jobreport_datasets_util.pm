# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_jobreport;

my $VERSION='$Revision: 1.00 $';

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_jobreport_datasets_constants;

sub get_datasetstat_from_DB {
  my $self = shift;
  my($stat_db,$stat_table,$where)=@_;

  if(!defined($stat_db)) {
    printf(STDERR "[get_datasetstat_from_DB] ERROR stat_db not defined (%s,%s,%s)\n",caller());
    return(); 
  };
  if(!defined($stat_table)) {
    printf(STDERR "[get_datasetstat_from_DB] ERROR stat_table not defined (%s,%s,%s)\n",caller());
    return(); 
  };

  # print "start get_datasetstat_from_DB $stat_db,$stat_table\n";
  my $dataref=$self->{DB}->query($stat_db,$stat_table,
                                  {
                                    type => "hash_values",
                                    hash_keys => "dataset",
                                    where => $where,
                                    hash_value => "name,ukey,lastts_saved,checksum,status,mts"
                                  });

  $self->{DATASETSTAT}->{$stat_db}->{$stat_table}=$dataref;
  # print "end get_datasetstat_from_DB $stat_db,$stat_table,$where\n";
}

sub save_datasetstat_in_DB {
  my $self = shift;
  my($stat_db,$stat_table,$where)=@_;

  # print "start save_datasetstat_in_DB $stat_db,$stat_table\n";
  # remove info from table
  if($where) {
    $self->{DB}->delete($stat_db,$stat_table,
                        {
                        type => 'some_rows',
                        where => $where    
                        });
  } else {
    $self->{DB}->delete($stat_db,$stat_table,
                        {
                        type => 'all_rows'
                        });
  }
  # add new dirstat to DB table
  my @tabstatcolsref=("dataset","name","ukey","lastts_saved","checksum","status","mts");
  my $seq=$self->{DB}->start_insert_sequence($stat_db,$stat_table,\@tabstatcolsref);
  my $ds=$self->{DATASETSTAT}->{$stat_db}->{$stat_table};
  foreach my $key (keys(%{$ds})) {
    if(!defined($ds->{$key}->{"dataset"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR dataset for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"name"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR name for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"ukey"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR ukey for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"lastts_saved"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR lastts_saved for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"checksum"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR checksum for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"status"})) {
      print STDERR "[save_datasetstat_in_DB] ERROR status for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };
    if(!defined($ds->{$key}->{"mts"})) {
      print "save_datasetstat_in_DB: ERROR status for key $key not defined in table $stat_table of db $stat_db\n";
      next; 
    };

    my @data = ($ds->{$key}->{"dataset"},
                $ds->{$key}->{"name"},
                $ds->{$key}->{"ukey"},
                $ds->{$key}->{"lastts_saved"},
                $ds->{$key}->{"checksum"},
                $ds->{$key}->{"status"},
                $ds->{$key}->{"mts"});
    $self->{DB}->insert_sequence($stat_db,$stat_table,$seq,\@data  );
  }
  $self->{DB}->end_insert_sequence($stat_db,$stat_table,$seq);

  # print "end save_datasetstat_in_DB $stat_db,$stat_table\n";
}

sub diff_datasetstat_with_DB {
  my $self = shift;
  my($stat_db,$stat_table,$where,$filename)=@_;

  # print "start get_datasetstat_from_DB $stat_db,$stat_table\n";
  my $orids=$self->{DB}->query($stat_db,$stat_table,
				    {
				      type => "hash_values",
				      hash_keys => "dataset",
				      where => $where,
				      hash_value => "name,ukey,lastts_saved,checksum,status,mts"
				    });
  my $ds=$self->{DATASETSTAT}->{$stat_db}->{$stat_table};

  open(LOG, "> $filename") or die "cannot open $filename";
  printf(LOG "WHERE: %s\n",$where); 
  printf(LOG "KEYS:  %d keys <> %d keys \n",scalar keys(%{$orids}), scalar keys(%{$ds}));
  # NEW files
  foreach my $key (keys(%{$ds})) {
    if(!exists($orids->{$key})) {
      printf(LOG "[%8s] %-70s %-30s %8d %d %d %-40s %d\n","NEW",
	     $ds->{$key}->{"dataset"},$ds->{$key}->{"name"},$ds->{$key}->{"ukey"},$ds->{$key}->{"lastts_saved"},$ds->{$key}->{"checksum"},
	     &get_status_desc($ds->{$key}->{"status"}),$ds->{$key}->{"mts"});
    }
  }

  # REMOVED files
  foreach my $key (keys(%{$orids})) {
    if(!exists($ds->{$key})) {
      printf(LOG "[%8s] %-70s %-30s %8d %d %d %-40s %d\n","REMOVED",
	     $orids->{$key}->{"dataset"},$orids->{$key}->{"name"},$orids->{$key}->{"ukey"},$orids->{$key}->{"lastts_saved"},$orids->{$key}->{"checksum"},
	     &get_status_desc($orids->{$key}->{"status"}),$orids->{$key}->{"mts"});
    } else {
      if( ($orids->{$key}->{"dataset"} ne $ds->{$key}->{"dataset"} )
	  || ($orids->{$key}->{"name"} ne $ds->{$key}->{"name"} )
	  || ($orids->{$key}->{"ukey"} != $ds->{$key}->{"ukey"} )
	  || ($orids->{$key}->{"lastts_saved"} != $ds->{$key}->{"lastts_saved"} )
	  || ($orids->{$key}->{"checksum"} != $ds->{$key}->{"checksum"} )
	  || ($orids->{$key}->{"status"} != $ds->{$key}->{"status"} )
	  || ($orids->{$key}->{"mts"} != $ds->{$key}->{"mts"} )
	  ) {
	printf(LOG "[%8s] %-70s %-30s %8d %10d %8d %-40s %10d\n","DIFF <",
	       $orids->{$key}->{"dataset"},$orids->{$key}->{"name"},$orids->{$key}->{"ukey"},$orids->{$key}->{"lastts_saved"},$orids->{$key}->{"checksum"},
	       &get_status_desc($orids->{$key}->{"status"}),$orids->{$key}->{"mts"});
	
	printf(LOG "[%8s] %-70s %-30s %-8s %-10s %-8s %-40s %-10s\n","DIFF >",
	       $orids->{$key}->{"dataset"} ne $ds->{$key}->{"dataset"}?$ds->{$key}->{"dataset"}:"-",
	       $orids->{$key}->{"name"} ne $ds->{$key}->{"name"}?$ds->{$key}->{"name"}:"-",
	       $orids->{$key}->{"ukey"} ne $ds->{$key}->{"ukey"}?$ds->{$key}->{"ukey"}:"-",
	       $orids->{$key}->{"lastts_saved"} != $ds->{$key}->{"lastts_saved"}?$ds->{$key}->{"lastts_saved"}:"-",
	       $orids->{$key}->{"checksum"} != $ds->{$key}->{"checksum"}?$ds->{$key}->{"checksum"}:"-",
	       $orids->{$key}->{"status"} != $ds->{$key}->{"status"}?&get_status_desc($ds->{$key}->{"status"}):"-",
	       $orids->{$key}->{"mts"} != $ds->{$key}->{"mts"}?$ds->{$key}->{"mts"}:"-"
	    );
	
      }
    }
  }

  close(LOG);
}


1;
