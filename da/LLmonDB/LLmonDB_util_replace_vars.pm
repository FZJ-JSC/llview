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

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use POSIX qw(strftime);
use LML_da_util qw( sec_to_date_iso );

sub replace_vars {
  my($self) = shift;
  my($sql)=@_;
  my $new_sql=$sql;

  if($new_sql=~/SYSTEM_?NAME/) {
    my $system_name=$self->{SYSTEM_NAME};
    $new_sql=~s/SYSTEM_?NAME/$system_name/gs;
  }
  return($self->replace_tsvars($new_sql,$self->{CURRENTTS},$self->{REALCURRENTTS}));
  #
  $self;
}

sub replace_tsvars {
  my($self) = shift;
  my($sql,$nowts,$realnowts)=@_;
  my $new_sql=$sql;

  if($new_sql=~/TS_STARTOFTODAY/) {
    my (undef,undef,undef,$mday,$mon,$year)=localtime($nowts);
    my $ts_startoftoday=timelocal(0,0,0,$mday,$mon,$year);
    $new_sql=~s/TS_STARTOFTODAY/$ts_startoftoday/gs;
    # printf( "TS_STARTOFTODAY: %d - %d diff=%.2f \n",$nowts,$ts_startoftoday,($nowts-$ts_startoftoday)/3600.0);
  }
  if($new_sql=~/DATE_NOW/) {
    my $ldate=&sec_to_date_iso($nowts);
    $new_sql=~s/DATE_NOW/$ldate/gs;
  }
  if(defined($realnowts)) {
    if($new_sql=~/REAL_TS_NOW/) {
      $new_sql=~s/REAL_TS_NOW/$realnowts/gs;
    }
  }
  if($new_sql=~/TS_NOW/) {
    $new_sql=~s/TS_NOW/$nowts/gs;
  }
  return($new_sql);
  #
  $self;
}

sub timeexpr_to_sec {
  my($self) = shift;
  my($expr)=@_;
  my $value=-1;

  if($expr=~/([\d.]+)([dhm])/) {
    my($val,$unit)=($1,$2);
    $value=$val*60 if($unit eq "m");
    $value=$val*60*60 if($unit eq "h");
    $value=$val*24*60*60 if($unit eq "d");
  } else {
    $value=$expr;
  }

  return($value);
  #
  $self;
}

1;
