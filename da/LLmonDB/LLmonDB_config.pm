# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Wolfgang Frings (Forschungszentrum Juelich GmbH) 

package LLmonDB_config;

my $VERSION='$Revision: 1.00 $';
my $debug=0;

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );
use IO::File;
use YAML::XS;
use File::Spec;
#use YAML::Tiny;
use JSON;

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub new {
  my $self    = {};
  my $proto   = shift;
  my $class   = ref($proto) || $proto;
  my $opt_configfile = shift;
  my $verbose = shift;

  printf("  LLmonDB_config: new %s\n",ref($proto)) if($debug>=3);

  $self->{CONFIGFILE}  = File::Spec->rel2abs($opt_configfile);
  # print "TMPDEB: $opt_configfile -> $self->{CONFIGFILE}\n";
  my($v,$configpath,$cfile)=File::Spec->splitpath($opt_configfile);
  # print "TMPDEB: $self->{CONFIGFILE} -> $configpath,$cfile\n";

  $self->{VERBOSE}     = $verbose; 
  $self->{CFILE}       = $cfile;
  $self->{CONFIGPATH}  = $configpath;
  
  $self->{RAWCONFIGDATA}   = "";
  $self->{CONFIGDATA}      = {};
  $self->{FILECACHE}       = {};
  $self->{SEARCHPATH}      = [];
  
  bless $self, $class;

  return $self;
}


sub read_configfile {
  my($self) = shift;
  my($filename,$orig_filename,$depth,$prespace) = @_;

  # my $data=$prespace."# included from $filename\n";
  my $data="";

  if(exists($self->{FILECACHE}->{$filename})) {
    $data.=$self->read_configfile_from_cache($filename,$orig_filename,$depth,$prespace);
  } else {
    $data.=$self->read_configfile_from_file($filename,$orig_filename,$depth,$prespace);
  }
  
  return($data);
}

sub read_configfile_from_file {
  my($self) = shift;
  my($filename,$orig_filename,$depth,$prespace) = @_;

  if($self->{VERBOSE}) {
    printf("LLmonDB_config: %s reading %s\n"," "x($depth*3),$filename) if($depth<=1);
  }
  if($debug) {
    printf("LLmonDB_config: %s reading %s\n"," "x($depth*3),$filename);
  }

  # get location of file, needed for includes
  my(undef,$configpath,undef)=File::Spec->splitpath($filename);

  my $data="";

  my $fh = IO::File->new();
  &check_folder("$filename");
  if ($fh->open("< $filename")) {
    while(my $line=<$fh>) {
      push(@{$self->{FILECACHE}->{$filename}},$line) if($depth>1);
      if($line=~/^(\s*)%include /) {
        $data.=$self->process_include($filename,$orig_filename,$line,$depth,$prespace);
      } elsif($line=~/^(\s*)%includedir /) {
        $self->process_includedir($filename,$orig_filename,$line);
      } else {
        $data.=$prespace.$line;
      }
    }
    $fh->close;
  } else {
    print STDERR "LLmonDB_config: ERROR, cannot open $filename\n";
  }
  
  return($data);
}

sub read_configfile_from_cache {
  my($self) = shift;
  my($filename,$orig_filename,$depth,$prespace) = @_;

  printf("LLmonDB_config: %s reading %s from cache\n"," "x($depth*3),$filename) if($debug);

  my $data="";
  foreach my $line (@{$self->{FILECACHE}->{$filename}}) {
    if($line=~/^(\s*)%include /) {
      $data.=$self->process_include($filename,$orig_filename,$line,$depth,$prespace);
    } elsif($line=~/^(\s*)%includedir /) {
      $self->process_includedir($filename,$orig_filename,$line);
    } else {
      $data.=$prespace.$line;
    }
  }
  
  return($data);
}

