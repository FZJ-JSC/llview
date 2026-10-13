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
use Time::HiRes qw ( time );
use IO::File;
use Parallel::ForkManager;

sub DBstat {
  my($self) = shift;
  my($dblist,$tmpdir,$MAX_PROCESSES) = @_;
  my($db,$table);
  my($data);
  my $currentts=$self->{CURRENTTS};
  my $currentdate=sec_to_date($currentts);
  printf("$self->{INSTNAME}  LLmonDB: start archive_data at $currentdate\n") if($debug>=3);

  my $db_to_stat=undef;
  if(defined($dblist)) {
    foreach my $d (split(/\s*,\s*/,$dblist)) {
      $db_to_stat->{$d}=1;
    }
  }

  $tmpdir="." if(! defined($tmpdir));
  
  # parallel processing
  my $pm = Parallel::ForkManager->new($MAX_PROCESSES,$tmpdir);

  # data structure retrieval and handling
  $pm -> run_on_finish ( # called BEFORE the first call to start()
          sub {
            my ($pid, undef, undef, undef, undef, $data_structure_reference) = @_;
            
            # retrieve data structure from child
            if (defined($data_structure_reference)) {  # children are not forced to send anything
              foreach my $db (keys(%{$data_structure_reference})) {
                $data->{$db}=$data_structure_reference->{$db};
              }
            } else {  # problems occurring during storage or retrieval will throw a warning
              print qq|No message received from child process $pid!\n|;
            }
          });

  my $dbcnt=0;
  # look up db/table combinations, needed later for non_existent option
  DB_LOOP:
  foreach $db (keys(%{$self->{CONFIGDATA}->{databases}})) {
    if(defined($db_to_stat)) {
      if(!exists($db_to_stat->{$db})) {
        printf("$self->{INSTNAME}  LLmonDB:     -> skip DB $db due to dblist option\n") if($self->{VERBOSE});
        next;
      }
    }
    $dbcnt++;
    # Forks and returns the pid for the child: # my $pid = 
    $pm->start($db) and next DB_LOOP;
    my $ldata;
    my $qtime=time();
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      my $options=$tableref->{options};
      my $is_time_aggr=0;
      my @res=(-1);
      if(exists($options->{update})) {
        if(exists($options->{update}->{sql_update_contents})) {
          if(exists($options->{update}->{sql_update_contents}->{aggr_by_time_resolutions})) {
            @res=@{$options->{update}->{sql_update_contents}->{aggr_by_time_resolutions}};
            $is_time_aggr=1;
          }
        }
      }
      foreach my $res (@res) {
        my $ltable=$table;
        if($res!=-1) {
          $ltable=sprintf("%s_res_%04d",$table,$res);
        }
        $ldata->{$db}->{$ltable}->{ts}=int($currentts);
        $ldata->{$db}->{$ltable}->{time_aggr_res}=$res;
        $ldata->{$db}->{$ltable}->{db}="$db";
        $ldata->{$db}->{$ltable}->{table}="$ltable";
        $ldata->{$db}->{$ltable}->{tabpath}="$db/$ltable";
        if($res==-1) {
          $ldata->{$db}->{$ltable}->{nrows}=$self->query($db,$table,
                                                          {
                                                            type => 'get_count'
                                                          });
        } else {
          $ldata->{$db}->{$ltable}->{nrows}=$self->query($db,$table,
                                                          {
                                                            type => 'get_count',
                                                            where => " ( _time_res = $res ) "
                                                          });
        }
        my $columnsref=$tableref->{columns};
        my $tscol=undef;

        foreach my $searchpattern (
            "ts", "lastts", "lastts_saved","errmsgts","rc_lastts", "step_lastts",
            "ldlastts", "falastts", "icmaplastts",
            "fs_all_fslastts","fs_project_fslastts", "fs_fscratch_fslastts", "fs_scratch_fslastts","fs_home_fslastts", "fs_fastdata_fslastts",
            "gpulastts", "nodeerrts", "startts", "max_ts", "cores_lastts"
            ) {
          foreach my $colref (@{$columnsref}) {
            if($colref->{name} eq $searchpattern) {
              $tscol=$colref->{name};
              last;
            }
          }
          last if ($tscol);
        }

        if(defined($tscol) && ($ldata->{$db}->{$ltable}->{nrows}>0) ) {
          my $where=" ( $tscol > 0 ) ";
          if($res!=-1) {
            $where.=" AND ( _time_res = $res ) "
          }
          $ldata->{$db}->{$ltable}->{ts_min}=$self->query($db,$table,
                                                          {
                                                            type => 'get_min',
                                                            where => $where,
                                                            hash_key => $tscol
                                                          });
          $ldata->{$db}->{$ltable}->{ts_max}=$self->query($db,$table,
                                                          {
                                                            type => 'get_max',
                                                            where => $where,
                                                            hash_key => $tscol
                                                          });
        } else {
          $ldata->{$db}->{$ltable}->{ts_min}=-1;
          $ldata->{$db}->{$ltable}->{ts_max}=-1;
        }
		
        if( defined($ldata->{$db}->{$ltable}->{ts_min}) && defined($ldata->{$db}->{$ltable}->{ts_max}) ) {
          $ldata->{$db}->{$ltable}->{ts_dur}=$ldata->{$db}->{$ltable}->{ts_max}-$ldata->{$db}->{$ltable}->{ts_min};
        } else {
          $ldata->{$db}->{$ltable}->{ts_max}=-1;
          $ldata->{$db}->{$ltable}->{ts_min}=-1;
          $ldata->{$db}->{$ltable}->{ts_dur}=0;
        }
      }
    }
    printf("%s  LLmonDB:     query db [%2d]%-36s in %4.2fs\n",$self->{INSTNAME},$dbcnt,$db,time()-$qtime) if($self->{VERBOSE});
    $pm->finish(0,$ldata); # Terminates the child process
  }
  printf("%s LLmonDB: wait for childs (%d)\n",$self->{INSTNAME},scalar $pm->running_procs());
  $pm->wait_all_children;
  printf("%s LLmonDB: wait for childs ready (%d)\n",$self->{INSTNAME},scalar $pm->running_procs());

  printf("$self->{INSTNAME}  LLmonDB: end DBstat_data \n") if($debug>=3);
  return($data);
}

1;