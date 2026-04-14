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

#  /home/llstat/llview_package/da/LL_jobreport/LL_jobreport_dataset_mngt.pl -v -dbdir ~/s1/perm/db -config ~/c1/server/LLgenDB/LLgenDB.yaml --statstat --systemname JUPITER_DEMO --tmpdir =~/s1/tmp -archdir ~/s1/arch -outdir ~/s1/tmp/
sub stat_datasets {
  my $self = shift;
  my ($DB, $force) = @_;
  my $basename = $self->{BASENAME};

  my $config_ref = $DB->get_config();

  my $varsetref;
  if (exists($config_ref->{$basename}->{paths})) {
    foreach my $p (keys(%{$config_ref->{$basename}->{paths}})) {
      $varsetref->{$p} = $config_ref->{$basename}->{paths}->{$p};
    }
  }

  # scan for stat db/tabs
  my $stattable;
  my $sets;
  foreach my $datasetref (@{$config_ref->{$basename}->{datafiles}}) {
    my $dataset = $datasetref->{dataset};
    my $name = $dataset->{name};
    next if (!exists($dataset->{stat_table}));

    my ($sdb,$stab)=($dataset->{stat_database}, $dataset->{stat_table});
    my $set="NOTDEF";  
    $set=$dataset->{set} if(exists($dataset->{set}));
    $sets->{$set}->{datasets}->{$name}++;
    
    $stattable->{$sdb}->{$stab}->{$dataset}=1;
    
  }

  if(1) {
      print "List of active Stat-DB:\n";
      print "="x120,"\n";
      foreach my $sdb (sort(keys(%{$stattable}))) {
	  printf("%40s: %s\n",
		 $sdb,
		 join(",",(sort(keys(%{$stattable->{$sdb}}))))
	      );
      }
      print "="x120,"\n";
  }
  
  if(1) {
      print "List of active Set:\n";
      print "="x120,"\n";
      foreach my $set (sort(keys(%{$sets}))) {
	  printf("%-30s: %s\n",
		 $set,
		 join(",",(sort(keys(%{$sets->{$set}->{datasets}}))))
	      );
      }
      print "="x120,"\n";
  }
  
  return();
}


1;