sub process_include {
  my($self) = shift;
  my($filename,$orig_filename,$line,$depth,$prespace) = @_;
  my $data="";

  chomp($line);
  return($data) if($line!~/^(\s*)%include \"([^\"]+)\"/);
  
  my $prespaceinc=$1;
  my $ifn=$2;
  
  # get location of file in orig location, needed for includes
  my(undef,$orig_configpath,undef)=File::Spec->splitpath($orig_filename);
  my $orig_infile=File::Spec->rel2abs( $ifn, $orig_configpath );
  printf("process_include ORIG  -> %-50s\n",$orig_infile) if($debug);

  # return($data);
  
  my $found=0;
  foreach my $ref (@{$self->{SEARCHPATH}}) {
    my $infile=$orig_infile;
    $infile=~s/$ref->{from}/$ref->{to}/s;
    printf("process_include TEST  -> %-50s  -> -%20s ",$ifn,$infile)  if($debug);
    $found=0;
    if(exists($self->{FILECACHE}->{$infile})) {
      $found=1;
    } elsif(-f $infile) {
      $found=1;
    }
    if($found) {
      printf(" FOUND\n") if($debug);
      $data.=$self->read_configfile($infile,$orig_infile,$depth+1,$prespace.$prespaceinc);
      last;
    } else {
      printf(" NO\n") if($debug);
    }
  }
  if(!$found) {
    printf(STDERR "ERROR: file not found in any includedir: %-50s\n",$ifn);
  }

  return($data);
}

sub process_includedir {
  my($self) = shift;
  my($filename,$orig_filename,$line) = @_;
  my $data="";
  
  chomp($line);

  # get location of file, needed for includes
  my(undef,$configpath,undef)=File::Spec->splitpath($filename);

  return($data) if($line!~/^\s*%includedir \"([^\"]+)\"/);
  
  my $idir=$1;
  my $indir=File::Spec->rel2abs( $idir, $configpath );
  $indir.="/" if($indir!~/\/$/);
  my($ref);
  $ref->{from}=$configpath;
  $ref->{to}=$indir;
  push(@{$self->{SEARCHPATH}},$ref);
  print "process_includedir: $configpath -> $indir\n"  if($debug);
  
  return($data);
}

sub load_config {
  my($self) = shift;
  
  if(!$self->{CONFIGFILE}) {
    print STDERR "LLmonDB_config: ERROR, load_config no configfile specified\n";
    return(0); 
  } 
  if(! -f $self->{CONFIGFILE}) {
    print STDERR "LLmonDB_config: ERROR, load_config configfile $self->{CONFIGFILE} not found\n";
    return(0); 
  }

  #  init search path
  my(undef,$configpath,undef)=File::Spec->splitpath($self->{CONFIGFILE});
  my $ref;
  $ref->{from}=$configpath;$ref->{to}=$configpath;
  push(@{$self->{SEARCHPATH}},$ref);
  
  my $data=$self->read_configfile($self->{CONFIGFILE},$self->{CONFIGFILE},1,"");
  $self->{RAWCONFIGDATA}=$data;
  
  if($ENV{LLMONDB_PRINT_CONFIG_TO_DIR}) {
    my $cfile=$self->{CFILE};$cfile=~s/\.yaml$//s;
    my $outfile=File::Spec->catfile($ENV{LLMONDB_PRINT_CONFIG_TO_DIR},"${cfile}_raw.yaml");
    print "LLmonDB_config: LLMONDB_PRINT_CONFIG_TO_DIR: write $outfile\n";
    $self->print_to($outfile);
  }
  
  # $self->{CONFIGDATA}=YAML::XS::LoadFile( $self->{CONFIGFILE});
  $YAML::XS::Boolean = "JSON::PP";
  $self->{CONFIGDATA}=YAML::XS::Load( $data );

  if($ENV{LLMONDB_DUMP_CONFIG_TO_DIR}) {
    my $cfile=$self->{CFILE};$cfile=~s/\.yaml$//s;
    my $outfile=File::Spec->catfile($ENV{LLMONDB_DUMP_CONFIG_TO_DIR},"${cfile}_raw.dump");
    print "LLmonDB_config: LLMONDB_DUMP_CONFIG_TO_DIR: write $outfile\n";
    $self->dump_to($outfile);
  }

  if($ENV{LLMONDB_DUMP_CONFIG_TO_JSON}) {
    my $jsonfile = $ENV{LLMONDB_DUMP_CONFIG_TO_JSON};
    my $json_data = encode_json( $self->{CONFIGDATA} );
    open(OUT,"> $jsonfile") or die("cannot open $jsonfile for writing, exiting...");
    print OUT $json_data;
    close(OUT);
  }
  if($ENV{LLMONDB_DUMP_CONFIG_TO_YAML}) {
    my $yamlfile = $ENV{LLMONDB_DUMP_CONFIG_TO_YAML};
    open(OUT,"> $yamlfile") or die("cannot open $yamlfile for writing, exiting...");
    print OUT YAML::XS::Dump($self->{CONFIGDATA});
    close(OUT);
  }

  return(1);
}

sub print_to {
  my($self) = shift;
  my($outfile)=@_;
  
  if(defined($outfile)) {
    if($outfile eq "stdout") {
      print "LLmonDB_config: print full config file:\n";
      print $self->{RAWCONFIGDATA};
    } else {
      open(OUT,"> $outfile") or die("cannot open $outfile for writing, exiting...");
      print OUT $self->{RAWCONFIGDATA};
      close(OUT);
    }
  }
}

sub dump_to {
  my($self) = shift;
  my($outfile,$depth)=@_;
  
  if(defined($depth)) {
    $Data::Dumper::Maxdepth=$depth;
  }
  if(defined($outfile)) {
    if($outfile eq "stdout") {
      print "LLmonDB_config: print full config file:\n";
      print Dumper($self->{CONFIGDATA});
    } else {
      open(OUT,"> $outfile") or die("cannot open $outfile for writing, exiting...");
      print OUT Dumper($self->{CONFIGDATA});
      close(OUT);
    }
  }
  if(defined($depth)) {
    $Data::Dumper::Maxdepth=0;
  }
}

  
sub get_contents {
  my($self) = shift;

  return($self->{CONFIGDATA});
}

sub get_columns_defs {
  my($self) = shift;
  my($db,$table)=@_; 
  my(@collist,$colhash,$colref,$retdata,$tableref);
  my @cols=();

  foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
    $tableref=$t->{table};
    last if($tableref->{name} eq $table);
  }

  foreach $colref (@{$tableref->{columns}}) {
    my $name=$colref->{name};
    my $type=$colref->{type};
    if(exists($self->{CONFIGDATA}->{datatypes}->{$type})) {
      if(exists($self->{CONFIGDATA}->{datatypes}->{$type}->{sql})) {
        my $sql=$self->{CONFIGDATA}->{datatypes}->{$type}->{sql};
        # print "TMPDEB: '$name' -> '$sql'\n";
        $sql=~s/^\s//gs;
        $sql=~s/\s\s/ /gs;
        $colhash->{$name}->{name}=$name;
        $colhash->{$name}->{sql}=$sql;
        push( @collist, $name);
      } else {
        print STDERR "LLmonDB_config: WARNING: datatype contains no sql declaration for $type, skipping column\n";
      }
    } else {
      print STDERR "LLmonDB_config: WARNING: no datatype found for $type, skipping column\n";
    }
  }
  $retdata->{collist}=\@collist;
  $retdata->{coldata}=$colhash;
  return($retdata);
}


# returns for a givrn table a list of index lists
# (data structure of result is a list of list)
sub get_index_columns {
  my($self) = shift;
  my($db,$table)=@_;
  my $result=[]; 
  my $tableref;
  
  foreach my $t (@{$self->{CONFIGDATA}->{databases}->{$db}->{tables}}) {
    $tableref=$t->{table};
    last if($tableref->{name} eq $table);
  }

  return($result) if(!exists($tableref->{options}));
  return($result) if(!exists($tableref->{options}->{index}));

  if(ref($tableref->{options}->{index})) {
      if(ref($tableref->{options}->{index}) eq "ARRAY") {
        foreach my $il (@{$tableref->{options}->{index}}) {
          push(@{$result},[split(/\s*,\s*/,$il)]);
        }
      } else {
        print STDERR "LLmonDB_config: WARNING: unknown index data structure for table $db, $table\n";
      }
  } else {
      push(@{$result},[split(/\s*,\s*/,$tableref->{options}->{index})]);
  }
  return($result);
}

1;
