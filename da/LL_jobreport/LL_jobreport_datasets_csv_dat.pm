# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 
#    Nabil Abubaker (Forschungszentrum Juelich GmbH)

package LML_jobreport;

my $VERSION='$Revision: 1.00 $';
my($debug)=0;
my($check)=1;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub process_data_query_and_save_csv_dat {
  my $self = shift;
  my($dataset,$filepath_parsed)=@_;

  my $starttime=time();
  my $col=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{filemap_col};
  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};
  my $sql_debug=0;
  if(exists($dataset->{sqldebug})) {
    $sql_debug=1 if($dataset->{sqldebug}=~/yes/i);
  }
  my $where="";
  if(exists($dataset->{sql_where})) {
    $where.=$self->{DB}->replace_tsvars($dataset->{sql_where},$self->{CURRENTTS});
  }

  if(!exists($self->{TABLES}->{$dataset->{data_database}})) {
    printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database});
    return;
  }
  # if(!exists($self->{TABLES}->{$dataset->{data_database}}->{$dataset->{data_table}})) {
  #   printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database},$dataset->{data_table});
  #   return;
  # }

  # check data tables
  my $from;
  my $joincol="";
  my $joincol_sql="";   # Prepare Quoted Identifiers for Join Column
  my @datatables=split(/\s*,\s*/,$dataset->{data_table});
  if($#datatables>0) {
    my @fromlist; my $c=0;
    if(!exists($dataset->{data_table_join_col})) {
      print STDERR "LLmonDB:    ERROR, attribute data_table_join_col missing for dataset $dataset->{name}\n";
      return();
    } else {
      $joincol=$dataset->{data_table_join_col};
      # Create quoted version for SQL
      $joincol_sql = $joincol; 
      $joincol_sql =~ s/^"|"$//g; 
      $joincol_sql = qq("$joincol_sql");
    }
    foreach my $d (@datatables) {
      $c++;
      # Quote table names in FROM list
      my $d_sql = $d; 
      $d_sql =~ s/^"|"$//g; 
      $d_sql = qq("$d_sql");
      
      push(@fromlist,sprintf("%s D%d", $d_sql, $c));
      if($c>1) {
        $where.=" AND " if($where);
        # Use quoted join column
        $where.=sprintf("D1.%s=D%d.%s", $joincol_sql, $c, $joincol_sql);
      }
    }
    $from = join(",",@fromlist);
  } else {
    # Quote single table name
    my $d_sql = $dataset->{data_table};
    $d_sql =~ s/^"|"$//g; 
    $d_sql = qq("$d_sql");
    $from = sprintf("%s D%d", $d_sql, 1);
  }

  if(exists($dataset->{time_aggr})) {
    if($dataset->{time_aggr} eq "span" ) {
      $where.=$self->process_data_query_time_aggr_get_where($dataset);
    }
  }

  # pre-process column_convert
  my $col_convert_by_col=$self->{LL_CONVERT}->init_column_convert_mapping($dataset->{column_convert}) if(exists($dataset->{column_convert}));
  my $col_convert_by_colnum;

  # check delimiter
  my $delimiter='';
  if($dataset->{format} eq "csv") {
    $delimiter=',' ;
    if(exists($dataset->{csv_delimiter})) {
      $delimiter=$dataset->{csv_delimiter};
    }
  }
  
  # check columns
  my (@cols,@cols_fmt,$format,$header,$tscol,$cnt);
  $cnt=0;$tscol=-1;
  
  # Quote 'dataset' column
  if(exists($dataset->{column_filemap})) {
    push(@cols,'S."dataset"'); 
  }
  # print Dumper($dataset);
  
  foreach my $col (split(/\s*,\s*/,$dataset->{columns})) {
    my ($c,$as,$ccol);
    if($col=~/^(.*)->(.*)$/) {
      $c=$1;$as=$2;$ccol=$2;
      
      # Clean and quote Alias
      $as =~ s/^"|"$//g;
      $as = qq( AS "$as"); # Add AS explicitly
    } else {
      $ccol=$c=$col;$as="";
    }
    if(exists($dataset->{column_ts})) {
      $tscol=$cnt if($ccol eq $dataset->{column_ts});
    }
    if(exists($col_convert_by_col->{$ccol})) {
      $col_convert_by_colnum->{$cnt}=$col_convert_by_col->{$ccol};
    }
    $cnt++;
    
    # Clean and quote Column Name
    my $c_sql = $c;
    $c_sql =~ s/^"|"$//g;
    $c_sql = qq("$c_sql");
    
    push(@cols,($c eq $joincol)?"D1.$c_sql$as":"$c_sql$as");
    push(@cols_fmt,"%s");
  }
  
  # predefine format string for printing
  if($dataset->{format} eq "dat") {
    $format=$dataset->{format_str};
    if(exists($dataset->{header})) {
      $header=$dataset->{header};
    } else {
      $header=sprintf($dataset->{format_header},(split(/\s*,\s*/,$dataset->{columns})));
    }
  } elsif($dataset->{format} eq "csv") {
    if(exists($dataset->{format_str})) {
      $format=$dataset->{format_str} ;
    } else {
      $format=join($delimiter,@cols_fmt);
    }
    if(exists($dataset->{header})) {
      $header=$dataset->{header};
    } else {
      $header=sprintf($format,(split(/\s*,\s*/,$dataset->{columns})));
    }
  } else {
    printf("%s process_data_query_and_save:      unknown file format %s\n",$self->{INSTNAME},$dataset->{format});
    return();
  }
  # printf("%s process_data_query_and_save_csv_dat: finished init after %7.4fs on %s\n",$self->{INSTNAME},time()-$starttime,$dataset->{name});

  $format.="\n"; $header.="\n";
  my $fh = IO::File->new();
  $self->{SAVE_LASTFH}=$fh;
  $self->{SAVE_LASTFILE}="---";

  # Clean Table/DB Names for SQL Injection
  my $data_db_sql = $dataset->{data_database}; $data_db_sql =~ s/^"|"$//g; $data_db_sql = qq("$data_db_sql");
  my $data_tb_sql = $dataset->{data_table};    $data_tb_sql =~ s/^"|"$//g; $data_tb_sql = qq("$data_tb_sql");
  my $stat_tb_sql = $dataset->{stat_table};    $stat_tb_sql =~ s/^"|"$//g; $stat_tb_sql = qq("$stat_tb_sql");
  
  # Clean TS Column
  my $ts_col_sql = $dataset->{column_ts} || ""; 
  $ts_col_sql =~ s/^"|"$//g; 
  $ts_col_sql = qq("$ts_col_sql") if $ts_col_sql;


  # generate multiple files from one query?
  if(exists($dataset->{column_filemap})) {
    # Clean the Filemap Column ($col is defined at top of subroutine)
    my $col_filemap_sql = $col;
    $col_filemap_sql = "" if(!defined($col_filemap_sql)); # Safety check
    $col_filemap_sql =~ s/^"|"$//g;
    $col_filemap_sql = qq("$col_filemap_sql");

    # Build the multi-table FROM clause correctly with aliases D1, D2, etc.
    my @from_multi_list;
    my $c = 0;
    foreach my $d (@datatables) {
      $c++;
      my $d_sql = $d; 
      $d_sql =~ s/^"|"$//g; 
      $d_sql = qq("$d_sql");
      # Attach the database name to each table (e.g., "jobreport"."jobmetrics" D2)
      push(@from_multi_list, sprintf("%s.%s D%d", $data_db_sql, $d_sql, $c));
    }
    
    # Extract D1 so we can explicitly INNER JOIN it with the Statistics table (S)
    my $d1_string = shift(@from_multi_list); 
    
    # Combine the remaining tables (D2, D3...) with commas if they exist
    my $rest_of_tables = @from_multi_list ? ", " . join(", ", @from_multi_list) : "";

    # Build the corrected SQL query
    my $sql=sprintf("SELECT %s FROM %s S INNER JOIN %s ON D1.%s=S.ukey AND D1.%s>S.lastts_saved AND S.\"NAME\"=\"%s\" %s %s ORDER BY S.\"dataset\",D1.%s",
                    join(",",@cols),
                    $stat_tb_sql,         # S  (e.g., datasetstat_user_csv)
                    $d1_string,           # D1 (e.g., jobreport.joblist D1)
                    $col_filemap_sql,
                    $ts_col_sql,
                    $dataset->{name},
                    $rest_of_tables,      # , D2, D3...
                    ($where)?"WHERE $where":"",
                    $ts_col_sql
                    );
    
    printf("%s process_data_query_and_save_csv_dat: (multi) sql: %s\n",$self->{INSTNAME},$sql) if($sql_debug);
    my $dataref=$self->{DB}->query($dataset->{stat_database},$dataset->{stat_table},
                                    {
                                      attach => $dataset->{data_database},
                                      type => "get_execute",
                                      sql => $sql,
                                      execute => sub {
                                                $self->write_data_to_multi_file_csv_dat([@_],$format,$ds,$tscol,$header,$col_convert_by_colnum,$delimiter);
                                              }
                                    });
  # check all files in $ds: if not exists create it 
  } else { # only a single file
    
    # Check if 'column_ts' is given when renew: 'delta'
    if (!exists($dataset->{column_ts})) {
      if (exists($dataset->{renew}) && $dataset->{renew} eq "delta") {
        print STDERR "$self->{INSTNAME} ERROR: $dataset->{data_table} uses renew='delta' but has no column_ts defined.\n";
      }
    }

    if (exists($dataset->{renew})) {
      if ($dataset->{renew} eq "delta" && $ts_col_sql) {
        $where .= " AND " if($where);
        # Quoted column name in WHERE
        $where .= sprintf("%s > %f", $ts_col_sql, $ds->{$filepath_parsed}->{lastts_saved});
      }
    }

    my $order = "";
    if (exists($dataset->{order})) {
      # Getting order for sorting
      my $orderby;
      my $ordertype;
      my (@order_cols);
      foreach my $c (split(/\s*,\s*/,$dataset->{order})) {
        $c =~ s/^\s+|\s+$//g;
        ($orderby, $ordertype) = split(' ', $c);
        
        # Quote order by column
        $orderby =~ s/^"|"$//g;
        $orderby = qq("$orderby");
        
        push(@order_cols,"D1.$orderby $ordertype");
      }
      $order = sprintf("ORDER BY %s", join(",",@order_cols));
    } else {
      # Only apply default sorting if the timestamp column actually exists
      if ($ts_col_sql) {
        $order = sprintf("ORDER BY D1.%s", $ts_col_sql);
      }
    }

    # build and call the query
    my $sql = sprintf("SELECT %s FROM %s %s %s;",
                      join(",",@cols),
                      $from,
                      ($where) ? "WHERE $where" : "",
                      $order
                    );

    printf("%s process_data_query_and_save_csv_dat: (single) sql: %s\n",$self->{INSTNAME},$sql) if($sql_debug);
    
    my $count = $self->{DB}->query($dataset->{stat_database}, $dataset->{stat_table},
                                  {
                                    attach => $dataset->{data_database},
                                    type => "get_execute",
                                    sql => $sql,
                                    execute => sub {
                                              $self->write_data_to_single_file_csv_dat([@_],
                                                          $format,$ds,$tscol,$header,
                                                          $col_convert_by_colnum,
                                                          $filepath_parsed,$delimiter);
                                                }
                                  });

    if ($count == 0) {
      # re-init file, if no data available 
      $self->write_data_to_single_file_csv_dat( undef,
                                                $format,$ds,$tscol,$header,
                                                $col_convert_by_colnum,
                                                $filepath_parsed,$delimiter);
    }
  }
  
  # printf("%s process_data_query_and_save_csv_dat: finished operation after %7.4fs on %s\n",$self->{INSTNAME},time()-$starttime,$dataset->{name});
  $self->{SAVE_LASTFH}->close() if($self->{SAVE_LASTFILE} ne "---");
}

