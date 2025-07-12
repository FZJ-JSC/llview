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
import ast
import getpass
import requests
import yaml
import json
from matplotlib import colormaps   # To loop over colors in footers
from matplotlib.colors import to_hex # Convert RGB to HEX
from itertools import count,cycle,product
from copy import deepcopy
from subprocess import check_output,run,PIPE

# Fixing/improving multiline output and strings with '+' of YAML dump
def str_presenter(dumper, data):
    """
    Configures yaml for dumping strings.
    Ref: https://stackoverflow.com/questions/8640959/how-can-i-control-what-scalar-form-pyyaml-uses-for-my-data
    and https://github.com/yaml/pyyaml/issues/240
    - Uses '|' for multiline strings.
    - Uses single quotes for strings containing special characters like '+' or ':'.
    - Uses default (plain) style for all other strings.
    """
    if data.count('\n') > 0:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style='|')
    elif '+' in data or ':' in data:
        return dumper.represent_scalar('tag:yaml.org,2002:str', data, style="'")
    return dumper.represent_scalar('tag:yaml.org,2002:str', data)
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
  This function generates the main tab configuration for LLview.
  When all benchmarks are empty, it generates an empty LML
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
              'default': True,
              'template': "/data/LLtemplates/CB",
              'context': "data/cb/cb_list.csv",
              # 'footer_graph_config': "/data/ll/footer_cblist.json",
              'ref': [ 'datatable' ],
              'data': {
                'default_columns': [ 'Name', 'Timings', '#Points' ]
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
      # From center to the outside
      'center_out': lambda i: abs(i - (list_length // 2))
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

  def __init__(self,name="",config="",lastts=0):
    self._raw = {}  # Dictionary with parsed raw information
    self._dict = {} # Dictionary with modified information (which is output to LML)
    self._name = name
    self._lastts = lastts

    self._sources = {} 
    self._metrics = {}
    self._parameters = {}
    self._graphparameters = {}
    self._annotations = {}
    self._config = {} 
    if name:
      self._raw[name] = []                  # List of dictionaries containing all data of current benchmark
      self._sources[name] = set()           # Set for source files of current benchmark
      self._metrics[name] = {}              # Dictionary for all parameter/metric/annotation names and types added to _dict for current benchmark
      self._parameters[name] = {}           # Dictionary of {parameter: description} shown on the table (one row per value parameter)
      self._graphparameters[name] = {}      # Dict of {parameters: [unique values]} shown on the graphs (one curve per value parameter)
      self._annotations[name] = []          # List of metrics that show as annotations on graphs
      if config:
        self._config[name] = config
    self._counter = count(start=0)          # counter for the total number of points
    self.log   = logging.getLogger('logger')

    # Definition of default values for each variable type
    self.default = {'str': 'unknown', 'int': -1, 'bool': None, 'float': 0, 'date': '-', 'ts': -1}

  def __add__(self, other):
    first = self
    second = other
    first._raw |= second._raw
    first._config |= second._config
    first._sources |= second._sources
    first._metrics |= second._metrics
    first._parameters |= second._parameters
    first._graphparameters |= second._graphparameters
    first._annotations |= second._annotations
    first.add(second._dict)
    return first

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

  def add(self, to_add: dict, add_to=None):
    """
    (Deep) Merge dictionary 'to_add' into internal 'self._dict'
    """
    # self._dict |= dict
    if not add_to:
      add_to = self._dict
    for bk, bv in to_add.items():
      av = add_to.get(bk)
      if isinstance(av, dict) and isinstance(bv, dict):
        self.add(bv,add_to=av)
      else:
        add_to[bk] = deepcopy(bv)
    return

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

  def empty(self):
    """
    Check if internal dict is empty: Boolean function that returns True if _dict is empty
    """
    return not bool(self._dict)

  def get_or_update_repo(self,folder="./"):
    """
    Getting folder to clone or pull the repo
    If not given, use current working directory
    (Env vars are expanded)
    """
    folder = os.path.expandvars(os.path.join(folder,self._name))
    # Storing folder to use later when getting sources
    self._config[self._name]['folder'] = folder


    if self._config[self._name]['username']:
      credentials = requests.utils.quote(self._config[self._name]['username']) + (f":{requests.utils.quote(self._config[self._name]['password'])}@" if self._config[self._name]['password'] else "@")
      self._config[self._name]['host'] = self._config[self._name]['host'].replace("://",f"://{credentials}")

    # If folder does not exist, git clone the repo
    # otherwise try to git pull in the folder
    if not os.path.isdir(folder):
      # Folder does not exist and 'host' is not given, can't do anything
      if 'host' not in self._config[self._name]:
        self.log.error(f"Repo does not exist in folder {folder} and 'host' not given! Skipping...\n")
        return False

      # Cloning repo
      self.log.info(f"Folder {folder} does not exist. Cloning...\n")

      cmd = ['git', 'clone', '-q', self._config[self._name]['host']]
      cmd.append(folder)
      self.log.debug("Cloning repo with command: {}\n".format(' '.join(cmd).replace(f":{self._config[self._name]['password']}@",":***@")))
      p = run(cmd, stdout=PIPE)
      if p.returncode:
        self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd).replace(f":{self._config[self._name]['password']}@",":***@")))
        return False
      
      if 'branch' in self._config[self._name]:
        cmd = ['git', '-C', folder, 'switch', '-q', self._config[self._name]['branch']]
        self.log.debug("Changing branch with command: {}\n".format(' '.join(cmd)))
        p = run(cmd, stdout=PIPE)
        if p.returncode:
          self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd)))
          return False
    else:
      if ('update' in self._config[self._name]) and (not self._config[self._name]['update']):
        self.log.info(f"Folder {folder} already exists, but update is skipped...\n")
        return True
      else:
        self.log.info(f"Folder {folder} already exists. Updating it...\n")

        # cmd = ['git', '-C', folder, 'pull', self._config[self._name]['host']]
        cmd = ['git', '-C', folder, 'pull', '-q']
        # self.log.debug("Running command: {}\n".format(' '.join(cmd).replace(f":{self._config[self._name]['password']}@",":***@")))
        self.log.debug("Running command: {}\n".format(' '.join(cmd)))
        p = run(cmd, stdout=PIPE)
        if p.returncode:
          # self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd).replace(f":{self._config[self._name]['password']}@",":***@")))
          self.log.error("Error {} running command: {}\n".format(p.returncode,' '.join(cmd)))
          return False
    return True

  def get_sources(self):
    """
    Get a list of all files from where the metrics will be obtained
    """

    for stype,source_list in self._config[self._name]['sources'].items():
      if stype == 'folders':
        # Looping through all given folders, check if it exists, 
        # and if so, get all files inside them into 'sources' set
        for folder in source_list:
          current_folder = os.path.join(self._config[self._name]['folder'],folder)
          if not os.path.isdir(current_folder):
            self.log.error(f"Folder '{current_folder}' does not exist! Skipping...\n")
            continue
          self._sources[self._name].update(os.path.join(current_folder, fn) for fn in next(os.walk(current_folder))[2])
      elif stype == 'files':
        # Looping through all given files, check if it exists, 
        # and if so, add them into 'sources' set
        for file in source_list:
          current_file = os.path.join(self._config[self._name]['folder'],file)
          if not os.path.isfile(current_file):
            self.log.error(f"File {current_file} does not exist! Skipping...\n")
            continue
          self._sources[self._name].update([current_file])
      elif stype == 'exclude' or stype == 'include':
        pass
      else:
        self.log.error(f"Unrecognised source type: {stype}. Please use 'files' or 'folders'.\n")
        continue
    # If 'exclude' and/or 'include' options are given, filter sources
    if 'exclude' in self._config[self._name]['sources'] or 'include' in self._config[self._name]['sources']:
      self.apply_pattern(
                          self._sources[self._name],
                          exclude=self._config[self._name]['sources']['exclude'] if 'exclude' in self._config[self._name]['sources'] else '',
                          include=self._config[self._name]['sources']['include'] if 'include' in self._config[self._name]['sources'] else ''
                        )
    self.log.debug(f"{len(self._sources[self._name])} sources for {self._name}: {self._sources[self._name]}\n")
    return

  def get_metrics(self):
    """
    Collect all given metrics from the sources and add them
    to self._dict
    """
    self.get_sources()
    if len(self._sources[self._name]) == 0:
      self.log.error(f"No sources to obtain metrics! Skipping...\n")
      return False

    #========================================================================================
    # Getting headers and information about parameters/metrics to be obtained
    headers = {}
    calc_headers = {}

    for _ in [key for key in ['parameters', 'metrics', 'annotations'] if key in self._config[self._name]]:
      # Adding one calc_headers per type to be able to write out error message when there's a problem below
      calc_headers[_] = {}

      # Getting the keys/headers of the metrics to be obtained from CSV file content
      # This is a mapping of old key into new key, when 'header' is given in the list of parameters/metrics/annotations
      # The key of the dict is the old one (used to read from the csv header), 
      # obtained from metric_name:'header' when present, otherwise the metric_name itself (no change in name)
      # The value of the dict is metric_name, which should be the new name to be used
      headers_current = {key if (not self._config[self._name][_][key]) or ('header' not in self._config[self._name][_][key]) else self._config[self._name][_][key]['header']:key for key in self._config[self._name][_].keys() if ((not self._config[self._name][_][key]) or ('from' not in self._config[self._name][_][key]) or ('from' in self._config[self._name][_][key] and self._config[self._name][_][key]['from'] == 'content'))}
      
      # Getting the keys:'from' of the metrics to be obtained from calculations 
      # (i.e., when one math operator is present)
      calc_headers_current = {key:self._config[self._name][_][key]['from'] for key in self._config[self._name][_].keys() if ((self._config[self._name][_][key] and 'from' in self._config[self._name][_][key] and re.search('[\+\-\*\/]',self._config[self._name][_][key]['from'])))}

      # Getting metric {names:types} for configuration file, from parameters/metrics/annotations
      # that are in csv headers and the ones that are calculated from others
      _metrics_current = {key_new: self._config[self._name][_][key_new]['type'] if self._config[self._name][_][key_new] and 'type' in self._config[self._name][_][key_new] else 'str' for key_new in list(headers_current.values())+list(calc_headers_current.keys())}
      if 'ts' in _metrics_current:
        _metrics_current['ts'] = 'ts' # using type 'ts' for timestamp

      headers |= headers_current
      calc_headers[_] |= calc_headers_current
      self._metrics[self._name] |= _metrics_current

    # Getting parameters and descriptions that will generate rows in the main table
    for key in self._config[self._name]['parameters'].keys():
      if self._config[self._name]['parameters'][key] and 'kind' in self._config[self._name]['parameters'][key] and self._config[self._name]['parameters'][key]['kind'] == 'graph': 
        self._graphparameters[self._name][key] = set()
      else:
        self._parameters[self._name][key] = self._config[self._name]['parameters'][key]['description'] if self._config[self._name]['parameters'][key] and 'description' in self._config[self._name]['parameters'][key] else key
    # Adding systemname default description
    if 'description' not in self._parameters[self._name]['systemname']:
      self._parameters[self._name]['systemname'] = 'System where the Benchmark was run'

    # Getting annotations that will be used in graphs
    for key in self._config[self._name]['annotations'].keys() if 'annotations' in self._config[self._name] else []:
      self._annotations[self._name].append(key)

    # Adding information for the status (bool), if the 'status' key is given
    # and it is to be obtained from the contents
    if 'status' in self._config[self._name] and ((not self._config[self._name]['status']) or ('from' not in self._config[self._name]['status']) or ('from' in self._config[self._name]['status'] and self._config[self._name]['status']['from'] == 'content')):
      headers |= {'status' if (not self._config[self._name]['status']) or ('header' not in self._config[self._name]['status']) else self._config[self._name]['status']['header']:'status'}
      self._metrics[self._name]['status'] = 'bool'
    # else:
      # If there's no status, get from the measured metrics:
      # If they are there, status='COMPLETED', if not, status='FAILED'

    #========================================================================================
    # Looping throught the sources to collect parameters/metrics

    # Temporary lastts:
    lastts_temp = 0
    for source in self._sources[self._name]:
      # Initializing variable to collect all data defined for given metric
      current_data = []

      # Getting information from content
      # Read source file to a list of dictionaries and filtering only the required metrics
      with open(source, 'r') as file:
        # Reading file into variable once to use for all given metrics
        if source.endswith(".csv"):
          data = csv.DictReader(file)
        elif source.endswith(".json"):
          data = flatten_json(json.load(file))
        else:
          self.log.error(f"Only CSV is implemented by now. Skipping file {source}...\n")
          continue

        # Getting data from file (CSV or JSON)
        for line in data:
          current_line = ({key_new: line[key_old] for key_old,key_new in headers.items()})

          for _ in [key for key in ['parameters', 'metrics', 'annotations'] if key in self._config[self._name]]:
            for key in calc_headers[_]:
              calc = calc_headers[_][key]
              for head in re.split("[\+\-\*\/]+", calc_headers[_][key]):
                calc = calc.replace(head,line[re.sub("^'|'$|^\"|\"$", '', head)])
              try:
                current_line[key] = self.safe_math_eval(calc)
              except SyntaxError as e:
                self.log.debug(f"Cannot obtain value of '{key}'={calc_headers[_][key]} from line: {line}.\n Using default value: {self.default[self._config[self._name][_][key]['type']]}\n")
                current_line[key] = self.default[self._config[self._name][_][key]['type']]
                self.log.debug(f"ERROR: {' '.join(traceback.format_exception(type(e), e, e.__traceback__))}\n")

          current_data.append(current_line)

        # Converting data obtained from file content and multiplying by factor, when present
        for key in list(headers.values())+[key for _ in calc_headers for key in calc_headers[_].keys()]:
          mtype = self._metrics[self._name][key]
          # Checking if key is in 'parameters','metrics' or 'annotations'
          if key in self._config[self._name]['parameters']:
            kind = 'parameters'
          elif key in self._config[self._name]['metrics']:
            kind = 'metrics'
          elif key in self._config[self._name]['annotations']:
            kind = 'annotations'
          else:
            kind = 'status'
          for data in current_data:
            if mtype == 'str':
              convert = self._config[self._name][kind][key]['regex'] if self._config[self._name][kind][key] and 'regex' in self._config[self._name][kind][key] else None
            else:
              convert = self._config[self._name][kind][key]['factor'] if kind != 'status' and self._config[self._name][kind][key] and 'factor' in self._config[self._name][kind][key] else None
            try:
              data[key] = self.convert_data(
                                            data[key],
                                            vtype='ts' if key == 'ts' else mtype,
                                            factor=convert,
                                            )
            except ValueError:
              self.log.debug(f"Cannot convert value '{data[key]}' for {kind[:-1]} '{key}' in source {source}! Skipping conversion...\n")
              continue

      # Getting common data and metrics that are obtained from filename
      common_data = {}
      common_data['__type'] = "benchmark"
      common_data['__prefix'] = "bm"
      if 'id' in self._config[self._name]:
        common_data['__id'] = self._config[self._name]['id']

      to_exclude = {}
      to_include = {}
      for _ in [key for key in ['parameters', 'metrics', 'annotations'] if key in self._config[self._name]]:
        # Collecting metrics and rules for excluding and/or including
        for metricname,metric_config in self._config[self._name][_].items():
          if not metric_config: continue
          if 'exclude' in metric_config:
            to_exclude[metricname] = metric_config['exclude']
          if 'include' in metric_config:
            to_exclude[metricname] = metric_config['include']
          if 'from' not in metric_config: continue
          if (metric_config['from']=='static') or (metric_config['from']=='value'):
            if 'value' not in metric_config:
              self.log.error(f"Metric '{metricname}' is selected to be obtained from static value, but no 'value' was given! Skipping...\n")
              continue
            common_data[metricname] = metric_config['value']
            self._metrics[self._name][metricname] = metric_config.get('type','str')
          elif ('name' in metric_config['from']):
            if 'regex' not in metric_config:
              self.log.error(f"Metric '{metricname}' is selected to be obtained from filename, but no 'regex' was given! Skipping...\n")
              continue
            # Getting metric from filename with given regex
            match = re.search(metric_config['regex'],source)
            if not match:
              self.log.error(f"{_[:-1].title()} '{metricname}' could not be matched using regex '{metric_config['regex']}' on filename '{source}'! Skipping {_[:-1]}...\n")
              continue
            if ('type' in metric_config):
              if ('date' in metric_config['type']):
                common_data[metricname] = dateutil.parser.parse(match.group(1)).strftime('%Y-%m-%d %H:%M:%S')
                self._metrics[self._name][metricname] = 'date'
              elif metric_config['type'] == 'int':
                common_data[metricname] = int(match.group(1))*metric_config['factor'] if 'factor' in metric_config else int(match.group(1))
                self._metrics[self._name][metricname] = metric_config['type']
              elif metric_config['type'] == 'float':
                common_data[metricname] = float(match.group(1))*metric_config['factor'] if 'factor' in metric_config else int(match.group(1))
                self._metrics[self._name][metricname] = metric_config['type']
              elif ('str' in metric_config['type']):
                common_data[metricname] = str(match.group(1))
                self._metrics[self._name][metricname] = 'str'
              elif ('bool' in metric_config['type']):
                common_data[metricname] = not (match.group(1).lower() in ['false']) if isinstance(match.group(1),str) else bool(match.group(1))
                self._metrics[self._name][metricname] = 'bool'
              elif (metric_config['type'] == 'ts'):
                common_data[metricname] = time.mktime(dateutil.parser.parse(match.group(1)).timetuple())
                self._metrics[self._name][metricname] = 'ts' # using type 'ts' for timestamp
              else:
                self.log.error(f"Type '{metric_config['type']}' for metric '{metricname}' not recognised! Use 'datetime', 'str', 'int' or 'float'. Skipping metric...\n")
                continue
            else:
              if metricname == 'ts': # if type is not given for metric 'ts'
                common_data[metricname] = time.mktime(dateutil.parser.parse(match.group(1)).timetuple())
                self._metrics[self._name][metricname] = 'ts' # using type 'ts' for timestamp
                # For timestamp 'ts' metric, store it
              else:
                # Default type is 'str'
                common_data[metricname] = str(match.group(1))
                self._metrics[self._name][metricname] = 'str'

      # Adding information for the status (bool), if the 'status' key is given
      # and it is to be obtained from the filename
      if 'status' in self._config[self._name] and ('from' in self._config[self._name]['status'] and 'name' in self._config[self._name]['status']['from']):
        if 'regex' not in self._config[self._name]['status']:
          self.log.error(f"'status' is selected to be obtained from filename, but no 'regex' was given! Skipping and using presence of metrics as status...\n")
        else:
          # Getting metric from filename with given regex
          match = re.search(self._config[self._name]['status']['regex'],source)
          if not match:
            self.log.error(f"'status' could not be matched using regex '{self._config[self._name]['status']['regex']}' on filename '{source}'! Skipping and using presence of metrics as status...\n")
          else:
            common_data['status'] = not (match.group(1).lower() in ['0','false','failed']) if isinstance(match.group(1),str) else bool(match.group(1))
            self._metrics[self._name]['status'] = 'bool'

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

      # Collecting unique values for graph parameters in current source:
      # (This has to be done before cleaning the old ts to be able to
      # collect all unique values)
      for param in self._graphparameters[self._name]:
        self._graphparameters[self._name][param].update([data[param] for data in current_data])

      # Getting the status from the metrics values if 'status' is not given as a column  
      # or if it was not obtained from content or filename
      for data in current_data:
        if 'status' not in data or data['status']==None:
          # Status is successful if all 'metrics' exist and are different than default
          data['status'] = True if all([data[key] for key in self._config[self._name]['metrics']]) and all([data[key]!=self.default[self._metrics[self._name][key]] for key in self._config[self._name]['metrics']]) else False
          self._metrics[self._name]['status'] = 'bool'

      self.log.debug(f"Data for {source} contains: {current_data}\n")  
      self.log.debug(f"Headers: {self._metrics[self._name]}\n")

      if current_data:
        # Saving all raw data, including all ts, to be able to get all combinations for graphs
        self._raw[self._name] += current_data

      # Filtering older timestamps when lastts is given and storing in self._dict
      # to be written out in LML
      # (This is done at the end to allow the possibility of ts to be added 
      # either from content or from common_data)
      if self._lastts:
        current_data[:] = [data for data in current_data if data['ts'] > self._lastts]
      # Storing temporary lastts from last timestamp of current data
      lastts_temp = max([data['ts'] for data in current_data]+[self._lastts,lastts_temp])

      if current_data: # Adding an id to current data, to have an unique identifier for the csv file generation
        self._dict |= ({f"{self._name}{idx}": data|{'id':'_'.join([data[key] for key in self._parameters[self._name]])} for idx,data in zip(self._counter,current_data)})

    # Storing new lastts from last timestamp of all data
    self._lastts = lastts_temp
    return True

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
      if value.replace('.','',1).isdigit():
        value = float(value)
      else:
        value = time.mktime(dateutil.parser.parse(value).timetuple())
    elif ('date' in vtype):
      value = time.mktime(dateutil.parser.parse(value).strftime('%Y-%m-%d %H:%M:%S'))
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
  
  def gen_dbupdate_conf(self,filename):
    """
    Create YAML file to be used in LLview for DBupdate configuration
    """
    self.log.info(f"Generating DB configuration file {filename}\n")

    lb = '\n' # Fix for backslash inside curly braces in f-strings (can be removed in Python >=3.12)

    # Columns for main table
    tables = []
    for benchname in self._metrics:
      columns = []
      for metric,mtype in self._metrics[benchname].items():
        # Defining a column for current metric
        column = {
                  'name': metric,
                  'type': f'{mtype}_t',
                  'LML_from': metric,
                  'LML_default': self.default[mtype]
                  }
        # Adding mandatory 'mintsinserted' for 'ts' column
        if metric == 'ts':
          column[f'mintsinserted_cb_{benchname}'] = f"mintsinserted_cb_{benchname}"
        # Collecting all columns
        columns.append(column)
      columns.append({
                      'name': 'id',
                      'type': f'ukey_t',
                      'LML_from': 'id',
                      'LML_default': ''
                      })

      # Main table with trigger to overview table cb_benchmarks
      tables.append({'table': { 
                                'name': f"cb_{benchname}_data",
                                'options': {
                                            'update': {
                                                        'LML': f"cb_{benchname}",
                                                        'mode': 'add',
                                                        'sql_update_contents': {
                                                          'vars': 'mintsinserted',
                                                          'sqldebug': 1,
                                                          'sql': f"""DELETE FROM cb_benchmarks WHERE name='{benchname}';
              INSERT INTO cb_benchmarks (name, systemname, count, min_ts, max_ts)
                        SELECT '{benchname}',systemname,
                              COUNT(ts),MIN(ts),MAX(ts)
                        FROM cb_{benchname}_data
                        GROUP by systemname;
""",
                                                                    },
                                                      },
                                            'update_trigger': [f"cb_{benchname}_data",f"cb_{benchname}_overview"]
                                          },
                                'columns': columns,
                              }
                    })
      
      # Getting list of metrics (i.e., not parameters or annotations)
      metrics = [key for key in self._config[benchname]['metrics'] if key != 'ts']

      # Overview table
      tables.append({'table': { 'name': f'cb_{benchname}_overview',
                                'options': {
                                            'update': {
                                                        'sql_update_contents': {
                                                          'sql': f"""DELETE FROM cb_{benchname}_overview;
                INSERT INTO cb_{benchname}_overview (id, name, count, min_ts, max_ts
                                {''.join([f", {key}" for key in self._parameters[benchname]])}
                                {''.join([f',{lb}                                {key}_min, {key}_avg, {key}_max' for key in metrics])}
                                )
                        SELECT id, '{benchname}',COUNT(ts),MIN(ts),MAX(ts)
                                {''.join([f", {key}" for key in self._parameters[benchname]])}
                                {''.join([f',{lb}                                MIN({key}),AVG({key}),MAX({key})' for key in metrics])}
                        FROM cb_{benchname}_data
                        GROUP by {', '.join(self._parameters[benchname])};
""",
                                                                    },
                                                      },
                                          },
                                'columns': [
                                  {'name': 'id',         'type': 'ukey_t'},
                                  {'name': 'name',       'type': 'str_t'},
                                  {'name': 'count',      'type': 'int_t'},
                                  {'name': 'min_ts',     'type': 'ts_t'},
                                  {'name': 'max_ts',     'type': 'ts_t'},
                                ]
                                +[{'name': key, 'type': f'{self._metrics[benchname][key]}_t'} for key in self._parameters[benchname]]
                                +[{'name': f'{key}_{suffix}', 'type': f'{self._metrics[benchname][key]}_t'} for key in metrics for suffix in ['min','avg','max']],
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

    pages = []
    for benchname in self._metrics:
      page = {'page': {
                        'name': benchname.upper(),
                        'section': f'cb_{benchname}',
                        'default': False,
                        'template': f'/data/LLtemplates/CB_{benchname}',
                        'context': f"data/cb/cb_{benchname}.csv",
                        'footer_graph_config': f"/data/ll/footer_cb_{benchname}.json",
                        'ref': [ 'datatable' ],
                        'data': {'default_columns': [ 'Name', 'System', '#Points', 'Timings', 'Parameters' ]}
                      }}
      pages.append(page)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(pages, file)

    return True

  def gen_template_conf(self,filename):
    """
    Create YAML file to be used in LLview for Template configuration
    """
    self.log.info(f"Generating Template configuration file {filename}\n")

    datasets = []
    for benchname in self._metrics:
      columns = [
      # {
      #   'field': "name",
      #   'headerName': "Name",
      #   'headerTooltip': "Benchmark name",
      # },
      {
        'field': "systemname",
        'headerName': "System",
        'headerTooltip': self._parameters[benchname]['systemname'],
      },
      {
        'field': "count",
        'headerName': "#Points",
        'headerTooltip': 'Number of points',
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
        'headerName': "Parameters",
        'groupId': "parameters",
        'children': [{
        'field': key,
        'headerName': key,
        'headerTooltip': self._parameters[benchname][key]}
                    for key in self._parameters[benchname] if key != 'systemname']
      }]

      dataset = {'dataset': {
                        'name': f'template_{benchname}_CB',
                        'set': 'template',
                        'filepath': f'$outputdir/LLtemplates/CB_{benchname}.handlebars',
                        'stat_database': 'jobreport_json_stat',
                        'stat_table': 'datasetstat_templates',
                        'format': 'datatable',
                        'ag-grid-theme': 'balham',
                        'columns': columns
                      }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file)

    return True

  def gen_tablecsv_conf(self,filename):
    """
    Create YAML file to be used in LLview for Table CSV configuration
    """
    self.log.info(f"Generating Table CSV configuration file {filename}\n")

    datasets = []

    for benchname in self._metrics:
      dataset = {'dataset': {
                        'name': f'cb_{benchname}_csv',
                        'set': 'csv_cb',
                        'filepath': f'$outputdir/cb/cb_{benchname}.csv.gz',
                        'data_database':   'CB',
                        'data_table': f'cb_{benchname}_overview',
                        'stat_table': 'datasetstat_support',
                        'stat_database': 'jobreport_json_stat',
                        'column_ts': 'max_ts',
                        'renew': 'always',
                        'csv_delimiter': ';',
                        'format': 'csv',
                        'column_convert': 'min_ts->todate_std_hhmm,max_ts->todate_std_hhmm',
                        'columns': f"name,count,min_ts,max_ts,{','.join(self._parameters[benchname].keys())}",
                      }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file)

    return True

  def gen_vars_conf(self,filename):
    """
    Create YAML file to be used to define Vars in LLview configuration
    """
    self.log.info(f"Generating Vars configuration file {filename}\n")

    vars = []

    for benchname in self._metrics:
      var = {
              'name': f'VAR_cb_{benchname}',
              'type': 'hash_values',    
              'database': 'CB',
              'table': f'cb_{benchname}_overview',
              'columns':  'id',
              'sql': f"SELECT id FROM cb_{benchname}_overview"
            }

      vars.append(var)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(vars, file)

    return True

  def gen_footercsv_conf(self,filename):
    """
    Create YAML file to be used for Footer CSVs in LLview configuration
    """
    self.log.info(f"Generating Vars configuration file {filename}\n")

    format_types = {
      'int': '%d',
      'float': '%f',
      'str': '%s',
      'bool': '%d',
      'date': '%s',
      'ts': '%s',
    }
    datasets = []
    for benchname in self._metrics:
      columns = [key for key in list(self._config[benchname]['metrics'].keys()) + list(self._graphparameters[benchname].keys()) + self._annotations[benchname]]
      dataset = {'dataset': {
                      'name':           f'cb_{benchname}_csv',
                      'set':            f'cb_{benchname}',
                      'FORALL':         f"A:VAR_cb_{benchname}",
                      'filepath':       f"$outputdir/cb/cb_{benchname}_${{A}}.csv" ,
                      'columns':        ','.join(columns),
                      'header':         ','.join(['date' if key=='ts' else key for key in columns]),
                      'column_convert': 'ts->todate_1',
                      'column_filemap': 'A:id',
                      'format_str':     ','.join([format_types[self._metrics[benchname][key]] for key in columns]),
                      'column_ts':      'ts',
                      'format':         'csv',
                      'renew':          'always',
                      'data_database':   'CB',
                      'data_table':      f'cb_{benchname}_data',
                      'stat_database':   'jobreport_CB_stat',
                      'stat_table':      'datasetstat',
            }}

      datasets.append(dataset)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(datasets, file)

    return True


  def gen_footer_conf(self,filename):
    """
    Create YAML file to be used in LLview for the Footer configuration
    """
    self.log.info(f"Generating Footer configuration file {filename}\n")

    footers = []
    for benchname in self._metrics:
      # Getting the metrics to group different graphs (each value generate a new graph)
      graph_metrics = [key for key in self._config[benchname]['metrics'] if key != 'ts']

      # Checking valid combinations of graph parameters
      # (This will only work if all data is in self._raw. If this is filtered before, it may happen that
      # not all valid combinations are generated)
      valid_combinations = [] # To store all valid combinations of graph parameters
      # Generating all possible combinations of the graph parameters
      for combination in product(*self._graphparameters[benchname].values()):
        valid_combination = True
        # Creating dictionary for current combination
        current_combination = {key:value for key,value in zip(self._graphparameters[benchname].keys(),combination)}
        for key,value in current_combination.items():
          # If value is default one, ignore this combination, as it didn't have a valid value
          if self.default[self._metrics[benchname][key]] == value:
            self.log.debug(f"Invalid combination {combination}, {key} has default value of {value}\n")
            valid_combination = False
            continue
          # If there's no value with the current combination, skip it
          if not any(set(current_combination.items()).issubset(set(data.items())) for data in self._raw[benchname]):
            self.log.debug(f"Combination {combination}, has no values\n")
            valid_combination = False
            continue
        if valid_combination:
          valid_combinations.append(current_combination)
      # Sorting list by key and value
      valid_combinations.sort(key=lambda d: tuple(sorted(d.items())))

      tabs = ['Benchmarks'] # To get
      # Getting configuration of the graphs:
      # Get the top-level configuration for the benchmark
      bench_config = self._config.get(benchname, {})
      # Get the 'traces' dictionary, or an empty dict if it's not there
      traces_config = bench_config.get('traces', {})
      # Get the 'colors' dictionary from within 'traces'
      colors_config = traces_config.get('colors', {})
      # Get the final values using their specific defaults
      colormap = colors_config.get('colormap', BenchRepo.DEFAULT_COLORMAP)
      skip_colors = colors_config.get('skip', [])
      sort_key_name = colors_config.get('sort_strategy', BenchRepo.DEFAULT_SORT_KEY)
      sort_function = BenchRepo.SORT_STRATEGIES.get(sort_key_name, BenchRepo.SORT_STRATEGIES[BenchRepo.DEFAULT_SORT_KEY])
      user_trace_styles = traces_config.get('styles', {})

      # Loop over tabs
      footersetelems = []
      for tab in tabs:
        # Loop over graphs
        graphs = []
        for graphelem in graph_metrics:
          # Restart colors for each graph 
          color_list = colormaps[colormap].colors
          indices_to_sort = range(len(color_list))
          colors = cycle([
              to_hex(color_list[idx]) for idx in sorted(
                  indices_to_sort, 
                  key=sort_function
              )
          ])
          # Loop over traces
          traces = []
          for traceelem in valid_combinations:
            color = next(colors)
            while color in skip_colors:
              color = next(colors)
            plot_properties = deepcopy(BenchRepo.DEFAULT_TRACE_STYLE)
            self.deep_update(plot_properties, user_trace_styles)
            plot_properties.update({ # Sorting keys of different types together (in reverse order to have str before int):
              'name': '<br>'.join(f"{key}: {traceelem[key]}" for mtype in sorted(self.default.keys(), reverse=True) for key in sorted(traceelem.keys()) if self._metrics[benchname][key] == mtype),
              'ycol': graphelem,
              'yaxis': "y",
              'where': traceelem
            })
            # Setting the colors
            if 'marker' in plot_properties:
              plot_properties['marker']['color'] = color
            if 'line' in plot_properties:
              plot_properties['line']['color'] = color
            # Adding on-hover/annotation data, if present
            if self._annotations[benchname]:
              onhover_data = {'onhover': [{key: {'name': key}} for key in self._annotations[benchname]]}
              plot_properties |= onhover_data
            trace = {'trace': plot_properties}
            traces.append(trace)          
          graph = {
            'graph': {
              'name': graphelem,
              'xcol': 'date',
              'layout': {
                'yaxis': {
                  'title': graphelem + (f" [{self._config[benchname]['metrics'][graphelem]['unit']}]" if "unit" in self._config[benchname]['metrics'][graphelem] else "")
                },
                'legend': {
                  'x': "1.02",
                  'xanchor': "left",
                  'y': "0.98",
                  'yanchor': "top",
                  'orientation': "v"
                }
              },
              'datapath': f"data/cb/cb_{benchname}_#System#{''.join([f'_#{key}#' for key in self._parameters[benchname].keys() if key != 'systemname'])}.csv",
              'traces': traces,
            }
          }
          graphs.append(graph)

        footersetelem = {
          'footersetelem': {
            'name': tab,
            'info': "System: #System#"+''.join([f", {key}: #{key}#" for key in self._parameters[benchname] if key != 'systemname']),
            'graphs': graphs
          }
        }
        footersetelems.append(footersetelem)

      footer = { 
        'footer': {
          'name': f'{benchname.upper()}',
          'filepath': f"$outputdir/ll/footer_cb_{benchname}.json",
          'stat_database': 'jobreport_json_stat',
          'stat_table': 'datasetstat_footer',
          'footerset': footersetelems,
        }
      }
      footers.append(footer)

    # Writing out YAML configuration file
    with open(filename, 'w') as file:
      yaml.safe_dump(footers, file)

    return True

  def query(self, metrics, prefix="", stype=""):
    """
    This function will loop through the metrics given in the list 'metrics'
    and perform them in the server defined in self.
    The values are put in the dict self._raw
    """

    # Looping over all metrics that should be put into the file
    for name,metric in metrics.items():
      if 'query' not in metric:
        self.log.debug(f"No query to be done for {name}\n")
        continue

      if not self._host:
        self.log.error(f"No hostname defined for current server. Query {name} cannot be done! Skipping...\n")
        continue

      self.log.debug(f"Performing query: {metric['query']}\n")
      url = f"https://{self._host}/api/v1/query?query={requests.utils.quote(metric['query'])}"
      self.log.debug(f"{url}\n")

      # Querying Prometheus server
      credentials = None
      if self._user and self._pass:
        credentials = (self._user, self._pass)
      r = requests.get(url, auth=credentials, timeout=(5,10))

      # If current query does not succeed, log error and continue to next query
      if not r.ok:
        self.log.error(f"Status <{r.status_code}> with query {url}\n")
        continue

      # Getting data from returned result of query
      data = r.json()['data']['result']

      # Looping over all instances (nodes/gpus) in current queried result
      for instance in data:
        # Getting name of the node
        pid = instance['metric']['instance']
        gpu = None
        if 'device' in instance['metric']:
          # If 'device' key is present, this is a gpu
          gpu = int(instance['metric']['device'].replace('nvidia',''))
        id = f"{pid}" + ( f"_{gpu:02d}" if isinstance(gpu,int) else "" )
        self._raw.setdefault(id,{})
        self._raw[id][name] = ast.literal_eval(instance['value'][1])
        if 'factor' in metric:
          self._raw[id][name] *= metric['factor']
        # Adding extra keys 
        self._raw[id]['ts'] = instance['value'][0]
        self._raw[id]['pid'] = pid
        self._raw[id]['id'] = id
        if gpu:
          self._raw[id]['feature'] = f"GPU{gpu}"

    for instance in self._raw:
      # Adding prefix and type of the unit, when given in the input
      if prefix:
          self._raw[instance]["__prefix"] = prefix
      if stype:
        self._raw[instance]["__type"] = stype
      # Adding default values for missing metrics
      for name,metric in metrics.items():
        if name not in self._raw[instance] and 'default' in metric:
          self._raw[instance][name] = metric['default']

    self._dict |= self._raw
    return


  def parse(self, cmd, timestamp="", prefix="", stype=""):
    """
    This function parses the output of Slurm commands
    and returns them in a dictionary
    """

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
      unitname = re.match("(\w+)",rawoutput).group(1)
      self.log.debug(f"Parsing units of {unitname}...\n")
      units = re.findall(f"({unitname}[\s\S]+?)\n\n",rawoutput)
      for unit in units:
        self.parse_unit_block(unit, unitname, prefix, stype)
    else:
      units = list(csv.DictReader(rawoutput.splitlines(), delimiter='|'))
      if len(units) == 0:
        self.log.warning(f"No output units from command {cmd}\n")
        return
      # Getting unit to be parsed from first keyword
      unitname = re.match("(\w+)",rawoutput).group(1)
      self.log.debug(f"Parsing units of {unitname}...\n")
      for unit in units:
        current_unit = unit[unitname]
        self._raw[current_unit] = {}
        # Adding prefix and type of the unit, when given in the input
        if prefix:
          self._raw[current_unit]["__prefix"] = prefix
        if stype:
          self._raw[current_unit]["__type"] = stype
        for key,value in unit.items():
          self.add_value(key,value,self._raw[current_unit])

    self._dict |= self._raw
    return

  def add_value(self,key,value,dict):
    """
    Function to add (key,value) pair to dict. It is separate to be easier to adapt
    (e.g., to not include empty keys)
    """
    dict[key] = value if value != "(null)" else ""
    return

  def parse_unit_block(self, unit, unitname, prefix, stype):
    """
    Parse each of the blocks returned by Slurm into the internal dictionary self._raw
    """
    # self.log.debug(f"Unit: \n{unit}\n")
    lines = unit.split("\n")
    # first line treated differently to get the 'unit' name and avoid unnecessary comparisons
    for pair in lines[0].strip().split(' '):
      key, value = pair.split('=',1)
      if key == unitname:
        current_unit = value
        self._raw[current_unit] = {}
        # Adding prefix and type of the unit, when given in the input
        if stype:
          self._raw[current_unit]["__prefix"] = prefix
        if stype:
          self._raw[current_unit]["__type"] = stype
      # JobName must be treated separately, as it does not occupy the full line
      # and it may contain '=' and ' '
      elif key == "JobName":
        value = re.search(".*JobName=(.*)$",lines[0].strip()).group(1)
        self._raw[current_unit][key] = value
        break
      self.add_value(key,value,self._raw[current_unit])

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
        self.add_value(key,value,self._raw[current_unit])
        continue
      # Now the pairs are separated by space
      for pair in line.split(' '):
        if len(splitted := pair.split('=',1)) == 2: # Checking if line is splittable on "=" sign
          key,value = splitted
        else:  # If not, split on ":"
          key,value = pair.split(":",1)
        if key in ['Dist']: #'JobName'
          self._raw[current_unit][key] = line.split(f'{key}=',1)[1]
          break
        self.add_value(key,value,self._raw[current_unit])
    return

  def apply_pattern(self,elements,exclude="",include=""):
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
            file.write(" <data key={:24s} value=\"{}\"/>\n".format('\"'+str(key)+'\"',value))
            continue
          if key.startswith('__'): continue
          if (not isinstance(value,str)) or (value != ""):
          # if (value) and (value != "0"):
            # Replacing double quotes with single quotes to avoid problems importing the values
            file.write(" <data key={:24s} value=\"{}\"/>\n".format('\"'+str(key)+'\"',value.replace('"', "'") if isinstance(value, str) else value))
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
    try:
      # Trying keychain first
      import keyring
      password = keyring.get_password('llview_prometheus', username)
      if password is None:
        getpass.getpass(f"Enter password for {username} on '{name}':")
        password = getpass.getpass(username,'llview_prometheus')
        keyring.set_password(name, username, password)
    except ImportError:
      log.error("Keyring module cannot be imported, password will not be saved.\n")
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

  if (args.singleLML):
    unique = BenchRepo()

  all_empty = True
  if config:
    for group_name,group_config in config.items():
      log.info(f"Processing '{group_name}'\n")

      # Checking if something is to be done on current repo
      if  ('sources' not in group_config) or (len(group_config['sources']) == 0) or \
          ('files' not in group_config['sources'] and 'folders' not in group_config['sources']) or \
          ('files' not in group_config['sources'] and 'folders' in group_config['sources'] and (len(group_config['sources']['folders']) == 0) ) or \
          ('files' in group_config['sources'] and (len(group_config['sources']['files']) == 0) and 'folders' not in group_config['sources']) or \
          (('files' in group_config['sources'] and len(group_config['sources']['files']) == 0) and ('folders' in group_config['sources'] and len(group_config['sources']['folders']) == 0)):
        log.warning("No 'sources' of metrics to process on this server. Skipping...\n")
        continue
      if ('metrics' not in group_config) or (len(group_config['metrics']) == 0):
        log.warning("No 'metrics' to collect on this server. Skipping...\n")
        continue
      if ('ts' not in group_config['metrics']):
        log.warning("No mandatory 'ts' metric given. Skipping...\n")
        continue
      if ('parameters' not in group_config) or (len(group_config['parameters']) == 0):
        log.warning("No 'parameters' to collect on this server. Skipping...\n")
        continue
      if ('systemname' not in group_config['parameters']):
        log.warning("No mandatory 'systemname' parameter given. Skipping...\n")
        continue

      # Getting credentials for the current server
      group_config['username'], group_config['password'] = get_credentials(group_name,group_config)

      start_time = time.time()

      log.info(f"Collecting '{group_name}' metrics...\n")

      # Initializing new object of type given in config
      bench = BenchRepo(
                        name=group_name,
                        config=group_config,
                        lastts=lastts[group_name] if group_name in lastts else 0,
                        )

      success = bench.get_or_update_repo(folder=args.repofolder if args.repofolder else './')
      if not success:
        log.error(f"Error cloning or updating repo '{group_name}'. Skipping...\n")
        continue

      success = bench.get_metrics()
      if not success:
        log.error(f"Error collecting metrics. Skipping...\n")
        continue

      end_time = time.time()
      lastts[group_name] = bench.lastts
      log.debug(f"Gathering '{group_name}' information took {end_time - start_time:.4f}s\n")

      # Add timing key
      # if not info.empty():
      timing = {}
      name = f'get{group_name}'
      timing[name] = {}
      timing[name]['startts'] = start_time
      timing[name]['datats'] = start_time
      timing[name]['endts'] = end_time
      timing[name]['duration'] = end_time - start_time
      timing[name]['nelems'] = len(bench)
      # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
      timing[name][f"__nelems_benchmark"] = len(bench)
      timing[name]['__type'] = 'pstat'
      timing[name]['__id'] = f'pstat_get{group_name}'
      bench.add(timing)

      if (not args.singleLML):
        if bench.empty():
          log.warning(f"Object for '{group_name}' is empty, nothing to output to LML! Skipping...\n")
        else:
          bench.to_LML(os.path.join(args.outfolder if args.outfolder else './',f"{group_name}_LML.xml"))
          all_empty = False

        # Creating configuration files
        success = bench.gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
        if not success:
          log.error(f"Error generating configuration files for '{group_name}'!\n")
          continue
      else:
        # Accumulating for a single LML
        unique = unique + bench

    # Writing out unique LML
    if (args.singleLML):
      if unique.empty():
        log.warning(f"Unique object is empty, nothing to output to LML! Skipping...\n")
        return
      else:
        unique.to_LML(os.path.join(args.outfolder if args.outfolder else './',args.singleLML))
        all_empty = False

      # Creating configuration files
      success = unique.gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
      if not success:
        log.error(f"Error generating configuration files!\n")
  else:
    log.warning(f"No repos given.\n")

  if all_empty:
    log.warning(f"Creating empty LLview config files...\n")
    success = BenchRepo().gen_configs(folder=(args.outconfigfolder if args.outconfigfolder else ''))
    if not success:
      log.error(f"Error generating empty configuration files!\n")
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
