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
  my $groupby="";
  if(exists($dataset->{group_by})) {
    $groupby="GROUP BY ".$dataset->{group_by};
  }
  my $where="";
  if(exists($dataset->{sql_where})) {
    $where.=$self->{DB}->replace_tsvars($dataset->{sql_where},$self->{CURRENTTS});
  }

  if(!exists($self->{TABLES}->{$dataset->{data_database}})) {
    printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database});
    return;
  }
#  if(!exists($self->{TABLES}->{$dataset->{data_database}}->{$dataset->{data_table}})) {
#    printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database},$dataset->{data_table});
#    return;
#  }

  # check data tables
  my $from;
  my $joincol="";
  my @datatables=split(/\s*,\s*/,$dataset->{data_table});
  if($#datatables>0) {
      my @fromlist; my $c=0;
      if(!exists($dataset->{data_table_join_col})) {
        print STDERR "LLmonDB:    ERROR, attribute data_table_join_col missing for dataset $dataset->{name}\n";
        return();
      } else {
        $joincol=$dataset->{data_table_join_col};
      }
      foreach my $d (@datatables) {
        $c++;
        push(@fromlist,sprintf("%s D%d",$d,$c));
        if($c>1) {
          $where.=" AND " if($where);
          $where.=sprintf("D1.%s=D%d.%s",$joincol,$c,$joincol);
        }
      }
      $from = join(",",@fromlist);
  } else {
      $from = sprintf("%s D%d",$dataset->{data_table},1);
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
  my $delimiter=',';
  if(exists($dataset->{csv_delimiter})) {
      $delimiter=$dataset->{csv_delimiter};
  }

  
  # check columns
  my (@cols,@cols_fmt,$format,$header,$tscol,$cnt);
  $cnt=0;$tscol=-1;
  if(exists($dataset->{column_filemap})) {
    push(@cols,"S.dataset");
  }
  # print Dumper($dataset);
  
  foreach my $col (split(/\s*,\s*/,$dataset->{columns})) {
    my ($c,$as,$ccol);
    if($col=~/^(.*)->(.*)$/) {
      $c=$1;$as=" as $2";$ccol=$2;
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
    push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
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

  # generate multiple files from one query?
  if(exists($dataset->{column_filemap})) {
    my $sql=sprintf("SELECT %s FROM %s.%s D1 INNER JOIN  %s S ON D1.%s=S.ukey AND D1.%s>S.lastts_saved AND S.NAME=\"%s\" %s ORDER BY S.dataset,D1.%s %s;",
                    join(",",@cols),
                    $dataset->{data_database},
                    $dataset->{data_table},
                    $dataset->{stat_table},
                    $col,
                    $dataset->{column_ts},
                    $dataset->{name},
                    ($where)?"WHERE $where":"",
                    $dataset->{column_ts},
                    ($groupby)?" $groupby":""
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
    if(!exists($dataset->{column_ts})) {
      print STDERR "$self->{INSTNAME} ERROR: $dataset->{data_table} no column_ts\n";
    }

    if(exists($dataset->{renew})) {
      if($dataset->{renew} eq "delta") {
        $where .= " AND " if($where);
        $where .= sprintf("%s > %f",$dataset->{column_ts},$ds->{$filepath_parsed}->{lastts_saved});
      }
    }

    my $order;
    if(exists($dataset->{order})) {
      # Getting order for sorting
      my $orderby;
      my $ordertype;
      my (@order_cols);
      foreach my $c (split(/\s*,\s*/,$dataset->{order})) {
        $c =~ s/^\s+|\s+$//g;
        ($orderby, $ordertype) = split(' ', $c);
        push(@order_cols,"D1.$orderby $ordertype");
      }
      $order=sprintf("ORDER BY %s",join(",",@order_cols));
    } else {
      $order = sprintf("ORDER BY D1.%s",$dataset->{column_ts})
    }

    # build and call the query
    my $sql=sprintf("SELECT %s FROM %s %s %s %s;",
                      join(",",@cols),
                      $from,
                      ($where)?"WHERE $where":"",
                      $order,
                      $(groupby)?" $groupby":""
                    );
    printf("%s process_data_query_and_save_csv_dat: (single) sql: %s\n",$self->{INSTNAME},$sql)  if($sql_debug);
    #	print "single: $where\n";
    my $count=$self->{DB}->query($dataset->{stat_database},$dataset->{stat_table},
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
    # print "TMPDEB: count=$count\n";
    if($count==0) {
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

sub write_data_to_multi_file_csv_dat {
  my $self = shift;
  my($dataref,$format,$ds,$tscol,$header,$col_convert,$delimiter)=@_;
  my $file=shift(@{$dataref});

  #  same file as last entry?
  if( $self->{SAVE_LASTFILE} ne $file ) {
    # if not close the old one if opened
    $self->{SAVE_LASTFH}->close() if($self->{SAVE_LASTFILE} ne "---");

    # open new file
    my $openop;
    
    if($ds->{$file}->{status} == FSTATUS_NOT_EXISTS) {
      $openop=">";
      $self->{COUNT_OP_NEW_FILE}++;
    } else {
      $openop=">>";
      $self->{COUNT_OP_EXISTING_FILE}++;
    }

    if (!($self->{SAVE_LASTFH}->open("$openop $self->{OUTDIR}/$file"))) {
      # print STDERR "LLmonDB:    ERROR, cannot open $self->{OUTDIR}/$file\n";
      return();
    }
    $self->{SAVE_LASTFH}->print($header) if($ds->{$file}->{status} == FSTATUS_NOT_EXISTS);
    $ds->{$file}->{status}=FSTATUS_EXISTS;
    $self->{SAVE_LASTFILE}=$file;
    # printf("%s write_data_to_multi_file_csv_dat:      open file %s %s\n",$self->{INSTNAME},$file,$openop);
  }
  # update last ts stored to file
  if($tscol>=0) {
    $ds->{$file}->{lastts_saved}=$dataref->[$tscol];
  } else {
    $ds->{$file}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  }
  $ds->{$file}->{mts}=$self->{CURRENTTS}; # last change ts

  # convert data
  while ( my ($colnum, $func) = each(%{$col_convert}) ) {
    $dataref->[$colnum]=&{$func}($dataref->[$colnum],$self);
  }
  # for(my $c=0;$c<$#{$dataref};$c++) {
  #   printf(STDERR "data convert error: undefined data: %s, col=%d (format=%s) (data=%s)\n",
  #                 $file,$c,$format,join(",",(@{$dataref}))) if(!defined($dataref->[$c]));
  #   printf(STDERR "data convert error: empty data: %s, col=%d (format=%s) (data=%s)\n",
  #                 $file,$c,$format,join(",",(@{$dataref}))) if($dataref->[$c] eq "");
  # }
  # write data
  if($check) {
    return if(!$self->check_printf($file,$format,$dataref));
  }
  for(my $colnum=0;$colnum<$#{$dataref};$colnum++) {
      $dataref->[$colnum]=~s/$delimiter/\\$delimiter/gs;
  }
  $self->{SAVE_LASTFH}->printf($format,@{$dataref}) ; 
  $self->{COUNT_OP_WRITE_LINE}++;
}

sub write_data_to_single_file_csv_dat {
  my $self = shift;
  my($dataref,$format,$ds,$tscol,$header,$col_convert,$file,$delimiter)=@_;

  #  same file as last entry?
  if( $self->{SAVE_LASTFILE} ne $file ) {
    # open new file
    $self->{COUNT_OP_NEW_FILE}++;

    my $openparm;
    if($file=~/\.gz$/) {
      $openparm="| gzip -c > $self->{OUTDIR}/$file";
    } else {
      $openparm="> $self->{OUTDIR}/$file";
    }

    &check_folder("$self->{OUTDIR}/$file");
    if (!($self->{SAVE_LASTFH}->open("$openparm"))) {
      print STDERR "LLmonDB:    ERROR, cannot open $self->{OUTDIR}/$file\n";
      die "stop";
      return();
    }
    $self->{SAVE_LASTFH}->print($header);
    $ds->{$file}->{status}=FSTATUS_EXISTS;
    $self->{SAVE_LASTFILE}=$file;
  }
  return() if(!defined($dataref));
  # update last ts stored to file
  if($tscol>=0) {
    $ds->{$file}->{lastts_saved}=$dataref->[$tscol];
  } else {
    $ds->{$file}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  }
  $ds->{$file}->{mts}=$self->{CURRENTTS}; # last change ts

  return() if(!defined($dataref));
  
  # convert data
  while ( my ($colnum, $func) = each(%{$col_convert}) ) {
    $dataref->[$colnum]=&{$func}($dataref->[$colnum],$self);
  }
  # write data
  if($check) {
    return if(!$self->check_printf($file,$format,$dataref));
  }

  for(my $colnum=0;$colnum<$#{$dataref};$colnum++) {
      $dataref->[$colnum]=~s/$delimiter/\\$delimiter/gs;
  }
  $self->{SAVE_LASTFH}->printf($format,@{$dataref}) ; 
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

  # get min values for each resolution
  my $sql=sprintf("SELECT _time_res,min(%s) min_ts FROM %s GROUP by _time_res",$dataref->{column_ts},$dataref->{data_table});
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
      push(@whereparts,"( (_time_res=$res) AND ($dataref->{column_ts}<$lastmints) )");
    } else {
      push(@whereparts,"(_time_res=$res)");
    }
    $lastmints=$mints_hash->{$res}->{min_ts};
  }
  
  my $where=join(" OR ",@whereparts);
  # print "TMPDEB: $dataref->{data_table} $where\n";

  return($where);
}

1;