# Writes rows from a DB query into multiple output files (based on column file mapping)
# Safely handles appending to both raw text (.csv) and compressed (.gz) files
sub write_data_to_multi_file_csv_dat {
  my $self = shift;
  my ($dataref, $format, $ds, $tscol, $header, $col_convert, $delimiter) = @_;
  
  # The first column in $dataref is S."dataset" (the filename)
  my $file = shift(@{$dataref});

  # If this row belongs to a different file than the last one, we must open a new file handle
  if ($self->{SAVE_LASTFILE} ne $file) {
    # If a file is already open, close it
    $self->{SAVE_LASTFH}->close() if ($self->{SAVE_LASTFILE} ne "---");

    my $openop;
    if ($ds->{$file}->{status} == FSTATUS_NOT_EXISTS) {
      $openop = ">";
      $self->{COUNT_OP_NEW_FILE}++;
    } else {
      $openop = ">>";
      $self->{COUNT_OP_EXISTING_FILE}++;
    }

    # If the target file is compressed, pipe to gzip so we don't corrupt the binary
    my $open_cmd;
    if ($file =~ /\.gz$/) {
      $open_cmd = "| gzip -c $openop $self->{OUTDIR}/$file";
    } else {
      $open_cmd = "$openop $self->{OUTDIR}/$file";
    }

    if (!($self->{SAVE_LASTFH}->open($open_cmd))) {
      # print STDERR "LLmonDB:    ERROR, cannot open $open_cmd\n";
      return();
    }
    
    $self->{SAVE_LASTFH}->print($header) if ($ds->{$file}->{status} == FSTATUS_NOT_EXISTS);
    
    # Never downgrade a compressed file back to FSTATUS_EXISTS
    if ($file =~ /\.gz$/) {
      $ds->{$file}->{status} = FSTATUS_COMPRESSED;
    } else {
      $ds->{$file}->{status} = FSTATUS_EXISTS;
    }
    
    $self->{SAVE_LASTFILE} = $file;
  }
  
  # Update last timestamp stored to file
  if ($tscol >= 0) {
    $ds->{$file}->{lastts_saved} = $dataref->[$tscol];
  } else {
    $ds->{$file}->{lastts_saved} = $self->{CURRENTTS};
  }
  $ds->{$file}->{mts} = $self->{CURRENTTS};

  # Convert data based on mapped functions
  while ( my ($colnum, $func) = each(%{$col_convert}) ) {
    $dataref->[$colnum] = &{$func}($dataref->[$colnum], $self);
  }
  
  if ($check) {
    return if (!$self->check_printf($file, $format, $dataref));
  }
  
  # Escape delimiters inside the data columns
  if($delimiter) {
      for (my $colnum = 0; $colnum < scalar @{$dataref}; $colnum++) {
	  $dataref->[$colnum] =~ s/$delimiter/\\$delimiter/gs;
      }
  }
  
  $self->{SAVE_LASTFH}->printf($format, @{$dataref}); 
  $self->{COUNT_OP_WRITE_LINE}++;
}


