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

my $caller=$0; $caller=~s/^.*\/([^\/]+)$/$1/gs;
my $instname="[${caller}][PRIMARY]";

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use LLmonDB_config;
use LLmonDB_check;
use LLmonDB_graphs;
use LLmonDB_sqlite;
use LLmonDB_input_LML;
use LLmonDB_input_LML_jobmap;
use LLmonDB_collectDB;
use LLmonDB_arch;
use LLmonDB_query;
use LLmonDB_delete;
use LLmonDB_insert;
use LLmonDB_DBstat;
use LLmonDB_util;
use LLmonDB_util_replace_vars;

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $configfile = shift;
  my $dbdir   = shift;
  my $archdir   = shift;
  my $verbose = shift;
  my $systemname = shift;
  my $currentts = shift;
  my $realcurrentts = shift;


  printf("  LLmonDB: new %s\n",ref($proto)) if($debug>=3);
  $self->{VERBOSE}    = $verbose; 
  $self->{DBDIR}      = $dbdir; 
  $self->{ARCHDIR}    = $archdir; 
  $self->{CONFIGFILE} = $configfile; 
  $self->{CONFIG}     = undef; 
  $self->{CONFIGDATA} = undef; 
  $self->{DATA}       = {}; 
  $self->{JOBNODEMAP} = {}; 
  $self->{JOBNODEMAP_AVAIL} = 0; 
  $self->{JOBTSMAP}   = {}; 
  $self->{JOBTSMAP_AVAIL}   = 0; 
  $self->{DBOBJS}     = {}; 
  $self->{DBcontains_map_data} = undef; 
  $self->{MAP_DATA_REQUIRED}=0;
  $self->{SYSTEM_NAME}="system";
  $self->{SYSTEM_NAME} = $systemname if(defined($systemname)); 
  if(defined($currentts)) {
    $self->{CURRENTTS} = $currentts;
  } else {
    $self->{CURRENTTS} = time(); 
  }
  if(defined($realcurrentts)) {
    $self->{REALCURRENTTS} = $realcurrentts;
  } else {
    $self->{REALCURRENTTS} = $self->{CURRENTTS}; 
  }
  
  $self->{SYSTEM_DESC}="system desc";
  $self->{CALLER}=$caller; $self->{CALLER}=~s/^.*\/([^\/]+)$/$1/gs;
  $self->{INSTNAME}=$instname;
  bless $self, $class;
  
  return $self;
}

sub DESTROY {
  my $self = shift;
  $self->close();
}

sub init {
  my($self) = shift;
  $self->{CONFIG}=LLmonDB_config->new($self->{CONFIGFILE},$self->{VERBOSE});
  $self->{CONFIG}->load_config();
  $self->{CONFIGDATA}=$self->{CONFIG}->get_contents();
  if(defined($self->{DBDIR})) {
    printf("  LLmonDB: set DB-DIR to %s (from option)\n",$self->{DBDIR}) if($self->{VERBOSE});
    $self->{CONFIGDATA}->{paths}->{dbdir}=$self->{DBDIR};
  }
  if(defined($self->{ARCHDIR})) {
    printf("  LLmonDB: set ARCH-DIR to %s (from option)\n",$self->{ARCHDIR}) if($self->{VERBOSE});
    $self->{CONFIGDATA}->{paths}->{archdir}=$self->{ARCHDIR};
  }
  
  printf("  LLmonDB: init, configfile=%s\n",$self->{CONFIGFILE}) if($debug>=3);
}

sub get_config {
  my($self) = shift;
  return($self->{CONFIGDATA});
}

sub get_confighandle {
  my($self) = shift;
  return($self->{CONFIG});
}

sub close_dbs {
  my($self) = shift;

  # cleanup DB
  foreach my $db (keys(%{$self->{DBOBJS}})) {
    $self->close_db($db);
  }
  printf("  LLmonDB: close DBs\n") if($debug>=3);
}

sub close {
  my($self) = shift;

  # cleanup DB
  foreach my $db (keys(%{$self->{DBOBJS}})) {
    $self->close_db($db);
  }
  printf("  LLmonDB: close\n") if($debug>=3);
}

1;
