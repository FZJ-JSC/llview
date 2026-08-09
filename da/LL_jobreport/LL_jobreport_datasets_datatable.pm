# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

package LML_jobreport;

my $VERSION = '$Revision: 1.00 $';

use strict;
use Data::Dumper;
use Time::Local;
use Time::HiRes qw ( time );

use lib "$FindBin::RealBin/../lib";
use LML_da_util qw( check_folder );

# Processes the dataset configuration to generate ag-Grid HTML and JavaScript templates.
# 
# Column definitions provided in the dataset are parsed, and proper JavaScript structures 
# are constructed. Properties translated by YAML parsers (such as booleans converted to 0 or 1) 
# are sanitized and correctly formatted. Appropriate filters are automatically injected 
# based on the specified cell data types.
# 
# Arguments:
#   $self      - The object instance.
#   $DB        - The database connection object.
#   $dataset   - Hash reference containing dataset configurations (e.g., columns, filepaths).
#   $varsetref - Hash reference containing variables to be substituted in the file path.
# 
# Returns:
#   void
# 
sub process_dataset_datatable {
  my $self = shift;
  my ( $DB, $dataset, $varsetref ) = @_;
  
  my $file = $dataset->{filepath};
  my $column_definitions = "";

  # Placeholder variables within the file path are replaced with their assigned values
  while ( my ( $key, $value ) = each( %{$varsetref} ) ) {
    $file =~ s/\$\{$key\}/$value/gs;
    $file =~ s/\$$key/$value/gs;
  }

  # print "process_dataset_datatable: file=$file\n";

  # The current status of the datasets is retrieved from the database
  $self->get_datasetstat_from_DB($dataset->{stat_database}, $dataset->{stat_table});

  my $ds = $self->{DATASETSTAT}->{ $dataset->{stat_database} }->{ $dataset->{stat_table} };

  # The dataset columns are scanned and initialized for processing
  my $columns = $dataset->{columns};
  my ( $data, $data_thead, $data_tfilter ) = ( "", "", "" );

  # my $theme = exists($dataset->{'ag-grid-theme'}) ? "ag-theme-".$dataset->{'ag-grid-theme'} : "ag-theme-balham";
  # my $grid .= "<div id=\"myGrid\" style=\"height: 100%;\" class=\"$theme\"></div>\n";
  
  # The HTML container for the grid is constructed
  my $grid .= "<div id=\"myGrid\" style=\"height: 100%;\"></div>\n";
  
  # A mapping of known ag-Grid boolean properties is defined to safely intercept and format YAML translations
  my %bool_keys = map { $_ => 1 } qw(
    sortable resizable hide editable suppressMenu floatingFilter 
    suppressFloatingFilterButton suppressHeaderMenuButton suppressMovable 
    checkboxSelection headerCheckboxSelection unSortIcon wrapText autoHeight
  );

  # my (%groups);
  my $coldefs .= "<script>\n";
  $coldefs .= "  view.columnDefs = [ \n";
  
  # Each entry within the column definitions list is iterated over
  foreach my $colref ( @{$columns} ) { 
    
    # A new column or column group is started
    $coldefs .= "    {\n";

    while ((my $key, my $ele) = each %{$colref}) {
      
      # Hash references, such as cellStyle, are manually serialized into JavaScript objects
      if (ref($ele) eq 'HASH') {
        my $str = "{ ";
        foreach my $k (keys %$ele) {
          $str .= "'$k': \"$ele->{$k}\", ";
        }
        $str =~ s/, $/ /; # Trailing commas are removed
        $str .= "}";
        $ele = $str;
      }

      if ($key eq 'children') {
        
        # When the key is 'children', it indicates a column group. 
        # The nested sub-columns are looped over and processed.
        $coldefs .= "      $key: [\n";
        foreach my $subele ( @{$ele} ) {
          
          # A child column definition is started
          $coldefs .= "        {\n";
          while ((my $subkey, my $value) = each %{$subele}) {
            
            # Child hash references are manually serialized
            if (ref($value) eq 'HASH') {
              my $str = "{ ";
              foreach my $k (keys %$value) {
                $str .= "'$k': \"$value->{$k}\", ";
              }
              $str =~ s/, $/ /; 
              $str .= "}";
              $value = $str;
            }

            # Boolean properties translated by YAML parsers to integers or empty strings are safely restored
            if ($bool_keys{$subkey} && defined $value) {
              $value = 'false' if $value eq '0' || $value eq '' || lc($value) eq 'false';
              $value = 'true'  if $value eq '1' || lc($value) eq 'true';
            }

            # Values are evaluated to determine if quotes should be omitted.
            # Nulls, JavaScript functions, object strings, specific unquoted keys, booleans, and valid numbers are left unquoted.
            if (!defined $value || lc($value) eq 'null') {
              $coldefs .= "          $subkey: null,\n";
            } elsif (($value =~/\(.*\)\s=>/) || ($value=~/^{.*}$/) || ($subkey=~'filterParams') || ($subkey=~'floatingFilterComponent') || ($value =~ /^(true|false|\-?(?:0|[1-9]\d*)(?:\.\d+)?)$/)) {
              $coldefs .= "          $subkey: $value,\n";
            } else {
              $coldefs .= "          $subkey: \"$value\",\n";
            }
            
            # Filter configurations are automatically injected when specific cell data types are detected
            if ($subkey eq "cellDataType" &&  $value eq "number") {
              $coldefs .= "          filter: \"agNumberColumnFilter\",\n";
              $coldefs .= "          filterParams: numberFilterParams,\n";
              $coldefs .= "          floatingFilterComponent: NumberFloatingFilterComponent,\n";
            } elsif ($subkey eq "cellDataType" &&  $value eq "date") {
              $coldefs .= "          filter: \"agDateColumnFilter\",\n";
              $coldefs .= "          filterParams: dateFilterParams,\n";
              # $coldefs .= "          floatingFilterComponent: NumberFloatingFilterComponent,\n";
            }
          }
          $coldefs .= "        },\n";
          # The child column definition is ended
        }
        $coldefs .= "      ],\n";
        
      } else {
        
        # Top-level booleans are safely restored
        if ($bool_keys{$key} && defined $ele) {
          $ele = 'false' if $ele eq '0' || $ele eq '' || lc($ele) eq 'false';
          $ele = 'true'  if $ele eq '1' || lc($ele) eq 'true';
        }

        # Elements are checked to ensure appropriate quotation marks are applied or omitted
        if (!defined $ele || lc($ele) eq 'null') {
          $coldefs .= "      $key: null,\n";
        } elsif (($ele =~/\(.*\)\s=>/) || ($ele =~ /^{.*}$/) || ($key=~'filterParams') || ($key=~'floatingFilterComponent') || ($ele =~ /^(true|false|\-?(?:0|[1-9]\d*)(?:\.\d+)?)$/)) {
          $coldefs .= "      $key: $ele,\n";
        } else {
          $coldefs .= "      $key: \"$ele\",\n";
        }

        # Top-level filters are automatically added for numerical configurations
        if ($key eq "cellDataType" &&  $ele eq "number") {
          $coldefs .= "        filter: \"agNumberColumnFilter\",\n";
          $coldefs .= "        filterParams: numberFilterParams,\n";
          $coldefs .= "        floatingFilterComponent: NumberFloatingFilterComponent,\n";
        }
      }
    }
    
    # The column or column group is ended
    $coldefs .= "    },\n";
  }
  $coldefs .= "  ]\n";
  $coldefs .= "</script>\n";

  $data .= $grid;
  $data .= $coldefs;

  # The generated HTML and JavaScript code is written to the specified file
  my $fh = IO::File->new();
  &check_folder("$file");
  if ( !( $fh->open("> $file") ) ) {
    print STDERR "LLmonDB:    ERROR, cannot open $file\n";
    die "stop";
    return ();
  }
  $fh->print($data);
  $fh->close();

  # The generated file is registered and formatted for the database
  my $shortfile = $file;
  $shortfile =~ s/$self->{OUTDIR}\///s;
  
  # The last timestamp and metadata are updated and stored
  $ds->{$shortfile}->{dataset} = $shortfile;
  $ds->{$shortfile}->{name} = $dataset->{name};
  $ds->{$shortfile}->{ukey} = -1;
  $ds->{$shortfile}->{status} = FSTATUS_EXISTS;
  $ds->{$shortfile}->{checksum} = 0;
  $ds->{$shortfile}->{lastts_saved} = $self->{CURRENTTS}; # Set due to lack of time dependent data
  $ds->{$shortfile}->{mts} = $self->{CURRENTTS}; # The last change timestamp is recorded

  # The status of the datasets is saved back into the database
  $self->save_datasetstat_in_DB($dataset->{stat_database}, $dataset->{stat_table});
}

1;
