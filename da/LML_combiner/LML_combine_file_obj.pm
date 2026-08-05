# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_combine_file_obj;

my($debug)=0;

use strict;
use lib "$FindBin::RealBin/../lib";
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $verbose = shift;
  my $timings = shift;
  my $keep = shift; # If true, two objects with the same ID are kept separated, the second ID is altered accordingly
  if(! defined($keep)) {
    $keep = 0;
  }
  $self->{DATA}      = {};
  $self->{VERBOSE}   = $verbose; 
  $self->{INSTNAME}  = $0; $self->{INSTNAME}=~s/^.*\///gs; $self->{INSTNAME}="[$self->{INSTNAME}]";
  $self->{TIMINGS}   = $timings; 
  $self->{LASTINFOID} = undef;
  $self->{KEEP} = $keep;
  printf("$self->{INSTNAME}\t new %s\n",ref($proto)) if($debug>=3);
  
  bless $self, $class;
  return $self;
}

sub get_data_ref {
  my($self) = shift;
  return($self->{DATA});
} 

sub get_stat {
  my($self) = shift;
  my($log,$type,%types,$id);
  $log="";
  
  $log.=sprintf("objects: total #%d\n",scalar keys(%{$self->{DATA}->{OBJECT}}));
  foreach $id (keys %{$self->{DATA}->{OBJECT}}) {
    $type=$self->{DATA}->{OBJECT}->{$id}->{type};
    $types{$type}++;
  }
  foreach $type (sort keys %types) {
    $log.=sprintf("        |-- %10d (%s)\n",$types{$type},$type);
  }
  return($log);
} 

