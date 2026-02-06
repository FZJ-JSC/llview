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

sub process_FORALL {
  my $self = shift;
  my($DB,$forall,$varsetref,$func_ref,$funcpar)=@_;

  printf("process_FORALL: start\n") if($debug);

  return if(!exists($forall->{FORALL}));
  my $loopvar=$forall->{FORALL};
  printf("process_FORALL: loopvar=%s\n",$loopvar) if($debug);

  return if(!defined($funcpar));
  printf("process_FORALL: funcpar=%s\n",$funcpar) if($debug);
  
  my($varlist,$dbvar)=split(":",$loopvar);
  my @vars=split(",",$varlist);
  my $dbvarref;
  if($dbvar=~/\(([^\)]+)\)/) {
    my $list=$1;
    foreach my $k (split(/\s*,\s*/,$list)) {
      $dbvarref->{$k}=1;
    }
  } else {
    if($self->check_var_from_DB($DB,$dbvar)) {
      $dbvarref=$self->{VARS}->{$dbvar}->{data};
    } else {
      printf("%s process_FORALL: WARNING problems with var: %s\n",$self->{INSTNAME}, $dbvar);
    }
  }
  
  # start recursion
  &_process_FORALL($self,\@vars,$varsetref,$dbvarref,$func_ref,$funcpar);

  printf("process_FORALL: end\n") if($debug);
}

sub _process_FORALL {
  my $self = shift;
  my($varsref,$varsetref,$dbvarref,$func_ref,$funcpar)=@_;

  # printf("_process_FORALL: start vars='%s'\n",join(",",@{$varsref})) if($debug);

  if( defined($varsref) && (@{$varsref} > 0) ) {
    # copy varset for recursion
    my $localvarsetref;
    while ( my ($key, $value) = each(%{$varsetref}) ) {
      $localvarsetref->{$key}=$value;
    }

    # get first var and the associated values
    my @vars=(@{$varsref});
    my $v=shift(@vars);
    my @valuelist=keys(%{$dbvarref});

    printf("_process_FORALL: loop var=%s vars='%s' #keys=%d\n",$v,join(",",@vars), scalar @valuelist) if($debug);
    # start recursion again
    foreach my $value (sort(@valuelist)) {
      $localvarsetref->{$v}=$value;
      &_process_FORALL($self,\@vars,$localvarsetref,$dbvarref->{$value},$func_ref,$funcpar);
      # last; # debug
    }
  } else {
    # end of recursion

    # There are some tables that contain entries with slashes. When they
    # are used in filenames (coming from the VAR), they should be escaped.
    # This is done here, only when they are used in 'filepath'
    my $local_funcpar;
    my $string_to_modify_ref; # Reference to the specific string we want to patch

    # Determine if input is Hash or String
    if (ref($funcpar) eq 'HASH') {
      # It's a Hash: Make a shallow copy
      my %copy = %{$funcpar};
      $local_funcpar = \%copy;
      
      # We only care if 'filepath' key exists
      if (exists($local_funcpar->{filepath})) {
        $string_to_modify_ref = \$local_funcpar->{filepath};
      }
    } else {
      # It's a String/Scalar: Make a copy
      $local_funcpar = $funcpar;
      # We try to modify the string itself
      $string_to_modify_ref = \$local_funcpar;
    }

    # Apply the logic if we found a string to modify
    if (defined($string_to_modify_ref)) {

      # Whitelist: Variables that are folders and MUST keep slashes
      my %dir_whitelist = (
        'outputdir' => 1,
        'tmpdir'    => 1,
        'dbdir'     => 1,
        'archdir'   => 1
      );

      while ( my ($key, $val) = each(%{$varsetref}) ) {
        # Skip if value has no slash, or key is whitelisted
        next if (!defined($val) || $val !~ /\//);
        next if (exists($dir_whitelist{$key}));

        # Check if this specific variable is used in the target string
        # We look for the pattern ${KEY}
        if ($$string_to_modify_ref =~ /\$\{\Q$key\E\}/) {
          
          # Create safe version with %2F
          my $safe_val = $val;
          $safe_val =~ s/\//%2F/g;
          
          # Substitute it immediately into the local copy
          # This prevents the raw slash from being substituted later
          $$string_to_modify_ref =~ s/\$\{\Q$key\E\}/$safe_val/g;
          
          # Debug print
          # print STDERR "DEBUG FIX: Replaced \${$key} with '$safe_val'\n" if($debug);
        }
      }
    }

    # Pass the locally modified parameters
    &$func_ref($self, $local_funcpar, $varsetref);
  }
  # printf("_process_FORALL: end\n") if($debug);
}

1;
