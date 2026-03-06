# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LML_jobreport;

my $VERSION='$Revision: 1.00 $';

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use LL_jobreport_datasets_constants;

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub process_data_query_and_save_access_cache {
  my $self = shift;
  my($dataset,$varsetref)=@_;

  #  required vars
  my $file=$dataset->{filepath};

  my $access_single_entry=0;
  if(exists($dataset->{access_type})) {
    $access_single_entry=1 if($dataset->{access_type} eq "single_entry");
  }
  
  # table cache
  my $table_cache="";
  if(exists($dataset->{table_cache})) {
    $table_cache=$dataset->{table_cache};
  } else {
    print STDERR "LLmonDB:    ERROR, table_cache not specified\n";
    return();
  }

  # pre-process column_convert
  my $col_convert_by_col;
  if(exists($dataset->{column_convert})) {
    $col_convert_by_col=$self->{LL_CONVERT}->init_column_convert_mapping($dataset->{column_convert});
  }
  
  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file=~s/\$\{$key\}/$value/gs;	$file=~s/\$$key/$value/gs;
    $value=~s/^0+//gs; # remove leading zeros
  }

  if(!exists($self->{TABLECACHE}->{$table_cache})) {
    $self->process_data_query_cache_table_access($table_cache,$dataset,$varsetref);
  }

  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};

  # generate multiple files from one query?
  if(exists($dataset->{column_filemap})) {
    # printf("%s process_data_query_and_save_access_cache:  create multiple files=%s\n",$self->{INSTNAME},$file);


    # search for entries to be stored
    my $skeylistref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{col_list};
    my $skey_to_filenameref=$self->{DATASETSTAT_MAP}->{$dataset->{name}}->{skey_to_filename};
    my $dataref;

    # print Dumper($skeylistref);
    # print Dumper($skey_to_filenameref);
    
    my $starttime=time();
    foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{data}}) {
      # map entry to file
      my @skeys;
      foreach my $v (@{$skeylistref}) {
        push(@skeys,$ref->{$v});
      }
      my $skey=join(":",@skeys);
      
      if(exists($skey_to_filenameref->{$skey})) {
        my $file=$skey_to_filenameref->{$skey};
      
        push(@{$dataref->{$file}},$ref);
        $self->{COUNT_OP_WRITE_LINE}++;
      } else {
        # print STDERR "process_data_query_and_save_access_cache ($dataset->{name}): WARNING $skey not in known files, skipping entry\n";
      }
    }
    # printf("%s process_data_query_cache_table: check entries in %7.4fs (%d files)\n",
    #         $self->{INSTNAME},time()-$starttime, scalar keys(%{$dataref})
    #       );

    # write files
    while ( my ($file, $dataref_per_file) = each(%{$dataref}) ) {
      $self->register_data_for_file_access_cache($table_cache,"$self->{OUTDIR}/$file",$ds,$dataref_per_file,$col_convert_by_col);
    }
  } else { # only a single file
  # search for entries to be stored
  my $dataref;
  foreach my $ref (@{$self->{TABLECACHE}->{$table_cache}->{data}}) {
    push(@{$dataref},$ref);
    $self->{COUNT_OP_WRITE_LINE}++;
  }
  
  $self->register_data_for_file_access_cache($table_cache,$file,$ds,$dataref,$col_convert_by_col);
  }
}

