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
import requests
from urllib.parse import quote, urlparse
import yaml
import json
import ast
from matplotlib import colormaps # type: ignore  # To loop over colors in footers
from matplotlib.colors import to_hex # Convert RGB to HEX
from itertools import count,cycle,product
from copy import deepcopy
from subprocess import check_output,run,PIPE
from typing import Tuple, List, Dict, Any, Union

# Optional: keyring
try:
  import keyring  # pyright: ignore [reportMissingImports]
except ImportError:
  keyring = None  # Set to None if not available

def range_validator(values: List[Union[float, int, None]], params: Dict[str, Any]) -> Tuple[List[bool], Dict[str, Any]]:
  """
  Checks if values are within [min, max].
  
  Args:
    values: List of numeric values (or None) to check.
    params: Dictionary containing 'min' and/or 'max' thresholds.
    
  Returns:
    Tuple containing:
    - List[bool]: True if valid, False if Warning.
    - Dict: Plotly layout additions (shapes/annotations) to visualize the thresholds.
    
  Raises:
    ValueError: If validation params are invalid.
  """
  min_val = params.get('min')
  max_val = params.get('max')

  if min_val is None and max_val is None:
    raise ValueError("range_validator requires 'min' or 'max' parameter.")  

  # Calculate Results
  results = []
  for val in values:
    if val is None:
      results.append(True) # Treat missing data as 'Valid' (ignore), but they should have been already filtered
      continue

    is_valid = True
    try:
      if min_val is not None and val < min_val:
        is_valid = False
      elif max_val is not None and val > max_val:
        is_valid = False
    except TypeError as e:
      # If we can't compare, it's a data error. Raise it so the user knows.
      raise TypeError(f"Cannot compare value '{val}' with thresholds: {e}")
      
    results.append(is_valid)
    
  # Generate visual layout additions (if not explicitly disabled)
  layout_additions = {'shapes': [], 'annotations': []}
  
  if params.get('annotations', True) is not False:
      
    # Base style for the threshold lines
    base_line = {
      'type': 'line',
      'xref': 'paper', # Line spans the entire width of the plot area
      'x0': 0,
      'x1': 1,
      'yref': 'y',
      'layer': 'below', # Keep lines behind the data
    }

    # Base style for the text labels
    base_text = {
      'xref': 'paper',
      'x': 0.98, # Position slightly outside the right edge of the plot area
      'xanchor': 'right',
      'yref': 'y',
      'showarrow': False,
      'font': {'color': 'rgba(255, 0, 0, 0.7)', 'size': 10}
    }

    if max_val is not None:
      # Shape: Solid red line
      shape_max = base_line.copy()
      shape_max.update({
        'y0': max_val, 'y1': max_val,
        'line': {'color': 'rgba(255, 0, 0, 0.5)', 'width': 1.5, 'dash': 'solid'}
      })
      layout_additions['shapes'].append(shape_max)

      # Annotation: "max" above the line
      ann_max = base_text.copy()
      ann_max.update({
        'y': max_val,
        'yanchor': 'bottom', # Anchor bottom of text to the line (puts text above)
        'text': 'max'
      })
      layout_additions['annotations'].append(ann_max)

    if min_val is not None:
      # Shape: Dashed red line
      shape_min = base_line.copy()
      shape_min.update({
        'y0': min_val, 'y1': min_val,
        'line': {'color': 'rgba(255, 0, 0, 0.5)', 'width': 1.5, 'dash': 'dash'}
      })
      layout_additions['shapes'].append(shape_min)

      # Annotation: "min" below the line
      ann_min = base_text.copy()
      ann_min.update({
        'y': min_val,
        'yanchor': 'top', # Anchor top of text to the line (puts text below)
        'text': 'min'
      })
      layout_additions['annotations'].append(ann_min)

  return results, layout_additions


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

def gen_tab_config(default=False,tabname='Benchmarks',suffix="cb",folder="./"):
  """
  This function generates the main tab configuration for LLview (with Overview + each Benchmark).
  """
  filename = os.path.join(folder,f'tab_{suffix}.yaml')
  log = logging.getLogger('logger')
  log.info(f"Generating main tab configuration file {filename}\n")

  pages = [{
    'page': {
      'name': tabname,
      'section': "benchmarks",
      'icon': "bar-chart",
      'pages': [
        {
          'page': {
            'name': "Overview",
            'section': "cblist",
            'default': default,
            'template': "/data/LLtemplates/CB",
            'context': "data/cb/cb_list.csv",
            # 'footer_graph_config': "/data/ll/footer_cblist.json",
            'ref': [ 'datatable' ],
            'data': {
              'default_columns': [ 'Name', 'Timings', '#Points', 'Status' ]
            }
          }
        },
        {'include_here': None}
      ]
    }
  }]

  # Writing out YAML configuration file
  raw_output = yaml.safe_dump(pages, None, default_flow_style=None)
  yaml_string = raw_output if isinstance(raw_output, str) else ""
  # Adding the include line (LLview-specific, not YAML standard)
  if yaml_string:
    yaml_string = yaml_string.replace("- {include_here: null}",'%include "./page_cb.yaml"')
  with open(filename, 'w') as file:
    file.write(yaml_string)

  return True

def sanitize_config_dict(config_dict, log, context=""):
  """
  Recursively checks all strings (keys and values) in a configuration dictionary
  for potentially dangerous characters. Only applies aggressive sanitization to fields 
  that will be used as SQL identifiers (tables, columns) or shell commands.
  
  Allows: Alphanumeric, spaces, dashes, dots, slashes (/), square brackets ([]), hash (#).
  Strips: Quotes (single/double), semicolons, and other potentially dangerous symbols.
  
  Returns the sanitized dictionary, or raises a ValueError if a critical key is invalid.
  """
  # We use a pattern that matches what we ALLOW, and replace anything else.
  # \w: alphanumeric and underscore
  # \s: whitespace (spaces)
  # \-\.\/\[\]\H: dash, dot, slash (needed for URLs, dates, filenames), square brackets, hash
  # The ^ negates it, so we match anything NOT in this list.
  unsafe_pattern = re.compile(r'[^\w\s\-\.\/\[\]\#]')

  # Only sanitize keys that are known to be used as SQL identifiers.
  # This list must include any key whose VALUE becomes a column or table name.
  # Note: The keys of the 'metrics' dictionary are the column names.
  # The keys of the top-level dict are the repo/table names.
  dangerous_contexts = ['table', 'group_by', 'annotations'] # Values in these lists become SQL columns

  def check_and_clean_string(s, is_key=False, field_context=""):
    if not isinstance(s, str):
      return s
    
    # If this is one of the keys (e.g., metric names)
    if is_key:
      # Dictionary keys are often used as metric names (SQL columns) or tab names,
      # So we need to check all to be safe.
      cleaned = unsafe_pattern.sub('', s)
      if cleaned != s:
        error_msg = f"Invalid characters in config key '{s}'. Only alphanumeric, spaces, -, ., /, [, ], and # allowed."
        log.error(error_msg + "\n")
        raise ValueError(error_msg)
      return cleaned

    # Only sanitize the value if it belongs to a known dangerous context list.
    # For example, if field_context is 'table', s might be 'Node Count'. We sanitize it.
    # If field_context is 'regex', we leave it alone.
    if field_context in dangerous_contexts:
      cleaned = unsafe_pattern.sub('', s)
      if cleaned != s:
        log.warning(f"Sanitized unsafe string in {context or 'config'} under '{field_context}': '{s}' -> '{cleaned}'\n")
      return cleaned
      
    # If it's a value in a safe context (regex, description, mode), return it untouched.
    return s

  def sanitize_recursive(data, current_context=""):
    if isinstance(data, dict):
      clean_dict = {}
      for k, v in data.items():
        # Sanitize the key itself
        clean_k = check_and_clean_string(k, is_key=True, field_context=k)
        
        # We pass the key 'k' down as the context for its value 'v'.
        # If v is a list (like group_by: [A, B]), the items in the list will receive 'group_by' as context.
        clean_v = sanitize_recursive(v, current_context=clean_k)
        clean_dict[clean_k] = clean_v
      return clean_dict
      
    elif isinstance(data, list):
      # Items in a list inherit the context of the list's key
      return [sanitize_recursive(item, current_context) for item in data]
      
    else:
      return check_and_clean_string(data, is_key=False, field_context=current_context)

  return sanitize_recursive(config_dict)