sub read_lml_fast {
  my($self)  = shift;
  my $infile = shift;
  my $type   = shift;
  my($xmlin);
  my $rc=0;
  
  $self->{IDMAP} = {};

  my $tstart=time;
  if(!open(IN,$infile)) {
    print "could not open $infile, leaving...\n";
    return(0);
  }
  while(<IN>) {
    $xmlin.=$_;
  }
  close(IN);
  my $tdiff=time-$tstart;
  printf("$self->{INSTNAME} read $infile XML in %6.4f sec\n",$tdiff) if($self->{VERBOSE});

  $self->{DATA}->{SEARCHTYPE}=$type;
  $tstart=time;

  # light-weight self written xml parser, only working for simple XML files  
  $xmlin=~s/\n/ /gs;
  $xmlin=~s/\s\s+/ /gs;
  my ($tag,$tagname,$rest,$ctag,$nrc,@list);
  foreach $tag (split(/\>\s*/,$xmlin)) {
    $ctag.=$tag;
    $nrc=($ctag=~ tr/\"/\"/);
    if($nrc%2==0) {
      $tag=$ctag;
      $ctag="";
    } else {
      $ctag.=">";
      next;
    }
    
    # print STDERR "TAG: '$tag'\n";
    if($tag=~/^\s*<[\/\?](.*)[^\s\>]/) {
      $tagname=$1;
      $self->lml_end($self->{DATA},$tagname,());
    } elsif($tag=~/^\s*<([^\s]+)\s*$/) {
      $tagname=$1;
      # print STDERR "TAG0: '$tagname'\n";
      $self->lml_start($self->{DATA},$tagname,());
    } elsif($tag=~/^\s*<([^\s]+)(\s(.*)[^\/])$/) {
      $tagname=$1;
      $rest=$2;$rest=~s/^\s*//gs;$rest=~s/\s*$//gs;$rest=~s/""/"-LML-"/gs;
      # print STDERR "TAG1: '$tagname' rest='$rest'\n";
      @list = $rest =~ /([^\s]+?)="(.*?)"/g;
      $self->lml_start($self->{DATA},$tagname,@list);
    } elsif($tag=~/^\s*<([^\s]+)(\s(.*)\s?)\/$/) {
      $tagname=$1;
      $rest=$2;$rest=~s/^\s*//gs;$rest=~s/\s*$//gs;$rest=~s/""/"-LML-"/gs;
      # print STDERR "TAG2: '$tagname' rest='$rest' closed\n";
      @list = $rest =~ /([^\s]+?)="(.*?)"/g;
      $self->lml_start($self->{DATA},$tagname,@list);
      $self->lml_end($self->{DATA},$tagname,());
    }
  }

  $tdiff=time-$tstart;
  printf("$self->{INSTNAME} parse XML in %6.4f sec\n",$tdiff) if($self->{VERBOSE});

  # print Dumper($self->{DATA});
  return($rc);
}

sub lml_start {
  my $self=shift; # object reference
  my $o   =shift;
  my $name=shift;
  # print "TMPDEB: >",ref($o),"< >$name< (",join(',',@_),")\n";
  my($k,$v,$actnodename,$id);
  my %attr=(@_);

  foreach $k (sort keys %attr) {
    $attr{$k}=~s/-LML-//gs;
  }
  
  if($name eq "lml:lgui") {
    foreach $k (sort keys %attr) {
      $o->{LMLLGUI}->{$k}=$attr{$k};
    }
    return(1);
  }
  if($name eq "objects") {
    return(1);
  }
  if($name eq "information") {
    return(1);
  }
  if($name eq "object") {
    $id=$attr{id};
    if(exists($o->{OBJECT}->{$id})) {
      if($self->{KEEP} == 0 || exists($self->{IDMAP}->{$id}) ) {
        print STDERR "$self->{INSTNAME} WARNING: objects with id >$id< already exists, skipping...\n";
        return(0);
      } else { #Adjust the ID of this object
        my $prefix = $id;
        my $nr = 0;
        if($id =~ /^(\D+)(\d+)$/ ){
          $prefix = $1;
          $nr = $2;
        }
        my $newId = sprintf("%s%06d", $prefix, $nr);
        
        while( exists($o->{OBJECT}->{$newId}) ){#Search new ID, which is not occupied so far
          $nr++;
          $newId = sprintf("%s%06d", $prefix, $nr);
        }
        
        $self->{IDMAP}->{$id} = $newId;#Store the ID mapping for other objects
        
        print "Remap ID $id to $newId\n";
        
        $id = $newId;
        $attr{id} = $id;
      }
    }
    foreach $k (sort keys %attr) {
      # print "$k: $attr{$k}\n";
      $o->{OBJECT}->{$id}->{$k}=$attr{$k};
    }
    
    if( defined($o->{OBJECT}->{$id}->{"type"}) && $o->{OBJECT}->{$id}->{"type"} eq "jobattr" ){
      if(defined($o->{OBJECT}->{$id}->{"name"}) ){
        my $jobname = $o->{OBJECT}->{$id}->{"name"};
        # Search for existing job object with given name attribute, or at least containing the abov jobname
        my $oid;
        foreach $oid (keys(%{$o->{OBJECT}})){
          if( defined($o->{OBJECT}->{$oid}->{"type"}) && $o->{OBJECT}->{$oid}->{"type"} eq "job" ){
            if(defined($o->{OBJECT}->{$oid}->{"name"})) {
              my $realJobName = $o->{OBJECT}->{$oid}->{"name"};
              if( $realJobName =~ /$jobname/ ){
                $o->{OBJECT}->{$id}->{"name"} = $oid;#Save corresponding job id as name attribute of the jobattr object
                
                last;
              }
            }
          }
        }
      }
    }
    
    return(1);
  }
  if($name eq "info") {
    $id=$attr{oid};
    if($self->{KEEP} == 1 && exists($self->{IDMAP}->{$id})) {
      $id = $self->{IDMAP}->{$id};
      $attr{oid} = $id;
    }
    $o->{LASTINFOID}=$id;
    
    # Add jobattr elements to the corresponding info object of the actual job
    if( defined($o->{OBJECT}->{$id}->{"type"}) && $o->{OBJECT}->{$id}->{"type"} eq "jobattr" ){
      $o->{LASTINFOID} = $o->{OBJECT}->{$id}->{"name"};
      # Do not copy this info object to the output file
      # And do not copy the object declaration at all:
      delete $o->{OBJECT}->{$id};
      
      return (1);
    }
    
    if(exists($o->{INFO}->{$id})) {
      print STDERR "$self->{INSTNAME} WARNING: info with id >$id< already exists, skipping...\n";
      return(0);
    }
    foreach $k (sort keys %attr) {
      # print "$k: $attr{$k}\n";
      $o->{INFO}->{$id}->{$k}=$attr{$k};
    }
    return(1);
  }
  if($name eq "data") {
    $id=$o->{LASTINFOID};
    $k=$attr{key};
    $v=$attr{value};

    if(exists($o->{INFODATA}->{$id}->{$k})) {
      print STDERR "$self->{INSTNAME} WARNING: infodata with id >$id< and key >$k< already exists, skipping...\n";
      return(0);
    }
    $o->{INFODATA}->{$id}->{$k}=$v;
    return(1);
  }
  print STDERR "$self->{INSTNAME} WARNING: unknown tag >$name< \n";
}

sub lml_end {
  my $self=shift; # object reference
  my $name=shift;
}


sub write_lml {
  my($self) = shift;
  my $outfile = shift;
  my($k,$rc,$id);
  my $tstart=time;
  $rc=1;

  open(OUT,"> $outfile") || die "cannot open file $outfile";
  printf(OUT "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n");

  printf(OUT "<lml:lgui ");
  foreach $k (sort keys %{$self->{DATA}->{LMLLGUI}}) {
    printf(OUT "%s=\"%s\"\n ",$k,$self->{DATA}->{LMLLGUI}->{$k});
  }
  printf(OUT "     \>\n");

  printf(OUT "<objects>\n");
  foreach $id (sort keys %{$self->{DATA}->{OBJECT}}) {
    printf(OUT "<object");
    foreach $k (sort keys %{$self->{DATA}->{OBJECT}->{$id}}) {
      printf(OUT " %s=\"%s\"",$k,$self->{DATA}->{OBJECT}->{$id}->{$k});
    }
    printf(OUT "/>\n");
  }
  printf(OUT "</objects>\n");

  printf(OUT "<information>\n");
  foreach $id (sort keys %{$self->{DATA}->{INFO}}) {
    printf(OUT "<info");
    foreach $k (sort keys %{$self->{DATA}->{INFO}->{$id}}) {
      printf(OUT " %s=\"%s\"",$k,$self->{DATA}->{INFO}->{$id}->{$k});
    }
    printf(OUT ">\n");
    foreach $k (sort keys %{$self->{DATA}->{INFODATA}->{$id}}) {
      printf(OUT "<data key=\"%s\" value=\"%s\"/>\n",$k,$self->{DATA}->{INFODATA}->{$id}->{$k});
    }
    printf(OUT "</info>\n");
  }
  printf(OUT "</information>\n");
  printf(OUT "</lml:lgui>\n");
  close(OUT);

  my $tdiff=time-$tstart;
  printf("$self->{INSTNAME} wrote  XML in %6.4f sec to %s\n",$tdiff,$outfile) if($self->{TIMINGS});

  return($rc);
}

1;
