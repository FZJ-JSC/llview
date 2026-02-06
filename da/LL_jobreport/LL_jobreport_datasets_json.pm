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
my($debugJSON)=0; # enables pretty print of JSON files

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_jobreport_datasets_constants;

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub process_data_query_and_save_json {
  my $self = shift;
  my($dataset,$varsetref)=@_;

  my $groupby="";
  if(exists($dataset->{group_by})) {
    $groupby="GROUP BY ".$dataset->{group_by};
  }
  my $file=$dataset->{filepath};
  my $where="";
  if(exists($dataset->{sql_where})) {
    $where.=$self->{DB}->replace_tsvars($dataset->{sql_where},$self->{CURRENTTS});
  }

  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file=~s/\$\{$key\}/$value/gs;	$file=~s/\$$key/$value/gs;
    $where=~s/\$\{$key\}/$value/gs;	$where=~s/\$$key/$value/gs;
  }
  # print "process_data_query_and_save_json: file=$file\n";
  
  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};

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

  if(!exists($self->{TABLES}->{$dataset->{data_database}})) {
    printf("$self->{INSTNAME}  --> WARNING: query database %s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database});
    return;
  }
  foreach my $t (@datatables) {
    if(!exists($self->{TABLES}->{$dataset->{data_database}}->{$t})) {
      printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database},$t);
      return;
    }
  }

  # pre-process column_convert
  my $col_convert_by_col={};
  $col_convert_by_col=$self->{LL_CONVERT}->init_column_convert_mapping($dataset->{column_convert}) if(exists($dataset->{column_convert}));

  # check columns and make column names unique if they are used for join 
  my (@cols,$format,$tscol,$cnt);
  
  my $col_to_group=undef;
  if(exists($dataset->{column_groups})) {
    foreach my $g (keys(%{$dataset->{column_groups}})) {
      foreach my $col (split(/\s*,\s*/,$dataset->{column_groups}->{$g})) {
        my ($c,$as);
        if($col=~/^(.*)->(.*)$/) {
          $c=$1;$as=" as $2";
          $col_to_group->{$2}=$g;
        } else {
          $c=$col;$as="";
          $col_to_group->{$c}=$g;
        }
        push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
      }
    }
  } else {
    foreach my $col (split(/\s*,\s*/,$dataset->{columns})) {
      my ($c,$as);
      if($col=~/^(.*)->(.*)$/) {
        $c=$1;$as=" as $2";
      } else {
        $c=$col;$as="";
      }
      push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
    }
  }
  # print "TMPDEB: ",Dumper($col_to_group);
  my @order_cols;
  if(exists($dataset->{column_filemap})) {
    foreach my $c (@{$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list}}) {	
      push(@order_cols,($c eq $joincol)?"D1.$c":"$c");
    }
  }

  # Getting order for sorting
  my $orderby;
  my $ordertype;
  if(exists($dataset->{order})) {
    foreach my $c (split(/\s*,\s*/,$dataset->{order})) {
      $c =~ s/^\s+|\s+$//g;
      ($orderby, $ordertype) = split(' ', $c);
      push(@order_cols,($orderby eq $joincol)?"D1.$orderby $ordertype":"$orderby $ordertype");
    }
  }

  my $order="";
  if (@order_cols) {
    $order=sprintf("ORDER BY %s",join(",",@order_cols));
  }

  my $json_single_entry=0;
  if(exists($dataset->{json_type})) {
    $json_single_entry=1 if($dataset->{json_type} eq "single_entry");
  }

  my $fh = IO::File->new();
  $self->{SAVE_LASTFILE}="---";
  $self->{SAVE_LASTFH}=$fh;
  $self->{SAVE_DS}=[];
  
  # generate multiple files from one query?
  if(exists($dataset->{column_filemap})) {
    # build and call the query 
    my $sql=sprintf("SELECT %s FROM %s %s %s %s;",
                      join(",",@cols),
                      $from,
                      ($where)?"WHERE $where":"",
                      $order,
                      ($groupby)?" $groupby":""
                    );
    # printf("%s process_data_query_and_save_json: multi sql=%s\n",$self->{INSTNAME},$sql);

    my $skeylistref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list};
    my $skey_to_filenameref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{skey_to_filename};
    my $filemap_v=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{filemap_v};

    my $starttime=time();
    my $dataref=$self->{DB}->query($dataset->{data_database},$dataset->{data_table},
                                    {
                                      type => "get_execute_hash",
                                      sql => $sql,
                                      execute => sub {
                                                      $self->collect_data_for_file_json_multi_file(@_,$ds,
                                                                                                    $skeylistref,
                                                                                                    $skey_to_filenameref,
                                                                                                    $col_convert_by_col,
                                                                                                    $col_to_group,
                                                                                                    $json_single_entry,
                                                                                                    $dataset);
                                                    }
                                    });
    $self->write_data_to_file_json($self->{SAVE_LASTFILE},$ds,$json_single_entry,$dataset) if($self->{SAVE_LASTFILE} ne "---");
    # printf("%s process_data_query_and_save_json: executed multi JSON generation in %7.4fs\n",$self->{INSTNAME},time()-$starttime);

    if(0) {
      # check status of each file
      while ( my ($skey, $fp) = each(%{$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{skey_to_filename}}) ) {
        if(exists($ds->{$fp}->{status})) {
          $ds->{$fp}->{"name"}=$dataset->{name};
          $ds->{$fp}->{"ukey"}=-1;
        } else {
          # TODO: handle to create empty files if required
        }
        
      }
    }
  } else { # only a single file
    # build and call the query
    my $sql=sprintf("SELECT %s FROM %s %s %s",
                      join(",",@cols),
                      $from,
                      ($where)?"WHERE $where":"",
                      ($groupby)?" $groupby":""
                    );
    # printf("%s process_data_query_and_save_json: single sql=%s\n",$self->{INSTNAME},$sql);
    my $starttime=time();
    $self->{TIMINGS}=0.0;
    $self->{COUNT}=0;
    my $dataref=$self->{DB}->query($dataset->{data_database},$dataset->{data_table},
                                    {
                                      type => "get_execute_hash",
                                      sql => $sql,
                                      execute => sub {
                                                      $self->collect_data_for_file_json_single_file(@_,$ds,
                                                                                                    $col_convert_by_col,
                                                                                                    $col_to_group);
                                                      }
                                    });
    # printf("%s process_data_query_and_save_json: executed single JSON query in %7.4fs process in %7.4fs (#%d)\n",$self->{INSTNAME},
    #         time()-$starttime,$self->{TIMINGS},$self->{COUNT});
    
    $starttime=time();
    my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;
    $self->write_data_to_file_json($shortfile,$ds,$json_single_entry,$dataset);
    # printf("%s process_data_query_and_save_json: executed single JSON generation in %7.4fs\n",$self->{INSTNAME},time()-$starttime);
  }
  # printf("%s process_data_query_and_save_json:  sql=%s\n",$self->{INSTNAME},$sql);  
}