# Writes rows from a DB query into a single output file
sub write_data_to_single_file_csv_dat {
  my $self = shift;
  my ($dataref, $format, $ds, $tscol, $header, $col_convert, $file, $delimiter) = @_;

  # Open the file if it's not already open
  if ($self->{SAVE_LASTFILE} ne $file) {
    $self->{COUNT_OP_NEW_FILE}++;

    my $openparm;
    
    # Safely handle appending to a compressed file without corrupting the archive
    if ($file =~ /\.gz$/) {
      $openparm = "| gzip -c > $self->{OUTDIR}/$file";
    } else {
      $openparm = "> $self->{OUTDIR}/$file";
    }

    &check_folder("$self->{OUTDIR}/$file");
    if (!($self->{SAVE_LASTFH}->open("$openparm"))) {
      print STDERR "LLmonDB:    ERROR, cannot open $self->{OUTDIR}/$file\n";
      die "stop";
      return();
    }
    
    $self->{SAVE_LASTFH}->print($header);
    
    # Ensure a compressed file stays marked as compressed
    if ($file =~ /\.gz$/) {
      $ds->{$file}->{status} = FSTATUS_COMPRESSED;
    } else {
      $ds->{$file}->{status} = FSTATUS_EXISTS;
    }
    
    $self->{SAVE_LASTFILE} = $file;
  }
  
  # If dataref is undef, this was an empty initialization, and files are 
  # generated with lastts_saved 1 year before (-365*24*3600 on check_filepath). 
  # lastts_saved needs to be updated here, otherwise it remains stuck at "-1 year", 
  # which may lead the workflow to compress it immediately.
  if (!defined($dataref)) {
    $ds->{$file}->{lastts_saved} = $self->{CURRENTTS};
    $ds->{$file}->{mts} = $self->{CURRENTTS};
    return();
  }
  
  # Update last timestamp stored to file based on data
  if ($tscol >= 0) {
    $ds->{$file}->{lastts_saved} = $dataref->[$tscol];
  } else {
    $ds->{$file}->{lastts_saved} = $self->{CURRENTTS};
  }
  $ds->{$file}->{mts} = $self->{CURRENTTS};

  # Convert data based on mapped functions
  while ( my ($colnum, $func) = each(%{$col_convert}) ) {
    $dataref->[$colnum] = &{$func}($dataref->[$colnum], $self);
  }
  
  if ($check) {
    return if (!$self->check_printf($file, $format, $dataref));
  }

  # Escape delimiters inside the data columns
  if($delimiter) {
      for (my $colnum = 0; $colnum < scalar @{$dataref}; $colnum++) {
	  $dataref->[$colnum] =~ s/$delimiter/\\$delimiter/gs;
      }
  }
  
  $self->{SAVE_LASTFH}->printf($format, @{$dataref}); 
  $self->{COUNT_OP_WRITE_LINE}++;
}

