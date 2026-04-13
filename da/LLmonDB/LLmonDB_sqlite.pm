# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LLmonDB_sqlite;

my $VERSION='$Revision: 1.00 $';
my $debug=0;
my($LOGACCESS)=0;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use DBI;
use DBD::SQLite;
use DBD::SQLite::BundledExtensions;

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $dbdir   = shift;
  my $dbname  = shift;
  my $verbose = shift;

  printf("  LLmonDB_sqlite: new %s\n",ref($proto)) if($debug>=3);
  $self->{VERBOSE}   = $verbose; 
  $self->{DBINIT}    = 0; 
  $self->{DBDIR}     = $dbdir; 
  $self->{DBNAME}    = $dbname; 
  $self->{FNAME}     = "$dbdir/LLmonDB_${dbname}.sqlite"; 
  $self->{INSTNAME}  = $0; $self->{INSTNAME}=~s/^.*\///gs; $self->{INSTNAME}="[$self->{INSTNAME}]";
  $self->{EOTS}      = 0;
  $self->{AUTOCOMMIT} = 1; 

  bless $self, $class;
  return $self;
}

sub LOGREPORT {
  my $self = shift;
  my($dbname,$op,$caller1,$caller2,$caller3,$err)=@_;
  return() if(!$LOGACCESS);
  my $ts=time();

  my $logname = "$self->{DBDIR}/log/LLmonDB_${dbname}.log"; 
  open(LOG, ">> $logname");
  my $str=sprintf("[%10d]%10d+%4d: %-20s %-15s (SCRIPT:%s) (ERR:%s) (CALLER:%s,%s,%s)\n",$$,
                    $ts,
                    ($self->{EOTS}>0)?$ts-$self->{EOTS}:0,
                    $dbname,
                    $op,
                    $self->{INSTNAME},
                    defined($err)?$err:"-",
                    $caller1,$caller2,$caller3);
  
  print LOG $str;
  close(LOG);
}

sub mycommit() {
  my $self = shift;
  
  if(!$self->{AUTOCOMMIT}) {
    $self->{DBH}->commit() or die $self->{DBH}->errstr;
  }
}


sub DESTROY {
  my $self = shift;

  if($self->{DBINIT}) {
    $self->LOGREPORT($self->{DBNAME},"destroy without close",caller(),"");
  }
  
  # disconnect from the database
  $self->close_db();
}

# check on existence of data base file 
sub check_db_file {
  my($self) = shift;

  if(-f $self->{FNAME}) {
    return(1);
  } else {
    return(0);
  }
}

# init and open data base 
sub init_db {
  my($self) = shift;
  return if($self->{DBINIT}==1);
  
  my $db_exists;
  if(-f $self->{FNAME}) {$db_exists=1;}
  else                  {$db_exists=0;}

  # $self->LOGREPORT($self->{DBNAME},"open start",caller(),"");

  # connect to database
  print "$self->{INSTNAME}   LLmonDB_sqlite: connect to db $self->{FNAME} at ts=",time(),"\n"  if($self->{VERBOSE}==2);
  my $dbh = DBI->connect("dbi:SQLite:dbname=$self->{FNAME}","","",{PrintError => 1});
  $self->{DBH} = $dbh;
  $dbh->do("PRAGMA synchronous = OFF");
  $dbh->do("PRAGMA busy_timeout= 5000");
  $dbh->do("PRAGMA cache_size = 8000000");
  $dbh->do("PRAGMA journal_mode = WAL");
  $dbh->do("PRAGMA optimize");
  $dbh->{sqlite_allow_multiple_statements}=1;
  # should be enabled only for write access !!! TODO
  #    $dbh->do("PRAGMA auto_vacuum = INCREMENTAL");
  $self->{DBINIT}=1;
  $self->{DBH}->{AutoCommit}=$self->{AUTOCOMMIT};
  
  my $eots=time();
  $self->{EOTS}=$eots;
  $self->mycommit();
  DBD::SQLite::BundledExtensions->_load_extension($dbh,"series");
  $self->LOGREPORT($self->{DBNAME},"open",caller(),"");
}


sub does_table_exists {
  my ($self,$table_name) = @_;

  my $sql = "SELECT name FROM sqlite_master WHERE (type='table') and (name='$table_name')";

  my $sth = $self->{DBH}->prepare($sql);
  $sth->execute();

  my @info = $sth->fetchrow_array;
  my $exists = scalar @info;

  return $exists;
}


