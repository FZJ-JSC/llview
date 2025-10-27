# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_DBupdate_file;

my $VERSION='$Revision: 1.00 $';
my $debug=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use LML_file_obj;
use LML_DBupdate_adapt;
use LML_DBupdate_adapt_demo;

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $verbose = shift;
  my $dbdir = shift;
  my $demo = shift;

  printf("\t [LML_DBupdate_file] new %s\n",ref($proto)) if($debug>=3);
  $self->{VERBOSE}    = $verbose;
  $self->{DBDIR}      = $dbdir;
  $self->{DEMO}       = $demo;
  $self->{FILEHANDLER_LML}=undef;
  $self->{DATAAVAIL}  = 0; 
  $self->{DATA}       = {};
  
  my $data=$self->{DATA};
  $data->{SYSTEM_ENTRIES} = [];
  $data->{CLASSES_ENTRIES} = [];
  $data->{ENV_ENTRIES} = [];
  $data->{RESERVATION_ENTRIES} = [];
  $data->{SCHEDULER_ENTRIES} = [];
  $data->{NODE_ENTRIES} = [];
  $data->{GPUNODE_ENTRIES} = [];
  $data->{PARTITION_ENTRIES} = [];
  $data->{JOBS_ENTRIES} = [];
  $data->{JOBRC_ENTRIES} = [];
  $data->{JOBSTEP_ENTRIES} = [];
  $data->{JOBS_RUNNING_ENTRIES} = [];
  $data->{JOBS_IDLE_ENTRIES} = [];
  $data->{IOIJOB_ENTRIES} = [];
  $data->{IOIWF_ENTRIES} = [];
  $data->{CAPABILITIES} = {};
  $self->{MAPPING} = {};
  
  bless $self, $class;
  return $self;
}

sub read_LML {
  my($self) = shift;
  my($filename)=@_;
  my $fh=LML_file_obj->new($self->{VERBOSE},0);
  push(@{$self->{FILEHANDLER_LML}},$fh);
  $fh->read_rawlml_fast($filename);
  if($self->{VERBOSE}) {
    print $fh->get_stat();
  }
  printf("\t [LML_DBupdate_file] read_LML $filename\n") if($debug>=3);
}

sub get_data {
  my($self) = shift;
  my($checklmldata,$updatealways) =@_;

  if(!$self->{DATAAVAIL}) {
    $self->update_structure();

    if($checklmldata) {
      if(!exists($self->{DATA}->{SYSTEM_TS})) {
        printf(STDERR "\n[LML_DBupdate_file] ERROR SYSTEM_TS missing, probably no system element in input files, leaving...\n\n");
        return();
      }
    }

    $self->check_capabilities($updatealways);
    if($checklmldata) {
      $self->adapt_data();
      $self->adapt_data_demo_mode() if($self->{DEMO});
    }
    $self->{DATAAVAIL}=1;
  }
  printf("\t [LML_DBupdate_file] get_data\n") if($debug>=3);
  return($self->{DATA});
}

