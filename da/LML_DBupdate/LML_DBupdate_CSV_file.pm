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
my($debug)=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_file_csv;

my $patint="([\\+\\-\\d]+)";   # Pattern for Integer number
my $patfp ="([\\+\\-\\d.E]+)"; # Pattern for Floating Point number
my $patwrd="([\^\\s]+)";       # Pattern for Work (all noblank characters)
my $patbl ="\\s+";             # Pattern for blank space (variable length)

sub read_CSV {
  my($self) = shift;
  my($filename)=@_;
  
  if(! -f $filename) {
    printf(STDERR "\n[LML_DBupdate_CSV_file] ERROR: file $filename not found, leaving...\n\n");
    return();
  }
  my $tag;
  $filename=~/^.*\/([^\/]+)$/;
  my $help=$1;
  if($help=~/db_$patwrd\_tab\_$patwrd\_date\_$patint\_w$patint\./) {
    $tag=$2;
  } elsif($help=~/d$patint\_ts$patint\_(.*)\./) {
    $tag=$3;
  } else {
    $tag=$help;
    $tag=~s/^.*\///s;
    $tag=~s/\.csv$//s;
  }
  $tag=uc($tag)."_ENTRIES";
  # print "[read_CSV] TMPDEB: tag: $filename -> $tag\n";
  my $csv_file=LL_file_csv->new($self->{VERBOSE});
  $csv_file->read_CSV($filename);
  push(@{$self->{DATA}->{$tag}},@{$csv_file->{DATA}});

  # print "TMPDEB:",Dumper($self->{DATA});
}

1;