def fetch_remote_config(repo_config, log):
  """
  Fetches a single file directly from a Git repository via API, without cloning.
  Currently supports GitLab repositories.
  """
  host_url = repo_config.get('host')
  filepath = repo_config.get('include')
  branch = repo_config.get('branch', 'main')
  token = repo_config.get('token')

  if not host_url or not filepath:
    log.error("Missing 'host' or 'include' in configuration for remote fetch.\n")
    return None

  try:
    # Parse the host URL to build the GitLab API request
    # Example host: https://gitlab.jsc.fz-juelich.de/SLPP/pepc/pepc-de-pthread
    parsed_url = urlparse(host_url)
    
    # The project path is everything after the domain, without leading/trailing slashes or .git
    project_path = parsed_url.path.strip('/').replace('.git', '')
    
    # GitLab API requires the project path to be URL-encoded
    encoded_project_path = quote(project_path, safe='')

    #Normalize the filepath to remove './' or '../' artifacts ---
    clean_filepath = os.path.normpath(filepath)

    # Build the GitLab API URL for a single file
    # Format: https://gitlab.example.com/api/v4/projects/<encoded_path>/repository/files/<filepath>/raw?ref=<branch>
    api_url = f"{parsed_url.scheme}://{parsed_url.netloc}/api/v4/projects/{encoded_project_path}/repository/files/{quote(clean_filepath, safe='')}/raw"
    
    params = {'ref': branch}
    headers = {}
    
    # Add Private-Token header if a token is provided
    if token:
      headers['PRIVATE-TOKEN'] = token

    log.info(f"Fetching remote configuration via API: {api_url} (ref: {branch})\n")
    
    response = requests.get(api_url, headers=headers, params=params, timeout=10)
    
    if response.status_code == 200:
      # Parse the downloaded text as YAML
      included_config = yaml.safe_load(response.text)
      if isinstance(included_config, dict):
        return included_config
      else:
        log.error(f"Remote file '{clean_filepath}' is not a valid YAML dictionary.\n")
        return None
    else:
      log.error(f"Failed to fetch remote config (HTTP {response.status_code}): {response.text}\n")
      return None

  except yaml.YAMLError as ye:
    log.error(f"YAML Parsing Error in remote configuration '{filepath}':\n{ye}\n")
    return None
  except Exception as e:
    log.error(f"Error fetching remote configuration: {e}\n")
    return None

