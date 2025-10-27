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
    if($tables_in_DB_ref) {
      %tables_in_db = map { $_ => 1 } @{$tables_in_DB_ref};
    }
    # print "tables_in_db:",Dumper(\%tables_in_db);
    
    # check tables from config
    foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
      my $tableref=$t->{table};
      $table=$tableref->{name};

      my $do_recreate_table=0;
      
      printf("  LLmonDB:  -> check $db table $table\n") if($debug>=3);
      my $configcoldefs=$self->{CONFIG}->get_columns_defs($db,$table);

      if(exists($tables_in_db{$table})) {

        # check columns
        my $dbcoldefs=$dbobj->query_columns($table);
        # print "columns in Config table $table: @{$configcoldefs->{collist}}\n";
        # print "columns in DB     table $table: @{$dbcoldefs->{collist}}\n";

        # first, check cols from config file (only existence, order of cols need be changed in SQL)
        foreach my $col (@{$configcoldefs->{collist}}) {
          if(exists($dbcoldefs->{coldata}->{$col})) {
            if($configcoldefs->{coldata}->{$col}->{sql} ne $dbcoldefs->{coldata}->{$col}->{sql}) {
              $found++;
              printf("  LLmonDB:     CHECK: table column $col changed ('$dbcoldefs->{coldata}->{$col}->{sql}' to '$configcoldefs->{coldata}->{$col}->{sql}')]\n");
              printf("  LLmonDB:     [DRY: alter table column $col ]\n");
              if(!$dryrun) {
                $do_recreate_table=1;
              } else {
                printf("  LLmonDB:     [DRY: modify column $col of table $table ]\n");
              }
            } 
          } else {
            $found++;
            printf("  LLmonDB:     CHECK: table column $col missing in DB ('$configcoldefs->{coldata}->{$col}->{sql}')\n");
            if(!$dryrun) {
              $dbobj->add_column($table,$col,$configcoldefs->{coldata}->{$col}->{sql});
              $done++;
            } else {
              printf("  LLmonDB:     [DRY: add column $col to table $table ]\n");
            }
          }
        }

        # second, check cols from db file
        foreach my $col (@{$dbcoldefs->{collist}}) {
          if(!exists($configcoldefs->{coldata}->{$col})) {
            $found++;$dataloss++;
            printf("  LLmonDB:     CHECK: table column $col only in DB ('$dbcoldefs->{coldata}->{$col}->{sql}'), column will be removed\n");
            printf("  LLmonDB:     CHECK: WARNING [data loss], remove column will destroy data in this column !!!\n");
            if(!$dryrun) {
              $do_recreate_table=1;
              $done++;
              # $dbobj->remove_column($table,$col,$configcoldefs->{coldata}->{$col}->{sql});
            } else {
              printf("  LLmonDB:     [DRY: remove column $col to table $table ]\n");
            }
          }
        }

        if($do_recreate_table) {
          printf("  LLmonDB:     CHECK: re-create table $table in DB due to modification of columns, data of existing columns will be copied\n");
          if(!$dryrun) {
            $dbobj->recreate_table($table,$configcoldefs);
          } else {
            $found++;
            printf("  LLmonDB:     [DRY: re-create database table ($db,$table)]\n");
          }
        }
      } else {
        # create table
        printf("  LLmonDB:     CHECK: table $table missing in DB\n");
        if(!$dryrun) {
          $dbobj->create_table($table,$configcoldefs);
        } else {
          $found++;
          printf("  LLmonDB:     [DRY: create database table ($db,$table)]\n");
        }
      }
    }
    
    # check tables from db
    foreach $table (@{$tables_in_DB_ref}) {
      my $tab_exists=0;
      foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
        if($t->{table}->{name} eq $table) {
          $tab_exists=1; last;
        }
      }
      if(!$tab_exists) {
        printf("  LLmonDB:     CHECK: table $table in DB not in config file, remove table from data base\n");
        printf("  LLmonDB:     CHECK: WARNING [data loss], remove table will destroy data in this table !!!\n");
        $found++;$dataloss++;
        if(!$dryrun) {
          $dbobj->remove_table($table);
          $done++;
        } else {
          $found++;
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

      # check index from config
      my $indexdefs=$self->{CONFIG}->get_index_columns($db,$table);
      my $icount=0;
      foreach my $indexcoldefs (@{$indexdefs}) {
	  if($#{$indexcoldefs}>=0) {
	      $icount++;
	      $indextable=sprintf("%s_idx",$table) if($icount==1);
	      $indextable=sprintf("%s_%d_idx",$table,$icount) if($icount>1);
	      $indextables_in_config{$indextable}=1;
	      
	      # print "TMPDEB: $db,$table,$indextable\n" if($db eq "gpustate");
	      printf("  LLmonDB:  -> check $db indextable $indextable\n") if($debug>=3);
	      
	      # check if index table exists
	      if(exists($index_in_db{$indextable})) {
		  # check index columns
		  my $dbcoldefs=$dbobj->query_index_columns($indextable);
		  my $diff=0;
		  if($#{$indexcoldefs}!=$#{$dbcoldefs->{collist}}) {
		      $diff=1;
		  } else {
		      for(my $c=0;$c<=$#{$indexcoldefs};$c++) {
			  if($indexcoldefs->[$c] ne $dbcoldefs->{collist}->[$c]) {
			      $diff=1;
			  }
		      }
		  }
		  
		  if($diff) {
		      printf("  LLmonDB:     CHECK: indextable for table $table hast different columns  (DB:@{$indexcoldefs}) != (Config:@{$dbcoldefs->{collist}}), recreate index table\n");
		      if(!$dryrun) {
			  $dbobj->remove_index($indextable);
			  $dbobj->create_index($table,$indextable,$indexcoldefs);
		      } else {
			  $found++;
			  printf("  LLmonDB:     [DRY: re-create database index ($db,$indextable)]\n");
		      }
		  }
		  
	      } else {
		  printf("  LLmonDB:     CHECK: indextable for table $table does not exists in DB, create indextable\n");
		  if(!$dryrun) {
		      $dbobj->create_index($table,$indextable,$indexcoldefs);
		  } else {
		      $found++;
		      printf("  LLmonDB:     [DRY: create database index ($db,$indextable)]\n");
		  }
	      }
	  }
      }
    }
    
    # check tables index from db
    foreach $indextable (@{$index_in_DB_ref}) {
      if(!exists($indextables_in_config{$indextable})) {
        printf("  LLmonDB:     CHECK: indextable $indextable in DB not in config file, remove indextable from data base\n");
        if(!$dryrun) {
          $dbobj->remove_index($indextable);
        } else {
          $found++;
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