sub check_printf {
  my $self = shift;
  my($file,$format,$dataref)=@_;
  my $myformat=$format;$myformat=~s/\n//gs;
  my @fmts = ($myformat=~ m/(%[-\d.]*[sfgde])/g);
  my $numfmts = scalar @fmts;
  my $numdata = scalar @{$dataref};
  if($numfmts != $numdata) {
    printf(STDERR "ERROR: data convert: #fmts=%d numdata=%d (%s) fmt=[%s] vs. data=[%s]\n",$numfmts,$numdata,$file,$myformat,join(",",@{$dataref}));
    return(0);
  }
  for(my $c=0;$c<=$#fmts;$c++) {
    my $fmt=$fmts[$c];$fmt=~s/[-\d.]+//gs;
    if($fmt=~/%[dfe]/) {
      if($dataref->[$c]!~/^[\d\.\+\-e]+$/) {
        printf(STDERR "ERROR data convert: #fmts=%d fmt#=%d (%s) fmt=[%s] vs. data=[%s]\n",$numfmts,$c+1,$file,$fmt,$dataref->[$c]);
        printf(STDERR "ERROR data convert: %s\n",Dumper($dataref));
      }
    }
  }
  return(1);
}

sub process_data_query_time_aggr_get_where {
  my $self = shift;
  my($dataref)=@_;

  # Clean and Quote identifiers
  my $ts_col_sql = $dataref->{column_ts};
  $ts_col_sql =~ s/^"|"$//g;
  $ts_col_sql = qq("$ts_col_sql");
  my $table_sql = $dataref->{data_table};
  $table_sql =~ s/^"|"$//g;
  $table_sql = qq("$table_sql");

  # get min values for each resolution
  my $sql=sprintf("SELECT \"_time_res\",min(%s) min_ts FROM %s GROUP by \"_time_res\"",
                  $ts_col_sql,
                  $table_sql);
  my $mints_hash=$self->{DB}->query($dataref->{data_database},$dataref->{data_table},
                                    {
                                      sql => $sql,
                                      type => 'hash_values',
                                      hash_keys => '_time_res',
                                      hash_value => 'min_ts',
                                    });

  my @whereparts;
  my $lastmints=0;
  foreach my $res (sort {$a <=> $b} (keys(%{$mints_hash}))) {
    if($lastmints>0) {
      push(@whereparts,"( (\"_time_res\"=$res) AND ($ts_col_sql<$lastmints) )");
    } else {
      push(@whereparts,"(\"_time_res\"=$res)");
    }
    $lastmints=$mints_hash->{$res}->{min_ts};
  }
  
  my $where=join(" OR ",@whereparts);
  # print "TMPDEB: $dataref->{data_table} $where\n";

  return($where);
}