sub write_data_to_file_json {
  my $self = shift;
  my ($file,$ds,$json_single_entry,$dataset)=@_;

  my $openparm;
  if($file=~/\.gz$/) {
    $openparm="| gzip -c > $self->{OUTDIR}/$file";
  } else {
    $openparm="> $self->{OUTDIR}/$file";
  }
  &check_folder("$self->{OUTDIR}/$file");
  if (!($self->{SAVE_LASTFH}->open($openparm))) {
    if(0) {
      print STDERR "LLmonDB:    ERROR: cannot open $self->{OUTDIR}/$file\n";
      die "stop cannot open $file";
      return();
    }
    print STDERR "LLmonDB:    WARNING: cannot open $self->{OUTDIR}/$file, skipping...\n";
    return();
  }
  my $starttime=time();
  my $save_ds=$self->{SAVE_DS};
  my $numentries=scalar @{$self->{SAVE_DS}};
  if($json_single_entry) {
    if( $numentries==1 ) {
      $save_ds=$self->{SAVE_DS}->[0];
    }
  }
  $self->{SAVE_LASTFH}->print($self->encode_JSON($save_ds));
  $self->{SAVE_DS}=[];
  $self->{SAVE_LASTFH}->close();

  # update last ts stored to file
  $ds->{$file}->{dataset}=$file;
  $ds->{$file}->{status}=FSTATUS_EXISTS;
  $ds->{$file}->{name}=$dataset->{name} if(!exists($ds->{$file}->{name}));
  $ds->{$file}->{ukey}=-1 if(!exists($ds->{$file}->{ukey}));
  $ds->{$file}->{checksum}=0 if(!exists($ds->{$file}->{checksum}));
  $ds->{$file}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  $ds->{$file}->{mts}=$self->{CURRENTTS}; # last change ts
  
  $self->{COUNT_OP_NEW_FILE}++;

  # printf("%s write_data_to_file_json: %5d entries in %8.3fs to file=%s\n",$self->{INSTNAME},$numentries,time()-$starttime,$file) if($file=~/three/);
  return();
}