# create a new table
sub create_table {
  my($self) = shift;
  my($table,$sqlcoldefs)=@_;
  my ($col);

  # Make the TABLE name safe (Strip quotes -> Re-quote safely)
  my $safe_table = $table;
  $safe_table =~ s/^"|"$//g;
  if($safe_table eq '' || !defined $safe_table) {
    die "CREATE TABLE FAILED: invalid or empty table name '$table' in database $self->{DBNAME}\n";
  }
  $safe_table = $self->{DBH}->quote_identifier($safe_table);

  my $sql = "CREATE TABLE $safe_table (";
  my @help;

  foreach $col (@{$sqlcoldefs->{collist}}) {
    # Get the column name
    my $col_name = $sqlcoldefs->{coldata}->{$col}->{name};
    
    # Strip existing quotes (in case it came in as "colname")
    $col_name =~ s/^"|"$//g;
    
    # Re-quote safely using DBI
    my $safe_col_name = $self->{DBH}->quote_identifier($col_name);

    # Combine the Quoted Name with the Unquoted Type (e.g., INTEGER)
    push(@help, sprintf("%s %s",
                  $safe_col_name,
                  $sqlcoldefs->{coldata}->{$col}->{sql}));
  }

  $sql .= join(",", @help);
  $sql .= ")";

  # Execute SQL command inside eval to catch crashes
  my $rc = eval { $self->{DBH}->do($sql); };
  my $err = $@ || $self->{DBH}->errstr;

  # Check the result
  if ($err || !defined($rc)) {
    # There was an error, die
    die "CREATE TABLE FAILED via DBI!\nSQL: $sql\nError: " . $err;
  } 
  
  # Only print this if it actually succeeded
  print "\t   LLmonDB_sqlite: created table $table for $self->{FNAME} ($sql)\n";

  $self->mycommit();
  
  return 1;
}

# Recreate a table (Create New -> Copy Data -> Drop Old -> Rename New)
sub recreate_table {
  my($self) = shift;
  my($table, $sqlcoldefs) = @_;

  # Prepare Names
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  
  # Use a random suffix or distinct name to avoid collisions
  my $clean_newtable = sprintf("_new_%s_%d", $clean_table, time());

  # Quote Identifiers
  my $safe_table    = $self->{DBH}->quote_identifier($clean_table);
  my $safe_newtable = $self->{DBH}->quote_identifier($clean_newtable);

  # Build Column Definitions and Column List for SELECT
  my @col_defs;
  my @col_names;

  foreach my $col (@{$sqlcoldefs->{collist}}) {
    # Get raw name from config
    my $raw_col_name = $sqlcoldefs->{coldata}->{$col}->{name};
    $raw_col_name =~ s/^"|"$//g;
    
    my $safe_col_name = $self->{DBH}->quote_identifier($raw_col_name);
    
    push(@col_names, $safe_col_name);
    push(@col_defs, sprintf("%s %s", 
      $safe_col_name, 
      $sqlcoldefs->{coldata}->{$col}->{sql}
    ));
  }
  
  my $cols_str = join(",", @col_names);
  my $defs_str = join(",", @col_defs);

  # Start Transaction
  # If anything fails inside the eval, nothing changes in the DB.
  eval {
    $self->{DBH}->begin_work;

    # Create New Table
    my $sql_create = "CREATE TABLE $safe_newtable ($defs_str)";
    $self->{DBH}->do($sql_create);
    print "\t   LLmonDB_sqlite: created temp table $safe_newtable\n";

    #  Copy Data
    my $sql_copy = "INSERT INTO $safe_newtable ($cols_str) SELECT $cols_str FROM $safe_table";
    $self->{DBH}->do($sql_copy);
    print "\t   LLmonDB_sqlite: copied data to $safe_newtable\n";

    # Drop Old Table
    my $sql_drop = "DROP TABLE $safe_table";
    $self->{DBH}->do($sql_drop);
    print "\t   LLmonDB_sqlite: dropped old table $safe_table\n";

    # Rename New Table to Original Name
    my $sql_rename = "ALTER TABLE $safe_newtable RENAME TO $safe_table";
    $self->{DBH}->do($sql_rename);
    print "\t   LLmonDB_sqlite: renamed $safe_newtable to $safe_table\n";

    # Commit Transaction
    $self->{DBH}->commit;
  };

  # Handle Errors
  if ($@) {
    # Something went wrong. Rollback everything.
    # The DB returns to exactly how it was before we started.
    eval { $self->{DBH}->rollback; };
    
    print STDERR "\n" . ("!" x 60) . "\n";
    print STDERR "  LLmonDB_sqlite: ERROR in recreate_table for $table\n";
    print STDERR "  Error details: $@\n";
    print STDERR "  ACTION: Transaction Rolled Back. No changes made.\n";
    print STDERR ("!" x 60) . "\n\n";
    
    return 0; # Return failure
  }

  return 1; # Return success
}