# Pre-fetches database rows into memory to avoid redundant SQL queries
sub process_data_query_cache_table_csv_dat {
  my $self = shift;
  my ($table_cache, $dataset, $varsetref) = @_;

  my $where = "";
  if (exists($dataset->{sql_where})) {
    $where = $self->{DB}->replace_tsvars($dataset->{sql_where}, $self->{CURRENTTS});
    while ( my ($key, $value) = each(%{$varsetref}) ) {
      $where =~ s/\$\{$key\}/$value/gs;
      $where =~ s/\$$key/$value/gs;
    }
  }

  my $from;
  my $joincol     = "";
  my $joincol_sql = "";
  my @datatables  = split(/\s*,\s*/, $dataset->{data_table});

  if ($#datatables > 0) {
    my @fromlist;
    my $c = 0;
    if (!exists($dataset->{data_table_join_col})) {
      print STDERR "LLmonDB:    ERROR, attribute data_table_join_col missing for dataset $dataset->{name}\n";
      return();
    } else {
      $joincol     = $dataset->{data_table_join_col};
      $joincol_sql = $joincol;
      $joincol_sql =~ s/^"|"$//g;
      $joincol_sql = qq("$joincol_sql");
    }
    foreach my $d (@datatables) {
      $c++;
      my $d_sql = $d;
      $d_sql =~ s/^"|"$//g;
      $d_sql = qq("$d_sql");
      push(@fromlist, sprintf("%s D%d", $d_sql, $c));
      if ($c > 1) {
        $where .= " AND " if ($where);
        $where .= sprintf("D1.%s=D%d.%s", $joincol_sql, $c, $joincol_sql);
      }
    }
    $from = join(",", @fromlist);
  } else {
    my $d_sql = $dataset->{data_table};
    $d_sql =~ s/^"|"$//g;
    $d_sql = qq("$d_sql");
    $from = sprintf("%s D%d", $d_sql, 1);
  }

  my @cols;
  foreach my $col (split(/\s*,\s*/, $dataset->{columns})) {
    my ($c, $as);
    if ($col =~ /^(.*)->(.*)$/) {
      $c  = $1;
      $as = $2;
      $as =~ s/^"|"$//g;
      $as = qq( AS "$as");
    } else {
      $c  = $col;
      $as = "";
    }
    my $c_sql = $c;
    $c_sql =~ s/^"|"$//g;
    $c_sql = qq("$c_sql");
    push(@cols, ($c eq $joincol) ? "D1.$c_sql$as" : "$c_sql$as");
  }

  my @order_cols;
  if (exists($dataset->{column_filemap})) {
    foreach my $c (@{$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list}}) {
      push(@order_cols, ($c eq $joincol) ? "D1.$c" : "$c");
    }
  }

  if (exists($dataset->{order})) {
    foreach my $c (split(/\s*,\s*/, $dataset->{order})) {
      $c =~ s/^\s+|\s+$//g;
      my ($orderby, $ordertype) = split(' ', $c);
      $ordertype = $ordertype ? $ordertype : "";

      $orderby =~ s/^"|"$//g;
      $orderby = qq("$orderby");

      push(@order_cols, ($orderby eq $joincol_sql) ? "D1.$orderby $ordertype" : "$orderby $ordertype");
    }
  }

  my $order = "";
  if (@order_cols) {
    $order = sprintf("ORDER BY %s", join(",", @order_cols));
  }

  my $sql = sprintf("SELECT %s FROM %s %s %s;",
                    join(",", @cols),
                    $from,
                    ($where) ? "WHERE $where" : "",
                    $order
                  );

  if (exists($self->{TABLECACHE}->{$table_cache}->{sql_signature})) {
    if ($self->{TABLECACHE}->{$table_cache}->{sql_signature} ne $sql) {
      printf(STDERR "LLmonDB ERROR: Cache Collision Detected! Dataset '%s' is attempting to use table_cache '%s', but its underlying SQL differs from the dataset that originally built the cache. Please assign a unique table_cache name to this dataset.\n",
              $dataset->{name}, $table_cache);
      printf(STDERR "  Original SQL: %s\n  New SQL:      %s\n",
              $self->{TABLECACHE}->{$table_cache}->{sql_signature}, $sql);
    }
    return;
  }

  $self->{TABLECACHE}->{$table_cache}->{sql_signature} = $sql;
  $self->{TABLECACHE}->{$table_cache}->{dataset}       = $dataset;

  my $tc        = $self->{TABLECACHE}->{$table_cache};
  my $starttime = time();

  $tc->{dataset} = $self->{DB}->query($dataset->{data_database}, $dataset->{data_table},
                                      {
                                        type => "get_arrayref_of_hashref",
                                        sql  => $sql
                                      });

  printf("%s process_data_query_cache_table_csv_dat: pre-cache table in %7.4fs (%d entries)\n",
          $self->{INSTNAME}, time()-$starttime, scalar @{$tc->{dataset}}
        );
}