sub process_data_query_cache_table_access {
  my $self = shift;
  my($table_cache,$dataset,$varsetref)=@_;

  # create data structure
  $self->{TABLECACHE}->{$table_cache}->{dataset}=$dataset;
  my $tc=$self->{TABLECACHE}->{$table_cache};

  # replace variables in where attribute
  my $where="";
  if(exists($dataset->{sql_where})) {
    $where=$self->{DB}->replace_tsvars($dataset->{sql_where},$self->{CURRENTTS});
    while ( my ($key, $value) = each(%{$varsetref}) ) {
      $where=~s/\$\{$key\}/$value/gs;	$where=~s/\$$key/$value/gs;
    }
  }
  
  # check data tables and configure join if multiple tables are specified 
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
    $tc->{dataset}=undef;
    return;
  }
  foreach my $t (@datatables) {
    if(!exists($self->{TABLES}->{$dataset->{data_database}}->{$t})) {
      printf("$self->{INSTNAME}  --> WARNING: query table %s/%s not known, skipping dataset $dataset->{name}\n",$dataset->{data_database},$t);
      $tc->{dataset}=undef;
      return;
    }
  }
  # check columns and make column names unique if they are used for join 
  my (@cols,$format,$tscol,$cnt);
  
  my $cn=0;
  foreach my $col (split(/\s*,\s*/,$dataset->{columns})) {
    my ($c,$as);
    if($col=~/^(.*)->(.*)$/) {
      $c=$1;$as=" as $2";
    } else {
      $c=$col;$as="";
    }
    $tc->{coltonum}->{$c}=$cn;
    push(@cols,($c eq $joincol)?"D1.$c$as":"$c$as");
    $cn++;
  }

  # build and call the query 
  my $sql=sprintf("SELECT %s FROM %s %s",
                    join(",",@cols),
                    $from,
                    ($where)?"WHERE $where":""
                  );
  # printf("%s process_data_query_cache_table_access: sql=%s\n",$self->{INSTNAME},$sql);

  
  my $starttime=time();
  $tc->{data}=$self->{DB}->query($dataset->{data_database},$dataset->{data_table},
                                  {
                                    type => "get_arrayref_of_hashref",
                                    sql => $sql
                                  });
  # printf("%s process_data_query_cache_table_access: pre-cache table in %7.4fs (%d entries)\n",
  #         $self->{INSTNAME},time()-$starttime,  scalar @{$tc->{data}}
  #       );

  return();
}


sub process_data_query_drop_table_access {
  my $self = shift;
  my($table_cache,$dataset,$varsetref)=@_;

  # delete data structure
  delete($self->{TABLECACHE}->{$table_cache});
}


sub register_data_for_file_access_cache {
  my $self = shift;
  my($table_cache,$file,$ds,$dataref,$col_convert_by_col)=@_;

  # convert values
  my $ds_converted;
  my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;

  $self->{TABLECACHE}->{$table_cache}->{con_convert}->{$file}=$col_convert_by_col;
  $self->{TABLECACHE}->{$table_cache}->{fileop}->{$file}=$dataref;

  # update last ts stored to file
  $ds->{$shortfile}->{dataset}=$shortfile;
  $ds->{$shortfile}->{status}=FSTATUS_EXISTS;
  $ds->{$shortfile}->{checksum}=0;
  $ds->{$shortfile}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  $ds->{$shortfile}->{mts}=$self->{CURRENTTS}; # last change ts
  $self->{COUNT_OP_NEW_FILE}++;
  
  return();
}

sub write_data_to_file_access_cache {
  my $self = shift;
  my($table_cache,$part,$parlevel)=@_;

  my $starttime=time();
  my @filelist=(sort(keys(%{$self->{TABLECACHE}->{$table_cache}->{fileop}})));
  my $dataset=$self->{TABLECACHE}->{$table_cache}->{dataset};
  my $op=">";
  $op=">>" if(exists($dataset->{filemode}) && $dataset->{filemode} eq "append");
  my $numfiles=scalar @filelist;
  my $fcount=0;
  for(my $fnum=0;$fnum<$numfiles; $fnum++) {
    # do only the files for this part 
    next if(($fnum%$parlevel) != $part);
    $fcount++;
    
    my $file=$filelist[$fnum];
    
    my $fstarttime=time();
    
    # convert values
    my $count=0;
    my $data=$self->{TABLECACHE}->{$table_cache}->{fileop}->{$file};
    my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;

    my $datastr="";
    $datastr.=$dataset->{pre_rows}."\n" if(exists($dataset->{pre_rows}));
    foreach my $ref (@{$data}) {
      my @parms;
      foreach my $rcol (split(/\s,\s/,$dataset->{row_columns})) {
        push(@parms,$ref->{$rcol});
      }
      $datastr.=sprintf($dataset->{row_format},@parms);
      $count++;
    }
    $datastr.=$dataset->{post_rows}."\n" if(exists($dataset->{post_rows}));

    # Safely substitute ${VAR} format
    $datastr =~ s/\$\{(\w+)\}/
      if (defined $ENV{$1}) {
        $ENV{$1};
      } else {
        print STDERR "LLview WARNING: Environment variable \${$1} used in config but not defined. Substitution was not made.\n";
        "\${$1}";
      }
    /ge;
    # Safely substitute $ENV{VAR} format
    $datastr =~ s/\$ENV\{(\w+)\}/
      if (defined $ENV{$1}) {
        $ENV{$1};
      } else {
        print STDERR "LLview WARNING: Environment variable \$ENV{$1} used in config but not defined. Substitution was not made.\n";
        "\$ENV{$1}";
      }
    /ge;


    $datastr=~s/\\n/\n/gs;

    # write data to file
    my $fh = IO::File->new();
    my $openparm;
    if($file=~/\.gz$/) {
      $openparm="| gzip -c $op $file";
    } else {
      $openparm="$op $file";
    }
    &check_folder("$file");
    if (!($fh->open($openparm))) {
      printf(STDERR "%s write_data_to_file_access_cache:    WARNING: cannot open %s/%s, skipping...\n",$self->{INSTNAME},$self->{OUTDIR},$file);
      return();
    }
    
    $fh->print($datastr);
    $fh->close();

    # printf("%s write_data_to_file_access_cache: write data in %7.4fs (%d entries) $file\n",
    #         $self->{INSTNAME},time()-$fstarttime,  $count
    #       );
  }
  # printf("%s write_data_to_file_access_cache: %10s  write files %3d of %4d in %7.4fs\n",
  #         $self->{INSTNAME},  $table_cache, $fcount, $numfiles, time()-$starttime 
  #       );
  return();
}