# add column to a table
sub add_column {
  my($self) = shift;
  my($table, $col, $sqldef) = @_;

  # Clean and Quote Table Name
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);

  # Clean and Quote Column Name
  my $clean_col = $col;
  $clean_col =~ s/^"|"$//g;
  my $safe_col = $self->{DBH}->quote_identifier($clean_col);

  # Build SQL 
  my $sql = "ALTER TABLE $safe_table ADD COLUMN $safe_col $sqldef";

  # Execute SQL command inside eval to catch crashes
  my $rc = eval { $self->{DBH}->do($sql); };
  my $err = $@ || $self->{DBH}->errstr;

  # Check the result
  if ($err || !defined($rc)) {
    # If the error is just that the column exists, we Log it but return 0 (not done)
    if ($err =~ /duplicate column name/i) {
       # We return 0 because it didn't "solve" a missing column
       return 0; 
    }
    
    # Otherwise, this is a real error (like syntax), die
    die "ADD COLUMN FAILED!\nSQL: $sql\nError: " . $err;
  } 
  
  # Only print this if it actually succeeded
  print "\t   LLmonDB_sqlite: add column $safe_col to table $safe_table for $self->{FNAME} ($sql)\n";

  $self->mycommit();
  
  # Return 1 to indicate success
  return 1;
}


# remove column from a table
sub remove_column {
  my($self) = shift;
  my($table,$col)=@_;

  my $sql = "ALTER TABLE $table DROP COLUMN $col;";

  # $self->{DBH}->do($sql);
  # $self->mycommit();

  print "\t   LLmonDB_sqlite: delete column $col from table $table for $self->{FNAME} ($sql)\n";
  print "\t   LLmonDB_sqlite: WARNING: delete column $col from table $table for $self->{FNAME} NOT SUPPORTED in sqlite3\n";
  
  return();
}


# remove a new table
sub remove_table {
  my($self) = shift;
  my($table) = @_;

  # Clean the table name (strip existing quotes)
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;

  # Quote safely using DBI
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);

  # Build SQL
  my $sql = "DROP TABLE $safe_table";

  # Execute SQL command inside eval to catch crashes
  my $rc = eval { $self->{DBH}->do($sql); };
  my $err = $@ || $self->{DBH}->errstr;

  # Check the result
  if ($err || !defined($rc)) {
    # There was an error, die
    die "DROP TABLE FAILED!\nSQL: $sql\nError: " . $err;
  } 
  
  # Only print this if it actually succeeded
  print "\t   LLmonDB_sqlite: removed table $safe_table for $self->{FNAME} ($sql)\n";

  $self->mycommit();
  
  return 1;
}


