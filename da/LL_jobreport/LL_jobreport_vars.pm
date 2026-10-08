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
my($debug)=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

sub update_vars_from_DB {
  my $self = shift;
  my $DB=shift;
  my $basename=$self->{BASENAME};

  my $config_ref=$DB->get_config();

  foreach my $db (sort(keys(%{$config_ref->{databases}}))) {
    foreach my $t (@{$config_ref->{databases}->{$db}->{tables}}) {
      my $table=$t->{table}->{name};
      $self->{TABLES}->{$db}->{$table}=1;
    }
  }
  
  foreach my $varref (@{$config_ref->{$basename}->{vars}}) {
    next if(!exists($varref->{name}));	
    next if(!exists($varref->{type}));	
    next if(!exists($varref->{database}));	
    next if(!exists($varref->{table}));	
    next if(!exists($varref->{columns}));	
    my $varname=$varref->{name};   
    
    $self->{VARS}->{$varname}->{def}=$varref;
    $self->{VARS}->{$varname}->{data}=undef;
    
    my $defer=0;
    $defer=$varref->{defer} if(exists($varref->{defer}));
    if(!$defer) {
      $self->update_var_from_DB($DB,$self->{VARS}->{$varname});
    }
  }
  return();
}

sub check_var_from_DB {
  my $self = shift; 
  my($DB,$varname)=@_;
  if(exists($self->{VARS}->{$varname})) {
    if(!defined($self->{VARS}->{$varname}->{data})) {
      $self->update_var_from_DB($DB,$self->{VARS}->{$varname});
    }
  } else {
    printf("%s check_var_from_DB: WARNING: unknown var: %s\n",$self->{INSTNAME}, $varname);
    return(0);
  }
  return(1);
}

sub update_var_from_DB {
  my $self = shift; 
  my($DB,$vardataref)=@_;
  my $varref=$vardataref->{def};
  my $varname=$varref->{name};   
  my $vartype=$varref->{type};   
  my $db=$varref->{database};    
  my $table=$varref->{table};    
  my $columns=$varref->{columns};
  
  printf("update_var_from_DB: %-20s start\n",$varname) if($debug);
  printf("update_var_from_DB: %-20s columns=$columns\n",$varname) if($debug);

  if(!exists($self->{TABLES}->{$db})) {
    printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping var $varname\n",$db);
    $vardataref->{data}=undef;
    return;
  }
  if(!exists($self->{TABLES}->{$db}->{$table})) {
    printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping var $varname\n",$db,$table);
    $vardataref->{data}=undef;
    return;
  }

  if(!exists($varref->{sql})) {
    my $where=''; $where=$varref->{where} if(exists($varref->{where}));
    my @cols=split(",",$columns);
    my $lastcol=$cols[$#cols];
    
    my $dataref=$DB->query($db,$table,
                            {
                              type => $vartype,
                              hash_keys => \@cols,
                              hash_value => $lastcol,
                              where => $where
                            });
    $vardataref->{data}=$dataref;
    # printf("$varname: $vartype $db $table $columns '$where' --> %d\n",scalar keys(%{$dataref}));
  } else {
    my $sql=$self->{DB}->replace_tsvars($varref->{sql},$self->{CURRENTTS});
    my @cols=split(",",$columns);
    my $lastcol=$cols[$#cols];
    my $dataref=$DB->query($db,$table,
                            {
                              type => $vartype,
                              hash_keys => \@cols,
                              hash_value => $lastcol,
                              sql => $sql
                            });
    $vardataref->{data}=$dataref;
    if(scalar keys(%{$dataref}) > 0) {
      printf("$varname: $vartype $db $table $columns '%s' --> %d\n",$sql,scalar keys(%{$dataref}));
    } else {
      printf("$varname: $vartype $db $table $columns '%s' --> EMPTY\n",$sql);
    }
    # print Dumper($dataref);
  }
  printf("update_var_from_DB: %-20s end\n",$varname) if($debug);
}

sub apply_varset {
  my $self = shift; 
  my($var,$varsetref)=@_;
  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $var=~s/\$\{$key\}/$value/gs;	$var=~s/\$$key/$value/gs;
  }
  return($var);
}

1;