# add structural info to data to support easy access to the entries
sub update_structure {
  my($self) = shift;

  my $data=$self->{DATA};
  my($key,$ref,$fh);

  foreach $fh (@{$self->{FILEHANDLER_LML}}) {
    keys(%{$fh->{DATA}->{OBJECT}}); # reset iterator
    while(($key,$ref)=each(%{$fh->{DATA}->{OBJECT}})) {
      if($ref->{type} eq 'system') {
        # print "TMPDEB: found system\n";
        $ref=$fh->{DATA}->{INFODATA}->{$key};
        push(@{$data->{SYSTEM_ENTRIES}},$key);
        
        if($ref->{type}) {
          $data->{SYSTEM_TYPE}=$ref->{type};
          $data->{SYSTEM_TIME}=$ref->{system_time};
          $data->{SYSTEM_TS}=LML_da_util::date_to_sec($data->{SYSTEM_TIME});
          # print "TMPDEB: found data->{SYSTEM_TS}=$data->{SYSTEM_TS}\n";
        }
      } elsif ($ref->{type} eq 'class') {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $cref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{CLASSES_ENTRIES}},$cref);
        }
      } elsif ($ref->{type} eq 'env') {
        push(@{$data->{ENV_ENTRIES}},$key);
      } elsif (($ref->{type} eq 'res') || ($ref->{type} eq 'reservation')) {
        my $resinfo=$fh->{DATA}->{INFODATA}->{$key};
        push(@{$data->{RESERVATION_ENTRIES}},$resinfo);
      } elsif (($ref->{type} eq 'scheduler') || ($ref->{type} eq 'sched')) {
        push(@{$data->{SCHEDULER_ENTRIES}},$key);
      } elsif ($ref->{type} eq 'node') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};
        
        if($key=~/^gpu/) {
          #  GPU node
          push(@{$data->{GPUNODE_ENTRIES}},$nodeinfo);
          my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};
          $data->{GPUNODES_BY_NODEID}->{$nodeid}=$nodeinfo;
        } else {
          # normal nodes
          if(exists($data->{NODES_BY_NODEID}->{$nodeid})) {
            # add new attributes to existing entry
            foreach $key (keys(%{$nodeinfo})) {
              $data->{NODES_BY_NODEID}->{$nodeid}->{$key}=$nodeinfo->{$key};
            }
          } else {
            push(@{$data->{NODE_ENTRIES}},$nodeinfo);
            $data->{NODES_BY_NODEID}->{$nodeid}=$nodeinfo;
          }

          # check if node contains additional data
          if(exists($nodeinfo->{fs_bwr_scratch})) {
            if(!exists($data->{IONODES_BY_NODEID}->{$nodeid})) {
              push(@{$data->{IONODE_ENTRIES}},$nodeinfo);
              $data->{IONODES_BY_NODEID}->{$nodeid}=$nodeinfo;
            }
          }

          # check if node contains additional data
          if(exists($nodeinfo->{fb_mbin})) {
            if(!exists($data->{FBNODES_BY_NODEID}->{$nodeid})) {
              push(@{$data->{FBNODE_ENTRIES}},$nodeinfo);
              $data->{FBNODES_BY_NODEID}->{$nodeid}=$nodeinfo;
            }
          }
        }
      } elsif ($ref->{type} eq 'ionode') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};

        $nodeinfo->{id}=$nodeid;
        if(!exists($data->{IONODES_BY_NODEID}->{$nodeid})) {
          push(@{$data->{IONODE_ENTRIES}},$nodeinfo);
          $data->{IONODES_BY_NODEID}->{$nodeid}=$nodeinfo;
        }

        if(0) { 	# not needed anymore
          # add data to node data structure
          if(exists($data->{NODES_BY_NODEID}->{$nodeid})) {
            # add new attributes to existing entry
            foreach $key (keys(%{$nodeinfo})) {
              $data->{NODES_BY_NODEID}->{$nodeid}->{$key}=$nodeinfo->{$key};
            }
          } else {
            push(@{$data->{NODE_ENTRIES}},$nodeinfo);
            $data->{NODES_BY_NODEID}->{$nodeid}=$nodeinfo;
          }
        }
      } elsif ($ref->{type} eq 'fbnode') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};

        $nodeinfo->{id}=$nodeid;
        if(exists($nodeinfo->{fb_ts})) {	
          if($nodeinfo->{fb_ts}=~/\d+/) {
            if(!exists($data->{FBNODES_BY_NODEID}->{$nodeid})) {
              push(@{$data->{FBNODE_ENTRIES}},$nodeinfo);
              $data->{FBNODES_BY_NODEID}->{$nodeid}=$nodeinfo;
            }
          }
        }
      } elsif ($ref->{type} eq 'cpuinfo') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};

        $nodeinfo->{id}=$nodeid;
        if(exists($nodeinfo->{cpu_ts})) {	
          if($nodeinfo->{cpu_ts}=~/\d+/) {
            if(!exists($data->{CINODES_BY_NODEID}->{$nodeid})) {
              push(@{$data->{CINODE_ENTRIES}},$nodeinfo);
              $data->{CINODES_BY_NODEID}->{$nodeid}=$nodeinfo;
            }
          }
        }
      } elsif ($ref->{type} eq 'coreinfo') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};

        if(exists($nodeinfo->{percore})) {
          my @pairs=(split(",",$nodeinfo->{percore}));
          my $numphyscore=( scalar @pairs ) / 2;
          my $pcores;
          foreach my $pair (@pairs) {
            my($cpu,$usage)=(split(":",$pair));
            my $ref;
            $ref->{name}=$nodeid;
            $ref->{core}=$cpu;
            $ref->{usage}=$usage;
            push(@{$data->{COREINFO_ENTRIES}},$ref);
            if($cpu<$numphyscore) {
                my $pcore=$cpu;
                $pcores->{$pcore}->{name}=$nodeid;
                $pcores->{$pcore}->{core}=$pcore;
                $pcores->{$pcore}->{usage1}=$usage;
            } else {
              my $pcore=$cpu-$numphyscore;
              $pcores->{$pcore}->{usage2}=$usage;
            }
          }
          foreach my $p (sort(keys(%{$pcores}))) {
            push(@{$data->{PCOREINFO_ENTRIES}},$pcores->{$p});
          }
        }
      } elsif ($ref->{type} eq 'icmap') {
        my $nodeinfo=$fh->{DATA}->{INFODATA}->{$key};
        my $nodeid = $fh->{DATA}->{OBJECT}->{$key}->{name};

        $nodeinfo->{id}=$nodeid;
        if($nodeinfo->{ts}=~/\d+/) {
          if(!exists($data->{ICMAPNODES_BY_NODEID}->{$nodeid})) {
            push(@{$data->{ICMAP_ENTRIES}},$nodeinfo);
            $data->{ICMAPNODES_BY_NODEID}->{$nodeid}=$nodeinfo;
          }
        }
      } elsif ($ref->{type} eq 'partition') {
        push(@{$data->{PARTITION_ENTRIES}},$key);
      } elsif ($ref->{type} eq 'step') {
        my $jref    = $fh->{DATA}->{INFODATA}->{$key};
        push(@{$data->{JOBSTEP_ENTRIES}},$jref);
      } elsif ($ref->{type} eq 'pstat') {
        push(@{$data->{PSTAT_ENTRIES}},$key);
      } elsif ($ref->{type} eq "job") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          my $jobstep = $fh->{DATA}->{OBJECT}->{$key}->{name};

          if(exists($jref->{rc})) {
            push(@{$data->{JOBRC_ENTRIES}},$jref);
            $data->{JOBRC_BY_JOBSTEP}->{$jobstep}=$jref;
          } else {
            push(@{$data->{JOBS_ENTRIES}},$jref);
            if($jref->{state} eq "Running") {
              push(@{$data->{JOBS_RUNNING_ENTRIES}},$jref);
              $data->{JOBS_RUNNING_BY_JOBSTEP}->{$jobstep}=$jref;
            } else {
              push(@{$data->{JOBS_IDLE_ENTRIES}},$jref);
              $data->{JOBS_IDLE_BY_JOBSTEP}->{$jobstep}=$jref;
            }
          }
        }
      } elsif ($ref->{type} eq "joberr") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          my $jobstep = $fh->{DATA}->{OBJECT}->{$key}->{name};
          push(@{$data->{JOBERR_ENTRIES}},$jref);
          $data->{JOBERR_BY_JOBSTEP}->{$jobstep}=$jref;
        }
      } elsif ($ref->{type} eq "nodeerr") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          my $jobstep = $fh->{DATA}->{OBJECT}->{$key}->{name};
          push(@{$data->{NODEERR_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "DBstat") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{DBSTAT_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "DBgraph") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{DBGRAPH_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "steptime") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{STEPTIME_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "transferstat") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{TRANSFERSTAT_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "sysstat") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{SYSSTAT_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "rackpwr") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{RACKPWR_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "ndpwrinfo") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{NDPWRINFO_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "pwrinfo") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{PWRINFO_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "supportmap") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{SUPPORTMAP_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} =~ /(user|mentor|pipa)map/) {
        my $type=$1;
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          foreach my $p (split(",",$jref->{"projects"})) {
            my $ref;
            $ref->{ts}=$jref->{ts};
            $ref->{id}=$jref->{id};
            $ref->{wsaccount}=$jref->{wsaccount};
            $ref->{project}=$p;
            if($type eq "user")  {
              push(@{$data->{USERMAP_ENTRIES}},$ref);
            } elsif($type eq "mentor")  {
              push(@{$data->{MENTORMAP_ENTRIES}},$ref);
            } elsif($type eq "pipa")  {
              $ref->{kind}=$jref->{kind};
              push(@{$data->{PIPAMAP_ENTRIES}},$ref);
            }
          } 
        }
      } elsif ($ref->{type} eq "ioi") {
        if($key=~/^ioij/) {
          if(exists($fh->{DATA}->{INFODATA}->{$key})) {
            my $jref    = $fh->{DATA}->{INFODATA}->{$key};
            push(@{$data->{IOIJOB_ENTRIES}},$jref);
          }
        } elsif($key=~/^ioiw/) {
          if(exists($fh->{DATA}->{INFODATA}->{$key})) {
            my $jref    = $fh->{DATA}->{INFODATA}->{$key};
            push(@{$data->{IOIWF_ENTRIES}},$jref);
          }
        }
      } elsif ($ref->{type} eq "wfm_job") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{WFMJOB_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "jumonc") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{JUMONC_ENTRIES}},$jref);
        }
      } elsif ($ref->{type} eq "benchmark") {
        my $bmname = $fh->{DATA}->{OBJECT}->{$key}->{name};
        if($bmname=~/^([\D]+)\d+/) {
          my $bm=$1;
          if(exists($fh->{DATA}->{INFODATA}->{$key})) {
            my $jref    = $fh->{DATA}->{INFODATA}->{$key};
            push(@{$data->{"cb_${bm}_ENTRIES"}},$jref);
            # print "TMPDEB: CB, add entry $key to cb_${bm}\n";
          }
        }
      } elsif ($ref->{type} eq "trigger") {
        if(exists($fh->{DATA}->{INFODATA}->{$key})) {
          my $jref    = $fh->{DATA}->{INFODATA}->{$key};
          push(@{$data->{TRIGGER_ENTRIES}},$jref);
        }
      } else {
        printf(STDERR "\t [LML_DBupdate_file] WARNING: scan keys, unknown type %s\n",$ref->{type});
      }
    }
  } # foreach $fh
  
  printf("\t [LML_DBupdate_file] update structure\n") if($debug>=3);
}

