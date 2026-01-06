#!/usr/bin/env python3
# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH)

import argparse
import logging
import time
import csv
import dateutil
import re
import os
import sys
import traceback
import math
import csv
import getpass
from urllib.parse import quote
import yaml
import json
import ast
from matplotlib import colormaps   # To loop over colors in footers
from matplotlib.colors import to_hex # Convert RGB to HEX
from itertools import count,cycle,product
from copy import deepcopy
from subprocess import check_output,run,PIPE
from typing import Dict, Any

# Optional: keyring
try:
  import keyring  # pyright: ignore [reportMissingImports]
except ImportError:
  keyring = None  # Set to None if not available

# Fixing/improving multiline output and strings with special characters of YAML dump
def str_presenter(dumper, data):
  """
  Configures yaml for dumping strings.
  - Uses '|' for multiline strings.
  - Uses double quotes for strings containing spaces, for SQL compatibility.
  - Uses single quotes for strings containing other special characters like '+' or ':'.
  - Uses default (plain) style for all other strings.
  """
  # Check for multiline strings first (most distinct case)
  if data.count('\n') > 0:
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
  
  # Check for strings that contain a space and should be double-quoted.
  # We also check that it's not just a space, and has other characters.
  if ' ' in data and data.strip():
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='"')

  # Check for other special characters that need single quotes
  # (You can add or remove characters from this list as needed)
  if any(c in data for c in ['+', ':', '-', '{', '}', '[', ']']):
    return dumper.represent_scalar('tag:yaml.org,2002:str', data, style="'")
      
  # If none of the above, use the default plain style
  return dumper.represent_scalar('tag:yaml.org,2002:str', data)

# This part remains the same. It registers your custom presenter for all strings.
yaml.SafeDumper.add_representer(str, str_presenter)

def flatten_json(json_data):
  """
  Function to flatten a json file that is initially on the form:
  {
    "pipeline": {...},
    "jobs" : [
      {
        (...)
        "results" : [
          {
            ...
          }
        ]
      },
      {
      ...
      }
    ]
  }
  """
  flattened_data = []
  
  pipeline_info = json_data['pipeline']
  jobs = json_data['jobs']
  
  for job in jobs:
    job_info = {**pipeline_info, **job}  # Merge pipeline info and job info
    job_info.pop('results')  # Remove 'results' key from the merged dictionary

    results = job.get('results', [])
    for result in results:
      result_info = {**job_info, **result}  # Merge job info and result info
      flattened_data.append(result_info)
  
  return flattened_data

def gen_tab_config(empty=False,suffix="cb",folder="./"):
  """
  This function generates the main tab configuration for LLview (with Overview + each Benchmark).
  When all benchmarks are empty, it generates an empty YAML
  """
  filename = os.path.join(folder,f'tab_{suffix}.yaml')
  log = logging.getLogger('logger')
  log.info(f"Generating main tab configuration file {filename}\n")

  pages = []
  if not empty:
    pages = [{
      'page': {
        'name': "Benchmarks",
        'section': "benchmarks",
        'icon': "bar-chart",
        'pages': [
          {
            'page': {
              'name': "Overview",
              'section': "cblist",
              'default': False,
              'template': "/data/LLtemplates/CB",
              'context': "data/cb/cb_list.csv",
              # 'footer_graph_config': "/data/ll/footer_cblist.json",
              'ref': [ 'datatable' ],
              'data': {
                'default_columns': [ 'Name', 'Timings', '#Runs', 'Status' ]
              }
            }
          },
          {'include_here': None}
        ]
      }
    }]

  # Writing out YAML configuration file
  yaml_string = yaml.safe_dump(pages, default_flow_style=None)
  # Adding the include line (LLview-specific, not YAML standard)
  yaml_string = yaml_string.replace("- {include_here: null}",'%include "./page_cb.yaml"')
  with open(filename, 'w') as file:
    file.write(yaml_string)

  return True

