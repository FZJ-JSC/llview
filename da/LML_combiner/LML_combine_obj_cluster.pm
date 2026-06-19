# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_combine_obj_cluster;

use strict;
use Data::Dumper;

my($debug)=0;
my($debugjob)="1451691";

sub update {
  my($dataptr) = shift;
  my($dbdir) = shift;
  my(%gpuoffsets);
  my ($nodeioinforef,$nodeusageref,$nodeinforef);

  $nodeusageref=&get_job_node_usage($dataptr);

  &get_node_info($dataptr,\%gpuoffsets,$nodeusageref);

  &update_job_info($dataptr,\%gpuoffsets);

  &update_nodeio_info($dataptr);

  &update_nodefabric_info($dataptr);

  return(1);
} 

sub get_node_info {
  my($dataptr) = shift;
  my($gpuoffsetref) = shift;
  my($nodeusageref) = shift;
  my($id,$ncores,$ngpus,$name);
  my(%nodeattr,$nodeattrref,$noderef,$sid);

  # scan for additional attributes
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "nodeattr") {
      if(!exists($nodeattr{$dataptr->{OBJECT}->{$id}->{name}})) {
        # first attrbute definition found for that node
        $nodeattr{$dataptr->{OBJECT}->{$id}->{name}}=$dataptr->{INFODATA}->{$id};
      } else {
        # merge in this additional attributes
        foreach $sid (keys(%{$dataptr->{INFODATA}->{$id}})) {
          $nodeattr{$dataptr->{OBJECT}->{$id}->{name}}->{$sid}=$dataptr->{INFODATA}->{$id}->{$sid};
        }
      }
      delete($dataptr->{OBJECT}->{$id});
      delete($dataptr->{INFO}->{$id});
      delete($dataptr->{INFODATA}->{$id});
    }
  }

  # scan for gpus + add. attributes
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "node") {
      $name=$dataptr->{OBJECT}->{$id}->{name};
      $noderef=$dataptr->{INFODATA}->{$id};
      $ncores=$dataptr->{INFODATA}->{$id}->{ncores};
      if(exists($dataptr->{INFODATA}->{$id}->{gpus})) {
        $gpuoffsetref->{$name}=$ncores;
      }
        
      if(exists($nodeattr{$name})) {
        $nodeattrref=$nodeattr{$name};
        foreach $sid (keys(%{$nodeattrref})) {
          $noderef->{$sid}=$nodeattrref->{$sid};
        }
      }
    }
  }
  return();
}

sub update_job_info {
  my($dataptr) = shift;
  my($gpuoffsetref) = shift;
  my($id,$jobref,$spec,$node,$pos,$newnode,$newpos);
  
  # update job info
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "job") {
      $jobref=$dataptr->{INFODATA}->{$id};
      
      # update nodelist 
      next if(!exists($jobref->{state}));
      if($jobref->{state} !~ /^run/i) {
        if(!exists($jobref->{nodelist})) {
          $jobref->{nodelist}="-";
          $jobref->{totaltasks}=0;
        }
        if(!exists($jobref->{vnodelist})) {
          $jobref->{vnodelist}="-";
        }
      }
      # update totalcores
      if(!exists($jobref->{totalcores})) {
        print "update_job_info: could not find attributes for job $id to compute totalcores\n" if($debug);
      }
      
      if($jobref->{state} =~ /^run/i) {
        if(exists($jobref->{gpulist})) {
          foreach $spec (split(/\),?\(/,$jobref->{gpulist})) {
            if($spec=~/\(?([^,]+),(\d+)\)?/) {
              $node=$1;$pos=$2;
              $newnode=$node;$newnode=~s/\-gpu$//s;
              $newpos=$gpuoffsetref->{$newnode}+$pos;
              $jobref->{nodelist}.="($newnode,$newpos)";
              # $jobref->{nodelist}.="($node,$pos)";
            }
          }
        }
      }
    }
  }
  return(1);
}

