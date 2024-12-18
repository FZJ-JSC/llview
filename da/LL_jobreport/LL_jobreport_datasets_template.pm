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

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

sub process_dataset_template {
  my $self = shift;
  my($DB,$dataset,$varsetref)=@_;
  my $file=$dataset->{filepath};

  while ( my ($key, $value) = each(%{$varsetref}) ) {
    $file=~s/\$\{$key\}/$value/gs;	$file=~s/\$$key/$value/gs;
  }
  # print "process_dataset_template: file=$file\n";

  # get status of datasets from DB
  $self->get_datasetstat_from_DB($dataset->{stat_database},$dataset->{stat_table});

  my $ds=$self->{DATASETSTAT}->{$dataset->{stat_database}}->{$dataset->{stat_table}};

  # scan columns
  my $columns=$dataset->{columns};
  my ($data,$data_thead,$data_tfilter,$data_tbody)=("","","","");
  foreach my $colref (@{$columns}) {
    my $name=$colref->{name};
    
    # check attributes
    my $csort="N";	    $csort=$colref->{sort} if(exists($colref->{sort}));
    my $cgroup="";
    if(exists($colref->{group})) {
      $colref->{group} =~ s/\s/_/gs;
      $cgroup="group_".$colref->{group};
    }
    my $ctitle=$name;   $ctitle=$colref->{title} if(exists($colref->{title}));
    my $cdesc=$name;    $cdesc=$colref->{desc} if(exists($colref->{desc}));
    my $cformat="text-right"; $cformat=$colref->{format} if(exists($colref->{format}));
    my $cellcolor="";   $cellcolor="{{cell_color ".$colref->{cell_color}."}}; " if(exists($colref->{cell_color}));
    my $bg_color_map=""; $bg_color_map="{{cell_color ".$colref->{bg_color_map}."}}; " if(exists($colref->{bg_color_map}));
    my $fg_color="";    $fg_color="color: {{{".$colref->{fg_color}."}}}; " if(exists($colref->{fg_color}));
    my $style="";       $style=$colref->{style}."; " if(exists($colref->{style}));
    my $cdataformat=""; $cdataformat=$colref->{data_format} if(exists($colref->{data_format}));
    my $cdatapre="";    $cdatapre=$colref->{data_pre}." " if(exists($colref->{data_pre}));
    my $cdatapost="";   $cdatapost=" ".$colref->{data_post} if(exists($colref->{data_post}));
    my $noheader=0;     $noheader=$colref->{noheader} if(exists($colref->{noheader}));
    # print "TMPDEB: column: $name $csort $cgroup\n";
    
    #  header
    $data_thead.="              ";
    if(!$noheader) {
      # If HEADER is to be added
      # Header row:
      $data_thead.="<th onclick=\"sort_table(this,'$csort')\"";
      $data_thead.=" class=\"text-center clickable $cgroup\"";
      $data_thead.=" aria-label=\"$ctitle\" title=\"$cdesc\">";
      $data_thead.="$ctitle";
      $data_thead.="<span class=\"fa\" aria-hidden=\"true\"></span></th>\n";	
    } else {
      $data_thead.="<th class=\"$cgroup\" aria-label=\"$ctitle\" aria-hidden=\"true\" title=\"$cdesc\"></th>\n";	
    }
    #  filter
    $data_tfilter.="              ";
    if(!$noheader) {
      my $ctitle_escaped = $ctitle;
      $ctitle_escaped =~ s/\s/_/gs;
      $data_tfilter.="<th><input class=\"text-center\" type=\"text\" placeholder=\"filter\" id=\"filter_${ctitle_escaped}\"/></th>\n";
    } else {
      $data_tfilter.="<th></th>\n";
    }

    # body
    my $styles=${style}.${cellcolor}.${bg_color_map}.${fg_color};
    $styles=(${styles})?"style=\"${styles}\"":"";
    $data_tbody.="              ";
    $data_tbody.="<td ${styles} class=\"${cformat}\">";
    $data_tbody.="<span>" if($bg_color_map || $cellcolor);
    # When data_format is given, it can support different helper functions separated by comma
    # They are applied from right (first) to left (last). For the Handlebars, it must have the format
    # {{function3 (function2 (function1 <argument>)))}}
    my $finalformat = "$cdatapre$name$cdatapost";
    if ($cdataformat) {
      my @dataformats = reverse split(',', $cdataformat);
      foreach my $dataformat (@dataformats) {
        $finalformat = "(".$dataformat." ".$finalformat.")";
      }
      $finalformat = substr($finalformat, 1, -1);
    }
    $data_tbody.="{{{$finalformat}}}";
    # $data_tbody.="{{{$cdataformat$cdatapre$name$cdatapost}}}";
    $data_tbody.="</span>" if($bg_color_map || $cellcolor);
    $data_tbody.="</td>\n";
  }

  # check general attributes
  my $pre_table="";
  if(exists($dataset->{pretable})) {
    $pre_table=$dataset->{pretable};
  }

  # build html code
  $data.=$pre_table;
  $data.="<table class=\"table table-striped table-hover table-bordered table-sm\">\n";
  $data.="    <thead>\n";
  $data.="        <tr>\n";
  $data.=$data_thead;
  $data.="        </tr>\n";
  $data.="        <tr class=\"filter\">\n";
  $data.=$data_tfilter;
  $data.= "       </tr>\n";
  $data.="    </thead>\n";
  $data.="    <tbody>\n";
  $data.="        {{#each this}}\n";
  $data.="        <tr>\n";
  $data.=$data_tbody;
  $data.="        </tr>\n";
  $data.="        {{/each}}\n";
  $data.="    </tbody>\n";
  $data.="</table>\n";

  # print HTML code
  my $fh = IO::File->new();
  &check_folder("$file");
  if (!($fh->open("> $file"))) {
    print STDERR "LLmonDB:    ERROR, cannot open $file\n";
    die "stop";
    return();
  }
  $fh->print($data); 
  $fh->close();

  # register file
  my $shortfile=$file;$shortfile=~s/$self->{OUTDIR}\///s;
  # update last ts stored to file
  $ds->{$shortfile}->{dataset}=$shortfile;
  $ds->{$shortfile}->{name}=$dataset->{name};
  $ds->{$shortfile}->{ukey}=-1;
  $ds->{$shortfile}->{status}=FSTATUS_EXISTS;
  $ds->{$shortfile}->{checksum}=0;
  $ds->{$shortfile}->{lastts_saved}=$self->{CURRENTTS}; # due to lack of time dependent data
  $ds->{$shortfile}->{mts}=$self->{CURRENTTS}; # last change ts

  # save status of datasets in DB 
  $self->save_datasetstat_in_DB($dataset->{stat_database},$dataset->{stat_table});

}

1;