sub collect_data_for_file_json_single_file {
  my $self = shift;
  my($dataref,$ds,$col_convert,$col_to_group)=@_;

  my $starttime=time();

  # convert data
  while ( my ($col, $func) = each(%{$col_convert}) ) {
    # print STDERR "collect_data_for_file_json_single_file: no data for col $col\n" if(!exists($dataref->{$col}));
    # print STDERR "collect_data_for_file_json_single_file: data empty for col $col\n" if(!$dataref->{$col});
    $dataref->{$col}=&{$func}($dataref->{$col},$self);
    if(!defined($dataref->{$col})) {
      print STDERR "$self->{INSTNAME}\[".(caller(1))[3]."\]\[".(caller(0))[3]."\] ERROR: collect_data_for_file_json_single_file: error in data: undef, $ds, $col\n";
    }
  }
  
  # save data
  if(defined($col_to_group)) {
    my $ndataref;
    while ( my ($col, $group) = each(%{$col_to_group}) ) {
      $ndataref->{$group}->{$col}=$dataref->{$col};
    }
    push(@{$self->{SAVE_DS}},$ndataref);
  } else {
    push(@{$self->{SAVE_DS}},$dataref);
  }
  $self->{COUNT_OP_WRITE_LINE}++;
  $self->{TIMINGS}+=time()-$starttime;
  $self->{COUNT}++;
}

sub collect_data_for_file_json_multi_file {
  my $self = shift;
  my($dataref,$ds,$skeylistref,$skey_to_filenameref,$col_convert,$col_to_group,$json_single_entry,$dataset)=@_;

  my @skeys;
  foreach my $v (@{$skeylistref}) {
    push(@skeys,$dataref->{$v});
  }
  my $skey=join(":",@skeys);
  if(exists($skey_to_filenameref->{$skey})) {
    my $file=$skey_to_filenameref->{$skey};
    if( $self->{SAVE_LASTFILE} ne $file ) {
      $self->write_data_to_file_json($self->{SAVE_LASTFILE},$ds,$json_single_entry) if($self->{SAVE_LASTFILE} ne "---");
      $self->{SAVE_LASTFILE}=$file;
    }
  } else {
    print "collect_data_for_file_json_multi_file ($dataset->{name}): WARNING $skey not in known files, skipping entry\n";
    return();
  }
  
  # convert data
  while ( my ($col, $func) = each(%{$col_convert}) ) {
    if($dataref->{$col}=~/^\s*$/) {
      print STDERR "TMPDEB: no val for column $col ($dataset->{name})\n";
    }
    $dataref->{$col}=&{$func}($dataref->{$col},$self);
  }
  
  # save data
  if(defined($col_to_group)) {
    my $ndataref;
    while ( my ($col, $group) = each(%{$col_to_group}) ) {
      $ndataref->{$group}->{$col}=$dataref->{$col};
    }
    push(@{$self->{SAVE_DS}},$ndataref);
  } else {
    push(@{$self->{SAVE_DS}},$dataref);
  }
  $self->{COUNT_OP_WRITE_LINE}++;
}

sub encode_JSON {
  my $self = shift;
  my $data = shift;
  my $json_data;

  return("") if(!$data);
  
  if ( (ref($data) ne "HASH") && ref($data) ne "ARRAY") {
    print "$self->{INSTNAME} data is no hash or array $data.",caller(),"ref=",ref($data),"\n";
    # print Dumper($data);
  }
    
  if(!exists($self->{JSONOBJ})) {
    if(!$debugJSON) {
      $self->{JSONOBJ} = JSON->new();
    } else {
      my $jobj=JSON->new();
      print "$self->{INSTNAME} JSON VERSION: ",$jobj->VERSION,"  [USE PRETTY PRINT]\n";
      $self->{JSONOBJ} = $jobj->pretty();
      $self->{JSONOBJ} = $jobj->canonical(1);
    }
  }
  
  $json_data   = $self->{JSONOBJ}->encode( $data );
  return($json_data);
}

1;