# Cached memory rows are distributed into specific file structures based on configurations.
# Both multi-file datasets and single-file datasets are fully supported, alongside dynamic time-range filtering.
#
# Arguments:
#   $self      - (Object) The LML_jobreport instance
#   $dataset   - (HashRef) The configuration definitions for the dataset
#   $varsetref - (HashRef) Variable substitutions available
#
# Returns:
#   (Void)
sub process_data_query_and_save_csv_dat_cache {
  my $self = shift;
  my ($dataset, $varsetref) = @_;

  my $table_cache = $dataset->{table_cache};
  if (!defined($table_cache)) {
    print STDERR "LLmonDB:    ERROR, table_cache not specified\n";
    return();
  }

  if (!exists($self->{TABLECACHE}->{$table_cache})) {
    $self->process_data_query_cache_table_csv_dat($table_cache, $dataset, $varsetref);
  }

  my $col_convert_by_col = {};
  if (exists($dataset->{column_convert})) {
    $col_convert_by_col = $self->{LL_CONVERT}->init_column_convert_mapping($dataset->{column_convert});
  }

  my $delimiter = $dataset->{format} eq "csv" ? ',' : '';
  $delimiter = $dataset->{csv_delimiter} if (exists($dataset->{csv_delimiter}));
  my $max_entries = exists($dataset->{max_entries}) ? $dataset->{max_entries} : 500000;

  my $checksumvar = exists($dataset->{checksumvar}) ? $dataset->{checksumvar} : undef;

  # Expressions for time range filtering are evaluated dynamically to match JSON behavior.
  my $file = $dataset->{filepath};
  my $selecttimevar = exists($dataset->{selecttimevar}) ? $dataset->{selecttimevar} : undef;
  my $selecttimerange = "";
  if (exists($dataset->{selecttimerange})) {
    $selecttimerange = $self->{DB}->replace_tsvars($dataset->{selecttimerange}, $self->{CURRENTTS});
  }

  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file =~ s/\$\{$key\}/$value/gs;
    $file =~ s/\$$key/$value/gs;
    $value =~ s/^0+//gs; 
    $selecttimerange =~ s/\$\{$key\}/$value/gs;
    $selecttimerange =~ s/\$$key/$value/gs;
  }

  my($selecttimerange_begin, $selecttimerange_end) = (undef, undef);
  if ($selecttimerange) {
    ($selecttimerange_begin, $selecttimerange_end) = split(/\s*,\s*/, $selecttimerange);
    $selecttimerange_begin = eval($selecttimerange_begin);
    $selecttimerange_end = eval($selecttimerange_end);
  }

  my @cols_fmt;
  my $tscol = -1;
  my $cnt = 0;
  my $col_convert_by_colnum;
  my @raw_cols;

  foreach my $col (split(/\s*,\s*/, $dataset->{columns})) {
    my $c = ($col =~ /^(.*)->(.*)$/) ? $2 : $col;
    push(@raw_cols, $c);
    $tscol = $cnt if (exists($dataset->{column_ts}) && $c eq $dataset->{column_ts});
    $col_convert_by_colnum->{$cnt} = $col_convert_by_col->{$c} if (exists($col_convert_by_col->{$c}));
    push(@cols_fmt, "%s");
    $cnt++;
  }

  my $format = exists($dataset->{format_str}) ? $dataset->{format_str} : join($delimiter, @cols_fmt);
  my $header = exists($dataset->{header}) ? $dataset->{header} : sprintf($format, split(/\s*,\s*/, $dataset->{columns}));
  $format .= "\n"; 
  $header .= "\n";

  my $ds = $self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};

  # Multi-file processing is executed when a file mapping is defined.
  if (exists($dataset->{column_filemap})) {
    my $skeylistref = $self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list};
    my $skey_to_filenameref = $self->{DATASETSTAT_MAP}->{$dataset->{name}}->{skey_to_filename};
    my $dataref;
    my $checksumref;

    if (exists($dataset->{create_empty_files}) && ($dataset->{create_empty_files} eq "yes")) {
      foreach my $k (keys(%{$skey_to_filenameref})) {
        my $f = $skey_to_filenameref->{$k};
        $dataref->{$f} = [];
        $checksumref->{$f} = 0;
      }
    }

    foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{dataset}}) {
      if (defined($selecttimevar)) {
        next if($ref->{$selecttimevar} < $selecttimerange_begin);
        next if($ref->{$selecttimevar} >= $selecttimerange_end);
      }

      my @skeys;
      foreach my $v (@{$skeylistref}) {
        push(@skeys, $ref->{$v});
      }
      my $skey = join(":", @skeys);
      
      if (exists($skey_to_filenameref->{$skey})) {
        my $f = $skey_to_filenameref->{$skey};
        push(@{$dataref->{$f}}, $ref);
        
        $checksumref->{$f} = 0 if (!exists($checksumref->{$f}));
        $checksumref->{$f} += $ref->{$checksumvar} if (defined($checksumvar));
        $self->{COUNT_OP_WRITE_LINE}++;
      }
    }

    while ( my ($f, $dataref_per_file) = each(%{$dataref}) ) {
      $self->register_data_for_file_csv_dat_cache($table_cache, "$self->{OUTDIR}/$f", $ds, $dataref_per_file, $format, $header, $tscol, $col_convert_by_colnum, $delimiter, $max_entries, $dataset, \@raw_cols, $checksumvar, $checksumref->{$f});
    }
    
  # Single-file processing is executed when no dynamic mapping is required.
  } else {
    my $dataref;
    my $checksum = 0;

    foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{dataset}}) {
      if (defined($selecttimevar)) {
        next if($ref->{$selecttimevar} < $selecttimerange_begin);
        next if($ref->{$selecttimevar} >= $selecttimerange_end);
      }
      
      push(@{$dataref}, $ref);
      $checksum += $ref->{$checksumvar} if (defined($checksumvar));
      $self->{COUNT_OP_WRITE_LINE}++;
    }

    my $shortfile = $file;
    $shortfile =~ s/$self->{OUTDIR}\///s;

    $self->register_data_for_file_csv_dat_cache($table_cache, "$self->{OUTDIR}/$shortfile", $ds, $dataref, $format, $header, $tscol, $col_convert_by_colnum, $delimiter, $max_entries, $dataset, \@raw_cols, $checksumvar, $checksum);
  }
}