# create a new index table
sub create_index {
  my($self) = shift;
  my($table, $indextable, $colsref, $unique) = @_;

  # Clean and Quote Table Name
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);

  # Clean and Quote Index Name
  my $clean_index = $indextable;
  $clean_index =~ s/^"|"$//g;
  my $safe_indextable = $self->{DBH}->quote_identifier($clean_index);

  # Clean and Quote the List of Columns
  # Mapping over the array reference to fix every column individually.
  my @safe_cols = map {
      my $col = $_;
      $col =~ s/^"|"$//g;               # Strip existing quotes
      $self->{DBH}->quote_identifier($col); # Re-quote safely
  } @{$colsref};

  # Build SQL
  # Determine if we need UNIQUE INDEX or just INDEX
  my $type = $unique ? "UNIQUE INDEX" : "INDEX";
  
  my $sql = "CREATE $type $safe_indextable ON $safe_table (";
  $sql .= join(",", @safe_cols);
  $sql .= ")";

  # Execute inside an eval block to catch errors gracefully
  eval {
    $self->{DBH}->do($sql);
  };

  # Check for errors
  if ($@ || $self->{DBH}->err) {
    my $err_msg = $self->{DBH}->errstr;
    
    # Check if this is specifically a UNIQUE constraint error
    # SQLite typically returns: "UNIQUE constraint failed: ..."
    if ($unique && $err_msg =~ /UNIQUE constraint/i) {
      
      # Build the deduplication command dynamically
      # to suggest the user how to fix the error by deleting duplicated data on the table
      my $col_list = join(", ", @safe_cols);
      my $fix_sql = "DELETE FROM $safe_table WHERE rowid NOT IN (SELECT MIN(rowid) FROM $safe_table GROUP BY $col_list);";

      print STDERR "\n" . ("!" x 80) . "\n";
      print STDERR "  LLmonDB_sqlite: CRITICAL ERROR: Duplicate data detected while creating UNIQUE INDEX.\n";
      print STDERR "  LLmonDB_sqlite: The database contains duplicate rows for columns: $col_list\n";
      print STDERR "  LLmonDB_sqlite: To fix this, you must run the following SQL command to clean the data:\n";
      print STDERR "\n  $fix_sql\n\n";
      print STDERR "  LLmonDB_sqlite: After running this, try running checkDB again.\n";
      print STDERR ("!" x 80) . "\n\n";
    }

    # Pass the death up the chain
    die "CREATE INDEX FAILED!\nSQL: $sql\nError: " . $err_msg;
  }

  $self->mycommit();

  print "\t   LLmonDB_sqlite: created $type $safe_indextable for $self->{FNAME} ($sql)\n";
  
  return();
}

# remove a new index table
sub remove_index {
  my($self) = shift;
  my($indextable) = @_;

  # Clean the index name (strip existing quotes)
  my $clean_index = $indextable;
  $clean_index =~ s/^"|"$//g;

  # Quote safely using DBI
  my $safe_indextable = $self->{DBH}->quote_identifier($clean_index);

  # Build SQL
  my $sql = "DROP INDEX $safe_indextable";

  $self->{DBH}->do($sql)
    or die "DROP INDEX FAILED!\nSQL: $sql\nError: " . $self->{DBH}->errstr;

  $self->mycommit();

  print "\t   LLmonDB_sqlite: remove indextable $safe_indextable for $self->{FNAME} ($sql)\n";
  
  return();
}


sub close_db {
  my($self) = shift;
  
  return if($self->{DBINIT}==0);

  # disconnect from the database
  print "$self->{INSTNAME} disconnected from db $self->{FNAME} at ts=",time(),"\n" if($self->{VERBOSE}==2);
  $self->{DBH}->do("PRAGMA optimize");
  $self->{DBH}->disconnect() if $self->{DBH};
  $self->{DBINIT}=0;
  
  $self->LOGREPORT($self->{DBNAME},"close",caller(),"");
}



# return pointer to array of table names
sub query_tables {
  my($self) = shift;

  my ($values_ref,@data);
  
  my $sql = "SELECT name FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY 1";

  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
      # Add standard error logging
      my $db_error = $self->{DBH}->errstr;
      printf(STDERR "[query_tables] ERROR: %s\n", $db_error);
      return(undef);
  }

  my $rc=$sth->execute();
  $self->LOGREPORT($self->{DBNAME},"E:query_tables",caller(),$DBI::errstr) if(!defined($rc));

  while(@data = $sth->fetchrow_array()) {
    my $clean_name = $data[0];
    
    # Normalize the name by stripping potential quotes
    $clean_name =~ s/^"|"$//g;
    
    push(@{$values_ref}, $clean_name);
  }
  return($values_ref);
}