#  only for flat txt files
sub process_data_query_and_save_access {
  my $self = shift;
  my($dataset,$varsetref)=@_;
  
  my $file=$dataset->{filepath};

  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file=~s/\$\{$key\}/$value/gs;	$file=~s/\$$key/$value/gs;
  }
  
  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};

  # generate multiple files from one query?
  if(exists($dataset->{columns})) {
    printf(STDERR "%s ERROR: process_data_query_and_save_access: data columns/rows not yet supported, leaving...\n",$self->{INSTNAME});
    return();
  }
  if(exists($dataset->{column_filemap})) {
    printf(STDERR "%s ERROR: process_data_query_and_save_access: multiple files not yet supported, leaving...\n",$self->{INSTNAME});
    return();
  }

  # build and call the query
  my $starttime=time();
  my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;
  my $op=">";
  $op=">>" if(exists($dataset->{filemode}) && $dataset->{filemode} eq "append");
  
  # write data to file
  my $fh = IO::File->new();
  my $openparm;
  if($file=~/\.gz$/) {
    $openparm="| gzip -c $op $file";
  } else {
    $openparm="$op $file";
  }
  &check_folder("$file");
  if (!($fh->open($openparm))) {
    printf(STDERR "%s write_data_to_file_access_cache:    WARNING: cannot open %s/%s, skipping...\n",$self->{INSTNAME},$self->{OUTDIR},$file);
    return();
  }

  my $datastr="";
  $datastr.=$dataset->{pre_rows}."\n"  if(exists($dataset->{pre_rows}));
  $datastr.=$dataset->{rows}."\n"      if(exists($dataset->{rows}));
  $datastr.=$dataset->{post_rows}."\n" if(exists($dataset->{post_rows}));

  # Safely substitute ${VAR} format
  $datastr =~ s/\$\{(\w+)\}/
    if (defined $ENV{$1}) {
      $ENV{$1};
    } else {
      print STDERR "LLview WARNING: Environment variable \${$1} used in config but not defined. Substitution was not made.\n";
      "\${$1}";
    }
  /ge;
  # Safely substitute $ENV{VAR} format
  $datastr =~ s/\$ENV\{(\w+)\}/
    if (defined $ENV{$1}) {
      $ENV{$1};
    } else {
      print STDERR "LLview WARNING: Environment variable \$ENV{$1} used in config but not defined. Substitution was not made.\n";
      "\$ENV{$1}";
    }
  /ge;


  $datastr=~s/\\n/\n/gs;

  $fh->print($datastr);
  $fh->close();

  # update last ts stored to file
  $ds->{$shortfile}->{dataset}=$shortfile;
  $ds->{$shortfile}->{name}=$dataset->{name};
  $ds->{$shortfile}->{ukey}=-1;
  $ds->{$shortfile}->{status}=FSTATUS_EXISTS;
  $ds->{$shortfile}->{checksum}=0;
  $ds->{$shortfile}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  $ds->{$shortfile}->{mts}=$self->{CURRENTTS}; # last change ts
  $self->{COUNT_OP_NEW_FILE}++;
  
  # printf("%s process_data_query_and_save_json: executed single access file generation in %7.4fs\n",$self->{INSTNAME},time()-$starttime);
  
}

1;