# Queues the file operation into the caching engine for parallel execution
#
# Arguments:
#   $self         - (Object) The LML_jobreport instance
#   $table_cache  - (String) Name of the memory cache pool
#   $file         - (String) Target output file path
#   $ds           - (HashRef) Database status reference
#   $dataref      - (ArrayRef) Rows assigned to this file
#   $format       - (String) Explicit formatting string (if provided)
#   $header       - (String) Header line
#   $tscol        - (Integer) Index of the timestamp column
#   $col_convert  - (HashRef) Conversion functions to apply to columns
#   $delimiter    - (String) Character used to delimit values
#   $max_entries  - (Integer) Maximum number of rows allowed per file
#   $dataset      - (HashRef) Original dataset configuration definitions
#   $raw_cols     - (ArrayRef) The mapped column structure to extract
#
# Returns:
#   (Void)
sub register_data_for_file_csv_dat_cache {
  my $self = shift;
  my ($table_cache, $file, $ds, $dataref, $format, $header, $tscol, $col_convert, $delimiter, $max_entries, $dataset, $raw_cols, $checksumvar, $checksum) = @_;

  my $shortfile = $file;
  $shortfile =~ s/$self->{OUTDIR}\///s;

  # Checksum bypass logic. Skips writing entirely if data is unchanged
  my $process_file = 1;
  if (defined($checksumvar)) {
    $ds->{$shortfile}->{checksum} = 0 if (!exists($ds->{$shortfile}->{checksum}));
    if ($checksum != $ds->{$shortfile}->{checksum}) {
      $ds->{$shortfile}->{checksum} = $checksum;
    } else {
      $process_file = 0;	    
    }
  } else {
    $ds->{$shortfile}->{checksum} = 0;
  }

  if ($process_file) {
    # Cached complete datasets must always overwrite the old file, breaking the infinite append loop
    $self->{TABLECACHE}->{$table_cache}->{csv_openop}->{$file} = ">";
    $self->{TABLECACHE}->{$table_cache}->{csv_use_printf}->{$file} = exists($dataset->{format_str}) ? 1 : 0;

    if ($shortfile =~ /\.(gz|xz)$/) {
      $ds->{$shortfile}->{status} = FSTATUS_COMPRESSED;
    } else {
      $ds->{$shortfile}->{status} = FSTATUS_EXISTS;
    }

    $ds->{$shortfile}->{dataset} = $shortfile;
    $ds->{$shortfile}->{name} = $dataset->{name} if (!exists($ds->{$shortfile}->{name}));
    $ds->{$shortfile}->{lastts_saved} = $self->{CURRENTTS}; 
    $ds->{$shortfile}->{mts} = $self->{CURRENTTS}; 
    $self->{COUNT_OP_NEW_FILE}++;

    $self->{TABLECACHE}->{$table_cache}->{csv_format}->{$file} = $format;
    $self->{TABLECACHE}->{$table_cache}->{csv_header}->{$file} = $header;
    $self->{TABLECACHE}->{$table_cache}->{csv_tscol}->{$file} = $tscol;
    $self->{TABLECACHE}->{$table_cache}->{csv_delimiter}->{$file} = $delimiter;
    $self->{TABLECACHE}->{$table_cache}->{csv_max_entries}->{$file} = $max_entries;
    $self->{TABLECACHE}->{$table_cache}->{csv_con_convert}->{$file} = $col_convert;
    $self->{TABLECACHE}->{$table_cache}->{csv_fileop}->{$file} = $dataref;
    $self->{TABLECACHE}->{$table_cache}->{csv_raw_cols}->{$file} = $raw_cols;
  }
}