# return pointer to array of columns names
sub query_columns {
  my($self) = shift;
  my($table) = @_;
  my ($retval,@data, $coldef);
  
  # Clean the table name for the lookup. 
  # sqlite_master stores the name unquoted (usually), even if created with quotes.
  my $lookup_table = $table;
  $lookup_table =~ s/^"|"$//g;

  my $sql = "SELECT sql FROM sqlite_master WHERE type IN ('table','view') AND name = '$lookup_table'";

  my $sth = $self->{DBH}->prepare($sql);
  my $rc=$sth->execute();
  $self->LOGREPORT($self->{DBNAME},"E:query_columns",caller(),$DBI::errstr) if(!defined($rc));

  if(@data = $sth->fetchrow_array()) {
    if($data[0]=~/^[^\(]+\((.*)\)$/) {
      my $cols=$1;
      foreach $coldef (split(/\s*,\s*/,$cols) ) {
        if($coldef=~/^\s*([^\s]+)\s(.+)\s*$/) {
          my ($name,$sql)=($1,$2);
          
          # Strip quotes from the extracted column name.
          # If SQL is: "runtime-total" VARCHAR... -> $name becomes: runtime-total
          $name =~ s/^"|"$//g;

          push(@{$retval->{collist}},$name);
          $retval->{coldata}->{$name}->{name}=$name;
          $retval->{coldata}->{$name}->{sql}=$sql;
        }
      }
    }
  }
  return($retval);
}


# return pointer to array of table names
sub query_index_tables {
  my($self) = shift;

  my ($values_ref,@data);
  
  my $sql = "SELECT name FROM sqlite_master WHERE type IN ('index') AND name NOT LIKE 'sqlite_%' ORDER BY 1";

  my $sth = $self->{DBH}->prepare($sql);
  my $rc=$sth->execute();
  $self->LOGREPORT($self->{DBNAME},"E:query_index_tables",caller(),$DBI::errstr) if(!defined($rc));

  while(@data = $sth->fetchrow_array()) {
    push(@{$values_ref},$ data[0] );
  }
  return($values_ref);
}


# return pointer to array of columns names
sub query_index_columns {
  my($self) = shift;
  my($table) = @_;
  my ($retval,@data);
  
  my $sql = "SELECT sql FROM sqlite_master WHERE type IN ('index') AND name = '$table'";

  my $sth = $self->{DBH}->prepare($sql);
  my $rc=$sth->execute();
  $self->LOGREPORT($self->{DBNAME},"E:query_index_columns",caller(),$DBI::errstr) if(!defined($rc));

  if(@data = $sth->fetchrow_array()) {
    if($data[0]=~/\(([^\)]*)\)/) {
      my $cols=$1;
      foreach my $col (split(/\s*,\s*/,$cols) ) {
        push(@{$retval->{collist}},$col);
      }
    }
  }
  return($retval);
}


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


# end insert sequence
sub end_insert_sequence {
  my($self) = shift;
  my($sth) = @_;

  $sth->finish();
  $self->{DBH}->commit();
  # $self->mycommit();
  print "\t   LLmonDB_sqlite: end_insert_sequence\n" if($debug>=3);
  return();
}


# remove table contents
sub remove_contents {
  my($self) = shift;
  my($table) = @_;

  # Clean and Quote Table Name
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);

  my $sql = "DELETE FROM $safe_table";
  
  my $rc = $self->{DBH}->do($sql);
  
  printf("\t   LLmonDB_sqlite: removed (sql: %s...)\n", substr($sql,0,16)) if($debug>=3);
  $self->mycommit();
  
  return($rc);
}


# execute SQL-commands
sub execute_sql {
  my($self) = shift;
  my($sqllist) = @_;
  my $rc_all=0;
  foreach my $sql (split(/\s*;\s*/,$sqllist)) {
    # printf("\t   LLmonDB_sqlite: executed (sql: %s)\n",$sql);
    my $rc=$self->{DBH}->do($sql);
    $self->LOGREPORT($self->{DBNAME},"E:execute_sql",caller(),$DBI::errstr) if(!defined($rc));
    printf(STDERR "[execute_sql] \t   LLmonDB_sqlite: executed sql: %s \n",$sql) if(!defined($rc));
    $rc_all+=$rc  if(defined($rc));
  }
  $self->mycommit();
  
  return($rc_all);
}