class BenchRepo:
  """
  Class that stores and processes information from Slurm output  
  """

  # Default colormap to use on the footer
  DEFAULT_COLORMAP = 'Paired'
  # Different sorts of the colormaps
  SORT_STRATEGIES = {
    # A standard ascending sort
    'standard': None,  # Using None as the key is the same as lambda i: i
    # A standard descending sort
    'reverse': lambda i: -i,   
    # Sorts even numbers first, then odd numbers
    'interleave_even_odd': lambda i: (1 - (i & 1), i),
  }
  # The default key used if none is specified in the config
  DEFAULT_SORT_KEY = 'standard'
  # Default style of the traces
  DEFAULT_TRACE_STYLE = {
    'type': 'scatter',
    'mode': 'markers',
    'marker': {
      'opacity': 0.6,
      'size': 5
    }
  }

  def __init__(self,name="",config="",tab=None,lastts=0,skipupdate=False):
    self._dict = {}   # Dictionary with modified information (which is output to LML)
    self._name = name # Name of the group (outer key)
    self._tab = tab   # Name of the tab (if that's the case, otherwise None)
    self._lastts = lastts
    self._data = {}  # Data to be stored on the object
    self._skipupdate = skipupdate # Skip update of repos (when they were already cloned). Good to use when no new points exist (e.g., 2 consecutive runs)

    # If name is not given, this is the main object to collect the separate entries
    if name:
      # Determine the parent dictionary level.
      if self._tab:
        # Get or create the dictionary for 'name', then the one for 'self._tab'.
        target = self._data.setdefault(name, {}).setdefault(self._tab, {})
      else:
        # Get or create the dictionary for 'name'.
        target = self._data.setdefault(name, {})

      # Initialize all the data structures within that single target dictionary.
      target['raw'] = []             # List of dictionaries containing all data of current benchmark
      target['sources'] = set()      # Set for source files of current benchmark
      target['metrics'] = {}         # Dictionary for all parameter/metric/annotation names and types added to _dict for current benchmark
      target['parameters'] = {}      # Dictionary of {parameter: description} shown on the table (one row per value parameter)
      target['graphparameters'] = {} # Dict of {parameters: [unique values]} shown on the graphs (one curve per value parameter)
      target['annotations'] = set()  # Set of metrics that show as annotations on graphs
      if config:
        target['config'] = config

    self._counter = count(start=0)          # counter for the total number of points
    self.log   = logging.getLogger('logger')

    # Definition of default values for each variable type
    self.default = {'str': '', 'int': -1, 'bool': None, 'float': 0, 'date': '-', 'ts': -1}

  def __iadd__(self, other: 'BenchRepo') -> 'BenchRepo':
    """
    Implements the in-place addition (+=) operator.
    """
    if not isinstance(other, BenchRepo):
      return NotImplemented
    
    # Use the enhanced deep_merge function to merge the _data dictionaries
    self.deep_merge(self._data, other._data)
    
    # Use the add function to add the data from the 'other' instance
    self.add(other._dict)

    return self

  def __add__(self, other: 'BenchRepo') -> 'BenchRepo':
    """
    Implements the standard addition (+) operator.
    """
    if not isinstance(other, BenchRepo):
      return NotImplemented
    
    new_obj = deepcopy(self)
    new_obj += other
    return new_obj

  def __iter__(self):
    return (t for t in self._dict.keys())
    
  def __len__(self):
    return len(self._dict)

  def items(self):
    return self._dict.items()

  def __delitem__(self,key):
    del self._dict[key]

  @property
  def lastts(self):
    return self._lastts

  def deep_merge(self, target_dict: Dict[str, Any], source_dict: Dict[str, Any]) -> None:
    """
    Recursively merges the source dictionary into the target dictionary.

    This function modifies the target dictionary in place.
    It combines lists and sets, and recursively merges nested dictionaries.
    """
    # Iterate over each key-value pair in the dictionary we are adding from
    for key, source_value in source_dict.items():
      # Check if the key already exists in the target dictionary
      if key in target_dict:
        target_value = target_dict[key]
        
        # If both the target and source values are dictionaries, recurse
        if isinstance(target_value, dict) and isinstance(source_value, dict):
          self.deep_merge(target_value, source_value)
        
        # If both are lists, extend the target list with the source list
        elif isinstance(target_value, list) and isinstance(source_value, list):
          target_value.extend(source_value)
          
        # If both are sets, update the target set with the source set (union)
        elif isinstance(target_value, set) and isinstance(source_value, set):
          target_value.update(source_value)
          
        # Otherwise, the source value overwrites the target value
        else:
          target_dict[key] = deepcopy(source_value)
          
      # If the key does not exist in the target, add it
      else:
        target_dict[key] = deepcopy(source_value)

  def deep_update(self,target, override):
    """
    Recursively update a dictionary.
    """
    for key, value in override.items():
      if isinstance(value, dict):
        # Get the existing value or an empty dict, then recurse.
        target[key] = self.deep_update(target.get(key, {}), value)
      else:
        # Overwrite the value if it's not a dictionary.
        target[key] = value
    return target

  def add(self, to_add: dict, add_to=None):
    """
    (Deep) Merge dictionary 'to_add' into internal 'self._dict'
    """
    if not add_to:
      add_to = self._dict
    for bk, bv in to_add.items():
      av = add_to.get(bk)
      if isinstance(av, dict) and isinstance(bv, dict):
        self.add(bv, add_to=av)
      else:
        add_to[bk] = deepcopy(bv)
    return

  def empty(self):
    """
    Check if internal dict is empty: Boolean function that returns True if _dict is empty
    """
    return not bool(self._dict)

  def _get_benchmark_data(self, name: str, tab: str | None) -> dict:
    """
    Safely retrieves or creates the data dictionary for a specific benchmark and optional tab.
    
    This ensures the path exists, so you can safely read from OR assign to its keys.
    """
    # Start at the top level for the given benchmark name
    data_level = self._data.setdefault(name, {})
    
    # If a tab is specified, go one level deeper
    if tab:
      return data_level.get(tab, {})
      
    # Otherwise, return the dictionary for the benchmark name
    return data_level

  def _iter_plots(self, config: dict):
    """
    A generator that iterates through the plots configuration, handling both
    tabbed and non-tabbed structures.

    Yields:
      tuple: (tab_name, plot_config)
              'tab_name' is a string if tabs are used, otherwise it is None.
              'plot_config' is the dictionary for a single plot.
    """
    plots_section = config.get('plots', [])

    # Case 1: The new structure with tabs
    if isinstance(plots_section, dict) and 'tabs' in plots_section:
      for tab_name, plots_in_tab in plots_section['tabs'].items():
        for plot_config in plots_in_tab:
          yield tab_name, plot_config
    
    # Case 2: The old structure (a simple list)
    elif isinstance(plots_section, list):
      for plot_config in plots_section:
        yield None, plot_config

  def get_or_update_repo(self,folder="./"):
    """
    Getting folder to clone or pull the repo
    If not given, use current working directory
    (Env vars are expanded)
    """
    folder = os.path.expandvars(os.path.join(folder,self._name))
    # Storing folder to use later when getting sources
    benchmark_data = self._get_benchmark_data(self._name, self._tab)
    config = benchmark_data['config']
    config['folder'] = folder

    if config['username']:
      credentials = quote(config['username']) + (f":{quote(config['password'])}@" if config['password'] else "@")
      config['host'] = config['host'].replace("://",f"://{credentials}")

    # If folder does not exist, git clone the repo
    # otherwise try to git pull in the folder
    if not os.path.isdir(folder):
      # Folder does not exist and 'host' is not given, can't do anything
      if 'host' not in config:
        self.log.error(f"Repo does not exist in folder {folder} and 'host' not given! Skipping...\n")
        return False

      # Cloning repo
      self.log.info(f"Folder {folder} does not exist. Cloning...\n")

      cmd = ['git', 'clone', '-q', config['host']]
      cmd.append(folder)
      self.log.debug("Cloning repo with command: {}\n".format(' '.join(cmd).replace(f":{config['password']}@",":***@")))
      p = run(cmd, stdout=PIPE)
      if p.returncode:
        self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd).replace(f":{config['password']}@",":***@")))
        return False
      
      if 'branch' in config:
        cmd = ['git', '-C', folder, 'switch', '-q', config['branch']]
        self.log.debug("Changing branch with command: {}\n".format(' '.join(cmd)))
        p = run(cmd, stdout=PIPE)
        if p.returncode:
          self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd)))
          return False
    else:
      if ('update' in config) and (not config['update']):
        self.log.info(f"Folder {folder} already exists, but update is skipped...\n")
        return True
      elif not self._skipupdate:
        self.log.info(f"Folder {folder} already exists. Updating it...\n")

        # cmd = ['git', '-C', folder, 'pull', config['host']]
        cmd = ['git', '-C', folder, 'pull', '-q']
        # self.log.debug("Running command: {}\n".format(' '.join(cmd).replace(f":{config['password']}@",":***@")))
        self.log.debug("Running command: {}\n".format(' '.join(cmd)))
        p = run(cmd, stdout=PIPE)
        if p.returncode:
          # self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd).replace(f":{config['password']}@",":***@")))
          self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd)))
          return False
    return True

  def get_sources(self):
    """
    Get a list of all files from where the metrics will be obtained
    """
    benchmark_data = self._get_benchmark_data(self._name, self._tab)
    config = benchmark_data['config']
    sources = benchmark_data['sources']

    for stype,source_list in config['sources'].items():
      if stype == 'folders':
        # Looping through all given folders, check if it exists, 
        # and if so, get all files inside them into 'sources' set
        for folder in source_list:
          current_folder = os.path.join(config['folder'],folder)
          if not os.path.isdir(current_folder):
            self.log.error(f"Folder '{current_folder}' does not exist! Skipping...\n")
            continue
          sources.update(os.path.join(current_folder, fn) for fn in next(os.walk(current_folder))[2])
      elif stype == 'files':
        # Looping through all given files, check if it exists, 
        # and if so, add them into 'sources' set
        for file in source_list:
          current_file = os.path.join(config['folder'],file)
          if not os.path.isfile(current_file):
            self.log.error(f"File {current_file} does not exist! Skipping...\n")
            continue
          sources.update([current_file])
      elif stype == 'exclude' or stype == 'include':
        pass
      else:
        self.log.error(f"Unrecognised source type: {stype}. Please use 'files' or 'folders'.\n")
        continue
    # If 'exclude' and/or 'include' options are given, filter sources
    if 'exclude' in config['sources'] or 'include' in config['sources']:
      self.apply_pattern(
                          sources,
                          exclude=config['sources'].get('exclude',''),
                          include=config['sources'].get('include','')
                        )
    self.log.debug(f"{len(sources)} sources for {self._name}: {sources}\n")
    return

  def get_metrics(self):
    """
    Collect all given metrics from the sources and add them
    to self._dict
    """
    self.get_sources()
    benchmark_data = self._get_benchmark_data(self._name, self._tab)
    combined_name = self._name.replace(" ","_") + (f"_{self._tab.replace(' ','_')}" if self._tab else "")
    sources = benchmark_data['sources']
    raw_data = benchmark_data['raw']

    if len(sources) == 0:
      self.log.error(f"No sources to obtain metrics! Skipping...\n")
      return False
    
    #========================================================================================
    # Getting headers and information about parameters/metrics to be obtained

    # Storing pointers to relevant data
    graphparameters = benchmark_data['graphparameters']
    parameters = benchmark_data['parameters']
    annotations = benchmark_data['annotations']
    config = benchmark_data['config']
    # metrics configuration
    metrics_section = config['metrics']

    # Getting all defined metrics:
    defined_metrics = set(metrics_section.keys())

    # Getting all metrics that are used:
    used_metrics = set()

    # Set to store metrics that are strictly required for plots (to not add default values)
    plot_metrics = set()

    # Add metrics from the table parameters
    used_metrics.update(config.get('table', []))
    # Add metrics from all plots
    for tab_name, plot_config in self._iter_plots(config):
      # Add the x and y axes if they are defined
      if plot_config.get('x'):
        used_metrics.add(plot_config['x'])
        plot_metrics.add(plot_config['x'])
      if plot_config.get('y'):
        used_metrics.add(plot_config['y'])
        plot_metrics.add(plot_config['y'])
      
      # Add all metrics used for traces and annotations
      used_metrics.update(plot_config.get('traces', []))
      plot_metrics.update(plot_config.get('traces', []))
      used_metrics.update(plot_config.get('annotations', []))

      # Starting a set to store the possible value of each of the traces/curves
      for key in plot_config.get('traces', []):
        graphparameters.setdefault(key, set())
      # Getting annotations that will be used in graphs
      for key in plot_config.get('annotations', []):
        annotations.add(key)

    # Check for any used metrics that were not defined
    undefined_metrics = used_metrics - defined_metrics

    if undefined_metrics:
      for metric_name in sorted(list(undefined_metrics)): # Sort for consistent error messages
        self.log.error(f"Configuration Error: Metric '{metric_name}' is used in 'table' or 'plots' but is not defined in the 'metrics' section.\n")
      return False # Abort processing

    # These will store the final, aggregated results
    headers = {}
    calc_headers = {}
    metrics_types = {}

    # Loop over the used metrics
    # 'metric_name' is the unique key (e.g., 'systemname', 'queue', 'probability', 'bandwidth')
    for metric_name in used_metrics:
      # Getting the specifications of the metrics
      # 'spec' is the dictionary of its properties (e.g., {'source': ..., 'type': ...})
      spec = metrics_section[metric_name]

      # Getting the keys/headers of the metrics to be obtained from CSV file content
      # This builds a mapping: old_header_name (from csv) -> new_header_name (metric_name)
      # We only include metrics that are sourced from 'content'
      # The default source is 'content' if 'from' is not specified in the spec
      if not isinstance(spec, dict) or spec.get('from', 'content') == 'content':
        
        # Determine the header name to look for in the CSV file
        # It prefers an explicit 'header' from the spec; otherwise, it falls back to the metric_name itself
        header_name = spec.get('header', metric_name) if isinstance(spec, dict) else metric_name

        # Map the CSV header_name to the internal metric_name
        headers[header_name] = metric_name

      # Getting metrics that are calculated from others using a formula
      # This looks for a 'from' expression that contains an arithmetic operator (+, -, *, /)
      if isinstance(spec, dict) and 'from' in spec:
        from_val = spec['from']
        if re.search(r'[+\-*/]', from_val):
          calc_headers[metric_name] = from_val

      # Getting the {name: type} mapping for every metric defined in the configuration
      # This ensures that any metric, regardless of its source, has a defined type
      
      # If the spec is a dictionary and defines a non-empty 'type', use it
      # Otherwise, fall back to the default type 'str'
      if isinstance(spec, dict) and spec.get('type'):
        metrics_types[metric_name] = spec['type']
      else:
        metrics_types[metric_name] = 'str'

    # Assiging type of internal status entry
    metrics_types['_status'] = 'str'

    # 'headers' and 'calc_headers' are now fully populated and ready for use

    # Assign the collected metric types to the class instance variable
    # These are the {name: type} mapping of all the metrics to be used
    benchmark_data['metrics'] = metrics_types

    # Getting parameters and descriptions that will generate rows in the main table
    for key in config.get('table', []):
      parameters[key] = metrics_section[key].get('description', key)

    #========================================================================================
    # Looping throught the sources to collect parameters/metrics

    # Temporary lastts:
    lastts_temp = 0
    required_keys = headers.keys()
    for source in sources:
      # Initializing variable to collect all data defined for given metric
      current_data = []

      # Dictionary to store metadata
      metadata = {}

      # Getting information from content
      # Read source file to a list of dictionaries and filtering only the required metrics
      with open(source, 'r') as file:
        # Reading file into variable once to use for all given metrics
        if source.endswith(".csv"):

          # We'll read the file once to filter comment lines that can be given with metadata
          data_lines = []
          for line in file:
            stripped_line = line.strip()

            # Check if the line is a comment
            if stripped_line.startswith('#'):
              # It's a comment line, so we try to parse it as JSON
              try:
                # Extract the content after the '#' symbol
                comment_json_str = stripped_line[1:].strip()
                
                # Ensure we don't try to parse an empty string (e.g., from a line that is just '#')
                if comment_json_str:

                  # Parse each line as a dict and merge
                  line_dict = ast.literal_eval(comment_json_str)
                  if isinstance(line_dict, dict):
                    metadata.update(line_dict)
                  else:
                    self.log.warning(f"Warning: Metadata line is not a dict: {line_dict}")
                      
                  # parsed_comment = json.loads(comment_json_str)
                  # # We only care about dictionary-type metadata
                  # if isinstance(parsed_comment, dict):
                  #   metadata.update(parsed_comment) # Simple dict merge
              except (ValueError, SyntaxError) as e:
              # except json.JSONDecodeError:
                # This line is a comment, but not valid JSON. Ignoring it.
                self.log.warning(f"Ignoring non-JSON comment in {source}: {stripped_line}\n")
                pass
            # If it's not a comment and not blank, it's a data line
            elif stripped_line:
              data_lines.append(line)

          # Parsing only the collected data lines with DictReader
          data = list(csv.DictReader(data_lines))
        elif source.endswith(".json"):
          data = flatten_json(json.load(file))
        else:
          self.log.error(f"Only CSV or JSON are implemented by now. Skipping file {source}...\n")
          continue

        # Ensure the file was not empty.
        if not data:
          self.log.debug(f"Source file {source} is empty or contains no data rows. Skipping...\n")
          continue

        # Check for missing keys
        available_keys = data[0].keys()
        missing_keys = set(required_keys) - set(available_keys)
        if missing_keys:
          keys_str = ", ".join(f"'{key}'" for key in sorted(list(missing_keys)))
          self.log.error(f"Required keys {keys_str} not found in file header of source {source}. Skipping...\n")
          continue

        # Identify the CSV header that corresponds to 'ts' (if it exists in the file)
        ts_csv_header = next((k for k, v in headers.items() if v == 'ts'), None)

        # Getting data from file (CSV or JSON)
        for line in data:

          # Check if 'ts' is present if it is required from content
          if ts_csv_header:
            if not str(line.get(ts_csv_header, '')).strip():
              self.log.debug(f"Skipping line due to empty 'ts' value.\n")
              continue

          # Use .get(key_old, '') to safely handle missing keys or empty values without skipping
          current_line = {key_new: line.get(key_old, '') for key_old, key_new in headers.items()}

          for key in calc_headers:
            calc = calc_headers[key]
            # Creating expression to be calculated with the values of the columns (selected by the headers) on the current line
            for head in re.split(r"[\+\-\*\/]+", calc_headers[key]):
              calc = calc.replace(head,line[re.sub("^'|'$|^\"|\"$", '', head)])
            try:
              current_line[key] = self.safe_math_eval(calc)
            except SyntaxError as e:
              self.log.debug(f"Cannot obtain value of '{key}'={calc_headers[key]} from line: {line}.\n Using default value: {self.default[metrics_section[key]['type']]}\n")
              current_line[key] = self.default[metrics_section[key]['type']]
              self.log.debug(f"ERROR: {' '.join(traceback.format_exception(type(e), e, e.__traceback__))}\n")

          current_data.append(current_line)

        # Converting data obtained from file content and multiplying by factor, when present
        for key in list(headers.values())+list(calc_headers.keys()):
          # Getting the type of the metric
          mtype = metrics_types[key]
          for data in current_data:
            if mtype == 'str':
              convert = metrics_section[key].get('regex')
            else:
              convert = metrics_section[key].get('factor')
            try:
              data[key] = self.convert_data(
                                            data[key],
                                            vtype='ts' if key == 'ts' else mtype,
                                            factor=convert,
                                            )
            except ValueError:
              self.log.debug(f"Cannot convert value '{data[key]}' for '{key}' in source {source}! Skipping conversion...\n")
              continue

      # Getting common data and metrics that are obtained from filename or from metadata
      common_data = {}
      common_data['__type'] = "benchmark"
      common_data['__prefix'] = "bm"
      if 'id' in config:
        common_data['__id'] = config['id']

      to_exclude = {}
      to_include = {}
      # Collecting metrics and rules for excluding and/or including
      for metric_name in used_metrics:
        spec = metrics_section[metric_name]
        if not spec: continue
        if 'exclude' in spec:
          to_exclude[metric_name] = spec['exclude']
        if 'include' in spec:
          to_include[metric_name] = spec['include']
        if 'from' not in spec: continue
        if (spec['from']=='static') or (spec['from']=='value'):
          if 'value' not in spec:
            self.log.error(f"Metric '{metric_name}' is selected to be obtained from static value, but no 'value' was given! Skipping...\n")
            continue
          common_data[metric_name] = spec['value']
          metrics_types[metric_name] = spec.get('type','str')
        elif ('name' in spec['from']):
          if 'regex' not in spec:
            self.log.error(f"Metric '{metric_name}' is selected to be obtained from filename, but no 'regex' was given! Skipping...\n")
            continue
          # Getting metric from filename with given regex          
          match = re.search(spec['regex'], source)
          if not match:
            self.log.error(f"'{metric_name}' could not be matched using regex '{spec['regex']}' on filename '{source}'! Skipping...\n")
            continue
          # Use the helper function to get the typed value
          raw_value = match.group(1)
          typed_value, value_type = self._type_cast_value(raw_value, spec, metric_name)
          
          if typed_value is not None:
            common_data[metric_name] = typed_value
            metrics_types[metric_name] = value_type
          else:
            continue # Skip if type casting failed
        elif (spec['from']=='metadata'):
          if not metadata:
            self.log.warning(f"Metric '{metric_name}' is from metadata, but no metadata was found in {source}. Skipping...\n")
            continue

          # Try to get the key from 'key', 'header' or from metric_name, in this order
          key_to_find = spec.get('key') or spec.get('header') or metric_name
          
          # Check if the key exists in the metadata
          if key_to_find not in metadata:
            self.log.warning(f"Metric '{metric_name}' requires key '{key_to_find}' from metadata, but it was not found in {source}. Skipping...\n")
            continue
            
          # Get the raw value from metadata
          raw_value = metadata[key_to_find]
          
          # Cast the value to the correct type
          typed_value, value_type = self._type_cast_value(raw_value, spec, metric_name)
          
          if typed_value is not None:
            common_data[metric_name] = typed_value
            metrics_types[metric_name] = value_type
          else:
            continue # Skip if type casting failed

      # Adding 'common_data' to all entries of 'current_data'
      current_data[:] = [(data|common_data) for data in current_data]

      # Applying filters 'exclude' and/or 'include' for each metric, when present
      # (This must be done before collecting the unique graph parameters
      # to remove unwanted values)
      self.apply_pattern(
                          current_data,
                          exclude=to_exclude,
                          include=to_include
                        )

      if 'ts' not in current_data[0]:
        self.log.error(f"'ts' could not be obtained for '{combined_name}'.\n")
        return False # Abort processing

      # Perform validation (to set the _status) and default-setting on each line
      # This is done after everything, such that missing data can still
      # be skipped from conversion, and 'ts' may still fail (if setting to default before,
      # it could be seen as valid)
      for line in current_data:
        # Assume the run is successful until proven otherwise.
        # If a status already exists (e.g., from common_data), respect it.
        run_status = line.get('_status', "SUCCESSFUL")

        # Use `used_metrics` to check all required fields.
        for metric in used_metrics:
          if metric in line:
            val = str(line.get(metric, '')).strip()
            is_empty = (not val or val.lower() in ['none', 'null', 'nan'])

            # If the value is not empty, it's valid
            if not is_empty:
              continue
            
            # For the plot metrics, set the problematic value to None, so it's not plotted
            if metric in plot_metrics:
              run_status = "FAILED"
              # Set the value to None so it will be skipped during plotting.
              line[metric] = None 
            
            # If a non-string value is empty, it's a failure and needs a default.
            # The default value of the string is '', so missing strings should not
            # trigger 'FAILED' status - which may be not intended in some cases,
            # but for others (i.e., 'flags used'), it's necessary

            # For the table parameters, annotations, etc. set the default value
            else:
              metric_type = metrics_types.get(metric, 'str')
              # If a non-string parameter is empty, it's a failure.
              if metric_type != 'str':
                run_status = "FAILED"
              
              # Set the value to its appropriate default for display in the table.
              line[metric] = self.default.get(metric_type, '')

        # Set the final, determined status for the line
        line['_status'] = run_status

      # Collecting unique values for graph parameters in current source:
      # (This has to be done before cleaning the old ts to be able to
      # collect all unique values)
      for param in graphparameters:
        graphparameters[param].update([data[param] for data in current_data])

      self.log.debug(f"Data for {source} contains: {current_data}\n")  
      self.log.debug(f"Headers: {metrics_types}\n")

      if current_data:
        # Saving all raw data, including all ts, to be able to get all combinations for graphs
        raw_data += current_data

      # Filtering older timestamps when lastts is given and storing in self._dict
      # to be written out in LML
      # (This is done at the end to allow the possibility of ts to be added 
      # either from content or from common_data)
      if self._lastts:
        current_data[:] = [data for data in current_data if data['ts'] > self._lastts]

      # Storing temporary lastts from last timestamp of current data
      lastts_temp = max([data['ts'] for data in current_data]+[self._lastts,lastts_temp])

      if current_data: # Adding an id to current data, to have an unique identifier for the csv file generation
        self._dict |= {
          f"{combined_name}_{next(self._counter)}": data | {
              'id': '_'.join([self._format_id_value(data.get(key)) for key in parameters])
          } 
          for data in current_data
        }

    # Storing new lastts from last timestamp of all data
    self._lastts = lastts_temp
    return True

  def _format_id_value(self, value):
    """
    Formats a value for an ID string, matching typical display logic.
    - Formats floats to a reasonable precision.
    - Removes trailing '.0' to match integer display.

    This should fix the issue of having a float .0 that is rounded up 
    when showing on the table, while the 'id' used for the filename still
    includes it (causing a 404 error).
    """
    if isinstance(value, float):
      # Format to a string with precision, then remove trailing '.0'
      formatted_str = f"{value:.6f}".rstrip('0').rstrip('.')
      return formatted_str
    return str(value)

  def _type_cast_value(self, raw_value, spec, metric_name):
    """
    Casts a raw string value to the correct type based on the metric's spec.
    Returns the typed value and its determined type string.
    """
    if 'type' in spec:
      if 'date' in spec['type']:
        typed_value = dateutil.parser.parse(raw_value).strftime('%Y-%m-%d %H:%M:%S')
        value_type = 'date'
      elif spec['type'] == 'int':
        typed_value = int(raw_value) * spec.get('factor', 1)
        value_type = 'int'
      elif spec['type'] == 'float':
        typed_value = float(raw_value) * spec.get('factor', 1)
        value_type = 'float'
      elif 'str' in spec['type']:
        typed_value = str(raw_value)
        value_type = 'str'
      elif 'bool' in spec['type']:
        typed_value = not (str(raw_value).lower() in ['false', '0', '']) if isinstance(raw_value, (str, int)) else bool(raw_value)
        value_type = 'bool'
      elif spec['type'] == 'ts':
        typed_value = time.mktime(dateutil.parser.parse(raw_value).timetuple())
        value_type = 'ts' # using type 'ts' for timestamp
      else:
        self.log.error(f"Type '{spec['type']}' for metric '{metric_name}' not recognised! Use 'date', 'str', 'int', 'float', 'bool', or 'ts'. Skipping metric...\n")
        return None, None
    else:
      # Default type handling
      if metric_name == 'ts': # if type is not given for metric 'ts'
        typed_value = time.mktime(dateutil.parser.parse(raw_value).timetuple())
        value_type = 'ts' # using type 'ts' for timestamp
        # For timestamp 'ts' metric, store it
      else:
        # Default type is 'str'
        typed_value = str(raw_value)
        value_type = 'str'
    
    return typed_value, value_type

  def safe_math_eval(self,string):
    """
    Safely evaluate math calculation stored in string
    """
    allowed_chars = "0123456789+-*(). /"
    for char in string:
      if char not in allowed_chars:
        raise Exception("UnsafeEval")
    return eval(string, {"__builtins__":None}, {})
  
  def convert_data(self,value,vtype='str',factor=None):
    """
    Converts 'value' to type 'vtype' and multiply by 'factor', if present
    """
    if vtype == 'ts':
      if isinstance(value, str) and value.replace('.', '', 1).isdigit():
        value = float(value)
      else:
        try:
          value = dateutil.parser.parse(value).timestamp()
        except (dateutil.parser.ParserError, TypeError):
          self.log.error(f"Warning: Could not parse timestamp from value: {value}. Skipping conversion...\n")
    elif ('date' in vtype):
      try:
        value = dateutil.parser.parse(value).timestamp()
      except (dateutil.parser.ParserError, TypeError):
        self.log.error(f"Warning: Could not parse timestamp from value: {value}. Skipping conversion...\n")
    elif vtype == 'int':
      value = int(value)*factor if factor else int(value)
    elif vtype == 'float':
      value = float(value)*factor if factor else float(value)
    elif 'bool' in vtype:
      value = bool(value)
    elif vtype == 'str':
      if factor:
        # Getting metric from filename with given regex
        match = re.search(factor,value)
        if not match:
          self.log.warning(f"'{value}' could not be matched using regex '{factor}'! No conversion will be made...\n")
          value = str(value)
        else:
          value = str(match.group(1))
      else:
        value = str(value)
    else:
      self.log.error(f"Type '{vtype}' not recognised! Use 'datetime', 'str', 'int' or 'float'. Skipping conversion...\n")
    return value

  def gen_configs(self,folder="./"):
    """
    Generates the different configuration files needed by LLview:
    - DBupdate configuration containing the DB and tables descriptions
    - Page configuration with pointers to the table and footer configurations
    - Template handlebar used to describe the table in the benchmark page
    - Table CSV configuration with the variables that will be on the table
    - VARS used to generate the CSV files

    - CSV configuration for the files with data for the footers
    - Footer configuration with the description of the tabs, graphs and curves
    """
    suffix = self._name if self._name else 'cb'

    return_code = True

    # DBupdate config
    success = self.gen_dbupdate_conf(os.path.join(folder,f'db_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating DB configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Page config
    success = self.gen_page_conf(os.path.join(folder,f'page_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Page configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Template config
    success = self.gen_template_conf(os.path.join(folder,f'template_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Template configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Table CSV config
    success = self.gen_tablecsv_conf(os.path.join(folder,f'tablecsv_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Table CSV configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # VARS config
    success = self.gen_vars_conf(os.path.join(folder,f'vars_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Vars configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Footer CSVs config
    success = self.gen_footercsv_conf(os.path.join(folder,f'csv_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Footer CSVs configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Footer config
    success = self.gen_footer_conf(os.path.join(folder,f'footer_{suffix}.yaml'))
    if not success:
      self.log.error("Error generating Footer configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    return return_code

  def _iter_all_data(self):
    """
    A generator that yields every metrics dictionary in the data structure,
    handling both tabbed and non-tabbed benchmarks.
    
    Yields:
      tuple: (benchname, tabname, metrics_dict)
              'tabname' will be None for non-tabbed benchmarks.
    """
    for benchname, bench_data in self._data.items():
      # Check for the no-tab case
      if 'metrics' in bench_data:
        yield benchname, None, bench_data
      else:
        # Loop through the tabs
        for tabname, tab_data in bench_data.items():
          if 'metrics' in tab_data:
            yield benchname, tabname, tab_data

  def _quote(self,identifier):
    return f'"{identifier}"'

  def gen_dbupdate_conf(self,filename):
    """
    Create YAML file to be used in LLview for DBupdate configuration
    """
    self.log.info(f"Generating DB configuration file {filename}\n")

    lb = '\n' # Fix for backslash inside curly braces in f-strings (can be removed in Python >=3.12)

    # This list will hold all table definitions
    tables = []
    # This set will track unique benchmarks to generate the final aggregation tables
    benchmarks_processed = set()

    # Looping over all the benchmarks inside this object
    # (It can be done for each benchmark/tab or for all collected ones when singleLML is used)
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Add the benchmark name to our set for post-processing
      benchmarks_processed.add(benchname)

      # Table names cannot (should not?) contain spaces, but tab names may have spaces (maybe also benchmark names)
      # This name is for the per-tab/per-benchmark tables
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")
      columns = []

      # Getting references to relevant data
      metrics = benchmark_data['metrics']
      config = benchmark_data['config']
      parameters = benchmark_data['parameters']

      # Looping over all the metrics that are used in this benchmark, which should be put into the DB
      for metric,mtype in metrics.items():
        metric_str = metric.replace(' ','_')
        # Defining a column for current metric
        column = {
          'name': metric_str,
          'type': f'{mtype}_t',
          'LML_from': metric_str,
          'LML_default': self.default[mtype]
        }
        # Adding mandatory 'LML_minlastinsert' for 'ts' column
        if metric == 'ts':
          # The table name here must be the specific per-tab data table name
          column[f'LML_minlastinsert'] = f"mintsinserted"
          # column[f'mintsinserted_cb_{combined_name}_data'] = f"mintsinserted_cb_{combined_name}_data"
        # Collecting all columns
        columns.append(column)
      # Adding id of type ukey_t, needed for internal usage on LLview
      columns.append({
        'name': 'id',
        'type': f'ukey_t',
        'LML_from': 'id',
        'LML_default': ''
      })

      # Main data table (per tab), which triggers an intermediate timestamps table
      tables.append({'table': { 
                                'name': f"cb_{combined_name}_data",
                                'options': {
                                            'update': {
                                                        'LML': f"cb_{combined_name}",
                                                        'mode': 'add',
                                                        'sql_update_contents': {
                                                          'vars': 'mintsinserted',
                                                          'sqldebug': 1,
                                                          # This SQL first deletes its old entries from the timestamp table,
                                                          # then inserts the new ones, tagging them with its own name as the source.
                                                          'sql': f"""DELETE FROM "cb_{benchname}_timestamps" WHERE source = "{combined_name}";
              INSERT INTO "cb_{benchname}_timestamps" ("ts", "source", "_status")
                        SELECT "ts", "{combined_name}", "_status"
                        FROM "cb_{combined_name}_data";
""",
                                                                    },
                                                      },
                                            # This triggers its own overview and the benchmark's timestamp aggregator
                                            'update_trigger': [f"cb_{combined_name}_data", f"cb_{combined_name}_overview", f"cb_{benchname}_timestamps"]
                                          },
                                'columns': columns,
                              }
                    })

      # Getting list of metrics that are plotted on the graphs (not in table nor annotations)
      # to get min/avg/max on the overview table
      graph_metrics = [plot['y'] for tab, plot in self._iter_plots(config) if 'y' in plot]

      # Prepare the comma-separated list of sanitized parameter names
      params_str = ''.join([f', "{key.replace(' ', '_')}"' for key in parameters])

      # Prepare the INSERT list for the aggregated metrics
      insert_metrics_str = ''.join([f',{lb}                                "{m.replace(' ', '_')}_min", "{m.replace(' ', '_')}_avg", "{m.replace(' ', '_')}_max"' for m in graph_metrics])

      # Prepare the SELECT list for the aggregated metrics
      select_metrics_str = ''.join([f',{lb}                                MIN("{m.replace(' ', '_')}"),AVG("{m.replace(' ', '_')}"),MAX("{m.replace(' ', '_')}")' for m in graph_metrics])

      # Prepare the GROUP BY list
      groupby_params_str = ', '.join([f'"{key.replace(' ', '_')}"' for key in parameters])

      # Description of the overview table for this given benchmark/tab
      # This is also a per-tab table now
      tables.append({'table': { 'name': f'cb_{combined_name}_overview',
                                'options': {
                                            'update': {
                                                        'sql_update_contents': {
                                                          # This SQL now correctly references the per-tab/combined_name tables
                                                          'sql': f"""DELETE FROM "cb_{combined_name}_overview";
                INSERT INTO "cb_{combined_name}_overview" ("id", "name", "_status", "count", "valid_count", "min_ts", "max_ts"
                                {params_str}{insert_metrics_str}
                                )
                        SELECT id, "{combined_name}",
                                (SELECT "_status" FROM "cb_{combined_name}_data" AS T2 WHERE T2.id = "cb_{combined_name}_data".id ORDER BY "ts" DESC LIMIT 1),
                                COUNT("ts"), 
                                SUM(CASE WHEN _status <> 'FAILED' THEN 1 ELSE 0 END),
                                MIN("ts"), MAX("ts")
                                {params_str}{select_metrics_str}
                        FROM "cb_{combined_name}_data"
                        GROUP by {groupby_params_str};
""",
                                                                    },
                                                      },
                                          },
                                'columns': [
                                  {'name': 'id',         'type': 'ukey_t'},
                                  {'name': 'name',       'type': 'str_t'},
                                  {'name': '_status',    'type': 'str_t'}, 
                                  {'name': 'count',      'type': 'int_t'},
                                  {'name': 'valid_count','type': 'int_t'},
                                  {'name': 'min_ts',     'type': 'ts_t'},
                                  {'name': 'max_ts',     'type': 'ts_t'},
                                ]
                                +[{'name': key.replace(' ', '_'), 'type': f'{metrics[key]}_t'} for key in parameters]
                                +[{'name': f'{key.replace(' ', '_')}_{suffix}', 'type': f'{metrics[key]}_t'} for key in graph_metrics for suffix in ['min','avg','max']],
                              }
                    })

    # After processing all tabs, create the intermediate timestamp tables for each benchmark
    for benchname in benchmarks_processed:
      tables.append({'table': {
                                'name': f"cb_{benchname}_timestamps",
                                # This table's job is to collect all timestamps and trigger the final update
                                'options': {
                                            'update': {
                                                        'sql_update_contents': {
                                                          'sqldebug': 1,
                                                          'sql': f"""DELETE FROM "cb_benchmarks" WHERE name="{benchname}";
                          INSERT INTO "cb_benchmarks" ("name", "count", "valid_count", "min_ts", "max_ts", "_status")
                                    SELECT "{benchname}",
                                          COUNT("ts"), 
                                          SUM(CASE WHEN _status <> 'FAILED' THEN 1 ELSE 0 END),
                                          MIN("ts"), MAX("ts"),
                                          (SELECT "_status" FROM "cb_{benchname}_timestamps" ORDER BY "ts" DESC LIMIT 1)
                                    FROM "cb_{benchname}_timestamps";
""", # The last "_status" value is added here
                                                                    },
                                                      },
                                          },
                                # It needs a 'ts' column and a 'source' column to track which tab the data came from
                                'columns': [
                                  {'name': 'ts',      'type': 'ts_t'},
                                  {'name': 'source',  'type': 'str_t'},
                                  {'name': '_status', 'type': 'str_t'},
                                ],
                              }
                    })

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(tables, file, default_flow_style=None)

    return True

  def gen_page_conf(self,filename):
    """
    Create YAML file to be used in LLview for Page configuration
    """
    self.log.info(f"Generating Page configuration file {filename}\n")

    # Intermediate dictionary to group pages and tabs by benchmark name
    # The keys will be the benchmark names
    pages_data = {}

    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Getting reference to config
      config = benchmark_data['config']

      # Common dictionary structure for a page or a tab's content
      content_definition = {
        'default': False,
        'template': f'/data/LLtemplates/CB_{combined_name}',
        'context': f"data/cb/cb_{combined_name}.csv",
        'footer_graph_config': f"/data/ll/footer_cb_{combined_name}.json",
        'description': config.get('description',''),
        'ref': [ 'datatable' ],
        'data': {
          'default_columns': [ 'Name', 'Timings', 'Parameters', '#Runs', 'Status' ],
          'info': [{'Benchmark' : benchname}]
          }
      }
      if tabname:
        # --- This is a tab ---
        # Get or create the main page entry for this benchmark
        # This ensures we have a place to append the tab
        benchmark_page = pages_data.setdefault(benchname, {
          'name': benchname,
          'section': f'cb_{benchname.replace(" ","_")}',
          'tabs': [] # Initialize the list of tabs
        })

        # Add the tab's specific name to its content
        content_definition['name'] = tabname
        content_definition['section'] = f'cb_{tabname.replace(" ","_")}'
        
        # Add the fully defined tab to the page's list of tabs
        benchmark_page['tabs'].append(content_definition)

      else:
        # --- This is a standalone page (no tabs) ---
        # Add the page's name to its content
        content_definition['name'] = benchname.replace(" ","_")
        content_definition['section'] = f'cb_{benchname.replace(" ","_")}'
        
        # Store it directly under its benchmark name
        pages_data[benchname] = content_definition

    # After collecting all data, format it into the final list structure for YAML
    pages = []
    for page_data in pages_data.values():
      pages.append({'page': page_data})

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(pages, file, default_flow_style=None)

    return True

  def gen_template_conf(self,filename):
    """
    Create YAML file to be used in LLview for Template configuration
    """
    self.log.info(f"Generating Template configuration file {filename}\n")

    datasets = []
    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths and identifiers
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Get a reference to the parameters for this specific benchmark/tab
      parameters = benchmark_data['parameters']

      # The column definitions are built for each benchmark/tab
      columns = [{
        'headerName': "Parameters",
        'groupId': "parameters",
        'children': [{
        'field': key,
        'headerName': key,
        'headerTooltip': description} for key, description in parameters.items()]
      },
      {
        'headerName': "Timings",
        'groupId': "Timings",
        'children': [
          {
            'field': "min_ts",
            'headerName': "Date of First Run", 
            'headerTooltip': "Minimum timestamp of the benchmark",
            'cellDataType': "text",
          },
          {
            'field': "max_ts",
            'headerName': "Date of Last Run", 
            'headerTooltip': "Maximum timestamp of the benchmark",
            'cellDataType': "text",
          },
        ]
      },
      {
        'headerName': "#Runs",
        'groupId': "#Runs",
        'children': [
          {
            'field': "count",
            'headerName': "Total", 
            'headerTooltip': "Total number of runs",
          },
          {
            'field': "valid_count",
            'headerName': "Valid", 
            'headerTooltip': "Number of valid runs",
          },
        ]
      },
      {
        'field': "_status",
        'headerName': "Status",
        'cellStyle': "(params) => cell_color(params)",
        'headerTooltip': 'Status of the last run',
      }]

      # The main dataset dictionary for this benchmark/tab
      dataset = {'dataset': {
        'name': f'template_{combined_name}_CB',
        'set': 'template',
        'filepath': f'$outputdir/LLtemplates/CB_{combined_name}.handlebars',
        'stat_database': 'jobreport_json_stat',
        'stat_table': 'datasetstat_templates',
        'format': 'datatable',
        'ag-grid-theme': 'balham',
        'columns': columns
      }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file, default_flow_style=None)

    return True

  def gen_tablecsv_conf(self,filename):
    """
    Create YAML file to be used in LLview for Table CSV configuration
    """
    self.log.info(f"Generating Table CSV configuration file {filename}\n")

    datasets = []

    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths and identifiers
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Get a reference to the table parameters for this specific benchmark/tab
      parameters = benchmark_data['parameters']

      # Columns to be included in the csv file: all that are not table parameters (which will be in the filename)
      # Graph metrics/measurements (y) including 'ts', parameters for different traces (graphparameters), and annotations
      columns = [key for key in parameters.keys()]
      columns_str = [f'"{key.replace(' ','_')}"' for key in columns]
      dataset = {'dataset': {
        'name': f'cb_{combined_name}_csv',
        'set': 'csv_cb',
        'filepath': f'$outputdir/cb/cb_{combined_name}.csv.gz',
        'data_database':   'CB',
        'data_table': f'cb_{combined_name}_overview',
        'stat_table': 'datasetstat_support',
        'stat_database': 'jobreport_json_stat',
        'column_ts': 'max_ts',
        'renew': 'always',
        'csv_delimiter': ';',
        'format': 'csv',
        'column_convert': 'min_ts->todate_std_hhmm,max_ts->todate_std_hhmm',
        'header':  f"name;count;valid_count;min_ts;max_ts;_status;{';'.join(columns)}",
        'columns': f"name,count,valid_count,min_ts,max_ts,_status,{','.join(columns_str)}",
      }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file, default_flow_style=None)

    return True

  def gen_vars_conf(self,filename):
    """
    Create YAML file to be used to define Vars in LLview configuration
    """
    self.log.info(f"Generating Vars configuration file {filename}\n")

    vars = []

    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths and identifiers
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      var = {
        'name': f'VAR_cb_{combined_name}',
        'type': 'hash_values',    
        'database': 'CB',
        'table': f'cb_{combined_name}_overview',
        'columns':  'id',
        'sql': f'SELECT "id" FROM "cb_{combined_name}_overview"'
      }

      vars.append(var)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(vars, file, default_flow_style=None)

    return True

  def gen_footercsv_conf(self,filename):
    """
    Create YAML file to be used for Footer CSVs in LLview configuration
    """
    self.log.info(f"Generating Vars configuration file {filename}\n")

    format_types = {
      'int': '%d',
      'float': '%s', # We will use the string output to allow empty values
      'str': '%s',
      'bool': '%d',
      'date': '%s',
      'ts': '%s',
    }
    datasets = []
    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths and identifiers
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Get references to the data for this specific benchmark/tab
      metrics = benchmark_data['metrics']
      parameters = benchmark_data['parameters']

      # Columns to be included in the csv file: all that are not table parameters (which will be in the filename)
      # Graph metrics/measurements (y) including 'ts', parameters for different traces (graphparameters), and annotations
      columns = [key for key in metrics.keys() if key not in parameters]
      columns_str = [f'"{key.replace(' ','_')}"' for key in columns]
      dataset = {'dataset': {
        'name':           f'cb_{combined_name}_csv',
        'set':            f'cb_{combined_name}',
        'FORALL':         f"A:VAR_cb_{combined_name}",
        'filepath':       f"$outputdir/cb/cb_{combined_name}_${{A}}.csv" ,
        'columns':        ','.join(columns_str),
        'header':         ','.join(['date' if key=='ts' else key for key in columns]),
        'column_convert': 'ts->todate_1',
        'column_filemap': 'A:id',
        'format_str':     ','.join([format_types[metrics[key]] for key in columns]),
        'column_ts':      'ts',
        'format':         'csv',
        'renew':          'always',
        'data_database':   'CB',
        'data_table':      f'cb_{combined_name}_data',
        'stat_database':   'jobreport_CB_stat',
        'stat_table':      'datasetstat',
      }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file, default_flow_style=None)

    return True


  def gen_footer_conf(self,filename):
    """
    Create YAML file to be used in LLview for the Footer configuration
    """
    self.log.info(f"Generating Footer configuration file {filename}\n")

    footers = []
    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths and identifiers
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Getting references to all necessary data for this benchmark/tab
      metrics = benchmark_data['metrics']
      config = benchmark_data['config']
      graphparameters = benchmark_data['graphparameters']
      parameters = benchmark_data['parameters']
      raw_data = benchmark_data['raw']

      # Create a map from the y-axis name (the graph's identifier) to its annotations
      plot_annotations_map = {
        plot['y']: plot.get('annotations', [])
        for tab, plot in self._iter_plots(config)
        if 'y' in plot
      }

      # Checking valid combinations of graph parameters
      # (This will only work if all data is in raw_data. If this is filtered before, it may happen that
      # not all valid combinations are generated)
      valid_combinations = [] # To store all valid combinations of graph parameters
      # Generating all possible combinations of the graph parameters
      if graphparameters: # Ensure graphparameters is not empty before creating product
        for combination in product(*graphparameters.values()):
          valid_combination = True
          # Creating dictionary for current combination
          current_combination = {key:value for key,value in zip(graphparameters.keys(),combination)}
          for key,value in current_combination.items():
            # If value is default one, ignore this combination, as it didn't have a valid value
            if self.default[metrics[key]] == value:
              self.log.debug(f"Invalid combination {combination}, {key} has default value of {value}\n")
              valid_combination = False
              continue
            # If there's no value with the current combination, skip it
            if not any(set(current_combination.items()).issubset(set(data.items())) for data in raw_data):
              self.log.debug(f"Combination {combination}, has no values\n")
              valid_combination = False
              continue
          if valid_combination:
            valid_combinations.append(current_combination)
      # Sorting list by key and value
      valid_combinations.sort(key=lambda d: tuple(sorted(d.items())))

      # Getting global defaults for traces/colors
      global_traces_config = config.get('traces', {})
      # Global Colors Defaults
      global_colors_config = global_traces_config.get('colors', {})
      default_colormap = global_colors_config.get('colormap', BenchRepo.DEFAULT_COLORMAP)
      default_skip = global_colors_config.get('skip', [])
      default_sort_key = global_colors_config.get('sort_strategy', BenchRepo.DEFAULT_SORT_KEY)
      
      # Global Styles Defaults
      global_trace_styles = global_traces_config.get('styles', {})

      # Build a map of {tab_name: [list_of_plots]}
      footer_tabs_map = {}
      for tab_name, plot_config in self._iter_plots(config):
        # If no tabs, the tab_name is None. We'll use a default name.
        actual_tab_name = tab_name if tab_name is not None else 'Benchmarks'
        # Get or create the list for this tab and append the plot
        footer_tabs_map.setdefault(actual_tab_name, []).append(plot_config)

      # Loop over footer tabs
      footersetelems = []
      for tab_name, plots_in_tab in footer_tabs_map.items():
        # Loop over graphs
        graphs = []

        # Iterate over the plot configuration objects
        for plot_config in plots_in_tab:
          if 'y' not in plot_config: continue
          graphelem = plot_config['y']

          # Resolve Colors for this specific plot (Local > Global > Default)
          local_colors = plot_config.get('colors', {})
          
          current_colormap = local_colors.get('colormap', default_colormap)
          current_skip = local_colors.get('skip', default_skip)
          current_sort_key = local_colors.get('sort_strategy', default_sort_key)

          # Resolve Styles for this specific plot (Local merged into Global)
          local_styles = plot_config.get('styles', {})
          
          # Start with global styles
          current_trace_styles = deepcopy(global_trace_styles)
          # Update with local plot-specific styles
          self.deep_update(current_trace_styles, local_styles)

          # Prepare Colormap Generator
          sort_function = BenchRepo.SORT_STRATEGIES.get(current_sort_key, BenchRepo.SORT_STRATEGIES[BenchRepo.DEFAULT_SORT_KEY])
          cmap = colormaps[current_colormap]
          if hasattr(cmap, 'colors'):
            color_list = cmap.colors # type: ignore
          else:
            self.log.error(f"Colormap {current_colormap} does not have 'colors' property. Using '{BenchRepo.DEFAULT_COLORMAP}' instead...\n")
            color_list = colormaps[BenchRepo.DEFAULT_COLORMAP].colors # type: ignore
          
          indices_to_sort = range(len(color_list))
          colors = cycle([
            to_hex(color_list[idx]) for idx in sorted(
              indices_to_sort, 
              key=sort_function
            )
          ])

          # Loop over traces
          traces = []
          
          # Handle case where there are no 'traces' defined in config (single curve)
          # If valid_combinations is empty, we create a single dummy 'traceelem' (empty dict)
          # so the loop runs exactly once.
          # This is used to plot single curves without any filter ('where' keys)
          combinations_to_process = valid_combinations if valid_combinations else [{}]

          for traceelem in combinations_to_process:
            color = next(colors)
            while color in current_skip: # Use current_skip
              color = next(colors)

            # Start with Hardcoded Default
            plot_properties = deepcopy(BenchRepo.DEFAULT_TRACE_STYLE)
            # Update with resolved (Global+Local) styles
            self.deep_update(plot_properties, current_trace_styles)

            # If traceelem is populated (normal traces), generate name and 'where' clause
            # otherwise (traceelem is empty, single curve), generate a simple name without 'where' keys
            if traceelem:
              name_str = '<br>'.join(f"{key}: {traceelem[key]}" for mtype in sorted(self.default.keys(), reverse=True) for key in sorted(traceelem.keys()) if metrics[key] == mtype)
              update_dict = {
                'name': name_str,
                'where': traceelem
              }
            else:
              # Single curve case: Name matches the Y-axis metric, no 'where' filter
              update_dict = {
                'name': graphelem,
              }

            plot_properties.update({ 
              'ycol': graphelem,
              'yaxis': "y",
              **update_dict # Merge the specific props
            })
            
            # Setting the colors
            if 'marker' in plot_properties:
              plot_properties['marker']['color'] = color
            if 'line' in plot_properties:
              plot_properties['line']['color'] = color

            # Adding on-hover/annotation data, if present
            # Get the annotations for the current graph
            current_graph_annotations = plot_annotations_map.get(graphelem, [])

            if current_graph_annotations:
              onhover_data = {'onhover': [{key: {'name': key}} for key in current_graph_annotations]}
              plot_properties |= onhover_data
            trace = {'trace': plot_properties}
            traces.append(trace)  

          graph = {
            'graph': {
              'name': graphelem,
              'xcol': 'date',
              'layout': {
                'yaxis': {
                  'title': graphelem + (f" [{config['metrics'][graphelem]['unit']}]" if "unit" in config.get('metrics', {}).get(graphelem, {}) else "")
                },
                'legend': {
                  'x': "1.02", 'xanchor': "left", 'y': "0.98", 'yanchor': "top", 'orientation': "v"
                }
              },
              'datapath': f"data/cb/cb_{combined_name}{''.join([f'_#{key}#' for key in parameters.keys()])}.csv",
              'traces': traces,
            }
          }
          graphs.append(graph)

        footersetelem = {
          'footersetelem': {
            'name': tab_name,
            'info': ', '.join([f"{key}: #{key}#" for key in parameters]),
            'graphs': graphs
          }
        }
        footersetelems.append(footersetelem)

      footer = { 
        'footer': {
          'name': combined_name,
          'filepath': f"$outputdir/ll/footer_cb_{combined_name}.json",
          'stat_database': 'jobreport_json_stat',
          'stat_table': 'datasetstat_footer',
          'footerset': footersetelems,
        }
      }
      footers.append(footer)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(footers, file, default_flow_style=None)

    return True

  def parse(self, cmd, timestamp="", prefix="", stype=""):
    """
    This function parses the output of Slurm commands
    and returns them in a dictionary
    """

    # Create a temporary, local dictionary for this parsing job.
    parsed_data = {}

    # Getting Slurm raw output
    rawoutput = check_output(cmd, shell=True, text=True)
    # 'scontrol' has an output that is different from
    # 'sacct' and 'sacctmgr' (the latter are csv-like)
    if("scontrol" in cmd):
      # If result is empty, return
      if (re.match("No (.*) in the system",rawoutput)):
        self.log.warning(rawoutput.split("\n")[0]+"\n")
        return
      # Getting unit to be parsed from first keyword
      unitname = (m.group(1) if (m := re.match(r"(\w+)", rawoutput)) else None)
      self.log.debug(f"Parsing units of {unitname}...\n")
      units = re.findall(fr"({unitname}[\s\S]+?)\n\n",rawoutput)
      for unit in units:
        self.parse_unit_block(unit, unitname, prefix, stype, parsed_data)
    else:
      units = list(csv.DictReader(rawoutput.splitlines(), delimiter='|'))
      if len(units) == 0:
        self.log.warning(f"No output units from command {cmd}\n")
        return
      # Getting unit to be parsed from first keyword
      unitname = (m.group(1) if (m := re.match(r"(\w+)", rawoutput)) else None)
      self.log.debug(f"Parsing units of {unitname}...\n")
      for unit in units:
        current_unit = unit[unitname]
        parsed_data[current_unit] = {}
        # Adding prefix and type of the unit, when given in the input
        if prefix:
          parsed_data[current_unit]["__prefix"] = prefix
        if stype:
          parsed_data[current_unit]["__type"] = stype
        for key,value in unit.items():
          self.add_value(key,value,parsed_data[current_unit])

    self._dict |= parsed_data
    return

  def add_value(self,key,value,dict):
    """
    Function to add (key,value) pair to dict. It is separate to be easier to adapt
    (e.g., to not include empty keys)
    """
    dict[key] = value if value != "(null)" else ""
    return

  def parse_unit_block(self, unit, unitname, prefix, stype, parsed_data):
    """
    Parse each of the blocks returned by Slurm into the provided parsed_data dictionary.
    """
    # self.log.debug(f"Unit: \n{unit}\n")
    lines = unit.split("\n")
    # first line treated differently to get the 'unit' name and avoid unnecessary comparisons
    current_unit = None
    for pair in lines[0].strip().split(' '):
      key, value = pair.split('=',1)
      if key == unitname:
        current_unit = value
        parsed_data[current_unit] = {}
        # Adding prefix and type of the unit, when given in the input
        if prefix:
          parsed_data[current_unit]["__prefix"] = prefix
        if stype:
          parsed_data[current_unit]["__type"] = stype
      # JobName must be treated separately, as it does not occupy the full line
      # and it may contain '=' and ' '
      elif key == "JobName":
        if not current_unit:
          # This should not happen, as the current_unit always show up before JobName
          self.log.error("Encountered JobName before any unit definition\n")
          return
        value = (m.group(1) if (m := re.search(".*JobName=(.*)$",lines[0].strip())) else None)
        parsed_data[current_unit][key] = value
        break
      self.add_value(key,value,parsed_data[current_unit])

    # Other lines must be checked if there are more than one item per line
    # When one item per line, it must be considered that it may include '=' in 'value'
    for line in [_.strip() for _ in lines[1:]]:
      # Skip empty lines
      if not line: continue
      self.log.debug(f"Parsing line: {line}\n")
      # It is necessary to handle lines that can contain '=' and ' ' in 'value' first
      if len(splitted := line.split('=',1)) == 2: # Checking if line is splittable on "=" sign
        key,value = splitted
      else:  # If not, split on ":"
        key,value = line.split(":",1)
      # Here must be all fields that can contain '=' and ' ', otherwise it may break the workflow below 
      if key in ['Comment','Reason','Command','WorkDir','StdErr','StdIn','StdOut','TRES','OS']: 
        self.add_value(key,value,parsed_data[current_unit])
        continue
      # Now the pairs are separated by space
      for pair in line.split(' '):
        if len(splitted := pair.split('=',1)) == 2: # Checking if line is splittable on "=" sign
          key,value = splitted
        else:  # If not, split on ":"
          key,value = pair.split(":",1)
        if key in ['Dist']: #'JobName'
          parsed_data[current_unit][key] = line.split(f'{key}=',1)[1]
          break
        self.add_value(key,value,parsed_data[current_unit])
    return

  def apply_pattern(self,elements,exclude={},include={}):
    """
    Loops over all units in elements to:
    - remove items that match 'exclude'
    - keep only items that match 'include'
    """
    to_remove = set()
    if isinstance(elements,set):
      # When elements is a set (e.g. 'sources' list)
      # Check if each of the elements of the set contains the patterns
      for unit in elements:
        if exclude and self.search_patterns(exclude,unit):
          to_remove.add(unit)
        if include and not self.search_patterns(include,unit):
          to_remove.add(unit)
      elements -= to_remove
    if isinstance(elements,list):
      # When elements is a list (e.g. 'metrics' list, containing a list of dicts)
      # Check if each of the elements of the list contains the patterns
      for idx,unit in enumerate(elements):
        if exclude and self.check_unit(idx,unit,exclude,text="excluded"):
          to_remove.add(idx)
        if include and not self.check_unit(idx,unit,include,text="included"):
          to_remove.add(idx)
      for idx in sorted(to_remove, reverse=True): # Must be removed from last to first, otherwise elements change
        del elements[idx]
    elif isinstance(elements,dict):
      # When elements is a dict (e.g. internal self._dict)
      # Check if the unitname or the metrics inside contain the patterns
      for unitname,unit in elements.items():
        if exclude and self.check_unit(unitname,unit,exclude,text="excluded"):
          to_remove.add(unitname)
        if include and not self.check_unit(unitname,unit,include,text="included"):
          to_remove.add(unitname)
      for unitname in to_remove:
        del elements[unitname]
    return

  def search_patterns(self,patterns,unit):
    """
    Search 'unitname' for pattern(s).
    Returns True if of the pattern is found
    """
    if isinstance(patterns,str): # If rule is a simple string
      return bool(re.search(patterns, unit))
    elif isinstance(patterns,list): # If list of rules
      for pattern in patterns: # loop over list - that can be strings or dictionaries
        if isinstance(pattern,str): # If item in list is a simple string
          if re.search(pattern, unit):
            return True # Returns True if a pattern is found
    #     elif isinstance(pattern,dict): # If item in list is a dictionary
    #       for key,value in pat.items():
    #         if isinstance(value,str): # if dictionary value is a simple string
    #           if (key in unit) and re.match(value, unit[key]):
    #             self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key of list\n")
    #             return True
    #         elif isinstance(value,list): # if dictionary value is a list
    #           for v in value:
    #             if (key in unit) and re.match(v, unit[key]): # At this point, v in list can only be a string
    #               self.log.debug(f"Unit {unitname} is {text} due to {v} rule in list of {key} key of list\n")
    #               return True
    # elif isinstance(pattern,dict): # If dictionary with rules
    #   for key,value in pattern.items():
    #     if isinstance(value,str): # if dictionary value is a simple string
    #       if (key in unit) and re.match(value, unit[key]):
    #         self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key\n")
    #         return True
    #     elif isinstance(value,list): # if dictionary value is a list
    #       for v in value:
    #         if (key in unit) and re.match(v, unit[key]): # At this point, v in list can only be a string
    #           self.log.debug(f"Unit {unitname} is {text} due to {v} rule in list of {key} key\n")
    #           return True            
    return False

  def check_unit(self,unitname,unit,pattern,text="included/excluded"):
    """
    Check 'current_unit' name with rules for exclusion or inclusion. (exclusion is applied first)
    Returns True if unit is to be skipped
    """
    if isinstance(pattern,str): # If rule is a simple string
      if re.search(pattern, unitname):
        self.log.debug(f"Unit {unitname} is {text} due to {pattern} rule\n")
        return True
    elif isinstance(pattern,list): # If list of rules
      for pat in pattern: # loop over list - that can be strings or dictionaries
        if isinstance(pat,str): # If item in list is a simple string
          if re.search(pat, unitname):
            self.log.debug(f"Unit {unitname} is {text} due to {pat} rule in list\n")
            return True
        elif isinstance(pat,dict): # If item in list is a dictionary
          for key,value in pat.items():
            if isinstance(value,str): # if dictionary value is a simple string
              if (key in unit) and re.search(value, unit[key]):
                self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key of list\n")
                return True
            elif isinstance(value,list): # if dictionary value is a list
              for v in value:
                if (key in unit) and re.search(v, unit[key]): # At this point, v in list can only be a string
                  self.log.debug(f"Unit {unitname} is {text} due to {v} rule in list of {key} key of list\n")
                  return True
    elif isinstance(pattern,dict): # If dictionary with rules
      for key,value in pattern.items():
        if isinstance(value,str): # if dictionary value is a simple string
          if (key in unit) and re.search(value, unit[key]):
            self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key\n")
            return True
        elif isinstance(value,list): # if dictionary value is a list
          for v in value:
            if (key in unit) and re.search(v, unit[key]): # At this point, v in list can only be a string
              self.log.debug(f"Unit {unitname} is {text} due to {v} rule in list of {key} key\n")
              return True
    return False

  def map(self, mapping_dict):
    """
    Map the dictionary using (key,value) pair in mapping_dict
    (Keys that are not present are removed)
    """
    new_dict = {}
    skip_keys = set()
    for unit,item in self._dict.items():
      new_dict[unit] = {}
      for key,map in mapping_dict.items():
        # Checking if key to be modified is in object
        if key not in item:
          skip_keys.add(key)
          continue
        new_dict[unit][map] = item[key]
      # Copying also internal keys that are used in the LML
      if '__type' in item:
        new_dict[unit]['__type'] = item['__type']
      if '__id' in item:
        new_dict[unit]['__id'] = item['__id']
      if '__prefix' in item:
        new_dict[unit]['__prefix'] = item['__prefix']
    if skip_keys:
      self.log.warning(f"Skipped mapping keys (at least on one node): {', '.join(skip_keys)}\n")
    self._dict = new_dict
    return

  def modify(self, modify_dict):
    """
    Modify the dictionary using functions given in modify_dict
    """
    skipped_keys = set()
    for item in self._dict.values():
      for key,modify in modify_dict.items():
        # Checking if key to be modified is in object
        if key not in item:
          skipped_keys.add(key)
          continue
        if isinstance(modify,str):
          for funcname in [_.strip() for _ in modify.split(',')]:
            try:
              func = globals()[funcname]
              item[key] = func(item[key])
            except KeyError:
              self.log.error(f"Function {funcname} is not defined. Skipping it and keeping value {item[key]}\n")
        elif isinstance(modify,list):
          for funcname in modify:
            try:
              func = globals()[funcname]
              item[key] = func(item[key])
            except KeyError:
              self.log.error(f"Function {funcname} is not defined. Skipping it and keeping value {item[key]}\n")
    if skipped_keys:
      self.log.warning(f"Skipped modifying keys (at least on one node): {', '.join(skipped_keys)}\n")
    return

  def to_LML(self, filename, prefix="", stype=""):
    """
    Create LML output file 'filename' using
    information of self._dict
    """
    self.log.info(f"Writing LML data to {filename}... ")
    # Creating folder if it does not exist
    os.makedirs(os.path.dirname(filename), exist_ok=True)
    # Opening LML file
    with open(filename,"w") as file:
      # Writing initial XML preamble
      file.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" )
      file.write("<lml:lgui xmlns:lml=\"http://eclipse.org/ptp/lml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n" )
      file.write("    xsi:schemaLocation=\"http://eclipse.org/ptp/lml http://eclipse.org/ptp/schemas/v1.1/lgui.xsd\"\n" )
      file.write("    version=\"1.1\">\n" )

      # Creating first list of objects
      file.write("<objects>\n" )
      digits = int(math.log10(len(self._dict)))+1 if len(self._dict)>0 else 1
      i = 0
      for key,item in self._dict.items():
        if "__id" not in item:
          item["__id"] = f'{prefix if prefix else item["__prefix"]}{i:0{digits}d}'
          i += 1
        file.write(f'<object id=\"{item["__id"]}\" name=\"{key}\" type=\"{stype if stype else item["__type"]}\"/>\n')
      file.write("</objects>\n")

      # Writing detailed information for each object
      file.write("<information>\n")
      # Counter of the number of items that define each object
      i = 0
      # Looping over the items
      for item in self._dict.values():
        # The objects are unique for the combination {jobid,path}
        file.write(f'<info oid=\"{item["__id"]}\" type=\"short\">\n')
        # Looping over the quantities obtained in this item
        for key,value in item.items():
          # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
          if key.startswith('__nelems'): 
            file.write(" <data key={:24s} value=\"{}\"/>\n".format('\"'+str(key.replace(" ","_"))+'\"',value))
            continue
          if key.startswith('__'): continue
          if (not isinstance(value,str)) or (value != ""):
          # if (value) and (value != "0"):
            # Replacing double quotes with single quotes to avoid problems importing the values
            file.write(" <data key={:24s} value=\"{}\"/>\n".format(
                '\"'+str(key.replace(" ","_"))+'\"', 
                value.replace('"', "'") if isinstance(value, str) else ("" if value is None else value)
            ))
        # if ts:
        #   file.write(" <data key={:24s} value=\"{}\"/>\n".format('\"ts\"',ts))

        file.write(f"</info>\n")
        i += 1

      file.write("</information>\n" )
      file.write("</lml:lgui>\n" )

    log_continue(self.log,"Finished!")

    return


def log_continue(log,message):
  """
  Change formatter to write a continuation 'message' on the logger 'log' and then change the format back
  """
  for handler in log.handlers:
    handler.setFormatter(CustomFormatter("%(message)s (%(lineno)-3d)[%(asctime)s]\n",datefmt=log_config['datefmt']))

  log.info(message)

  for handler in log.handlers:
    handler.setFormatter(CustomFormatter(log_config['format'],datefmt=log_config['datefmt']))
  return


def get_credentials(name,config):
  """
  This function receives a server 'name' and 'config', checks 
  the options in the server configuration and gets the username 
  and password according to what is given:
  - if 'username' and 'password' are given, read them and return
  - if "credentials: 'module'" is chosen, then a module 'credentials' with a function 'get_user_pass' 
    must be in PYTHONPATH and "return username,password"
  - if "credentials: 'none'" is used, perform queries without authentication
  - if username and/or password are not obtained from the options above,
    ask in the command line (if 'keyring' module is present, store password there)
    - if no username is given, perform queries without authentication
  """
  log = logging.getLogger('logger')
  username = None
  password = None
  if "token" in config:
    username = 'oauth2'
    password = config['token']
  elif "credentials" in config:
    if isinstance(config['credentials'],dict):
      # Trying to get 'username' and 'password' from configuration
      # password is only tried if username is present
      if ('username' not in config['credentials']):
        log.error("'username' not in credentials configuration! Skipping...\n")
      else:
        username = os.path.expandvars(config['credentials']['username'])
        if ('password' not in config['credentials']):
          log.warning("'password' not in credentials configuration! Skipping...\n")
        else:
          password = os.path.expandvars(config['credentials']['password'])
    elif config['credentials'] == 'module':
      try: 
        # Internal function
        from credentials import get_user_pass
        username,password = get_user_pass()
      except ModuleNotFoundError:
        log.critical("Credentials was chosen to be obtained via module, but module 'credentials' does not exist!\n")
    elif config['credentials'] == 'none':
      log.debug("Queries will be done without authentication\n")
      return None,None
  # If username was not obtained in config or module, ask now
  if not username:
    username = input("Username:")
    if not username:
      log.info("No username given, queries will be done without authentication\n")
      return None,None
  # If username was not obtained in config or module, ask now
  if not password:
    if keyring:
      log.info("Keyring module found, attempting to retrieve password.\n")
      password = keyring.get_password('llview_prometheus', username)
      if password is None:
        password_input = getpass.getpass(f"Enter password for {username} on '{name}' (will be stored in keychain):")
        keyring.set_password(name, username, password_input)
        password = password_input
    else:
      log.warning("Keyring module cannot be imported, password will not be saved.\n")
      password = getpass.getpass(f"Enter password for {username}:")
  return username,password



def parse_config_yaml(filename):
  """
  YAML configuration parser
  """
  # Getting logger
  log = logging.getLogger('logger')
  log.info(f"Reading config file {filename}...\n")

  with open(filename, 'r') as configyml:
    configyml = yaml.safe_load(configyml)
  return {} if configyml == None else configyml

class CustomFormatter(logging.Formatter):
  """
  Formatter to add colors to log output
  (adapted from https://stackoverflow.com/a/56944256/3142385)
  """
  def __init__(self,fmt,datefmt=""):
    super().__init__()
    self.fmt=fmt
    self.datefmt=datefmt
    # Colors
    self.grey = "\x1b[38;20m"
    self.yellow = "\x1b[93;20m"
    self.blue = "\x1b[94;20m"
    self.magenta = "\x1b[95;20m"
    self.cyan = "\x1b[96;20m"
    self.red = "\x1b[91;20m"
    self.bold_red = "\x1b[91;1m"
    self.reset = "\x1b[0m"
    # self.format = "%(asctime)s %(funcName)-18s(%(lineno)-3d): [%(levelname)-8s] %(message)s"

    self.FORMATS = {
      logging.DEBUG: self.cyan + self.fmt + self.reset,
      logging.INFO: self.grey + self.fmt + self.reset,
      logging.WARNING: self.yellow + self.fmt + self.reset,
      logging.ERROR: self.red + self.fmt + self.reset,
      logging.CRITICAL: self.bold_red + self.fmt + self.reset
    }
    
  def format(self, record):
    log_fmt = self.FORMATS.get(record.levelno)
    formatter = logging.Formatter(fmt=log_fmt,datefmt=self.datefmt)
    return formatter.format(record)
    
# Adapted from: https://stackoverflow.com/a/53257669/3142385
class _ExcludeErrorsFilter(logging.Filter):
  def filter(self, record):
    """Only lets through log messages with log level below ERROR ."""
    return record.levelno < logging.ERROR

log_config = {
  'format': "%(asctime)s %(funcName)-18s(%(lineno)-3d): [%(levelname)-8s] %(message)s",
  'datefmt': "%Y-%m-%d %H:%M:%S",
  # 'file': 'slurm.log',
  # 'filemode': "w",
  'level': "INFO" # Default value; Options: 'DEBUG', 'INFO', 'WARNING', 'ERROR' from more to less verbose logging
}
def log_init(level):
  """
  Initialize logger
  """

  # Getting logger
  log = logging.getLogger('logger')
  log.setLevel(level if level else log_config['level'])

  # Setup handler (stdout, stderr and file when configured)
  oh = logging.StreamHandler(sys.stdout)
  oh.setLevel(level if level else log_config['level'])
  oh.setFormatter(CustomFormatter(log_config['format'],datefmt=log_config['datefmt']))
  oh.addFilter(_ExcludeErrorsFilter())
  oh.terminator = ""
  log.addHandler(oh)  # add the handler to the logger so records from this process are handled

  eh = logging.StreamHandler(sys.stderr)
  eh.setLevel('ERROR')
  eh.setFormatter(CustomFormatter(log_config['format'],datefmt=log_config['datefmt']))
  eh.terminator = ""
  log.addHandler(eh)  # add the handler to the logger so records from this process are handled

  if 'file' in log_config:
    fh = logging.FileHandler(log_config['file'], mode=log_config['filemode'])
    fh.setLevel(level if level else log_config['level'])
    fh.setFormatter(CustomFormatter(log_config['format'],datefmt=log_config['datefmt']))
    fh.terminator = ""
    log.addHandler(fh)  # add the handler to the logger so records from this process are handled

  return

################################################################################
# MAIN PROGRAM:
################################################################################
def main():
  """
  Main program
  """
  
  # Parse arguments
  parser = argparse.ArgumentParser(description="Prometheus Plugin for LLview")
  parser.add_argument("--config",          default=False, help="YAML config file (or folder with YAML configs) containing the information to be gathered and converted to LML")
  parser.add_argument("--loglevel",        default=False, help="Select log level: 'DEBUG', 'INFO', 'WARNING', 'ERROR' (more to less verbose)")
  parser.add_argument("--singleLML",       default=False, help="Merge all sections into a single LML file")
  parser.add_argument("--tsfile",          default=False, help="File to read/write timestamp")
  parser.add_argument("--outfolder",       default=False, help="Reference output folder for LML files")
  parser.add_argument("--repofolder",      default=False, help="Folders where the repos will be cloned")
  parser.add_argument("--outconfigfolder", default=False, help="Folder to generate config files")
  parser.add_argument("--skipupdate",      action='store_true', help="Skip updating the repos (if they don't exist, they will still be cloned)")

  args = parser.parse_args()

  # Configuring the logger (level and format)
  log_init(args.loglevel)
  log = logging.getLogger('logger')

  if args.config:
    if os.path.isfile(args.config):
      config = parse_config_yaml(args.config)
    elif os.path.isdir(args.config):
      config_files = [os.path.join(args.config, fn) for fn in next(os.walk(args.config))[2]]
      config = {}
      for file in [_ for _ in config_files if _.endswith('.yaml') or _.endswith('.yml')]:
        config |= parse_config_yaml(file)
    else:
      log.critical(f"Config {args.config} does not exist!\n")
      parser.print_help()
      exit(1)
  else:
    log.critical("Config file not given!\n")
    parser.print_help()
    exit(1)

  # If tsfile is given, read the ts when the last update was obtained
  # Points with ts before this one will be ignored
  lastts={}
  if args.tsfile:
    if os.path.isfile(args.tsfile):
      with open(args.tsfile, 'r') as file:
        lastts = yaml.safe_load(file)
    else:
      log.warning(f"'ts' file {args.tsfile} does not exist! Getting all results...\n")

  unique = BenchRepo()

  all_empty = True
  if config:

    # Start generic timer
    start_time = time.time()

    # Looping over outer entries, that should represent repositories
    for repo_name,repo_config in config.items():
      log.info(f"Processing '{repo_name}'\n")

      # Getting credentials for the current server
      repo_config['username'], repo_config['password'] = get_credentials(repo_name,repo_config)

      # Checking if tabs within a page exist to loop through them
      internal_tabs = False
      if "tabs" in repo_config:
        internal_tabs = True
        # Gathering configuration that will be common for all internal tabs
        common_config = {key:value for key,value in repo_config.items() if key !="tabs"}
        # Distributing common configuration for all internal tabs (rewriting specific configuration with the most internal one)
        for tab in repo_config['tabs'].keys():
          repo_config['tabs'][tab] = common_config | repo_config['tabs'][tab]

      # Normalizing the tabs or single page for loop
      group = repo_config['tabs'] if internal_tabs else {repo_name: repo_config}

      # Loop over tabs (if existing) or single page
      # (group points to either the tabs or to the single page)
      for group_name,group_config in group.items():
        sources = group_config.get('sources') or {}
        group = 'tab' if internal_tabs else 'repository'
        combined_name = f"{repo_name}:{group_name}" if internal_tabs else repo_name

        # Checking if something is to be done on current repo
        if not (sources.get('files') or sources.get('folders')):
          log.warning(f"No 'sources' of metrics to process for this {group}. Skipping...\n")
          continue
        if not group_config.get('metrics'):
          log.warning(f"No 'metrics' to collect for this {group}. Skipping...\n")
          continue
        if not group_config.get('table'):
          log.warning(f"No 'table' to display for this {group}. Skipping...\n")
          continue
        if not group_config.get('plots'):
          log.warning(f"No 'plots' to display for this {group}. Skipping...\n")
          continue

        # Start repo timer
        repo_start_time = time.time()

        log.info(f"Collecting data for '{combined_name}'...\n")

        # Initializing new object of type given in config
        # This object is given per page or per internal tab (in case tabs are given)
        bench = BenchRepo(
          name=repo_name,
          tab=group_name if internal_tabs else None,
          config=group_config,
          lastts=lastts[combined_name] if combined_name in lastts else 0,
          skipupdate=args.skipupdate,
        )

        success = bench.get_or_update_repo(folder=args.repofolder if args.repofolder else './')
        if not success:
          log.error(f"Error cloning or updating repository of '{combined_name}'. Skipping...\n")
          continue

        success = bench.get_metrics()
        if not success:
          log.error(f"Error collecting metrics. Skipping...\n")
          continue

        # End repo timer
        repo_end_time = time.time()
        lastts[combined_name] = bench.lastts
        log.debug(f"Gathering '{combined_name}' information took {repo_end_time - repo_start_time:.4f}s\n")

        # When there's an object per entry, the LML and configurations are generated for each of them
        if (not args.singleLML):

          # Outputing the different LMLs (that must be added to the DBupdate workflow on LLview)
          if bench.empty():
            log.warning(f"Object for '{combined_name}' is empty, output will include only timings...\n")

          # Add timing key for each 
          # if not empty():
          timing = {}
          name = f'get{combined_name.replace(" ","_")}'
          timing[name] = {}
          timing[name]['startts'] = repo_start_time
          timing[name]['datats'] = repo_start_time
          timing[name]['endts'] = repo_end_time
          timing[name]['duration'] = repo_end_time - repo_start_time
          timing[name]['nelems'] = len(bench)
          # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
          timing[name][f"__nelems_benchmark"] = len(bench)
          timing[name]['__type'] = 'pstat'
          timing[name]['__id'] = f'pstat_get{combined_name.replace(" ","_")}'
          bench.add(timing)

          bench.to_LML(os.path.join(args.outfolder if args.outfolder else './',f"{combined_name.replace(" ","_")}_LML.xml"))
          all_empty = False

          # Creating configuration files
          success = bench.gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
          if not success:
            log.error(f"Error generating configuration files for '{combined_name}'!\n")
            continue
        else:
          # Accumulating for a single LML
          unique = unique + bench

    # End generic timer
    end_time = time.time()

    # Writing out unique LML
    if (args.singleLML):
      # Outputing single LML (that must be added to the DBupdate workflow on LLview)
      if unique.empty():
        log.warning(f"Unique object is empty, output will include only timings...\n")

      # Add timing key for each 
      # if not empty():
      timing = {}
      name = f'getBenchmarks'
      timing[name] = {}
      timing[name]['startts'] = start_time
      timing[name]['datats'] = start_time
      timing[name]['endts'] = end_time
      timing[name]['duration'] = end_time - start_time
      timing[name]['nelems'] = len(unique)
      # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
      timing[name][f"__nelems_benchmark"] = len(unique)
      timing[name]['__type'] = 'pstat'
      timing[name]['__id'] = f'pstat_getBenchmarks'
      unique.add(timing)

      unique.to_LML(os.path.join(args.outfolder if args.outfolder else './',args.singleLML))
      all_empty = False

      # Creating configuration files
      success = unique.gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
      if not success:
        log.error(f"Error generating configuration files!\n")
  else:
    log.warning(f"No repos given.\n")

  # Creating required configuration files if all benchmarks are empty
  if all_empty:
    log.warning(f"Creating empty LLview config files...\n")
    success = BenchRepo().gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
    if not success:
      log.error(f"Error generating empty configuration files!\n")

  # Creating LLview tab configuration file
  success = gen_tab_config(empty=all_empty,folder=(args.outconfigfolder if args.outconfigfolder else ''))
  if not success:
    log.error(f"Error generating tab configuration file!\n")

  # Writing last 'end_time' to tsfile
  if args.tsfile:
    # Writing out YAML configuration file
    with open(args.tsfile, 'w') as file:
      yaml.safe_dump(lastts, file, default_flow_style=None)

  log.debug("FINISH\n")
  return

if __name__ == "__main__":
  main()
