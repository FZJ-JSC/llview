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

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );


sub start_insert_sequence {
  my($self) = shift;
  my($db,$table,$colsref)=@_;
  printf("  LLmonDB: start of start of insert_sequence %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  my $seq=$dbobj->start_insert_sequence($table,$colsref);
  printf("  LLmonDB: end of start of insert_sequence\n") if($debug>=3);

  return($seq);
}

sub insert_sequence {
  my($self) = shift;
  my($db,$table,$seq,$data)=@_;
  printf("  LLmonDB: start of end insert_sequence %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  $dbobj->insert_sequence($seq,$data);
  printf("  LLmonDB: end of end insert_sequence\n") if($debug>=3);

  return();
}

sub end_insert_sequence {
  my($self) = shift;
  my($db,$table,$seq)=@_;
  printf("  LLmonDB: start of end insert_sequence %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  $dbobj->end_insert_sequence($seq);
  printf("  LLmonDB: end of end insert_sequence\n") if($debug>=3);

  return();
}

sub start_insert_sequence_batch {
  my($self) = shift;
  my($db,$table,$colsref,$batch_size)=@_;
  printf("  LLmonDB: start of start of insert_sequence_batch %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  my $seq=$dbobj->start_insert_sequence_batch($table,$colsref,$batch_size);
  printf("  LLmonDB: end of start of insert_sequence_batch\n") if($debug>=3);

  return( $seq );
}

sub insert_sequence_batch {
  my($self) = shift;
  my($db,$table,$seq,$data)=@_;
  printf("  LLmonDB: start of end insert_sequence_batch %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  $dbobj->insert_sequence_batch($seq,$data);
  printf("  LLmonDB: end of end insert_sequence_batch\n") if($debug>=3);

  return();
}


sub end_insert_sequence_batch {
  my($self) = shift;
  my($db,$table,$seq)=@_;
  printf("  LLmonDB: start of end insert_sequence_batch %s/%s\n",$db,$table) if($debug>=3);

  my $dbobj=$self->get_db_handle($db);
  $dbobj->end_insert_sequence_batch($seq);
  printf("  LLmonDB: end of end insert_sequence_batch\n") if($debug>=3);

  return();
}


1;