# return pointer to result of query
sub query {
  my($self) = shift;
  my($table,$optsref) = @_;
  my ($retval);

  # print Dumper($optsref);
  my $type="aref_of_aref";
  $type=$optsref->{type} if(exists($optsref->{type}));

  $type="hash_values" if ($type eq "hash_single_value"); # old name
  if($type eq "hash_values") {
    $retval=$self->query_hash_values_table($table,
                              $optsref->{hash_keys},
                              $optsref->{hash_value},
                              $optsref->{where},
                              $optsref->{sql}
                            );
  } elsif($type eq "get_arrayref_of_arrayref") {
    $retval=$self->query_arrayref_of_arrayref_table($table,
                                        $optsref->{where},
                                        $optsref->{sql}
                                      );
  } elsif($type eq "get_arrayref_of_hashref") {
    $retval=$self->query_arrayref_of_hashref_table($table,
                                      $optsref->{where},
                                      $optsref->{sql}
                                    );
  } elsif($type eq "get_min") {
    $retval=$self->query_get_min($table,
                        $optsref->{hash_key},
                        $optsref->{where},
                      );
  } elsif($type eq "get_max") {
    $retval=$self->query_get_max($table,
                        $optsref->{hash_key},
                        $optsref->{where},
                      );
  } elsif($type eq "get_count") {
    $retval=$self->query_get_count($table,
                        $optsref->{where},
                        );
  } elsif($type eq "get_execute") {
    $retval=$self->query_get_execute($table,
                          $optsref->{columns},
                          $optsref->{where},
                          $optsref->{sql},
                          $optsref->{attach},
                          $optsref->{execute},
                          "array"
                        );

  } elsif($type eq "get_execute_hash") {
    $retval=$self->query_get_execute($table,
                        $optsref->{columns},
                        $optsref->{where},
                        $optsref->{sql},
                        $optsref->{attach},
                        $optsref->{execute},
                        "hash"
                      );

  } else {
    print STDERR "[query] \t   LLmonDB_sqlite: ERROR in query, unknown type $type\n";
  }
  return($retval);
}

sub query_hash_values_table {
  my($self) = shift;
  my($table,$nkeys,$nvalue,$where,$qsql) = @_;
  my ($retval,$keylist);

  if(ref(\$nkeys) eq "SCALAR") {
    $keylist=$nkeys;
  } else {
    $keylist=join(",",@{$nkeys});
  } 
  # print "query_hash_values_table: $nkeys (".ref(\$nkeys).") -> $keylist\n";
  my $sql;
  if(!defined($qsql)) {
    if(!defined($table)) {
      printf(STDERR "[query_hash_values_table] \t LLmonDB_sqlite: ERROR - 'table' argument is undefined.\n");
      printf(STDERR "  Database: %s\n", $self->{DBNAME});
      printf(STDERR "  Caller: %s line %s\n", caller());
      return(undef);
    }
    $sql = "SELECT $keylist,$nvalue FROM $table";
    $sql.=" WHERE $where" if($where);
  } else {
    $sql=$qsql;
  }
  
  my $sth = $self->{DBH}->prepare($sql);
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_hash_values_table] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table (if provided): %s\n", defined($table) ? $table : 'N/A');
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  
  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_hash_values_table] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  $retval = $sth->fetchall_hashref($nkeys);

  print "\t   LLmonDB_sqlite: query_hash_single_table $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}


sub query_arrayref_of_arrayref_table {
  my($self) = shift;
  my($table,$where,$qsql) = @_;
  my ($retval);

  my $sql;
  if(!defined($qsql)) {
    # Quote table name safely
    my $safe_table = $self->{DBH}->quote_identifier($table);
    $sql = "SELECT * FROM $safe_table";
    $sql.=" WHERE $where" if($where);
  } else {
    $sql=$qsql;
    # print "query_hash_values_table: sql=$sql\n";
  }
  
  # print "query_arrays_table: $sql\n";
  
  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_arrayref_of_arrayref_table] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table: %s\n", defined($table) ? $table : 'N/A');
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  
  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_arrayref_of_arrayref_table] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  $retval = $sth->fetchall_arrayref();

  print "\t   LLmonDB_sqlite: query_arrays_table $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}

sub query_arrayref_of_hashref_table {
  my($self) = shift;
  my($table,$where,$qsql) = @_;
  my ($retval);

  my $sql;
  if(!defined($qsql)) {
    # Quote table name safely
    my $safe_table = $self->{DBH}->quote_identifier($table);
    $sql = "SELECT * FROM $safe_table";
    $sql.=" WHERE $where" if($where);
  } else {
    $sql=$qsql;
    # print "query_hash_values_table: sql=$sql\n";
  }
  
  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_arrayref_of_hashref_table] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table: %s\n", defined($table) ? $table : 'N/A');
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  
  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_arrayref_of_hashref_table] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  $retval = $sth->fetchall_arrayref({});

  print "\t   LLmonDB_sqlite: query_arrays_table $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}

