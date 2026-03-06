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
my $debug=3;

use strict;
use warnings::unused;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use FindBin;
use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub checkDB {
  my($self) = shift;
  my($dryrun)=@_;
  my($db,$found,$done,$dataloss);
  
  printf("  LLmonDB: start check %s\n",($dryrun?"[dryrun]":"")) if($debug>=3);
  my $dbdir=$self->{CONFIGDATA}->{paths}->{dbdir};
  $found=$done=$dataloss=0;
  
  foreach $db (sort(keys(%{$self->{CONFIGDATA}->{databases}}))) {
    printf("  LLmonDB:  -> check $db\n") if($debug>=3);
    my $dbobj=LLmonDB_sqlite->new($dbdir,$db,$self->{VERBOSE});

    # first check: exist DB
    if($dbobj->check_db_file()) {
      printf("  LLmonDB:   - db file exists\n") if($debug>=3);
    } else {
      $found++;
      printf("  LLmonDB:   CHECK: database $db missing\n");
      printf("  LLmonDB:   - db file does not exist\n");
      if(!$dryrun) {
        &check_folder($dbdir.'/');
        $dbobj->init_db();
        $dbobj->close_db();
        $done++;
      } else {
        printf("  LLmonDB:     [DRY: create database ($db, file)]\n");
      }
    }

    # second check: tables
    $dbobj->init_db();

    my (%tables_in_db,$table);

    # get tables in DB
    my $tables_in_DB_ref = $dbobj->query_tables();
    
    # Helper map for case-insensitive lookup
    my %tables_in_db_lc; 

    if($tables_in_DB_ref) {
      # Build standard map (including the safe quoting fix we discussed)
      %tables_in_db = map { 
        my $t = $_; $t =~ s/^"|"$//g; 
        $t => 1 
      } @{$tables_in_DB_ref};

      # Build lowercase map for robust matching
      foreach my $t (@{$tables_in_DB_ref}) {
        my $clean_t = $t; 
        $clean_t =~ s/^"|"$//g;
        $tables_in_db_lc{lc($clean_t)} = $clean_t;
      }
    }
    
    # check tables from config
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      
      # Clean table name for consistent lookup (strip quotes)
      my $clean_table = $table;
      $clean_table =~ s/^"|"$//g;

      my $do_recreate_table=0;
      my $table_diffs = 0; # Counter for differences found in this table
      
      printf("  LLmonDB:  -> check $db table $table\n") if($debug>=3);
      my $configcoldefs=$self->{CONFIG}->get_columns_defs($db,$table);

      # Check existence using lowercase map to find mismatches like "table" vs "TABLE"
      my $db_table_match = $tables_in_db_lc{lc($clean_table)};

      if(defined($db_table_match) || exists($tables_in_db{$clean_table}) || exists($tables_in_db{$table})) {
        
        # Use the name actually found in the DB (e.g. "table")
        my $real_db_table_name = $db_table_match || $clean_table;

        # Check if the casing is different
        if($real_db_table_name ne $clean_table) {
          $found++;
          $table_diffs++; # Track this difference
          printf("  LLmonDB:     CHECK: table name casing changed ('$real_db_table_name' to '$clean_table')\n");
          
          if(!$dryrun) {
            $do_recreate_table=1;
          } else {
            printf("  LLmonDB:     [DRY: rename/recreate table $clean_table ]\n");
          }
        }

        # Query columns using the REAL name so the DB driver finds it
        my $dbcoldefs=$dbobj->query_columns($real_db_table_name);
        
        # Create a normalized lookup for config columns
        my %clean_config_lookup;
        foreach my $k (keys %{$configcoldefs->{coldata}}) {
          my $ck = $k; 
          $ck =~ s/^"|"$//g;
          $clean_config_lookup{$ck} = $k;
        }

        # first, check cols from config file
        foreach my $col (@{$configcoldefs->{collist}}) {
          my $clean_col = $col;
          $clean_col =~ s/^"|"$//g;
          
          if(exists($dbcoldefs->{coldata}->{$clean_col})) {
            if($configcoldefs->{coldata}->{$col}->{sql} ne $dbcoldefs->{coldata}->{$clean_col}->{sql}) {
              $found++;
              $table_diffs++; # Track specific difference for this table
              printf("  LLmonDB:     CHECK: table column $col changed ('$dbcoldefs->{coldata}->{$clean_col}->{sql}' to '$configcoldefs->{coldata}->{$col}->{sql}')]\n");
              printf("  LLmonDB:     [DRY: alter table column $col ]\n");
              if(!$dryrun) {
                $do_recreate_table=1;
              } else {
                printf("  LLmonDB:     [DRY: modify column $col of table $table ]\n");
              }
            } 
          } else {
            $found++;
            $table_diffs++;
            printf("  LLmonDB:     CHECK: table column $col missing in DB ('$configcoldefs->{coldata}->{$col}->{sql}')\n");
            if(!$dryrun) {
              # Capture the return value (1 = success, 0 = failure/skipped)
              my $success = $dbobj->add_column($table,$col,$configcoldefs->{coldata}->{$col}->{sql});
              # Only increment done if we actually did something
              if ($success) {
                $done++;
                $table_diffs--; # Decrement because we just fixed it immediately (don't count in recreate)
              }
            } else {
              printf("  LLmonDB:     [DRY: add column $col to table $table ]\n");
            }
          }
        }

        # second, check cols from db file
        foreach my $col (@{$dbcoldefs->{collist}}) {
          if(!exists($clean_config_lookup{$col})) {
            $found++;$dataloss++;
            $table_diffs++;
            printf("  LLmonDB:     CHECK: table column $col only in DB ('$dbcoldefs->{coldata}->{$col}->{sql}'), column will be removed\n");
            printf("  LLmonDB:     CHECK: WARNING [data loss], remove column will destroy data in this column !!!\n");
            if(!$dryrun) {
              $do_recreate_table=1;
            } else {
              printf("  LLmonDB:     [DRY: remove column $col to table $table ]\n");
            }
          }
        }

        if($do_recreate_table) {
          printf("  LLmonDB:     CHECK: re-create table $table in DB due to modification of columns, data of existing columns will be copied\n");
          if(!$dryrun) {
            # Capture the return value (1 = success, 0 = failure/skipped)
            my $success = $dbobj->recreate_table($clean_table,$configcoldefs);
            
            # Only increment done if we actually did something
            if ($success) {
              $done += $table_diffs; # Adding all pending differences for this table
            }
          } else {
            $found++;
            printf("  LLmonDB:     [DRY: re-create database table ($db,$table)]\n");
          }
        }
      } else {
        # create table
        $found++; 
        printf("  LLmonDB:     CHECK: table $table missing in DB\n");
        if(!$dryrun) {
          # Capture the return value (1 = success, 0 = failure/skipped)
          my $success = $dbobj->create_table($table,$configcoldefs);
          
          # Only increment done if we actually did something
          if ($success) {
            $done++;
          }
        } else {
          printf("  LLmonDB:     [DRY: create database table ($db,$table)]\n");
        }
      }
    }
    
    # check tables from db
    foreach $table (@{$tables_in_DB_ref}) {
      my $tab_exists=0;
      foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
        my $cfg_table = $t->{table}->{name};
        $cfg_table =~ s/^"|"$//g;
        if($cfg_table eq $table) {
          $tab_exists=1; last;
        }
      }
      if(!$tab_exists) {
        printf("  LLmonDB:     CHECK: table $table in DB not in config file, remove table from data base\n");
        printf("  LLmonDB:     CHECK: WARNING [data loss], remove table will destroy data in this table !!!\n");
        $found++;$dataloss++;
        if(!$dryrun) {
          # Capture the return value (1 = success, 0 = failure/skipped)
          my $success = $dbobj->remove_table($table);
          
          # Only increment done if we actually did something
          if ($success) {
            $done++;
          }
        } else {
          printf("  LLmonDB:     [DRY: remove database table ($db,$table)]\n");
        }
      }
    }

    # get tables index from db
    my (%index_in_db,%indextables_in_config,$indextable);
    my $index_in_DB_ref = $dbobj->query_index_tables();
    if($index_in_DB_ref) {
      %index_in_db = map { $_ => 1 } @{$index_in_DB_ref};
    }

    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};
      my $clean_table = $table;
      $clean_table =~ s/^"|"$//g;

      my $indexdefs=$self->{CONFIG}->get_index_columns($db,$table);
      my $icount=0;
      
      # Loop over the structure of indexdefs (list of hashrefs including index and unique flag)
      foreach my $indexdef (@{$indexdefs}) {
        # Extract columns and unique flag
        my $indexcoldefs = $indexdef->{cols};
        my $is_unique    = $indexdef->{unique};

        if($#{$indexcoldefs}>=0) {
          $icount++;
          
          # Naming convention: _idx for standard, _uidx for unique
          # This change ensures we automatically clean up old standard indexes
          # if we switch to unique in the config.
          my $suffix = $is_unique ? "uidx" : "idx";

          $indextable=sprintf("%s_%s",$clean_table,$suffix) if($icount==1);
          $indextable=sprintf("%s_%d_%s",$clean_table,$icount,$suffix) if($icount>1);
          $indextables_in_config{$indextable}=1;

          printf("  LLmonDB:  -> check $db indextable $indextable\n") if($debug>=3);

          if(exists($index_in_db{$indextable})) {
            my $dbcoldefs=$dbobj->query_index_columns($indextable);
            my $diff=0;
            if($#{$indexcoldefs}!=$#{$dbcoldefs->{collist}}) {
              $diff=1;
            } else {
              for(my $c=0;$c<=$#{$indexcoldefs};$c++) {
                # Get and clean config column
                my $clean_idx_col = $indexcoldefs->[$c];
                $clean_idx_col =~ s/^"|"$//g; # Remove surrounding quotes
                
                # Get and clean DB column
                my $clean_db_col = $dbcoldefs->{collist}->[$c];
                $clean_db_col =~ s/^"|"$//g;  # Remove surrounding quotes

                # Compare cleaned versions
                if($clean_idx_col ne $clean_db_col) {
                  $diff=1;
                }
              }
            }

            if($diff) {
              $found++; 
              printf("  LLmonDB:     CHECK: indextable for table $table has different columns  (DB:@{$dbcoldefs->{collist}}) != (Config:@{$indexcoldefs}), recreate index table\n");
              if(!$dryrun) {
                $dbobj->remove_index($indextable);
                # Pass unique flag to create_index
                $dbobj->create_index($table,$indextable,$indexcoldefs,$is_unique);
                $done++;
              } else {
                printf("  LLmonDB:     [DRY: re-create database index ($db,$indextable)]\n");
              }
            }
          } else {
            $found++; 
            printf("  LLmonDB:     CHECK: indextable for table $table does not exists in DB, create indextable\n");
            if(!$dryrun) {
              # Pass unique flag to create_index
              $dbobj->create_index($table,$indextable,$indexcoldefs,$is_unique);
              $done++;
            } else {
              printf("  LLmonDB:     [DRY: create database index ($db,$indextable)]\n");
            }
          }
        }
      }
    }
    
    foreach $indextable (@{$index_in_DB_ref}) {
      if(!exists($indextables_in_config{$indextable})) {
        printf("  LLmonDB:     CHECK: indextable $indextable in DB not in config file, remove indextable from data base\n");
        $found++; 
        if(!$dryrun) {
          $dbobj->remove_index($indextable);
          $done++;
        } else {
          printf("  LLmonDB:     [DRY: remove database index ($db,$indextable)]\n");
        }
      }
    }
  }
  
  printf("\t %s\n","-"x60);
  if($found>0) {
    printf("  LLmonDB: RESULTS, %d difference(s) found\n",$found);
    if(!$dryrun) {
      printf("  LLmonDB: RESULTS, %d difference(s) solved\n",$done);
      if($found>$done) {
        printf("  LLmonDB: RESULTS, %d difference(s) were not solved, please check logs\n",$done-$found);
      }
    } else {
      printf("  LLmonDB: RESULTS, please use option --force to solve difference(s)\n");
      printf("  LLmonDB: RESULTS, WARNING, be careful, some operation may destroy data in DB !!!\n") if($dataloss>0);
    }
  } else {
    printf("  LLmonDB: RESULTS, no difference(s) found\n");
  }

  printf("\t %s\n","-"x60);
  printf("  LLmonDB: end check\n") if($debug>=3);
}

1;