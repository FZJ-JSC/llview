# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

package LML_da_workflow_obj;

my $debug=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $verbose = shift;
  my $timings = shift;
  printf("\t LML_da_workflow_obj: new %s\n",ref($proto)) if($debug>=3);
  $self->{DATA}      = {};
  $self->{VERBOSE}   = $verbose; 
  $self->{TIMINGS}   = $timings; 
  $self->{LASTINFOID} = undef;
  bless $self, $class;
  return $self;
}

sub read_xml_fast {
  my($self) = shift;
  my $infile  = shift;
  my($xmlin);
  my $rc=0;

  my $tstart=time;
  if(!open(IN,$infile)) {
    print STDERR "$0: ERROR: could not open $infile, leaving...\n";return(0);
  }
  # Slurp the file
  { local $/; $xmlin = <IN>; }
  close(IN);
  
  my $tdiff=time-$tstart;
  printf("LML_da_workflow_obj: read  XML in %6.4f sec\n",$tdiff) if($self->{VERBOSE});

  if(!$xmlin) {
    print STDERR "$0: ERROR: empty file $infile, leaving...\n";return(0);
  }

  $tstart=time;

  # Clean up newlines for simpler regexes
  $xmlin=~s/\n/ /gs;
  $xmlin=~s/\s\s+/ /gs;

  my ($tag, $tagname, $rest, @list);

  # Loop through the string finding Tags one by one.
  # The Regex Explanation:
  # <              : Match start of tag
  # (?:            : Non-capturing group for tag content
  #   "[^"]*"      : Match double-quoted strings (fastest simple case)
  #   |            : OR
  #   '[^']*'      : Match single-quoted strings
  #   |            : OR
  #   [^'">]       : Match anything that isn't a quote or end-tag
  # )*             : Repeat 0 or more times
  # >              : Match end of tag
  while ($xmlin =~ /(<(?:"[^"]*"|'[^']*'|[^'">])*>)/gs) {
    $tag = $1;
    
    # Check for Comments
    if ($tag =~ /^<\!--/) {
      next;
    }
    
    # Check for End Tags </tag>
    elsif ($tag =~ /^<\/\s*([^\s>]+)/) {
      $tagname = $1;
      $self->xml_end($self->{DATA}, $tagname, ());
    }
    
    # Check for Start Tags (with optional self-closing /)
    # This regex captures the Name ($1) and the raw attributes string ($2)
    elsif ($tag =~ /^<([^\s\/>]+)(?:\s+(.*?))?\s*(\/?)>$/) {
      $tagname     = $1;
      my $attr_str = $2 || "";
      my $is_closed= $3; # If this is "/", it is a self-closing tag
      
      # Efficiently parse all attributes (key="val" or key='val') 
      # including escaped quotes inside values.
      @list = ();
      while ($attr_str =~ /([^\s=]+)\s*=\s*(["'])((?:\\.|(?!\2).)*)\2/g) {
        my ($k, $q, $v) = ($1, $2, $3);
        $v =~ s/\\$q/$q/g; # Unescape the specific quote type used
        push(@list, $k, $v);
      }

      # Call Start
      $self->xml_start($self->{DATA}, $tagname, @list);

      # If self-closing <tag ... />, immediately call End
      if ($is_closed eq "/") {
        $self->xml_end($self->{DATA}, $tagname, ());
      }
    }
  }

  $tdiff=time-$tstart;
  printf("LML_da_workflow_obj: parse XML in %6.4f sec\n",$tdiff) if($self->{VERBOSE});

  # FOR DEBUG
  # local $Data::Dumper::Useqq = 1; # Force double quotes to see backslashes clearly
  # local $Data::Dumper::Indent = 1;
  # local $Data::Dumper::Sortkeys = 1;
  # print STDERR Dumper($self->{DATA});
  # ---

  return($rc);
}

sub xml_start {
  my $self=shift; # object reference
  my $o   =shift;
  my $name=shift;
  my($k,$v,$actnodename,$id,$sid,$oid);

  # print "LML_da_workflow_obj: lml_start >$name< \n";

  if($name eq "!--") {
    return(1);
  }
  my %attr=(@_);

  foreach $k (sort keys %attr) {
    
    # Substitute ${VAR} ONLY if NOT escaped
    # Matches: ${VAR}
    # Ignored: \${VAR}
    while ( $attr{$k} =~ /(?<!\\)\$\{(\w+)\}/ ) {
      my $var = $1;
      if (defined($ENV{$var})) {
        $attr{$k} =~ s/(?<!\\)\$\{$var\}/$ENV{$var}/g;
      } else {
        $attr{$k} =~ s/(?<!\\)\$\{$var\}//g;
      }
    }

    # Substitute $ENV{VAR} ONLY if NOT escaped
    while ( $attr{$k} =~ /(?<!\\)\$ENV\{(\w+)\}/ ) {
      my $var = $1;
      if (defined($ENV{$var})) {
        $attr{$k} =~ s/(?<!\\)\$ENV\{$var\}/$ENV{$var}/g;
      } else {
        $attr{$k} =~ s/(?<!\\)\$ENV\{$var\}//g;
      }
    }
  }

  if($name eq "LML_da_workflow") {
    foreach $k (sort keys %attr) {
      $o->{LML_da_workflow}->{$k}=$attr{$k};
    }
    return(1);
  }

  if($name eq "vardefs") {
    return(1);
  }
  if($name eq "var") {
    push(@{$o->{vardefs}->[0]->{var}},\%attr);
    return(1);
  }
  if($name eq "step") {
    $id=$attr{id};
    $o->{LASTSTEPID}=$id;
    foreach $k (sort keys %attr) {
      $o->{step}->{$id}->{$k}=$attr{$k};
    }
    return(1);
  }
  if($name eq "cmd") {
    $id=$attr{id};
    $sid=$o->{LASTSTEPID};

    push(@{$o->{step}->{$sid}->{cmd}},\%attr);

    return(1);
  }

  # unknown element
  print "LML_da_workflow_obj: WARNING unknown tag >$name< \n";
}

sub xml_end {
  my $self=shift; # object reference
  my $o   =shift;
  my $name=shift;
  # print "LML_da_workflow_obj: lml_end >$name< \n";

  if($name=~/vardefs/) {
  }
  if($name=~/step/) {
    $o->{LASTSTEPID}=undef;
  }

#    print Dumper($o->{NODEDISPLAYSTACK});
}


sub write_xml {
  my($self) = shift;
  my($k,$rc,$id,$c,$key,$ref);
  my $outfile  = shift;
  my $tstart=time;
  my $data="";

  $rc=1;

  open(OUT,"> $outfile") || die "cannot open file $outfile";

  printf(OUT "<LML_da_workflow ");
  foreach $k (sort keys %{$self->{DATA}->{LML_da_workflow}}) {
    printf(OUT "%s=\"%s\"\n ",$k,$self->{DATA}->{LMLLGUI}->{$k});
  }
  printf(OUT "     \>\n");

  printf(OUT "<vardefs>\n");
  foreach $ref (@{$self->{DATA}->{vardefs}->[0]->{var}}) {
    printf(OUT "<var");
    foreach $k (sort keys %{$ref}) {
      printf(OUT " %s=\"%s\"",$k,$ref->{$k});
    }
    printf(OUT "/>\n");
  }
  printf(OUT "</vardefs>\n");

  foreach $id (sort keys %{$self->{DATA}->{step}}) {
    printf(OUT "<step");
    foreach $k (sort keys %{$self->{DATA}->{step}->{$id}}) {
      next if($k eq "cmd");
      printf(OUT " %s=\"%s\"",$k,$self->{DATA}->{step}->{$id}->{$k});
    }
    printf(OUT ">\n");
    if(exists($self->{DATA}->{step}->{$id}->{cmd})) {
      foreach $ref (@{$self->{DATA}->{step}->{$id}->{cmd}}) {
        printf(OUT "<cmd ");
        foreach $k (sort keys %{$ref}) {
          printf(OUT " %s=\"%s\"",$k,$ref->{$k});
        }
        printf(OUT "/>\n");
      }
    }
    printf(OUT "</step>\n");
  }
  
  printf(OUT "</LML_da_workflow>\n");
  
  close(OUT);

  my $tdiff=time-$tstart;
  printf("LML_da_workflow_obj: wrote  XML in %6.4f sec to %s\n",$tdiff,$outfile) if($self->{TIMINGS});
  
  return($rc);
}

1;