sub query_get_min {
  my($self) = shift;
  my($table,$key,$where) = @_;
  my ($retval);
    
  # Quote both table AND column (key) identifiers safely
  my $safe_table = $self->{DBH}->quote_identifier($table);
  my $safe_key   = $self->{DBH}->quote_identifier($key);

  my $sql = "SELECT min($safe_key) FROM $safe_table";
  $sql.=" WHERE $where" if($where);
  
  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_min] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table: %s\n", $table);
    printf(STDERR "  Column: %s\n", $key);
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  
  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_min] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  if (my @data = $sth->fetchrow_array()) {
    $retval=$data[0];
  } else {
    $retval=-1;
  }
  
  print "\t   LLmonDB_sqlite: query_get_min $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}

sub query_get_max {
  my($self) = shift;
  my($table,$key,$where) = @_;
  my ($retval);
    
  # Quote both table AND column (key) identifiers safely
  my $safe_table = $self->{DBH}->quote_identifier($table);
  my $safe_key   = $self->{DBH}->quote_identifier($key);

  my $sql = "SELECT max($safe_key) FROM $safe_table";
  $sql.=" WHERE $where" if($where);
  
  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_max] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table: %s\n", $table);
    printf(STDERR "  Column: %s\n", $key);
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  
  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_max] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  if (my @data = $sth->fetchrow_array()) {
    $retval=$data[0];
  } else {
    $retval=-1;
  }
  
  print "\t   LLmonDB_sqlite: query_get_max $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}

sub query_get_count {
  my($self) = shift;
  my($table,$where) = @_;
  my ($retval);
    
  my $safe_table = $self->{DBH}->quote_identifier($table);

  my $sql = "SELECT count(*) FROM $safe_table";
  $sql.=" WHERE $where" if($where);
  
  my $sth = $self->{DBH}->prepare($sql);
  
  if(!$sth) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_count] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Table: %s\n", $table);
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }

  if (!$sth->execute()) {
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_count] \t LLmonDB_sqlite: ERROR - Cannot execute SQL statement.\n");
    printf(STDERR "  Database: %s\n", $self->{DBNAME});
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    $self->LOGREPORT($self->{DBNAME},"E:query_get_count",caller(),$DBI::errstr);
    return(undef);
  }

  if (my @data = $sth->fetchrow_array()) {
    $retval=$data[0];
  } else {
    $retval=-1;
  }
  
  print "\t   LLmonDB_sqlite: query_get_count $sql\n" if($debug>=3);
  # print Dumper($retval);
  return($retval);
}


sub query_get_execute {
  my($self) = shift;
  my($table,$columns,$where,$qsql,$attach,$funcref,$qtype) = @_;
  my ($retval,@data,$hashref,$sql);

  if(!defined($qsql)) {
    $sql = sprintf ("SELECT %s FROM %s",join(",",@{$columns}),$table);
    $sql.=" WHERE $where" if($where);
  } else {
    $sql=$qsql;
  }

  if(defined($attach)) {
    # END TRANSACTION;
    
    my $endtransaction="";
    $endtransaction="END TRANSACTION;" if(!$self->{AUTOCOMMIT});
    
    my $attsql=sprintf("${endtransaction}ATTACH DATABASE '%s/LLmonDB_%s.sqlite' as %s",
                        $self->{DBDIR}, $attach, $attach);
    my $arc=$self->{DBH}->do($attsql);
    print "\t   LLmonDB_sqlite: query_get_execute do $attsql rc=$arc\n" if($debug>=3);
    $self->LOGREPORT($self->{DBNAME},"E:query_get_execute: attach to $attach",caller(),$DBI::errstr) if(!defined($arc));
    $self->LOGREPORT($attach,"E:query_get_execute: attach from $self->{DBNAME}",caller(),$DBI::errstr) if(!defined($arc));
    # $self->get_database_structure();
  }
  
  my $sth = $self->{DBH}->prepare($sql);
  if(!$sth) {
    # Get the detailed error message from the database handle
    my $db_error = $self->{DBH}->errstr;
    printf(STDERR "[query_get_execute] \t LLmonDB_sqlite: ERROR - Cannot prepare SQL statement.\n");
    printf(STDERR "  Main Database: %s \n", $self->{DBNAME});
    printf(STDERR "  Attached Database: %s \n", defined($attach) ? $attach : 'None');
    printf(STDERR "  Table (if provided): %s\n", defined($table) ? $table : 'N/A');
    printf(STDERR "  Database Error: %s\n", $db_error);
    printf(STDERR "  Full SQL Dump:\n---\n%s\n---\n", $sql);
    return(undef);
  }
  my $rc=$sth->execute();
  print "\t   LLmonDB_sqlite: query_get_execute execute rc=$rc\n" if($debug>=3);
  $self->LOGREPORT($self->{DBNAME},"E:query_get_execute",caller(),$DBI::errstr) if(!defined($rc));
  my $c=0;
  if($qtype eq "array") {
    while (@data = $sth->fetchrow_array()) {
      &$funcref(@data); $c++;
    }
  } elsif($qtype eq "hash") { 
    while ($hashref = $sth->fetchrow_hashref()) {
      &$funcref($hashref); $c++;
    }
  } else {
    print STDERR "[query_get_execute] \t   LLmonDB_sqlite: ERROR in query_get_execute, unknown qtype $qtype\n";
  }
  $retval=$c;

  if(defined($attach)) {
    my $endtransaction="";
    $endtransaction="END TRANSACTION;" if(!$self->{AUTOCOMMIT});
    my $attsql=sprintf("${endtransaction}DETACH DATABASE %s", $attach);
    my $drc=$self->{DBH}->do($attsql);
    $self->LOGREPORT($self->{DBNAME},"E:query_get_execute: dettach to $attach",caller(),$DBI::errstr) if(!defined($drc));
    $self->LOGREPORT($attach,"E:query_get_execute: dettach from $self->{DBNAME}",caller(),$DBI::errstr) if(!defined($drc));
  }

  print "\t   LLmonDB_sqlite: query_get_execute $sql ($c entries)\n" if($debug>=3);
  return($retval);
}


