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
use JSON;

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub create_views {
  my $self = shift;
  my $DB=shift;
  my $basename=$self->{BASENAME};
  my $starttime=time();
  my $config_ref=$DB->get_config();

  # 0: init instantiated variables
  ################################
  my $varsetref;
  $varsetref->{"systemname"}=$self->{SYSTEM_NAME};
  if(exists($config_ref->{$basename}->{paths})) {
    foreach my $p (keys(%{$config_ref->{$basename}->{paths}})) {
      $varsetref->{$p}=$config_ref->{$basename}->{paths}->{$p};
    }
  }

  # scan all views
  my $vcount=0;
  foreach my $vref (@{$config_ref->{$basename}->{views}}) {
    my $vstarttime=time();
    next if(!exists($vref->{view}));
    next if(!exists($vref->{view}->{name}));
    next if(!exists($vref->{view}->{filepath}));
    my $vname=$vref->{view}->{name};
    $vcount++;
    # print Dumper($vref);
    $self->process_view($vname,$vref->{view},$varsetref);
    printf("%s create_views:[%02d] view %-20s    in %7.4fs\n",$self->{INSTNAME}, $vcount,$vname, time()-$vstarttime);
  }
  
  return();
}

sub process_view {
  my $self = shift;
  my ($vname,$viewref,$varsetref)=@_;
  my ($dsref);
  my $file=$self->apply_varset($viewref->{filepath},$varsetref);

  foreach my $name ("title","image","home","logo","info","search_field","status","systems","demo") {
    $dsref->{$name}=$self->apply_varset($viewref->{$name},$varsetref) if(exists($viewref->{$name}));
  }
  if(exists($viewref->{data})) {
    foreach my $name ("system","permission","view") {
      $dsref->{data}->{$name}=$self->apply_varset($viewref->{data}->{$name},$varsetref) if(exists($viewref->{data}->{$name}));
    }
  }

  if(exists($viewref->{pages})) {
    foreach my $pref (@{$viewref->{pages}}) {
      push(@{$dsref->{pages}},$self->process_view_page($pref->{page},$varsetref)) if(exists($pref->{page}));
    }
  }

  # get status of datasets from DB
  my $where="name='".$viewref->{name}."'";
  $self->get_datasetstat_from_DB($viewref->{stat_database},$viewref->{stat_table},$where);

  if(!defined($viewref->{stat_database})) {
    printf(STDERR "[process_view] ERROR stat_db not defined vname=%s (%s,%s,%s)\n",$vname,caller());
    return(); 
  };
  if(!defined($viewref->{stat_table})) {
    printf(STDERR "[process_view] ERROR stat_table not defined vname=%s (%s,%s,%s)\n",$vname,caller());
    return(); 
  };

  my $ds=$self->{DATASETSTAT}->{$viewref->{stat_database}}->{$viewref->{stat_table}};

  # save the JSON file
  my $fh = IO::File->new();
  &check_folder("$file");
  if (!($fh->open("> $file"))) {
    print STDERR "LLmonDB:    WARNING: cannot open $file, skipping...\n";
    return();
  }
  $fh->print($self->encode_JSON($dsref));
  $fh->close();

  # register file
  my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;
  # update last ts stored to file
  $ds->{$shortfile}->{dataset}=$shortfile;
  $ds->{$shortfile}->{name}=$viewref->{name};
  $ds->{$shortfile}->{ukey}=-1;
  $ds->{$shortfile}->{status}=FSTATUS_EXISTS;
  $ds->{$shortfile}->{checksum}=0;
  $ds->{$shortfile}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  $ds->{$shortfile}->{mts}=$self->{CURRENTTS}; # last change ts

  # save status of datasets in DB 
  $self->save_datasetstat_in_DB($viewref->{stat_database},$viewref->{stat_table},$where);

  # print "process_view: file=$file ready\n";

}

sub process_view_page {
  my $self = shift;
  my ($pageref,$varsetref)=@_;
  my ($ds);

  foreach my $name ("name", "section", "icon", "context", "href", "default", "description", "tabs",
                    "template", "footer_template", "footer_graph_config", "graph_page_config"
                    ) {
    $ds->{$name}=$self->apply_varset($pageref->{$name},$varsetref) if(exists($pageref->{$name}));
  }
  
  if(exists($pageref->{ref})) {
    foreach my $ref (@{$pageref->{ref}}) {
      push(@{$ds->{ref}},$ref);
    }
  }
  if(exists($pageref->{data})) {
    $ds->{data}=$pageref->{data};
  }
  if(exists($pageref->{functions})) {
    foreach my $ref (@{$pageref->{functions}}) {
      push(@{$ds->{functions}},$ref);
    }
  }
  if(exists($pageref->{scripts})) {
    foreach my $ref (@{$pageref->{scripts}}) {
      push(@{$ds->{scripts}},$ref);
    }
  }

  if(exists($pageref->{pages})) {
    foreach my $pref (@{$pageref->{pages}}) {
      push(@{$ds->{pages}},$self->process_view_page($pref->{page},$varsetref)) if(exists($pref->{page}));
    }
  }
  return($ds);
}

1;