sub get_job_node_usage {
  my($dataptr) = shift;
  my($id,$jobref,$spec,$node,$pos,$newnode,$newpos,%nodeusage);
  
  # update job info
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "job") {
      $jobref=$dataptr->{INFODATA}->{$id};
      next if(!exists($jobref->{state}));
      if($jobref->{state} =~ /^run/i) {
        if(exists($jobref->{nodelist})) {
          foreach $spec (split(/\),?\(/,$jobref->{nodelist})) {
            $spec=~/\(?([^,]+),(\d+)\)?/;$node=$1;$pos=$2;
            $nodeusage{$node}++;
          }
        }
      }
    }
  }
  return(\%nodeusage);
}


sub update_nodeio_info {
  my($dataptr) = shift;
  my($id,$sid,$ref,$noderef,$nodename,%partitions,%nodeioinfo,$ionode,@noioinfonodes);

  # add environment attributes to nodes

  # scan for partition names
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "env") {
      $partitions{$dataptr->{OBJECT}->{$id}->{name}}=$dataptr->{INFODATA}->{$id};
    }
    if($dataptr->{OBJECT}->{$id}->{type} eq "ionode") {
      $ionode=$dataptr->{OBJECT}->{$id}->{name};
      $nodeioinfo{$ionode}->{$ionode}=$dataptr->{INFODATA}->{$id};

      # remove it from data structure
      delete($dataptr->{OBJECT}->{$id});
      delete($dataptr->{INFO}->{$id});
      delete($dataptr->{INFODATA}->{$id});
    }
  }
  # update node info
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "node") {
      $noderef=$dataptr->{INFODATA}->{$id};
      $nodename=$dataptr->{OBJECT}->{$id}->{name};


      if($id eq "nd000000") {
        if(scalar keys(%nodeioinfo) > 0) {
          for my $fs ("scratch","project","largedata","fastdata","home") {
            $noderef->{"fs_bww_${fs}_MIN"}=$noderef->{"fs_bwr_${fs}_MIN"}=$noderef->{"fs_bw_all_MIN"}=$noderef->{"fs_oocr_${fs}_MIN"}=0;
            $noderef->{"fs_bww_${fs}_MAX"}=$noderef->{"fs_bwr_${fs}_MAX"}=$noderef->{"fs_bw_all_MAX"}=0.5*1024;   # reduced from 6*1024
            $noderef->{"fs_oocr_${fs}_MAX"}=1000; # reduced from 1000
            $noderef->{"fs_bww_${fs}_UNIT"}=$noderef->{"fs_bw_all_UNIT"}=$noderef->{"fs_bwr_${fs}_UNIT"}="MB/s";
            $noderef->{"fs_oocr_${fs}_UNIT"}="ops";
          }
        }
      }

      if(exists($nodeioinfo{$nodename})) {
        $ref=$nodeioinfo{$nodename}->{$nodename};

        for my $fs ("scratch","project","largedata","fastdata","home") {
          if(exists($ref->{"fs_bw_${fs}"})) { 
            if($ref->{"fs_dts_${fs}"}>0) {
              $noderef->{"fs_bww_${fs}"}=($ref->{"fs_bw_${fs}"}/1024.0/1024.0)/$ref->{"fs_dts_${fs}"};
              $noderef->{"fs_bwr_${fs}"}=($ref->{"fs_br_${fs}"}/1024.0/1024.0)/$ref->{"fs_dts_${fs}"};
              $noderef->{"fs_oocr_${fs}"}=($ref->{"fs_oc_${fs}"}+$ref->{"fs_cc_${fs}"})/$ref->{"fs_dts_${fs}"};
            }
          }
          if(exists($noderef->{"fs_bww_${fs}"}) && exists($noderef->{"fs_bwr_${fs}"})) {
            $noderef->{"fs_bw_all"}+=$noderef->{"fs_bww_${fs}"}+$noderef->{"fs_bwr_${fs}"};
          }
          if(exists($ref->{"fs_dts_${fs}"})) {
            $noderef->{"fs_dts_${fs}"}=$ref->{"fs_dts_${fs}"};
          }
        }
      } else {
        push(@noioinfonodes,$nodename);
      }
    }
  }

  if(scalar @noioinfonodes > 0) {
    printf("WARNING: no IO     info for node %d nodes\n",scalar @noioinfonodes ) if(!$debug);
    printf("WARNING: no IO     info for node %d nodes (%s)\n",scalar @noioinfonodes, join(',',sort(@noioinfonodes))) if($debug);
  }

  return(1);
}