# The queued data chunks are processed in parallel and written to disk.
# A compiled C library (Text::CSV_XS) is dynamically utilized for maximum performance if available.
# A micro-profiling mechanism is embedded to measure the exact CPU time consumed by data extraction, 
# conversion, formatting, and disk I/O.
#
# Arguments:
#   $self        - (Object) The LML_jobreport instance
#   $table_cache - (String) Name of the memory cache pool
#   $part        - (Integer) The worker ID for this parallel chunk
#   $parlevel    - (Integer) Total number of parallel workers
#
# Returns:
#   (Void)
sub write_data_to_file_csv_dat_cache {
  my $self = shift;
  my ($table_cache, $part, $parlevel) = @_;

  return if !exists($self->{TABLECACHE}->{$table_cache}->{csv_fileop});

  my $starttime = time();
  
  # Files are sorted by the number of rows they contain (descending) to implement 
  # Longest Processing Time (LPT) scheduling.
  my @filelist = sort { 
    scalar(@{$self->{TABLECACHE}->{$table_cache}->{csv_fileop}->{$b}}) 
    <=> 
    scalar(@{$self->{TABLECACHE}->{$table_cache}->{csv_fileop}->{$a}}) 
  } keys(%{$self->{TABLECACHE}->{$table_cache}->{csv_fileop}});
  
  my $numfiles  = scalar @filelist;
  my $fcount    = 0;
  my $lcount    = 0;

  # The availability of the compiled C library is verified.
  my $has_csv_xs = 0;
  eval {
    require Text::CSV_XS;
    $has_csv_xs = 1;
  };
  
  if (!$has_csv_xs && $part == 0) {
    printf(STDERR "%s WARNING: Text::CSV_XS module is missing. CSV generation is falling back to native Perl.\n", $self->{INSTNAME});
  }

  for (my $fnum = 0; $fnum < $numfiles; $fnum++) {
    next if (($fnum % $parlevel) != $part);
    $fcount++;

    my $file         = $filelist[$fnum];
    my $dataset_rows = $self->{TABLECACHE}->{$table_cache}->{csv_fileop}->{$file};
    my $raw_cols     = $self->{TABLECACHE}->{$table_cache}->{csv_raw_cols}->{$file};
    my $format       = $self->{TABLECACHE}->{$table_cache}->{csv_format}->{$file};
    my $header       = $self->{TABLECACHE}->{$table_cache}->{csv_header}->{$file};
    my $delimiter    = $self->{TABLECACHE}->{$table_cache}->{csv_delimiter}->{$file};
    my $col_convert  = $self->{TABLECACHE}->{$table_cache}->{csv_con_convert}->{$file};
    my $use_printf   = $self->{TABLECACHE}->{$table_cache}->{csv_use_printf}->{$file}  || 0;
    my $max_entries  = $self->{TABLECACHE}->{$table_cache}->{csv_max_entries}->{$file} || 500000;
    my $openop       = $self->{TABLECACHE}->{$table_cache}->{csv_openop}->{$file}      || ">";

    my @conversions;
    if (defined($col_convert)) {
      while (my ($colnum, $func) = each(%{$col_convert})) {
        push(@conversions, [$colnum, $func]);
      }
    }

    my $csv_engine;
    if ($has_csv_xs && !$use_printf && $delimiter) {
      $csv_engine = Text::CSV_XS->new({
        sep_char    => $delimiter,
        quote_char  => undef,
        escape_char => "\\",
        binary      => 1
      });
    }

    my @file_lines;
    my $numentries = 0;
    
    # Execution timers are initialized for profiling analysis.
    my $t_extract = 0.0;
    my $t_convert = 0.0;
    my $t_format  = 0.0;
    my $t_io      = 0.0;

    foreach my $row_ref (@{$dataset_rows}) {
      last if ($numentries >= $max_entries);
      $numentries++;

      # Extraction phase is timed.
      my $t0 = time();
      my @row = map { defined($_) ? $_ : "" } @{$row_ref}{@{$raw_cols}};
      my $t1 = time();
      $t_extract += ($t1 - $t0);

      # Conversion phase is timed.
      foreach my $conv (@conversions) {
        $row[$conv->[0]] = &{$conv->[1]}($row[$conv->[0]], $self);
      }
      my $t2 = time();
      $t_convert += ($t2 - $t1);

      # Formatting phase is timed.
      if ($use_printf) {
        my $line = sprintf($format, @row);
        chomp($line);
        push(@file_lines, $line);
      } elsif ($csv_engine) {
        $csv_engine->combine(@row);
        push(@file_lines, $csv_engine->string());
      } else {
        if ($delimiter) {
          for my $i (0 .. $#row) {
            if (defined($row[$i]) && index($row[$i], $delimiter) != -1) {
              $row[$i] =~ s/\Q$delimiter\E/\\$delimiter/g;
            }
          }
        }
        push(@file_lines, join($delimiter, @row));
      }
      my $t3 = time();
      $t_format += ($t3 - $t2);
    }
    
    $lcount += $numentries;

    my $csv_data = ($openop eq ">") ? $header : "";
    $csv_data .= join("\n", @file_lines) . "\n" if (@file_lines);

    my $fh = IO::File->new();
    my $openparm;

    if ($file =~ /\.gz$/) {
      $openparm = "| gzip -c > $file";
    } else {
      $openparm = "$openop $file";
    }

    &check_folder($file);
    if (!($fh->open($openparm))) {
      printf(STDERR "%s write_data_to_file_csv_dat_cache: WARNING: cannot open %s, skipping...\n",
              $self->{INSTNAME}, $file);
      next;
    }

    # I/O phase is timed.
    my $t_io_start = time();
    $fh->print($csv_data);
    $fh->close();
    $t_io = time() - $t_io_start;
    
    # A diagnostic profile is printed for files requiring significant processing time.
    # if ($numentries > 5000) {
    #   printf(STDERR "%s [DEBUG] %s (%d rows) -> Extract: %.3fs, Convert: %.3fs, Format: %.3fs, I/O: %.3fs\n",
    #          $self->{INSTNAME}, $file, $numentries, $t_extract, $t_convert, $t_format, $t_io);
    # }
  }

  printf("%s write_data_to_file_csv_dat_cache: %10s  write files %3d of %4d in %7.4fs (%5d lines)\n",
          $self->{INSTNAME}, $table_cache, $fcount, $numfiles, time()-$starttime, $lcount
        );
}

1;