sub get_database_structure {
  my($self) = shift;

  # Return the structure of the table execution_host
  my $sth = $self->{DBH}->prepare('pragma database_list');
  my $rc=$sth->execute();
  $self->LOGREPORT($self->{DBNAME},"E:get_database_structure",caller(),$DBI::errstr) if(!defined($rc));
  my @struct;
  while (my $row = $sth->fetchrow_arrayref()) {
    push @struct, @$row[1];
  }
  print "get_database_structure:",Dumper(\@struct);

  return @struct;
}

# return pointer to result of query
sub delete {
  my($self) = shift;
  my($table,$optsref) = @_;
  my ($retval);

  my $type="all_rows";
  $type=$optsref->{type} if(exists($optsref->{type}));

  if($type eq "all_rows") {
    $retval=$self->delete_all_rows($table);
  } elsif($type eq "some_rows") {
    $retval=$self->delete_some_rows($table,
                          $optsref->{where}
                        );
  } else {
    print STDERR "[delete] \t   LLmonDB_sqlite: ERROR in delete, unknown type $type\n";
  }
  $self->LOGREPORT($self->{DBNAME},"E:delete",caller(),$DBI::errstr) if(!defined($retval));
  return($retval);
}

sub delete_all_rows {
  my($self) = shift;
  my($table) = @_;
  my ($retval);
  
  # Clean and Quote Table Name
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);

  my $sql = "DELETE FROM $safe_table";
  
  my $rc = $self->{DBH}->do($sql);
  
  # Error logging
  $self->LOGREPORT($self->{DBNAME},"E:delete_all_rows",caller(),$DBI::errstr) if(!defined($rc));
  
  $self->mycommit();
  $retval = $rc;
  
  print "\t   LLmonDB_sqlite: delete_all_entries $sql ($rc entries)\n" if($debug>=3);
  return($retval);
}

sub delete_some_rows {
  my($self) = shift;
  my($table, $where) = @_;
  my ($retval);
  
  # Clean and Quote Table Name
  my $clean_table = $table;
  $clean_table =~ s/^"|"$//g;
  my $safe_table = $self->{DBH}->quote_identifier($clean_table);
  
  # Build SQL
  my $sql = "DELETE FROM $safe_table";
  $sql .= " WHERE $where" if($where);
  
  my $rc = $self->{DBH}->do($sql);
  
  # Error logging
  $self->LOGREPORT($self->{DBNAME},"E:delete_some_rows",caller(),$DBI::errstr) if(!defined($rc));
  
  if(!defined($rc)) {
    print STDERR "[delete_some_rows] \t   LLmonDB_sqlite: ERROR in delete_some_rows, sql=$sql\n";
  }
  
  $self->mycommit();
  $retval = $rc;
  
  print "\t   LLmonDB_sqlite: delete_some_entries $sql ($rc entries)\n" if($debug>=3);
  return($retval);
}

1;