class BenchRepo:
  """
  Class that stores and processes information from Slurm output  
  """

  # Default colormap to use on the footer
  DEFAULT_COLORMAP = 'tab10'
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
  # Default style of the plots
  DEFAULT_TRACE_STYLE = {
    'type': 'scatter',
    'mode': 'markers',
    'marker': {
      'opacity': 0.9,
      'size': 5
    }
  }

  def __init__(self,name="",config="",tab=None,lastts=None,skipupdate=False):
    self._dict = {}   # Dictionary with modified information (which is output to LML)
    self._name = name # Name of the group (outer key)
    self._tab = tab   # Name of the tab (if that's the case, otherwise None)
    self._lastts = lastts # Can be None (disabled), 0 (new), or >0 (existing)
    self._data = {}  # Data to be stored on the object
    self._skipupdate = skipupdate # Skip update of repos (when they were already cloned). Good to use when no new points exist (e.g., 2 consecutive runs)

    # If name is not given, this is the main object to collect the separate entries
    if name and config:
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

  @staticmethod
  def deep_update(target, override):
    """
    Recursively update a dictionary.
    """
    for key, value in override.items():
      if isinstance(value, dict):
        # Get the existing value or an empty dict, then recurse.
        target[key] = BenchRepo.deep_update(target.get(key, {}), value)
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

  @staticmethod
  def prepare_git_url(host, username, password):
    """
    Injects credentials into a Git URL for HTTPS cloning.
    Returns the authenticated URL.
    """
    if username:
      credentials = quote(username) + (f":{quote(password)}@" if password else "@")
      return host.replace("://", f"://{credentials}")
    return host

  def get_or_update_repo(self,folder="./"):
    """
    Getting folder to clone or pull the repo
    If not given, use current working directory
    (Env vars are expanded)
    """
    # Determine unique folder name
    # If tab exists, folder becomes ./Bench_Tab, otherwise ./Bench
    repo_dir_name = f"{self._name}_{self._tab}" if self._tab else self._name
    folder = os.path.expandvars(os.path.join(folder, repo_dir_name))

    # Storing folder to use later when getting sources
    benchmark_data = self._get_benchmark_data(self._name, self._tab)
    config = benchmark_data['config']
    config['folder'] = folder

    auth_host = self.prepare_git_url(config.get('host', ''), config.get('username'), config.get('password'))
    config['host'] = auth_host

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
        branch = config['branch']
        # Allow alphanumeric, dash, underscore, slash. Reject everything else.
        if not re.match(r'^[\w\-\/]+$', branch):
            self.log.error(f"Invalid characters in branch name: '{branch}'. Aborting.\n")
            return False
            
        cmd = ['git', '-C', folder, 'switch', '-q', branch]
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
        # and if so, get all files inside them (RECURSIVELY) into 'sources' set
        for folder in source_list:
          current_folder = os.path.join(config['folder'], folder)
          if not os.path.isdir(current_folder):
            self.log.error(f"Folder '{current_folder}' does not exist! Skipping...\n")
            continue
          # Walk the directory tree to find all files recursively
          for root, _, files in os.walk(current_folder):
            # Construct full paths for all files in this directory at once
            # and add them to the set in one go.
            sources.update(os.path.join(root, fn) for fn in files)
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

    # Always include 'ts' because it is mandatory for DB updates
    # For that, 'ts' must be defined in the metrics section
    used_metrics.add('ts') 

    # Set to store metrics that are strictly required for plots (to not add default values)
    plot_metrics = set()
    x_axis_metrics = set() # Track x-axis metrics

    # Add metrics from the table parameters
    used_metrics.update(config.get('table', []))
    # Add metrics from all plots
    for tab_name, plot_config in self._iter_plots(config):
      # Add the x and y axes if they are defined
      if x := plot_config.get('x'):
        used_metrics.add(x)
        plot_metrics.add(x)
        x_axis_metrics.add(x)
      if y := plot_config.get('y'):
        used_metrics.add(y)
        plot_metrics.add(y)
      
      # Add all metrics used for plot curves/traces and annotations
      group_by_cols = plot_config.get('group_by', [])
      used_metrics.update(group_by_cols)
      plot_metrics.update(group_by_cols)
      used_metrics.update(plot_config.get('annotations', []))

      # Starting a set to store the possible value of each of the grouping parameters
      for key in group_by_cols:
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
    # Determine strictly required keys (those without a default value)
    required_keys = set()
    for csv_header, metric_name in headers.items():
      # If the metric has a user-defined default, it is NOT required in the file
      if metrics_section[metric_name].get('default') is not None:
          continue
      required_keys.add(csv_header)
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
              except (ValueError, SyntaxError) as e:
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
        missing_keys = required_keys - set(available_keys)
        if missing_keys:
          keys_str = ", ".join(f"'{key}'" for key in sorted(list(missing_keys)))
          self.log.error(f"Required keys {keys_str} not found in file header of source {source}. Skipping...\n")
          continue

        # Identify CSV headers that correspond to ANY required X-axis metric
        # We need to map Internal Name -> CSV Header
        # headers dict is {CSV_Header: Internal_Name}
        # We want a list of CSV Headers where Internal_Name is in x_axis_metrics
        required_x_headers = [h_csv for h_csv, h_int in headers.items() if h_int in x_axis_metrics]

        # Getting data from file (CSV or JSON)
        for line in data:

          # Check if ALL required X-axis metrics present in the content are valid
          # If any required X metric is empty, skip the line.
          skip_line = False
          for x_header in required_x_headers:
            if not str(line.get(x_header, '')).strip():
              self.log.debug(f"Skipping line due to empty x-axis value for '{headers[x_header]}'.\n")
              skip_line = True
              break
          
          if skip_line:
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

      # Getting common data and metrics that are obtained from filename or from metadata
      # This is done BEFORE conversion, so we can validate and set status properly
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
          
          # Check if the regex captured a group
          if not match.groups():
            self.log.error(f"Regex '{spec['regex']}' matched '{source}' but did not capture any value (missing parentheses?). Skipping '{metric_name}'...\n")
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

      # If current_data is not empty but no x_axis_metrics are given, we can't plot
      missing_x = [x for x in x_axis_metrics if x not in current_data[0]]
      if current_data and missing_x:
        self.log.error(f"x-axis metric(s) {missing_x} could not be obtained for '{combined_name}'.\n")
        return False # Abort processing

      # Perform validation (to set the _status) and default-setting on each line
      # This is done BEFORE conversion, so empty/failed values don't crash the converter
      # and are kept for status history.
      for line in current_data:
        # Assume the run is successful until proven otherwise.
        # If a status already exists (e.g., from common_data), respect it.
        run_status = line.get('_status', "S")

        # Use `used_metrics` to check all required fields.
        for metric in used_metrics:
          is_empty = False
          
          # Check if metric exists and has content
          if metric in line:
            val = str(line.get(metric, '')).strip()
            if not val or val.lower() in ['none', 'null', 'nan']:
                is_empty = True
          else:
            # Metric is missing entirely from the source (e.g. optional column)
            is_empty = True

          # If the value is valid (exists and not empty), skip to next metric
          if not is_empty:
            continue
            
          # Handling Missing/Empty Values:

          metric_type = metrics_types.get(metric, 'str')
          
          # If the config has a 'default' key, use it
          specific_default = metrics_section[metric].get('default')
          
          if specific_default is not None:
            # Use the user-defined default
            line[metric] = specific_default
            # Note: We do NOT set status to 'F' here, because the user provided a fallback.
            # So, it is treated as a valid value.
          
          else:
            # Fallback to standard logic (Global Defaults)

            # If a non-string value is empty, it's a failure and needs a default.
            # The default value of the string is '', so missing strings should not
            # trigger 'F' status - which may be not intended in some cases,
            # but for others (i.e., 'flags used'), it's necessary
            # If a non-string parameter is empty AND no specific default exists, it's a failure.
            if metric_type != 'str':
              run_status = "F"
            
            # For the plot metrics, set the problematic value to None, so it's not plotted
            if metric in plot_metrics:
              run_status = "F"
              # Set the value to None so it will be skipped during plotting.
              line[metric] = None 
            else:
              # Set the value to the global type default.
              line[metric] = self.default.get(metric_type, '')

        # Set the final, determined status for the line
        line['_status'] = run_status

      # Before filtering the data, we capture a "stub" record
      # containing ONLY the metadata (common_data) + status + timestamp.
      # We will use this if all data rows are filtered out.
      stub_record = None
      if current_data:
        # Start with common data (System, Experiment, etc.)
        stub_record = common_data.copy()
        
        # Add the status from the first validated row (which reflects metadata health)
        stub_record['_status'] = current_data[0]['_status']

        # Initialize all content metrics to None, except for x-axis metrics
        # We must preserve x so the point exists on the graph axis
        for m in list(headers.values()) + list(calc_headers.keys()): 
          if m not in x_axis_metrics: 
            stub_record[m] = None
          elif m in current_data[0]:
            # Preserve the x value from the first row if it's not in common_data
            stub_record[m] = current_data[0][m]

      # Applying filters 'exclude' and/or 'include' for each metric, when present
      # (This must be done before collecting the unique graph parameters
      # to remove unwanted values, but should be done after the validation for the status
      # to avoid filtering failed runs and keep them in the status history)
      self.apply_pattern(
                          current_data,
                          exclude=to_exclude,
                          include=to_include
                        )

      # If data was filtered down to nothing, but we started with valid data (stub exists),
      # assume we want to keep the metadata record.
      if not current_data and stub_record:
        current_data.append(stub_record)

      # Converting data obtained from file content and multiplying by factor, when present
      # (Here we skip failed lines, since they don't have valid values)
      for key in list(headers.values())+list(calc_headers.keys()):
        # Getting the type of the metric
        mtype = metrics_types[key]
        for data in current_data:
          val = data.get(key)

          # Skip if value is missing or None (should be already handled by validation or stub)
          if val is None:
            continue

          # Skip if value is the default (already handled)
          if val == self.default.get(mtype): continue

          # Only skip if it's an empty string that would crash conversion for non-strings
          if val == '' and mtype != 'str':
              continue
          
          if mtype == 'str':
            convert = metrics_section[key].get('regex')
          else:
            convert = metrics_section[key].get('factor')
          try:
            data[key] = self.convert_data(
                                          val,
                                          vtype='ts' if key == 'ts' else mtype,
                                          factor=convert,
                                          )
          except ValueError:
            self.log.debug(f"Cannot convert value '{val}' for '{key}' in source {source}! Skipping conversion...\n")
            continue

      # Collecting unique values for graph parameters in current source:
      # (This has to be done before cleaning the old ts to be able to
      # collect all unique values)
      for param in graphparameters:
        # Get type info to help decide if we should filter defaults
        p_type = metrics_types.get(param, 'str')
        p_default = self.default.get(p_type)

        # Logic to keep values in graphparameters:
        # 1. data[param] is not None; OR
        # 2. It is a string (We allow empty strings/defaults for strings)
        # 3. It is not the default value (We hide "-1" for failed ints/floats)
        valid_values = [
            data[param] for data in current_data
            if data.get(param) is not None 
            and (p_type == 'str' or data[param] != p_default)
        ]
        
        graphparameters[param].update(valid_values)

      self.log.debug(f"Data for {source} contains: {current_data}\n")  
      self.log.debug(f"Headers: {metrics_types}\n")

      if current_data:
        # Saving all raw data, including all ts, to be able to get all combinations for graphs
        raw_data += current_data

      # Filtering older timestamps if tracking is enabled (not None) and storing in self._dict
      # to be written out in LML
      # (This is done at the end to allow the possibility of ts to be added 
      # either from content or from common_data)
      if self._lastts is not None:

        # We need 'ts' to filter. Check the first row (if data exists).
        if current_data and 'ts' not in current_data[0]:
          self.log.error(f"Data in '{combined_name}' does not contain 'ts', but 'tsfile' tracking is enabled. Cannot filter by time.\n")
        else:
          # Filter: Keep only new data
          # Note: self._lastts defaults to 0, so if new, all data > 0 is kept.
          current_data[:] = [data for data in current_data if data['ts'] > self._lastts]

          # Storing temporary lastts from last timestamp of current data
          if current_data:
            # Calculate max of current data, existing max (lastts_temp), and the previous boundary (_lastts)
            # This ensures _lastts only moves forward.
            lastts_temp = max([data['ts'] for data in current_data] + [self._lastts, lastts_temp])

      if current_data: # Adding an id to current data, to have an unique identifier for the csv file generation
        for data in current_data:
          # Generate a unique ID for self._dict
          unique_key = f"{combined_name}_{next(self._counter)}"
          
          # Store this key in the raw data object so we can use it later for mapping
          data['__output_key'] = unique_key 
          
          # Add to self._dict
          self._dict[unique_key] = data | {
            'id': '_'.join([self._format_id_value(data.get(key)) for key in parameters])
          }

    # Storing new lastts from last timestamp of all data
    if self._lastts is not None:
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
        typed_value = dateutil.parser.parse(raw_value).timestamp()
        value_type = 'ts' # using type 'ts' for timestamp
      else:
        self.log.error(f"Type '{spec['type']}' for metric '{metric_name}' not recognised! Use 'date', 'str', 'int', 'float', 'bool', or 'ts'. Skipping metric...\n")
        return None, None
    else:
      # Default type handling
      if metric_name == 'ts': # if type is not given for metric 'ts'
        typed_value = dateutil.parser.parse(raw_value).timestamp()
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

  def validate_metrics(self) -> bool:
    """
    Runs configured validation logic on the collected raw data.
    Returns: True if all validations ran (or were skipped safely), False on critical error.
    """
    benchmark_data = self._get_benchmark_data(self._name, self._tab)
    raw_data = benchmark_data['raw']
    metrics_section = benchmark_data['config']['metrics']
    
    # Initialize a dictionary to store layout additions per metric
    benchmark_data.setdefault('validation_layouts', {})

    if not raw_data:
      return True # No data to validate is technically a success

    for metric_name, spec in metrics_section.items():
      if 'validate' not in spec:
        continue
      
      validators = spec['validate']
      if not isinstance(validators, list):
        validators = [validators]

      for v_spec in validators:
        func_name = v_spec.get('name')
        module_name = v_spec.get('module')

        validator_func = None

        # Resolving function from module
        if module_name:
          try:
            mod = __import__(module_name, fromlist=[func_name])
            validator_func = getattr(mod, func_name)
          except (ImportError, AttributeError) as e:
            self.log.error(f"Validator '{func_name}' in module '{module_name}' could not be loaded: {e}\n")
            return False # Critical config error
        else:
          # Look in global scope (globals()) for the function
          if func_name in globals():
            validator_func = globals()[func_name]
          else:
            self.log.error(f"Validator function '{func_name}' not found.\n")
            return False # Critical config error

        # Preparing data for validation (Extract only the values for this metric)
        # We pass a copy of values to be safe.
        # We also need to map the results back to the rows, so order matters.
        values_to_check = [row.get(metric_name) for row in raw_data]

        # Calling validator function
        try:
          # API: func(values_list, params_dict) -> list of booleans
          validation_results, layout_additions = validator_func(values_to_check, v_spec)
        except Exception as e:
          # Catch errors raised by the validator (like the TypeError/ValueError we added)
          self.log.error(f"Validation failed for metric '{metric_name}' using '{func_name}': {e}\n")
          return False # Stop processing if validation crashes

        # Processing results
        if len(validation_results) != len(raw_data):
          self.log.error(f"Validator '{func_name}' returned {len(validation_results)} results, expected {len(raw_data)}.\n")
          return False

        # Store the layout additions for this metric
        if layout_additions:
          # Using setdefault and list extensions in case multiple validators 
          # (e.g. range AND outlier) add shapes to the same metric.
          metric_layouts = benchmark_data['validation_layouts'].setdefault(metric_name, {})
          
          if 'shapes' in layout_additions:
            metric_layouts.setdefault('shapes', []).extend(layout_additions['shapes'])
          if 'annotations' in layout_additions:
            metric_layouts.setdefault('annotations', []).extend(layout_additions['annotations'])

        for i, is_valid in enumerate(validation_results):
          if not is_valid:
            row = raw_data[i]

            # Check if row is already Failed (F)
            # Update status in the raw data (Internal State)
            row['_status'] = 'W'

            # Update status to Warning
            raw_data[i]['_status'] = 'W'
            # and the output dictionary (fot the LML output)
            output_key = row.get('__output_key')
            if output_key and output_key in self._dict:
              self._dict[output_key]['_status'] = 'W'
            # self.log.debug(f"Row {i} marked Warning by validator '{func_name}' on '{metric_name}'\n")
    return True


  def gen_configs(self,folder="./", history_n=5, failed_info=None):
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
    suffix = self._name.replace(" ","_") if self._name else 'cb'

    return_code = True

    # DBupdate config
    success = self.gen_dbupdate_conf(os.path.join(folder,f'db_{suffix}.yaml'),history_n=history_n)
    if not success:
      self.log.error("Error generating DB configuration file{}. Skipping...\n".format((' for \''+self._name+'\'') if self._name else ''))
      return_code = False

    # Page config
    success = self.gen_page_conf(os.path.join(folder,f'page_{suffix}.yaml'), failed_info=failed_info)
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

  def gen_dbupdate_conf(self, filename, history_n=5):
    """
    Create YAML file to be used in LLview for DBupdate configuration
    """
    self.log.info(f"Generating DB configuration file {filename}\n")

    lb = '\n' # Fix for backslash inside curly braces in f-strings (can be removed in Python >=3.12)

    # This list will hold all table definitions
    tables = []
    # This set will track unique benchmarks to generate the final aggregation tables
    benchmarks_processed = set()

    # Calculate length for N items: (N * 1 char for status) + (N-1 * 1 char for dash)
    history_str_len = (history_n * 2) - 1

    # Define the aggregation logic for status priority: F > W > S
    # If any row is 'F', the whole timestamp is 'F'.
    # Else if any row is 'W', the whole timestamp is 'W'.
    # Else 'S'.
    status_priority_sql = "CASE WHEN SUM(CASE WHEN \"_status\" = 'F' THEN 1 ELSE 0 END) > 0 THEN 'F' WHEN SUM(CASE WHEN \"_status\" = 'W' THEN 1 ELSE 0 END) > 0 THEN 'W' ELSE 'S' END"

    # Saving custom display names, in case they are given
    # to use on the cb_benchmarks query below
    custom_display_names = {}

    # Looping over all the benchmarks inside this object
    # (It can be done for each benchmark/tab or for all collected ones when singleLML is used)
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Add the benchmark name to our set for post-processing
      benchmarks_processed.add(benchname)

      # Table names cannot (should not?) contain spaces, but tab names may have spaces
      # This name is for the per-tab/per-benchmark tables
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")
      columns = []

      # Getting references to relevant data
      metrics = benchmark_data['metrics']
      config = benchmark_data['config']
      parameters = benchmark_data['parameters']

      # Extract the Custom Display Name
      custom_display_names[benchname] = config.get('name', benchname)

      # Looping over all the metrics that are used in this benchmark, which should be put into the DB
      for metric, mtype in metrics.items():
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
                                                        'mode': 'replace',
                                                        'sql_update_contents': {
                                                          'vars': 'mintsinserted',
                                                          'sqldebug': 1,
                                                          # This SQL first deletes its old entries from the timestamp table,
                                                          # then inserts the new ones, tagging them with its own name as the source.
                                                          # Group by timestamp; MIN(_status) ensures 'F' wins over 'S'
                                                          'sql': f"""DELETE FROM "cb_{benchname.replace(' ','_')}_timestamps" WHERE source = "{combined_name}";
              INSERT INTO "cb_{benchname.replace(' ','_')}_timestamps" ("ts", "source", "_status")
                        SELECT "ts", "{combined_name}", "_status"
                        FROM "cb_{combined_name}_data";
""".strip(),
                                                                    },
                                                      },
                                            # This triggers its own overview and the benchmark's timestamp aggregator
                                            'update_trigger': [f"cb_{combined_name}_data", f"cb_{combined_name}_overview", f"cb_{benchname.replace(' ','_')}_timestamps"]
                                          },
                                'columns': columns,
                              }
                    })

      # Getting list of metrics that are plotted on the graphs
      graph_metrics = [plot['y'] for tab, plot in self._iter_plots(config) if 'y' in plot]

      # Prepare sanitized parameter names and aggregated metrics strings
      params_str = ''.join([f', "{key.replace(" ", "_")}"' for key in parameters])
      insert_metrics_str = ''.join([f',{lb}                                "{m.replace(" ", "_")}_min", "{m.replace(" ", "_")}_avg", "{m.replace(" ", "_")}_max"' for m in graph_metrics])
      select_metrics_str = ''.join([
          f',{lb}                                MIN(NULLIF("{m.replace(" ", "_")}", "")),AVG(NULLIF("{m.replace(" ", "_")}", "")),MAX(NULLIF("{m.replace(" ", "_")}", ""))' 
          for m in graph_metrics
      ])
      groupby_params_str = ', '.join([f'"{key.replace(" ", "_")}"' for key in parameters])

      # Getting history of status (Oldest -> Newest)
      # Here we want to generate one status entry per timestamp
      # We use a subquery with ORDER BY to ensure GROUP_CONCAT joins them in chronological order.

      # This tells the subquery: "Only look at data that matches the current Overview row"
      # Example result: T2."System" = T1."System" AND T2."Experiment" = T1."Experiment"
      match_conditions = []
      for key in parameters:
        col_name = key.replace(' ', '_')
        match_conditions.append(f'T2."{col_name}" = T1."{col_name}"')
      
      match_expr = " AND ".join(match_conditions)
      if not match_expr: match_expr = "1=1" # Safety fallback

      # Building the History Subquery:
      # - Filter by the current parameters (match_expr)
      # - Group by "ts" to collapse multiple points into ONE status
      # - Use status_priority_sql to ensure F > W > S
      # - Order by "ts" ASC
      # - Concatenate the results
      inner_history_sql = f"SELECT GROUP_CONCAT(daily_stat, '-') FROM (SELECT {status_priority_sql} as daily_stat FROM \"cb_{combined_name}_data\" AS T2 WHERE {match_expr} GROUP BY \"ts\" ORDER BY \"ts\" ASC)"

      # We also need a subquery to count the DISTINCT timestamps for the final dash logic (when there are further status points)
      count_subquery = f"SELECT COUNT(DISTINCT \"ts\") FROM \"cb_{combined_name}_data\" AS T2 WHERE {match_expr}"

      history_expr = f"(CASE WHEN ({count_subquery}) > {history_n} THEN '-' || substr(({inner_history_sql}), -{history_str_len}) ELSE ({inner_history_sql}) END)"

      # Build a HAVING clause to exclude groups where ANY grouping parameter is empty
      # (These "ghost" groups would be "stuck" separately on the table, since they are not valid runs)
      # This string effectively hides rows where the primary keys are missing/invalid from the table
      having_clauses = [f'"{k.replace(" ", "_")}" <> \'\'' for k in parameters]
      having_str = "HAVING " + " AND ".join(having_clauses) if having_clauses else ""

      # Description of the overview table
      tables.append({'table': { 'name': f'cb_{combined_name}_overview',
                                'options': {
                                            'update': {
                                                        'sql_update_contents': {
                                                          'sql': f"""DELETE FROM "cb_{combined_name}_overview";
                INSERT INTO "cb_{combined_name}_overview" ("id", "name", "_status", "count", "valid_count", "min_ts", "max_ts"
                                {params_str}{insert_metrics_str}
                                )
                        SELECT id, "{custom_display_names[benchname]}",
                                {history_expr},
                                COUNT("ts"),
                                SUM(CASE WHEN "_status" <> 'F' THEN 1 ELSE 0 END),
                                MIN("ts"), MAX("ts")
                                {params_str}{select_metrics_str}
                        FROM (
                            SELECT * FROM "cb_{combined_name}_data" ORDER BY "ts" ASC
                        ) AS T1
                        GROUP by {groupby_params_str}
                        {having_str};
""".strip(),
                                                                    },
                                                      },
                                          },
                                'columns': [
                                  {'name': 'id',             'type': 'ukey_t'},
                                  {'name': 'name',           'type': 'str_t'},
                                  {'name': '_status',        'type': 'str_t'},
                                  {'name': 'count',          'type': 'int_t'},
                                  {'name': 'valid_count',    'type': 'int_t'},
                                  {'name': 'min_ts',         'type': 'ts_t'},
                                  {'name': 'max_ts',         'type': 'ts_t'},
                                ]
                                +[{'name': key.replace(' ', '_'), 'type': f'{metrics[key]}_t'} for key in parameters] 
                                # Aggregates (min/avg/max) are ALWAYS floats and can be NULL (in case there are failed runs for all entries of a row)
                                +[{'name': f"{key.replace(' ', '_')}_{suffix}", 'type': 'float_null_t'} for key in graph_metrics for suffix in ['min','avg','max']],
                              }
                    })

    # After processing all tabs, create the intermediate timestamp tables for each benchmark
    for benchname in benchmarks_processed:
      # Subquery to get one status per timestamp (F wins over S, so we use MIN) for the global timeline
      # No match_expr needed here because we are aggregating the whole benchmark table.
      inner_history_sql_global = f"SELECT GROUP_CONCAT(daily_stat, '-') FROM (SELECT {status_priority_sql} as daily_stat FROM \"cb_{benchname.replace(' ','_')}_timestamps\" GROUP BY \"ts\" ORDER BY \"ts\" ASC)"

      # Subquery to count UNIQUE runs for the dash logic
      count_subquery_global = f"SELECT COUNT(DISTINCT \"ts\") FROM \"cb_{benchname.replace(' ','_')}_timestamps\""

      history_expr_global = f"(CASE WHEN ({count_subquery_global}) > {history_n} THEN '-' || substr(({inner_history_sql_global}), -{history_str_len}) ELSE ({inner_history_sql_global}) END)"

      tables.append({'table': {
                                'name': f"cb_{benchname.replace(' ','_')}_timestamps",
                                # This table's job is to collect all timestamps and trigger the final update
                                'options': {
                                            'update': {
                                                        'sql_update_contents': {
                                                          'sqldebug': 1,
                                                          'sql': f"""DELETE FROM "cb_benchmarks" WHERE "id"="{benchname}";
                          INSERT INTO "cb_benchmarks" ("id", "name", "count", "valid_count", "min_ts", "max_ts", "_status")
                                    SELECT "{benchname}",
                                          "{custom_display_names[benchname]}",
                                          COUNT("ts"),
                                          SUM(CASE WHEN "_status" <> 'F' THEN 1 ELSE 0 END),
                                          MIN("ts"), MAX("ts"),
                                          {history_expr_global}
                                    FROM (SELECT * FROM "cb_{benchname.replace(' ','_')}_timestamps" ORDER BY "ts" ASC);
""".strip(),
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

  def gen_page_conf(self, filename, failed_info=None):
    """
    Create YAML file to be used in LLview for Page configuration
    """
    self.log.info(f"Generating Page configuration file {filename}\n")

    # Intermediate dictionary to group pages and tabs by benchmark name
    # The keys will be the benchmark names
    pages_data = {}

    failed_info = failed_info or {}

    # Looping over all the benchmarks and tabs
    for benchname, tabname, benchmark_data in self._iter_all_data():
      # Create the file-safe name for paths
      combined_name = benchname.replace(" ","_") + (f"_{tabname.replace(' ','_')}" if tabname else "")

      # Getting reference to config
      config = benchmark_data['config']

      # If the user provided 'name:' in the root config, use it
      # otherwise, fall back to the benchname (the repo name)
      custom_display_name = config.get('name', benchname)

      # Common dictionary structure for a page or a tab's content
      content_definition = {
        'default': False,
        'template': f'/data/LLtemplates/CB_{combined_name}',
        'context': f"data/cb/cb_{combined_name}.csv",
        'footer_graph_config': f"/data/ll/footer_cb_{combined_name}.json",
        'description': config.get('description',''),
        'ref': [ 'datatable' ],
        'data': {
          'default_columns': [ 'Name', 'Timings', 'Parameters', '#Points', 'Status' ],
          'info': [{'Benchmark' : custom_display_name}] 
          }
      }
      if tabname:
        # --- This is a tab ---
        # Get or create the main page entry for this benchmark
        # This ensures we have a place to append the tab
        benchmark_page = pages_data.setdefault(benchname, {
          'name': custom_display_name,
          'section': f'cb_{custom_display_name.replace(" ","_")}',
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
        content_definition['name'] = custom_display_name
        content_definition['section'] = f'cb_{custom_display_name.replace(" ","_")}'
        
        # Store it directly under its benchmark name
        pages_data[benchname] = content_definition

    # Process Failed Data and Warnings
    # failed_info format: { repo_name: { tab_name: ["Error 1", "Error 2"] } }
    
    is_global_dict = any(isinstance(v, dict) for v in failed_info.values()) if failed_info else False

    def process_failure(benchname, tabname, error_msgs):
      # Join multiple error/warning messages with line breaks
      joined_msgs = "<br>".join(error_msgs)
      formatted_error = f"<div style='color:red; margin-top:10px; padding:10px; border:1px solid red;'>{joined_msgs}</div>"
      
      # Try to get the custom name if the config survived parsing.
      # If the repo failed immediately (e.g. bad Git URL), _data won't have it,
      # so we safely fall back to the internal benchname.
      custom_name = benchname
      if benchname in self._data:
        # Get the config from the first available tab (or root if no tabs)
        first_key = list(self._data[benchname].keys())[0]
        root_cfg = self._data[benchname][first_key].get('config', {})
        custom_name = root_cfg.get('name', benchname)
      
      # Sanitize for the section ID (consistent with 'gen_benchmark_link' on JURI)
      safe_section_name = custom_name.replace(" ", "_")

      if tabname:
        # Tab level:
        if benchname not in pages_data:
          # If the benchmark does not exist, the entire repo failed to initialize -> create parent stub
          pages_data[benchname] = {
            'name': custom_name, 
            'section': f'cb_{safe_section_name.replace(" ","_")}',
            'description': "Benchmark partially or fully failed to load.",
            'tabs': []
          }
        
        benchmark_page = pages_data[benchname]
        
        # Check if the specific tab already exists (e.g., it succeeded but had warnings)
        existing_tab = next((t for t in benchmark_page.get('tabs', []) if t.get('name') == tabname), None)
        
        if existing_tab:
          # If the tab exists and has real data,
          # just append the warning box to its existing description.
          existing_tab['description'] = existing_tab.get('description', '') + formatted_error
        else:
          # If the tab completely failed and isn't in pages_data,
          # create a stub tab to show the error.
          stub_tab = {
            'name': tabname,
            'section': f'cb_{tabname.replace(" ","_")}',
            'default': False,
            'description': formatted_error,
            'ref': [] # No datatable
          }
          benchmark_page['tabs'].append(stub_tab)
            
      else:
        # Root level:
        if benchname in pages_data:
          # If the standalone page exists (it had warnings, but succeeded)
          pages_data[benchname]['description'] = pages_data[benchname].get('description', '') + formatted_error
        else:
          # If the standalone page failed completely
          pages_data[benchname] = {
            'name': custom_name,
            'section': f'cb_{safe_section_name.replace(" ","_")}',
            'default': False,
            'description': formatted_error,
            'ref': []
          }

    if failed_info:
      if is_global_dict:
        for b_name, tabs in failed_info.items():
          for t_name, err_list in tabs.items():
            process_failure(b_name, t_name, err_list)
      else:
        # We only have the tabs dict for self._name
        for t_name, err_list in failed_info.items():
          process_failure(self._name, t_name, err_list)

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
            'headerTooltip': "Minimum timestamp on the benchmark",
            'cellDataType': "text",
          },
          {
            'field': "max_ts",
            'headerName': "Date of Last Run", 
            'headerTooltip': "Maximum timestamp on the benchmark",
            'cellDataType': "text",
          },
        ]
      },
      {
        'headerName': "#Points",
        'groupId': "#Points",
        'children': [
          {
            'field': "count",
            'headerName': "Total", 
            'headerTooltip': "Total number of points",
          },
          {
            'field': "valid_count",
            'headerName': "Valid", 
            'headerTooltip': "Number of valid points",
          },
        ]
      },
      {
        'field': "_status",
        'headerName': "Status",
        'cellRenderer': "(params) => cell_status(params)",
        'headerTooltip': 'Status of the last runs, oldest (left) to newest (right)',
        'cellStyle': { 
          'display': 'flex', 
          'align-items': 'center', 
          'justify-content': 'center',
        }
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
      columns_str = [f'"{key.replace(" ","_")}"' for key in columns]
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
      'int': '%s',   # We will use the string output to allow empty values without errors on LLview's workflow
      'float': '%s', # We will use the string output to allow empty values without errors on LLview's workflow
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
      columns_str = [f'"{key.replace(" ","_")}"' for key in columns]
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

          x_metric = plot_config.get('x', 'ts') # Default to ts if missing
          x_col_name = 'date' if x_metric == 'ts' else x_metric

          # CALCULATING VALID COMBINATIONS FOR THIS SPECIFIC PLOT
          # Get the grouping keys (traces)
          current_group_by = plot_config.get('group_by', [])

          # Filter graphparameters to only include keys used in this plot's grouping
          # Sort the keys to ensure consistent column order
          sorted_keys = sorted([k for k in graphparameters.keys() if k in current_group_by])
          
          # Sort the values (sets) into lists to ensure consistent product generation
          sorted_value_lists = [sorted(list(graphparameters[k])) for k in sorted_keys]

          valid_combinations = [] 
          # Generating all possible combinations of the graph parameters for this plot
          if sorted_keys:
            # Use the sorted lists
            for combination in product(*sorted_value_lists):
              valid_combination = True
              # Creating dictionary for current combination
              # Zip with sorted_keys
              current_combination = {key:value for key,value in zip(sorted_keys, combination)}
              
              for key,value in current_combination.items():
                # If value is default one, ignore this combination, as it didn't have a valid value
                if self.default[metrics[key]] == value:
                  self.log.debug(f"Invalid combination {combination}, {key} has default value of {value}\n")
                  valid_combination = False
                  continue
                
                # If there's no value with the current combination, skip it
                # (Note: This checks if the combination exists in the raw data because even if nothing is plotted now, 
                # we have to plot the combinations for old points)
                if not any(set(current_combination.items()).issubset(set(data.items())) for data in raw_data):
                  self.log.debug(f"Combination {combination}, has no values\n")
                  valid_combination = False
                  continue
              
              if valid_combination:
                valid_combinations.append(current_combination)
            
            # Sorting list by key and value
            valid_combinations.sort(key=lambda d: tuple(sorted(d.items())))

          # Handle case where there are no groups/traces (single curve)
          # If valid_combinations is empty, we create a single dummy 'traceelem' (empty dict)
          combinations_to_process = valid_combinations if valid_combinations else [{}]

          # GET STYLES FROM THE COMBINED CONFIG
          # Since we propagated plot_settings into each plot, we read directly from plot_config.
          
          # Resolve Colors
          colors_config = plot_config.get('colors', {})
          current_colormap = colors_config.get('colormap', BenchRepo.DEFAULT_COLORMAP)
          current_skip = colors_config.get('skip', [])
          current_sort_key = colors_config.get('sort_strategy', BenchRepo.DEFAULT_SORT_KEY)

          # Resolve Layout
          current_trace_layout = plot_config.get('layout', {})
          # Resolve Styles
          current_trace_styles = plot_config.get('styles', {})

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
          for traceelem in combinations_to_process:
            color = next(colors)
            while color in current_skip: # Use current_skip
              color = next(colors)

            # Start with Hardcoded Default
            plot_properties = deepcopy(BenchRepo.DEFAULT_TRACE_STYLE)
            # Update with resolved styles (Merged Global + Local)
            self.deep_update(plot_properties, current_trace_styles)

            # If traceelem is populated (normal traces), generate name and 'where' clause
            # otherwise (traceelem is empty, single curve), generate a simple name without 'where' keys
            if traceelem:
              name_str = '<br>'.join(f"{key}: {traceelem[key]}" for mtype in sorted(self.default.keys(), reverse=True) for key in sorted(traceelem.keys()) if metrics[key] == mtype)
              # Creating 'where' to update 'ts' to 'date', as we do this change in the csv header
              where_clause = {}
              for k, v in traceelem.items():
                csv_key = 'date' if k == 'ts' else k
                where_clause[csv_key] = v

              update_dict = {
                'name': name_str,
                'where': where_clause
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
            # Get the annotations directly from the plot config
            current_graph_annotations = plot_config.get('annotations', [])

            if current_graph_annotations:
              onhover_data = {'onhover': [{key: {'name': key}} for key in current_graph_annotations]}
              plot_properties |= onhover_data
            
            trace = {'trace': plot_properties}
            traces.append(trace)  

          # Update layout with config ones (Merged Global + Local)
          layout = {
            'yaxis': {
              'title': graphelem + (f" [{config['metrics'][graphelem]['unit']}]" if "unit" in config.get('metrics', {}).get(graphelem, {}) else "")
            },
            'xaxis': {
              'title': x_metric if x_metric != 'ts' else None
            },
            'legend': {
              'x': "1.02", 'xanchor': "left", 'y': "0.98", 'yanchor': "top", 'orientation': "v"
            }
          }
          self.deep_update(layout, current_trace_layout)

          # Retrieve validation layout additions for this specific metric
          # Inject visual elements generated by validators like threshold lines
          validation_layouts = benchmark_data.get('validation_layouts', {}).get(graphelem, {})
          
          # Extend the layout with custom shapes if any were generated
          if validation_layouts.get('shapes'):
            layout.setdefault('shapes', []).extend(validation_layouts['shapes'])
            
          # Extend the layout with custom annotations if any were generated
          if validation_layouts.get('annotations'):
            layout.setdefault('annotations', []).extend(validation_layouts['annotations'])

          graph = {
            'graph': {
              'name': graphelem,
              'xcol': x_col_name,
              'layout': layout,
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
    elif isinstance(elements,list):
      # When elements is a list (e.g. 'metrics' list, containing a list of dicts)
      # Check if each of the elements of the list contains the patterns
      for idx,unit in enumerate(elements):

        # We want to preserve Failed runs to be able to set correctly the status history
        # If the unit (row) is marked as FAILED, we skip all filtering logic.
        # This ensures the failed run is kept in the list regardless of missing data.
        if isinstance(unit, dict) and unit.get('_status') == 'F':
            continue 
        
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
      try:
        return bool(re.search(patterns, unit))
      except re.error as e:
        self.log.error(f"Invalid Regex pattern '{patterns}': {e}\n")
        return False

    elif isinstance(patterns,list): # If list of rules
      for pattern in patterns: # loop over list - that can be strings or dictionaries
        if isinstance(pattern,str):  # If item in list is a simple string
          try:
            if re.search(pattern, unit):
              return True # Returns True if a pattern is found
          except re.error as e:
            self.log.error(f"Invalid Regex pattern '{pattern}': {e}\n")
            continue
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
        from credentials import get_user_pass # type: ignore
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
  parser = argparse.ArgumentParser(description="Git Plugin for LLview")
  parser.add_argument("--config",          default=False, help="YAML config file (or folder with YAML configs) containing the information to be gathered and converted to LML")
  parser.add_argument("--loglevel",        default=False, help="Select log level: 'DEBUG', 'INFO', 'WARNING', 'ERROR' (more to less verbose)")
  parser.add_argument("--singleLML",       default=False, help="Merge all sections into a single LML file")
  parser.add_argument("--tsfile",          default=False, help="File to read/write timestamp")
  parser.add_argument("--outfolder",       default=False, help="Reference output folder for LML files")
  parser.add_argument("--repofolder",      default=False, help="Folders where the repos will be cloned")
  parser.add_argument("--outconfigfolder", default=False, help="Folder to generate config files")
  parser.add_argument("--tabname",         default='Benchmarks', help="Default text on LLview tab")
  parser.add_argument("--skipupdate",      action='store_true', help="Skip updating the repos (if they don't exist, they will still be cloned)")
  parser.add_argument("--setdefault",      action='store_true', help="Set Benchmark page with 'default: true'")
  parser.add_argument("--statuspoints",    default=5, help="Set how many previous points are shown on the status column")

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
    if not isinstance(config, dict):
      log.error(f"Config file {args.config} must contain a dictionary/mapping.\n")
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
      if not isinstance(lastts, dict):
        # If the file does not return a dict, it's either empty or wrong. Restart the lastts dict here.
        lastts={}
    else:
      log.warning(f"'ts' file {args.tsfile} does not exist! Getting all results...\n")

  # When singleLML is used, the benchmarks are stored in this unique object
  unique = BenchRepo()

  # For separated benchmarks, the information is stored for individual output later
  successful_repos = {} 

  # Registry for failed repositories/tabs: we will collect the 
  # errors emmited to generate empty pages with the errors on the "description" box
  # Format: {'repo_name': {'tab_name': 'Error Message'}}
  # If it's a root-level error, 'tab_name' will be None.
  failed_repos = {}

  if config:
    # Start generic timer
    start_time = time.time()

    # Looping over outer entries, that should represent repositories
    for repo_name, repo_config in config.items():
      log.info(f"Processing '{repo_name}'\n")

      # Initialize registry for this repo
      failed_repos[repo_name] = {} 

      # Getting credentials for the current server
      repo_config['username'], repo_config['password'] = get_credentials(repo_name,repo_config)

      # For security: Define keys that users cannot override via 'include'
      protected_keys = ['host', 'branch', 'token', 'username', 'password', 'include']

      # Handling root-level remote configuration inclusion, if "include" is given
      if 'include' in repo_config:
        # Fetch the file directly into memory
        remote_config = fetch_remote_config(repo_config, log)

        if not remote_config:
          # If fetch_remote_config returned None (due to 404, bad YAML, etc.),
          # log an error and skip to the next repository.
          log.error(f"Failed to load root included configuration for '{repo_name}'. Skipping repository...\n")
          # Adding error to registry
          error_msg = f"<b>Configuration Error:</b> Failed to fetch included file '{repo_config['include']}'."
          failed_repos[repo_name].setdefault(None, []).append(error_msg)
          continue

        # Sanitize the fetched remote config, and remove protected keys from the downloaded file
        try:
          remote_config = sanitize_config_dict(remote_config, log, context=f"include file for {repo_name}")
        except ValueError:
          log.error(f"Failed to sanitize remote configuration for '{repo_name}'. Skipping repository.\n")
          # Adding error to registry
          error_msg = f"<b>Configuration Error:</b> Invalid characters in included file. {str(e)}"
          failed_repos[repo_name].setdefault(None, []).append(error_msg)
          continue
        for p_key in protected_keys:
          if p_key in remote_config:
            log.warning(f"Remote config attempted to override protected key '{p_key}'. Ignoring...\n")
            # Adding error to registry
            error_msg = f"<b>Configuration Warning:</b> Remote config cannot override '{p_key}'. Please contact admin."
            failed_repos[repo_name].setdefault(None, []).append(error_msg)
            del remote_config[p_key]

        # Merge the configurations
        # Apply the central repo_config ON TOP of the included remote config
        # to ensure secure settings (host, token) are not overwritten
        merged_config = deepcopy(remote_config)
        BenchRepo.deep_update(merged_config, repo_config)
        
        # Update the original repo_config in-place
        repo_config.clear()
        repo_config.update(merged_config)
        log.info(f"Successfully merged remote configuration for '{repo_name}'.\n")

      # Checking if tabs within a page exist to loop through them
      internal_tabs = False
      if "tabs" in repo_config:
        internal_tabs = True
        # Gathering configuration that will be common for all internal tabs
        common_config = {key:value for key,value in repo_config.items() if key !="tabs"}
        # Distributing common configuration for all internal tabs (rewriting specific configuration with the most internal one)
        for tab in list(repo_config['tabs'].keys()): # Using list of keys so we can safely delete broken tabs during iteration
          tab_config = repo_config['tabs'][tab]

          # Handling tab-level remote configuration inclusion, if "include" is given
          if 'include' in tab_config:
            # Creating a temporary config for fetching, inheriting host/token from common if needed
            fetch_config = {
              'host': tab_config.get('host', common_config.get('host')),
              'branch': tab_config.get('branch', common_config.get('branch', 'main')),
              'token': tab_config.get('token', common_config.get('token')),
              'include': tab_config['include']
            }
            # Fetch the file directly into memory
            remote_tab_config = fetch_remote_config(fetch_config, log)

            if not remote_tab_config:
              # If fetch_remote_config returned None (due to 404, bad YAML, etc.),
              # log an error and skip to the next repository.
              log.error(f"Failed to load included configuration for tab '{tab}' in '{repo_name}'. Skipping tab...\n")
              # Adding error to registry
              error_msg = f"<b>Configuration Error:</b> Failed to fetch included file for tab '{tab}'."
              failed_repos[repo_name].setdefault(tab, []).append(error_msg)
              del repo_config['tabs'][tab] # Remove the broken tab
              continue

            # Sanitize the fetched remote config, and remove protected keys from the downloaded file
            try:
              remote_tab_config = sanitize_config_dict(remote_tab_config, log, context=f"include file for tab {tab}")
            except ValueError:
              log.error(f"Failed to sanitize remote configuration for tab '{tab}'. Skipping tab.\n")
              # Adding error to registry
              error_msg = f"<b>Configuration Error:</b> Invalid characters in tab '{tab}'. {str(e)}"
              failed_repos[repo_name].setdefault(tab, []).append(error_msg)
              del repo_config['tabs'][tab]
              continue # Skip to the next tab
            for p_key in protected_keys:
              if p_key in remote_tab_config:
                log.warning(f"Remote tab config '{tab}' attempted to override protected key '{p_key}'. Ignoring...\n")
                # Adding error to registry
                error_msg = f"<b>Configuration Warning:</b> Remote config cannot override '{p_key}'. Please contact admin."
                failed_repos[repo_name].setdefault(tab, []).append(error_msg)
                del remote_tab_config[p_key]

            # Merging the configs: 
            # Apply the central tab_config on top of the included remote config
            merged_remote = deepcopy(remote_tab_config)
            BenchRepo.deep_update(merged_remote, tab_config)
            tab_config = merged_remote
            log.info(f"Successfully merged remote configuration for tab '{tab}'.\n")

          # Distributing common configuration for all internal tabs 
          # (rewriting common configuration with the now fully-resolved specific tab config)
          # Start with a deep copy of the common config
          merged_config = deepcopy(common_config)
          # Deep update it with the specific tab config
          # This ensures keys like 'plot_settings' get merged, not overwritten.
          BenchRepo.deep_update(merged_config, tab_config)
          
          # Store the final result
          repo_config['tabs'][tab] = merged_config

      # Normalizing the tabs or single page for loop
      group = repo_config['tabs'] if internal_tabs else {repo_name: repo_config}

      # This object will collect data from ALL tabs within this repository
      repo_bench = BenchRepo(name=repo_name) 

      # Start repo timer
      repo_start_time = time.time()

      # Loop over tabs (if existing) or single page
      # (group points to either the tabs or to the single page)
      for group_name, group_config in group.items():
        sources = group_config.get('sources') or {}
        group = 'tab' if internal_tabs else 'repository'
        # combined_name is used for logging and tracking specific tabs
        combined_name = f"{repo_name}:{group_name}" if internal_tabs else repo_name

        # Checking if something is to be done on current repo
        if not (sources.get('files') or sources.get('folders')):
          log.warning(f"No 'sources' of metrics to process for this {group}. Skipping...\n")
          error_msg = f"<b>Configuration Error:</b> No 'sources' defined."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue
        if not group_config.get('metrics'):
          log.warning(f"No 'metrics' to collect for this {group}. Skipping...\n")
          error_msg = f"<b>Configuration Error:</b> No 'metrics' defined."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue
        if not group_config.get('table'):
          log.warning(f"No 'table' to display for this {group}. Skipping...\n")
          error_msg = f"<b>Configuration Error:</b> No 'table' defined."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue
        if not group_config.get('plots'):
          log.warning(f"No 'plots' to display for this {group}. Skipping...\n")
          error_msg = f"<b>Configuration Error:</b> No 'plots' defined."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue

        # Propagate 'plot_settings' into individual plots
        # Get the global settings for this group (inherited from common_config if tabs exist)
        global_settings = group_config.get('plot_settings', {})
        plots_section = group_config.get('plots')

        # Normalize plots structure for iteration:
        # If it's a dict with 'tabs', we iterate over its values (lists of plots).
        # If it's a direct list, we wrap it in a list [plots_section].
        plots_groups = plots_section['tabs'].values() if (isinstance(plots_section, dict) and 'tabs' in plots_section) else [plots_section]

        # Propagate settings into every individual plot
        for plot_list in plots_groups:
          for i, plot in enumerate(plot_list):
            # Merge Global Settings + Specific Plot Settings
            # We start with globals (deepcopy to avoid nested ref issues), then overwrite with specifics.
            merged_plot = deepcopy(global_settings)
            merged_plot.update(plot)
            
            # Update the list in-place so downstream code sees the full config
            plot_list[i] = merged_plot

        log.info(f"Collecting data for '{combined_name}'...\n")
        
        # Determine the initial lastts value
        initial_lastts = None
        # Only set a numeric value if tracking is enabled via args.tsfile
        if args.tsfile:
          # If we have a recorded timestamp, use it. Otherwise, start at 0.
          initial_lastts = lastts.get(combined_name, 0)
        
        # Initializing new object of type given in config
        # This object is given per page or per internal tab (in case tabs are given)
        tab_bench = BenchRepo(
          name=repo_name,
          tab=group_name if internal_tabs else None,
          config=group_config,
          lastts=initial_lastts,
          skipupdate=args.skipupdate,
        )

        success = tab_bench.get_or_update_repo(folder=args.repofolder if args.repofolder else './')
        if not success:
          log.error(f"Error cloning or updating repository of '{combined_name}'. Skipping...\n")
          error_msg = f"<b>Git Error:</b> Failed to clone or pull repository."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue

        success = tab_bench.get_metrics()
        if not success:
          log.error(f"Error collecting metrics for '{combined_name}'. Skipping...\n")
          error_msg = f"<b>Data Processing Error:</b> Failed to collect or parse metrics. Ask admin for details."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue

        success = tab_bench.validate_metrics()
        if not success:
          log.error(f"Error validating metrics for '{combined_name}'. Skipping...\n")
          error_msg = f"<b>Validation Error:</b> Critical failure during metric validation."
          failed_repos[repo_name].setdefault(group_name if internal_tabs else None, []).append(error_msg)
          continue

        # Update lastts for this specific tab/combined_name
        if args.tsfile:
          lastts[combined_name] = tab_bench.lastts

        # This combines the _data (metrics, raw, etc.) and _dict (LML output)
        repo_bench += tab_bench

      # When no single LML is used (an output per repo), the LML and configurations are generated for each of them
      if (not args.singleLML):
        repo_end_time = time.time()
        log.debug(f"Gathering '{repo_name}' information took {repo_end_time - repo_start_time:.4f}s\n")

        # Outputing the different LMLs (that must be added to the DBupdate workflow on LLview)
        if repo_bench.empty():
          log.warning(f"Object for '{repo_name}' is empty, output will include only timings...\n")

        # Add timing key for the whole repo
        timing = {}
        name = f'get{repo_name.replace(" ","_")}'
        timing[name] = {}
        timing[name]['startts'] = repo_start_time
        timing[name]['datats'] = repo_start_time
        timing[name]['endts'] = repo_end_time
        timing[name]['duration'] = repo_end_time - repo_start_time
        timing[name]['nelems'] = len(repo_bench)
        timing[name]['__nelems_benchmark'] = len(repo_bench)
        timing[name]['__type'] = 'pstat'
        timing[name]['__id'] = f'pstat_get{repo_name.replace(" ","_")}'
        repo_bench.add(timing)

        # Storing the benchmark to create output later
        successful_repos[repo_name] = repo_bench
      else:
        # Accumulating for a single LML
        unique = unique + repo_bench

    # End generic timer
    end_time = time.time()

    # Writing out unique LML
    if (args.singleLML):
      # Outputing single LML (that must be added to the DBupdate workflow on LLview)
      if unique.empty():
        log.warning(f"Unique object is empty, output will include only timings...\n")

      # Add timing key for Unique object
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

      # Creating configuration files
      success = unique.gen_configs(
        folder=(args.outconfigfolder if args.outconfigfolder else ''), 
        history_n=args.statuspoints, 
        failed_info=failed_repos
      )
      if not success:
        log.error(f"Error generating configuration files!\n")
    else:
      # Generate outputs for separated repos
      
      # Output successful repositories (saved to 'successful_repos' in the loop above)
      for r_name, r_bench in successful_repos.items():
        r_bench.to_LML(
          os.path.join(args.outfolder if args.outfolder else './',f"{r_name.replace(' ','_')}_LML.xml"),
          prefix=r_name
        )

        success = r_bench.gen_configs(
          folder=(args.outconfigfolder if args.outconfigfolder else ''), 
          history_n=args.statuspoints, 
          failed_info={r_name: failed_repos.get(r_name, {})} # Pass only failures for this repo
        )
        if not success:
          log.error(f"Error generating configuration files for '{r_name}'!\n")

      # Output error pages for repositories that failed completely
      for r_name, failures in failed_repos.items():
        # If the repo never made it into successful_repos, it failed completely.
        # We must generate a stub page so the user sees the error.
        if r_name not in successful_repos and failures:
          log.info(f"Generating error stub page for failed repository '{r_name}'...\n")
          
          error_bench = BenchRepo(name=r_name)
          # Generating only the page config. No DB or CSV configs are needed.
          error_bench.gen_page_conf(
            os.path.join((args.outconfigfolder if args.outconfigfolder else ''), f'page_{r_name.replace(" ","_")}.yaml'),
            failed_info={r_name: failures}
          )
  else:
    log.warning(f"No repos given.\n")

  # Creating LLview tab configuration file
  success = gen_tab_config(default=args.setdefault,tabname=args.tabname, folder=(args.outconfigfolder if args.outconfigfolder else ''))
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
