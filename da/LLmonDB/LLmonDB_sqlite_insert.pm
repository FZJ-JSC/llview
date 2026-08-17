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

package LLmonDB_sqlite;

my $VERSION='$Revision: 1.00 $';
my $debug=0;
my($LOGACCESS)=0;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

# start insert sequence
sub start_insert_sequence {
  my($self) = shift;
  my($table,$colsref) = @_;
  my @placeholders=map { '?' } 1.. scalar @{$colsref};
  # First fix quotation of table and column names
  my $safe_table = $self->{DBH}->quote_identifier($table);
  my @safe_cols = map {
      my $col = $_;
      $col =~ s/^"|"$//g;               # Strip existing external quotes
      $self->{DBH}->quote_identifier($col); # Let DBI handle the quoting safely
  } @{$colsref};
  # Now prepare the SQL command
  my $sql = sprintf('INSERT INTO %s (%s) VALUES (%s)',
                    $safe_table,
                    join(",", @safe_cols),
                    join(",", @placeholders),
                    );
  my $sth = $self->{DBH}->prepare($sql) or die "PREPARE FAILED!\nError: " . $self->{DBH}->errstr . "\nSQL DUMP:\n$sql\n";

  $self->{DBH}->begin_work();
  printf("\t   LLmonDB_sqlite: start_insert_sequence %s (sql: %s...)\n",$table,substr($sql,0,16)) if($debug>=3);
  return($sth);
}

# end insert sequence
sub insert_sequence {
  my($self) = shift;
  my($sth,$dataref) = @_;
  my $rc=$sth->execute( @{$dataref} );
  $self->LOGREPORT($self->{DBNAME},"E:insert_sequence",caller(),$DBI::errstr) if(!defined($rc));
  return($rc);

  $self->{A}=0;  #dummy statement to avoid unused warning
}


# insert sequence
sub end_insert_sequence {
  my($self) = shift;
  my($sth) = @_;

  $sth->finish();
  $self->{DBH}->commit();
  # $self->mycommit();
  print "\t   LLmonDB_sqlite: end_insert_sequence\n" if($debug>=3);
  return();
}

sub start_insert_sequence_batch {
  my($self) = shift;
  my($table,$colsref,$batch_size) = @_;
  $batch_size //= 900;

  # Max 900 Platzhalter (sicherheitshalber unter 999)
  my $max_vars = 900;
  $batch_size = int($max_vars / scalar @{$colsref}) if $batch_size > int($max_vars / scalar @{$colsref});
  
  my $safe_table = $self->{DBH}->quote_identifier($table);
  my @safe_cols = map {
    my $col = $_;
    $col =~ s/^"|"$//g;
    $self->{DBH}->quote_identifier($col);
  } @{$colsref};
  
#  my $sync_old = $self->{DBH}->selectrow_arrayref("PRAGMA synchronous")->[0];
#  my $journal_old = $self->{DBH}->selectrow_arrayref("PRAGMA journal_mode")->[0];

#  $self->{DBH}->do("PRAGMA synchronous = OFF");
#  $self->{DBH}->do("PRAGMA journal_mode = MEMORY");
  
  $self->{DBH}->begin_work();
  print "\tstart_insert_sequence_batch $table (batch=$batch_size)\n" if $debug>=3;
  
  my $seq = {
    TABLE => $safe_table,
    COLS => \@safe_cols,
    BATCH_SIZE => $batch_size,
    BUFFER => [],
#    SYNC_OLD => $sync_old,
#    JOURNAL_OLD => $journal_old,
  };
  
  return $seq;
}

sub insert_sequence_batch {
  my($self) = shift;
  my($seq, $dataref) = @_;
  
  warn "WARNING: insert_sequence_batch: \$dataref is not an ARRAY ref at " . caller() . "\nParams: " . Dumper($dataref) unless ref($dataref) eq 'ARRAY';
  
  push @{$seq->{BUFFER}}, $dataref;
  
  if (scalar @{$seq->{BUFFER}} >= $seq->{BATCH_SIZE}) {
    $self->_flush_insert_buffer($seq);
  }
  
  return 1;
}

sub end_insert_sequence_batch {
  my($self) = shift;
  my($seq) = @_;
  
  $self->_flush_insert_buffer($seq);
  $self->{DBH}->commit();

#  $self->{DBH}->do("PRAGMA synchronous = " . $seq->{SYNC_OLD});
#  $self->{DBH}->do("PRAGMA journal_mode = " . $seq->{JOURNAL_OLD});

  print "\tend_insert_sequence_batch\n" if $debug>=3;
  return();
}

sub _flush_insert_buffer {
  my($self) = shift;
  my($seq) = @_;
  my $buffer = $seq->{BUFFER};
  
  return unless @$buffer;
  
  my $batch_size = scalar @$buffer;
  my $num_cols = scalar @{$seq->{COLS}};
  
  my $value_part = join(',', map { '(' . join(',', ('?') x $num_cols) . ')' } 1..$batch_size);
  my $sql = sprintf('INSERT INTO %s (%s) VALUES %s',
                    $seq->{TABLE},
                    join(",", @{$seq->{COLS}}),
                    $value_part);
  
  my $sth = $self->{DBH}->prepare($sql) or die "PREPARE FAILED: " . $self->{DBH}->errstr;

  my @flat = map {@$_} @$buffer;
  $sth->execute(@flat) or die "EXECUTE FAILED: " . $sth->errstr;
  
  print "\t_flush_insert_buffer: $batch_size rows\n" if $debug>=3;
  @$buffer = ();
  
  return $batch_size;
}

1;