sub check_capabilities {
  my($self) = shift;
  my($updatealways)=@_;
  
  my $data=$self->{DATA};
  my $cap=$self->{DATA}->{CAPABILITIES};
  my $capf=$self->{DATA}->{CAPABILITIES_FORCED};

  foreach my $e (keys(%{$data})) {
    if($e=~/^(.*)_ENTRIES$/) {
      if(scalar @{$data->{$e}} > 0) {
        my $c = $1;
        $c = ($c =~ /^cb_/) ? $c : lc($c); # Temporary fix for CB to keep capitalisation
        $cap->{$c}=1;
        $self->{DATA}->{ENTRIES_BY_CAP}->{$c}=$data->{$e};
      }
    }
  }
  if(defined($updatealways)) {
    foreach my $type (split(/\s*,\s*/,$updatealways)) {
      my $ltype=$type;
      $ltype = ($ltype =~ /^cb_/) ? $ltype : lc($ltype); # Temporary fix for CB to keep capitalisation
      if(!exists($self->{DATA}->{ENTRIES_BY_CAP}->{$ltype})) {
        $self->{DATA}->{ENTRIES_BY_CAP_FORCED}->{$ltype}=[];
        $capf->{$ltype}=1;
      }
    }
  }

  #  keep only gpu nodes for GPU LML file 
  if(0) {
    if($cap->{gpunode}) {
      for my $c (keys(%{$cap})) {
        delete($cap->{$c}) if($c ne "gpunode"); 
      }
    }
  }
  printf("\t [LML_DBupdate_file] found capabilities              %s\n",join(",",(sort(keys(%{$self->{DATA}->{ENTRIES_BY_CAP}}))))) if($self->{VERBOSE});
  printf("\t [LML_DBupdate_file] found capabilities to be forced %s\n",join(",",(sort(keys(%{$self->{DATA}->{ENTRIES_BY_CAP_FORCED}}))))) if($self->{VERBOSE});
  printf("\t [LML_DBupdate_file] check_capabilities\n") if($debug>=3);
}

sub dump_entries_by_cap {
  my($self) = shift;
  my($dumpdir)=@_;
  
  foreach my $c (keys(%{$self->{DATA}->{ENTRIES_BY_CAP}})) {
    my $starttime=time();
    my $cc=uc($c);
    my $outfile="$dumpdir/LMLdata_$cc.dump";
    open(OUT,"> $outfile") or die("cannot open $outfile for writing, exiting...");
    print OUT Dumper($self->{DATA}->{ENTRIES_BY_CAP}->{$c});
    close(OUT);
    printf("\t: dumping LML data to %-40s in %7.4fs\n",$outfile,time()-$starttime);
  }
}

sub close {
  my($self) = shift;
  printf("\t [LML_DBupdate_file] close\n") if($debug>=3);
}

1;
