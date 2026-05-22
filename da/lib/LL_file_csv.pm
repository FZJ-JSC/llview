# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
package LL_file_csv;

my($debug)=0;

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
  printf(STDERR "[LL_file_csv]\t new %s $class\n",ref($proto)) if($debug>=3);
  $self->{DATA}      = [];
  $self->{VERBOSE}   = 0; 
  $self->{VERBOSE}   = $verbose if(defined($verbose));  
  $self->{TIMINGS}   = 0; 
  $self->{TIMINGS}   = $timings if(defined($timings)); 
  bless $self, $class;
  return $self;
}

# read csv file into memory
# data is stored in $self->{DATA}=[hash1, hash2, ...]
#                   hash<n> = key values from CSV file                  
sub read_CSV {
  my($self) = shift;
  my($filename)=@_;
  
  printf("[LL_file_csv] \t read_CSV $filename\n") if($self->{VERBOSE});

  if(! -f $filename) {
    printf(STDERR "[LL_file_csv] ERROR file $filename not found, leaving ...\n\n");
    return();
  }
  if($filename=~/.csv$/) {
    open(CSV,$filename) or die "cannot open '$filename'";
  } elsif($filename=~/.csv.xz$/) {
    open(CSV,"xzcat $filename|") or die "cannot open '$filename'";
  } elsif($filename=~/.csv.gz$/) {
    open(CSV,"zcat $filename|") or die "cannot open '$filename'";
  } else {
    printf(STDERR "[LL_file_csv] ERROR unknown file type extension $filename, leaving ...\n\n");
    return();
  }
  my @keys;
  my $firstline=<CSV>;
  chomp($firstline);
  #    print "TMPDEB: first line: $firstline\n";
  if($firstline=~/^\#DATE:/) {
    # it's a archived DB file, skip line
    $firstline=<CSV>; # COUNT:
    $firstline=<CSV>; # COLUMNS:
    if($firstline!~/^\#COLUMNS:/) {
      printf(STDERR "[LL_file_csv] ERROR no COLUMNS entry found in archDB CSV file $filename, leaving ...\n\n");
      return();
    }
    $firstline=~s/^\s*\#COLUMNS\: //s;$firstline=~s/\n//gs;
    @keys=split('\s*,\s*',$firstline);
  } else {
    # it's normal CSV file, first line contains header
    $firstline=~s/^\s*\#//s;$firstline=~s/\n//gs;
    @keys=split('\s*,\s*',$firstline);
  }
  my $numkeys=scalar @keys;
  printf("[LL_file_csv] \t #keys=%d (%s)\n",$numkeys,join(",",@keys))  if($self->{VERBOSE});
  my $count_lines=0;
  my $count_skipped=0;
  my $count_headers=1;
  while(my $dataline=<CSV>) {
    next if($dataline=~/^\#DATE:/);
    next if($dataline=~/^\#COUNT:/);
    chomp($dataline);
    if($dataline=~/^#COLUMNS:/) {
      $dataline=~s/^\s*\#COLUMNS\: //s;$dataline=~s/\n//gs;
      @keys=split('\s*,\s*',$dataline);
      $numkeys= scalar @keys;
      printf("[LL_file_csv] \t #keys=%d (%s)\n",$numkeys,join(",",@keys)) if($debug>=3);
      $count_headers++;
      next;
    }
    $dataline=~s/\n//gs;
    $dataline=~s/\\\\,/\0/gs;
    my @values=split('\s*,\s*',$dataline,-1);
    for(my $k=0;$k<=$#values;$k++) {
      $values[$k]=~s/\0/\,/gs;
    }
    if( (scalar @values) != $numkeys) {
      printf(STDERR "[LL_file_csv] ERROR number of elements (%d) in line differs from #keys (%d), skipping line ($dataline) ...\n",(scalar @values), $numkeys);
      $count_skipped++;
      # print STDERR "TMPDEB: dataline (",scalar @values," [$numkeys]): $dataline\n";
      for(my $k=0;$k<=$#values;$k++) {
        printf(" [%3d] %-20s = %s\n",$k, $keys[$k],$values[$k]);
      }
      next;
    }
    my $ref;
    for(my $k=0;$k<=$#values;$k++) {
      $ref->{$keys[$k]}=$values[$k];
    }
    push(@{$self->{DATA}},$ref);
    $count_lines++;
    if($count_lines%25000==0) {
      if($self->{VERBOSE}) {
        $|=1;printf("[LL_file_csv] \t %6d lines processed (%d skipped, %d headers)\n",$count_lines,$count_skipped,$count_headers);$|=0;
      }
    }
    #	last if($count_lines>50000);
  }
  if($self->{VERBOSE}) {
    $|=1;printf("[LL_file_csv] \t %6d lines processed (%d skipped, %d headers)\n",$count_lines,$count_skipped,$count_headers);$|=0;
  }
  CORE::close(CSV);
}

1;