sub update_nodefabric_info {
  my($dataptr) = shift;
  my($id,$sid,$ref,$noderef,$nodename,%partitions,%nodefbinfo,$fbnode,@nofbinfonodes);

  # add environment attributes to nodes

  # scan for partition names
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "fbnode") {
      $fbnode=$dataptr->{OBJECT}->{$id}->{name};
      $nodefbinfo{$fbnode}->{$fbnode}=$dataptr->{INFODATA}->{$id};

      # remove it from data structure
      delete($dataptr->{OBJECT}->{$id});
      delete($dataptr->{INFO}->{$id});
      delete($dataptr->{INFODATA}->{$id});
    }
  }

  if(scalar keys(%nodefbinfo) == 0) {
    return(1); # nothing to do 
  }
  # update node info
  foreach $id (keys(%{$dataptr->{OBJECT}})) {
    if($dataptr->{OBJECT}->{$id}->{type} eq "node") {
      $noderef=$dataptr->{INFODATA}->{$id};
      $nodename=$dataptr->{OBJECT}->{$id}->{name};


      if($id eq "nd000000") {
        if(scalar keys(%nodefbinfo) > 0) {
          $noderef->{fb_mbout_MIN}=$noderef->{fb_mbin_MIN}=$noderef->{fb_pckout_MIN}=$noderef->{fb_pckin_MIN}=0;
          $noderef->{fb_mbout_MAX}=$noderef->{fb_mbin_MAX}=6000;
          $noderef->{fb_pckout_MAX}=$noderef->{fb_pckin_MAX}=10000000;
          $noderef->{fb_mbin_UNIT}=$noderef->{fb_mbout_UNIT}="MB/s";
          $noderef->{fb_pckin_UNIT}=$noderef->{fb_pckout_UNIT}="packets";
        }
      }

      if(exists($nodefbinfo{$nodename})) {
        $ref=$nodefbinfo{$nodename}->{$nodename};
        
        # WORK
        if(exists($ref->{fb_mbout})) {
          #print "WARNING: $nodename no dts\n" if(!defined($ref->{fb_dts}));
          #print "WARNING: $nodename no fb_mbin\n",Dumper($ref) if(!defined($ref->{fb_mbin}));
          if($ref->{fb_dts}>0) {
          $noderef->{fb_mbin}=($ref->{fb_mbin})/$ref->{fb_dts};
          $noderef->{fb_mbout}=($ref->{fb_mbout})/$ref->{fb_dts};
          $noderef->{fb_pckin}=($ref->{fb_pckin})/$ref->{fb_dts};
          $noderef->{fb_pckout}=($ref->{fb_pckout})/$ref->{fb_dts};
          }
        }
      } else {
        push(@nofbinfonodes,$nodename) if($nodename!~/^jrc[56]/); # no info from OPA nodes
      }
    }
  }

  if(scalar @nofbinfonodes > 0) {
    printf("WARNING: no fabric info for node %d nodes (%s)\n",scalar @nofbinfonodes, join(',',sort(@nofbinfonodes)));
  }

  return(1);
}

sub get_nodelist_usage {
  my($nodelist,$jobid,$nodeusageref)=@_;
  my($spec,$node,$num,$ppn);
  my(%nodehash);
  print "TMPDEB: get_nodelist_usage $jobid, $nodelist\n" if($jobid=~/$debugjob/);

  foreach $spec (split(/\),?\(/,$nodelist)) {
    $spec=~/\(?([^,]+),(\d+)\)?/;$node=$1;$num=$2;
    $nodehash{$node}++;
  }
  foreach $node (sort(keys(%nodehash))) {
    if(exists($nodeusageref->{$node})) {
      $ppn=$nodeusageref->{$node};
    } else {
      $ppn=1;
      print "get_nodelist_usage: WARNING no usage of node $node\n";
    }
    $nodehash{$node}/=$ppn;
    print "TMPDEB: get_nodelist_usage $jobid, nodehash{$node}=$nodehash{$node}\n" if($jobid=~/$debugjob/);
  }
  return(\%nodehash);
}

1;
