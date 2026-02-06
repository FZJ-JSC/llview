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
#    Yannik Müller (Forschungszentrum Juelich GmbH)
#    Matthias Lapu (CEA)

import argparse
import logging
import time
from datetime import datetime
import re
import os
import sys
import math
import csv
from copy import deepcopy
from subprocess import check_output
from typing import Dict, Any

def expand_NodeList(nodelist: str) -> str:
  r"""
  Split node list by commas only between groups of nodes, not within groups
  Returns all complete node names separated by a single space
  Regex notes:
    [^\[]+ - matches anything (at lest one character) but the '[' literal
    (?:\[[\d,-]*\])? - matches zero or one (optional) node groupings like '[1,3,5-8,10]'
    General Documentation https://docs.python.org/3/library/re.html#regular-expression-syntax
  """
  expandedlist = ""
  for nodelist in re.findall(r'([^\[]+(?:\[[\d,-]*\])?),?',nodelist):
    match = re.findall( r"(.+?)\[(.*?)\]|(.+)", nodelist)[0]
    if match[2] == nodelist:
      # single node
      expandedlist += f"{nodelist} "
      continue
    # multiple nodes in node list as in "node[a,b,m-n,x-y]"
    for node in match[1].split(','):
      # splitting eventual consecutive nodes with '-'
      list = node.split('-',1)
      if len(list)==1:
        # single node
        expandedlist += f"{match[0]}{list[0]} "
      else:
        # multi-node separated by '-'
        for i in range(int(list[0]),int(list[1])+1):
          expandedlist += f"{match[0]}{i:0{len(list[0])}} "  
  return expandedlist.rstrip()

def add_CPUs_to_nodelist(nodelist: str, numcpus: int) -> str:  
  expandedlist = ""
  for node in nodelist.split(" "):
    expandedlist += f"({node},{numcpus})"
  return expandedlist

def remove_duplicate(id: str) -> str:
  """
  Remove duplicate values from id
  """
  match = re.match(r'(\d+)-(\d+)$',id)
  return match.group(1) if match else id

def remove_key(value: str) -> str:
  """
  Remove keyword and '=' sign
  """
  newvalue = value.split('=',1)
  return newvalue[1] if len(newvalue) == 2 else value

def remove_id_num(id: str) -> str:
  """
  Remove id number (inside parenthesis)

  Remove integers at the end of the id. 
  If no integer at the end is matched, return the id itself.
  """
  m = re.match(r'(.+)\(\d+\)$',id)
  return m.group(1) if m else id

def to_seconds(time: str) -> int:
  """
  Transform different time formats to number of seconds (integer)
  """
  ret = time
  patint = r'([\+\-]?[\d]+)'
  if match := re.match(fr'\({patint} seconds\)',time):
    ret = int(match.group(1))
  elif match := re.match(f'{patint} minutes',time):
    ret = int(match.group(1))*60
  elif match := re.match(f'^{patint}[:]{patint}[:]{patint}$',time):
    ret = int(match.group(1)) * 60 * 60 + int(match.group(2)) * 60 + int(match.group(3))
  elif match := re.match(f'^{patint}[-]{patint}[:]{patint}[:]{patint}$',time):
    ret = int(match.group(1)) * 24 * 60 * 60 + int(match.group(2)) * 60 * 60 + int(match.group(3)) * 60 + int(match.group(4))
  return int(ret)

def to_hours(time: str) -> (float|str):
  if not time: return time
  comp = [float(_) for _ in re.split('[-:]',time)]
  ret = comp[-4]*24 if len(comp)==4 else 0 + comp[-3] + comp[-2]/60 + comp[-1]/60/60
  return ret

def get_state(job_state: str, reason: str) -> tuple[str, str]:
  """
  Define the jobstate
  """
  status = "UNDETERMINED"
  detailed_status = "QUEUED_ACTIVE"
  if job_state == "PENDING" or job_state == "SUSPENDED":
    status = "SUBMITTED"
    if ( reason == "JobHeldUser" ): detailed_status = "USER_ON_HOLD" 
    elif ( reason == "JobHeldAdmin" ): detailed_status = "SYSTEM_ON_HOLD" 
  elif ( status == "CONFIGURING" ):
    status = "SUBMITTED"
  elif ( job_state == "RUNNING" ):
    status = "RUNNING"
  elif ( job_state == "COMPLETED" or job_state == "COMPLETING" ):
    status = "COMPLETED"
    detailed_status = "JOB_OUTERR_READY"
  elif ( job_state == "CANCELLED" ):
    status = "COMPLETED"
    detailed_status = "CANCELLED"
  elif ( job_state == "FAILED" or job_state == "NODE_FAIL" or job_state == "TIMEOUT" ):
    status = "COMPLETED"
    detailed_status = "FAILED"
  return status, detailed_status


def modify_date(date: str) -> str:
  return date.replace("T"," ")

def modify_state(state: str) -> str:
  """
  Adapt the 'state' value
  """
  ret = state
  # Nodes
  if ( state == "NoResp" ): ret = "Down"   
  elif ( state == "ALLOC" ): ret = "Running"
  elif ( state == "ALLOCATED" ): ret = "Running"
  elif ( state == "DOWN" ): ret = "Down"   
  elif ( state == "DRAIN" ): ret = "Drained"
  elif ( state == "FAIL" ): ret = "Down"   
  elif ( state == "FAILING" ): ret = "Down"   
  elif ( state == "IDLE" ): ret = "Idle"   
  elif ( state == "MIXED" ): ret = "Running"
  elif ( state == "MAINT" ): ret = "Maint"  
  elif ( state == "POWER_DOWN" ): ret = "Down"   
  elif ( state == "POWER_UP" ): ret = "Down"   
  elif ( state == "RESUME" ): ret = "Down"   
  elif ( state == "DOWN+DRAIN" ): ret = "Down"   
  elif ( state == "DOWN*+DRAIN" ): ret = "Down"   
  elif ( state == "MAINT+DRAIN" ): ret = "Down"   
  elif ( state == "MAINT*+DRAIN" ): ret = "Maint"  
  elif ( state == "UNKNOWN+MAINTENANCE" ): ret = "Maint"  
  elif ( state == "IDLE+DRAIN" ): ret = "Drained"
  elif ( state == "RESERVED+DRAIN" ): ret = "Drained"
  elif ( state == "IDLE+COMPLETING" ): ret = "Idle"   

  #Jobs
  elif ( state == "CANCELLED"): ret = "Cancelled" 
  elif ( state == "COMPLETED"): ret = "Completed" 
  elif ( state == "CONFIGURING"): ret = "Pending"   
  elif ( state == "COMPLETING"): ret = "Completed" 
  elif ( state == "FAILED"): ret = "Failed"    
  elif ( state == "NODE_FAIL"): ret = "Failed"    
  elif ( state == "PENDING"): ret = "Pending"   
  elif ( state == "RUNNING"): ret = "Running"   
  elif ( state == "SUSPENDED"): ret = "Suspended" 
  elif ( state == "TIMEOUT"): ret = "Failed"    

  return ret

def modify_load(load: str) -> str:
  """ 
  Fix load value when == N/A 
  """
  return "-1" if load == "N/A" else load

def id_to_username(state: str) -> str:
  """
  Convert user id to username (must be run in the computer where the information is obtainable by `id <uid>`)
  """
  log = logging.getLogger('logger')

  ret = state
  # Getting the username for "CANCELLED by id" messages
  if match := re.match('^CANCELLED by (.+)$',state):
    id = match.group(1)
    rawoutput = check_output(f"id {id}", shell=True, text=True)
    if match := re.match(fr'^uid={id}\((.+?)\).*$',rawoutput):
        ret = f"CANCELLED by {match.group(1)}";  
    else: 
      log.error(f"Error getting username of uid {id}\n")
  return ret

def sysinfo(options: dict, slurm_info) -> dict:
  """
  Specific function to add extra items to sysinfo
  """
  
  log = logging.getLogger('logger')

  # Adding basic information from the system (currently only 'cluster' type)
  log.info("Adding extra information for sysinfo...\n")

  import platform
  sysextra = {}
  sysinfoid = 'cluster'
  sysextra[sysinfoid] = {}
  sysextra[sysinfoid]['hostname'] = platform.node()
  sysextra[sysinfoid]['system_time'] = time.strftime("%m/%d/%y-%H:%M:%S")
  sysextra[sysinfoid]['type'] = 'Cluster'
  sysextra[sysinfoid]['__type'] = 'system'
  sysextra[sysinfoid]['__prefix'] = 'sys'

  # If motd file is given, read it and get the data
  if ('motd' in options):
    try:
      with open(options['motd'], 'r') as file:
        sysextra[sysinfoid]['motd'] = ""
        for line in file:
          line = line.strip('\n')
          # Skip initial lines starting with '*'
          if re.match(r"^\*+$",line) or re.match(r"^\*\*",line): continue
          line = re.sub(r"^\*\s+|\s+\*$","",line)
          line = line.replace('"','&quot;') # Escaping double quotes on the xml
          sysextra[sysinfoid]['motd'] += line+"\\n"
    except FileNotFoundError:
      log.error(f"motd file {options['motd']} does not exist! Skipping it...\n")
  return sysextra


def accountinfo(options: dict, accounts_info) -> dict:
  """
  Specific function to modify accounts, and add extra items to accountinfo
  """
  accountextra = {}
  accountmodified = {}

  # Updating the accounts dictionary by adding or removing keys
  for accountname,accountinfo in accounts_info.items():
    accountmodified.setdefault(accountinfo['USER'],{})

    for key,value in accountinfo.items():
      if key not in accountmodified[accountinfo['USER']]:
        accountmodified[accountinfo['USER']][key] = value
      elif key == 'ACCOUNT':
        accountmodified[accountinfo['USER']][key] += f",{value}"

  # Modifying the accounts_info to the one based on username
  accounts_info._dict = accountmodified

  return accountextra


def nodeinfo(options: dict, nodes_info) -> dict:
  """
  Specific function to add extra items to nodeinfo
  """
  log = logging.getLogger('logger')

  # Getting information from the nodes
  log.info("Adding extra information for nodeinfo...\n")

  nodeextra = {}

  # Updating the nodes dictionary by adding or removing keys
  for nodename,nodeinfo in nodes_info.items():
    # Adding gpus information for GPU nodes (which include 'Gres' key)
    if ('Gres' in nodeinfo) and (match := re.search(r'gpu:(?:[^:()]+:)*(\d+)',nodeinfo['Gres'])):
      nodeinfo['gpus'] = match.group(1)

  # Gathering information about the partitions
  partitions = SlurmInfo()
  partitions.parse_input('scontrol show part --detail --all')
  # partitions.to_LML('./partitions_LML.xml','part')

  # Adding information about the different classes/partitions in each node
  nodes_info_dict = nodes_info._dict
  for partname,partition in partitions.items():
    if ('Nodes' in partition ) and ('TotalNodes' in partition ) and ('TotalCPUs' in partition ):
      if partition['TotalNodes'] == 0: continue
    for node in expand_NodeList(partition['Nodes']).split(' '):
      if(node in nodes_info_dict):
        nodeextra.setdefault(node,{})
        nodeextra[node].setdefault('classes','')
        # Getting total number of CPUs/Threads in each partition, in this priority
        # From nodes_info,'CPUTot' -> nodes_info,'ThreadsPerCore'*'CoresPerSocket'*'Sockets' -> from partition,'TotalCPUs'/'TotalNodes'
        if ('CPUTot' in nodes_info_dict[node]):
          nodeextra[node]['classes']+=f"[{partname}:{nodes_info_dict[node]['CPUTot']}]"
        elif ('ThreadsPerCore' in nodes_info_dict[node] and 'CoresPerSocket' in nodes_info_dict[node] and 'Sockets' in nodes_info_dict[node]):          
          nodeextra[node]['classes']+=f"[{partname}:{nodes_info_dict[node]['ThreadsPerCore']*nodes_info_dict[node]['CoresPerSocket']*nodes_info_dict[node]['Sockets']}]"
        else:
          nodeextra[node]['classes']+=f"[{partname}:{partition['TotalCPUs']/partition['TotalNodes']}]"
      # else:
      #   log.debug(f"Unknown node {node} in partition {partname}!\n")

  # Adding Used Memory information
  systemname = ""
  for nodename,nodeinfo in nodes_info.items():
    UsedMem = None

    if not (re.match(r'^\d+$',nodeinfo['FreeMem'])): #.e.g FreeMem=N/A
      log.warning(f"FreeMem {nodeinfo['FreeMem']} not an integer for node {nodename}, falling back to AllocMem \n")

    elif (re.match(r'^\d+$',nodeinfo['RealMemory'])) and (re.match(r'^\d+$',nodeinfo['FreeMem'])):

      # Getting reserved memory:
      memreserved = 0
      if ('mem_reserved' in options):
        if isinstance(options['mem_reserved'],float) or isinstance(options['mem_reserved'],int):
          memreserved =  options['mem_reserved']
        elif isinstance(options['mem_reserved'],dict):
          if not systemname: systemname = get_system_name(options)
          memreserved = options['mem_reserved'][systemname] if systemname in options['mem_reserved'] else 0
      else:
        memreserved = 0
      UsedMem = float(nodeinfo['RealMemory']) - float(nodeinfo['FreeMem']) - (memreserved)
      if (UsedMem) < 0:
        log.warning(f"Negative UsedMem in node {nodename}: {UsedMem}\n")
        UsedMem = None

    # Falling back to AllocMem if there is an issue with RealMemory and FreeMem
    # .e.g FreeMem = N/A or FreeMem > RealMemory
    if UsedMem is None :
      if re.match(r'^\d+$',nodeinfo['AllocMem']):
        UsedMem = float(nodeinfo['AllocMem'])
        log.info(f"Using AllocMem as fallback for node {nodename}: {UsedMem}\n")
      else:
        log.warning(f"Could not determine memory usage for node {nodename}\n")
        continue
      nodeinfo['UsedMem'] = UsedMem

  return nodeextra


def jobinfo(options: dict, jobs_info) -> dict:
  """
  Specific function to add extra items to jobinfo
  """
  log = logging.getLogger('logger')

  # Getting information from the jobs
  log.info("Adding extra information for jobinfo...\n")

  jobextra = {}

  # Updating the jobs dictionary by adding or removing keys
  for jobname,jobinfo in jobs_info.items():
    # Adding status and detailedstatus to jobs
    jobinfo['status'],jobinfo['detailedstatus'] = get_state(jobinfo['JobState'] if 'JobState' in jobinfo else "", jobinfo['Reason'] if 'Reason' in jobinfo else "")
    jobinfo['MinCPUsNode'] = int(int(jobinfo['NumCPUs'])/int(jobinfo['NumNodes']))
    if 'totaltasks' not in jobinfo:
      jobinfo['totaltasks'] = int(int(jobinfo['NumCPUs'])/int(jobinfo['CPUs/Task']))
    if 'NodeList' in jobinfo and jobinfo['NodeList']:
      jobinfo['NodeList'] = add_CPUs_to_nodelist(jobinfo['NodeList'],jobinfo['MinCPUsNode'])
    if 'SchedNodeList' in jobinfo and jobinfo['SchedNodeList']:
      jobinfo['SchedNodeList'] = add_CPUs_to_nodelist(jobinfo['SchedNodeList'],jobinfo['MinCPUsNode'])
    
    # jobinfo['totaltasks'] = jobinfo['NumCPUs'] 'totaltasks' $jobs{"$jobid"}{NumCPUs} if (!exists($jobs{"$jobid"}{totaltasks}))


  # Gathering information about the job steps
  # steps = SlurmInfo()
  # steps.parse_input('scontrol show steps')
  # # steps.to_LML('./steps_LML.xml',prefix='st',stype='steps')
  # for stepname,step in steps.items():
  #   match = re.match('((\w+)\.\w+)',stepname)
  #   jobid = re.match('((\w+)\.\w+)',stepname).group(2)


  return jobextra

def stepinfo(options: dict, steps_info) -> dict:
  """
  Specific function to add extra items to stepinfo
  """
  log = logging.getLogger('logger')

  # Getting information from the steps
  log.info("Adding extra information for stepinfo...\n")

  stepsextra = {}
  # Using 'info' as the variable name to avoid shadowing the function name 'stepinfo'
  for stepname, info in steps_info.items():
    stepsextra.setdefault(stepname, {})
    
    # Match 'jobid' and 'step' from the stepname string
    name_match = re.match(r'^([\d\_\+]+)\.?(.*)$', stepname)
    # Check if the match was successful before accessing groups
    if name_match:
      stepsextra[stepname]['jobid'] = name_match.group(1)
      stepsextra[stepname]['step'] = name_match.group(2) if name_match.group(2) else 'job'
    else:
      # Fallback values if the stepname does not match the expected pattern
      stepsextra[stepname]['jobid'] = '-'
      stepsextra[stepname]['step'] = '-'

    # Match 'rc' and 'signr' from the ExitCode value
    exit_match = re.match(r'^(\d*):?(\d*)$', info['ExitCode'])
    # Check if the match was successful to prevent AttributeError
    if exit_match:
      stepsextra[stepname]['rc'] = exit_match.group(1) if exit_match.group(1) else '-'
      stepsextra[stepname]['signr'] = exit_match.group(2) if exit_match.group(2) else '-'
    else:
      # Fallback values if ExitCode is empty or in an unexpected format
      stepsextra[stepname]['rc'] = '-'
      stepsextra[stepname]['signr'] = '-'
      
  return stepsextra


class SlurmInfo:
  """
  Class that stores and processes information from Slurm output  
  """
  def __init__(self):
    self._raw = {}  # Dictionary with parsed raw information
    self._dict = {} # Dictionary with modified information (which is outputted to LML)
    self.log   = logging.getLogger('logger')

  def __iadd__(self, other: 'SlurmInfo') -> 'SlurmInfo':
    """
    Implements the in-place addition (+=) operator.
    """
    if not isinstance(other, SlurmInfo):
      return NotImplemented
    
    # Use the enhanced deep_merge function to merge the _data dictionaries
    self.deep_merge(self._raw, other._raw)
    
    # Use the add function to add the data from the 'other' instance
    self.add(other._dict)

    return self

  def __add__(self, other: 'SlurmInfo') -> 'SlurmInfo':
    """
    Implements the standard addition (+) operator.
    """
    if not isinstance(other, SlurmInfo):
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

  def parse(self,options):
    # Modifying SLURM output with functions
    if 'modify_after_parse' in options:
      self.modify(options['modify_after_parse'])

    # Using function of name 'key' (current key being processed, e.g.: nodeinfo, jobinfo, etc.), when defined,
    # to modify that particular group/dictionary and items
    if 'apply_function' in options:
      if options['apply_function'] in globals():
        func = globals()[options['apply_function']]
        self.add(func(options,self))
      else:
        self.log.error(f"Function '{options['apply_function']}' is not defined in the program! Skipping...")

    # Modifying SLURM output with functions
    if 'modify_before_mapping' in options:
      self.modify(options['modify_before_mapping'])

    # Applying pattern to include or exclude units
    if 'exclude' in options or 'include' in options:
      self.apply_pattern(
                          exclude=options['exclude'] if 'exclude' in options else '',
                          include=options['include'] if 'include' in options else ''
                        )

    # Mapping keywords
    if 'mapping' in options:
      self.map(options['mapping'])

    return

  def parse_input(self, initial_cmd, foreach=[None], timestamp={}, prefix="", stype="", delimiter="|"):
    """
    This function parses the output of Slurm commands
    and returns them in a dictionary
    """
    # Looping over a given quantity 
    # (this can only happen when adding extra information to a given block via 'add' keyword)
    # Each entry in foreach must be a dictionary with {"key_to_be_substituted_in_cmd": "value"}
    # e.g., {'jobid': 999999}
    for loop_entry in foreach:
      # Starting new command for current call
      cmd = initial_cmd
      # If a timestamp file is given, the query should be made in a given period
      # This is set by the flags '-S <start_time> -E <end_time>' and the file
      # 'timestampfile' stores the last timestamp for which information was obtained
      if timestamp and ('file' in timestamp):
        end_ts = time.time() - timestamp['ts_delay'] if 'ts_delay' in timestamp else 0

        if os.path.isfile(timestamp['file']):
          try:
            with open(timestamp['file'], 'r') as f:
              last_ts = float(f.readline())
          except ValueError:
            self.log.error(f"Error reading timestamp from {timestamp['file']}! Check if file is correct or delete it.\n")
            return
          self.log.debug(f"Last timestamp from {timestamp['file']}: {last_ts}\n")
        else:
          last_ts = end_ts-1*24*60*60
          self.log.debug(f"Timestamp file {timestamp['file']} does not exist. Getting information from the last day...\n")
        last_date = datetime.fromtimestamp(last_ts).strftime('%m/%d/%y-%H:%M:%S')
        end_date = datetime.fromtimestamp(end_ts).strftime('%m/%d/%y-%H:%M:%S')
        self.log.debug(f"Getting information from {last_date} to {end_date}\n")
        cmd = f"{cmd} -S {last_date} -E {end_date}"

        # Write timestamp of last query to file
        with open(timestamp['file'], 'w') as f:
          f.write(f'{end_ts}')

      # If there's a loop to be done, substitute the desired key in the command
      if loop_entry:
        for key,value in loop_entry.items():
          cmd = cmd.replace(f"$${key}$$",value)

      # Getting Slurm raw output
      rawoutput = check_output(cmd, shell=True, text=True)
      # 'scontrol' has an output that is different from
      # 'sacct' and 'sacctmgr' (the latter are csv-like)
      if("scontrol" in cmd):
        # Parsing 'scontrol' command
        # If result is empty, return
        if (re.match("No (.*) in the system",rawoutput)):
          self.log.warning(rawoutput.split("\n")[0]+"\n")
          continue
        # Getting unit to be parsed from first keyword
        # Match 'unitname' from the rawoutput string
        name_match = re.match(r"(\w+)",rawoutput)
        # Check if the match was successful before accessing groups
        if not name_match:
          self.log.error(f"Could not match unitname in output: {rawoutput}. Skipping...\n")
          continue
        unitname = name_match.group(1)
        self.log.debug(f"Parsing units of {unitname}...\n")
        units = re.findall(fr"({unitname}[\s\S]+?)\n\n",rawoutput)
        for unit in units:
          self.parse_unit_block(unit, unitname, prefix, stype)
      else:
        # Parsing 'sacct' or 'sacctmgr' or 'sstat' commands
        units = list(csv.DictReader(rawoutput.splitlines(), delimiter=delimiter))
        if len(units) == 0:
          self.log.warning(f"No output units from command '{cmd}'\n")
          continue
        # Getting unit to be parsed from first keyword
        # Match 'unitname' from the rawoutput string
        name_match = re.match(r"(\w+)",rawoutput)
        # Check if the match was successful before accessing groups
        if not name_match:
          self.log.error(f"Could not match unitname in output: {rawoutput}. Skipping...\n")
          continue
        unitname = name_match.group(1)
        self.log.debug(f"Parsing units of {unitname} in output of '{cmd}'...\n")
        for unit in units:
          current_unit = unit[unitname]
          self._raw.setdefault(current_unit,{})
          # Adding prefix and type of the unit, when given in the input
          if "__prefix" not in self._raw[current_unit] and prefix:
            self._raw[current_unit]["__prefix"] = prefix
          if "__type" not in self._raw[current_unit] and stype:
            self._raw[current_unit]["__type"] = stype
          for key,value in unit.items():
            # If the value exist, join with new one separated by comma
            # Unless the value is the current_unit, since that does not need accumulation
            # (Only add if values are different)
            if (key in self._raw[current_unit]) and (value != current_unit) and (value not in self._raw[current_unit][key].split(',')): 
              value_to_add = f"{self._raw[current_unit][key]},{value}"
            else:
              value_to_add = value
            self.add_value(key,value_to_add,self._raw[current_unit])
      self._dict |= self._raw
    return

  def add_value(self,key,value,dict):
    """
    Function to add (key,value) pair to dict. 
    This is a separate function to make it easier to adapt some corner cases
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
    # Split the first line into individual key=value pairs
    parts = lines[0].strip().split(' ')
    current_unit = None

    # Handle the first element separately to define the 'current_unit'
    if parts:
      key, value = parts[0].split('=', 1)
      if key == unitname:
        current_unit = value
        self._raw[current_unit] = {}
        # Adding prefix and type of the unit to the dictionary
        if stype:
          self._raw[current_unit]["__prefix"] = prefix
          self._raw[current_unit]["__type"] = stype
        # Add the unit itself as the first value
        self.add_value(key, value, self._raw[current_unit])

    # If the unit context was not set, return
    if not current_unit:
      self.log.error(f"Could not match unit in line: {parts[0]}. Skipping...\n")
      return

    # Process the rest of the pairs (skipping the first one)
    for pair in parts[1:]:
      key, value = pair.split('=', 1)
      
      # JobName requires special handling as it may contain '=' and ' '
      if key == "JobName":
        # Search for 'JobName' in the full first line string
        name_match = re.search(".*JobName=(.*)$", lines[0].strip())
        if not name_match:
          self.log.error(f"Could not match JobName in line: {lines[0].strip()}. Skipping...\n")
          continue
        
        value = name_match.group(1)
        self._raw[current_unit][key] = value
        # Stop processing the line once JobName is handled
        break
      
      # Handle standard key=value pairs
      self.add_value(key, value, self._raw[current_unit])

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
      if key in ['Comment','Extra','Reason','Command','WorkDir','StdErr','StdIn','StdOut','TRES','OS']: 
        self.add_value(key,value,self._raw[current_unit])
        continue
      # Now the pairs are separated by space
      for pair in line.split(' '):
        if len(splitted := pair.split('=',1)) == 2: # Checking if line is splittable on "=" sign
          key,value = splitted
        else:  # If not, split on ":"
          if len(split_pair := pair.split(":",1)) == 2:
            key,value = split_pair
          else:
            self.log.error(f"Could not parse pair '{pair}' in line '{line}'. Skipping line...\n")
            break
        if key in ['Dist']: #'JobName'
          self._raw[current_unit][key] = line.split(f'{key}=',1)[1]
          break
        self.add_value(key,value,self._raw[current_unit])
    return

  def apply_pattern(self,exclude="",include=""):
    """
    Loops over all units in self._dict to:
    - remove items that match 'exclude'
    - keep only items that match 'include'
    """
    to_remove = []
    for unitname,unit in self._dict.items():
      if exclude and self.check_unit(unitname,unit,exclude,text="excluded") == True:
        to_remove.append(unitname)
      if include and self.check_unit(unitname,unit,include,text="included") == False:
        to_remove.append(unitname)
    for unitname in to_remove:
      del self._dict[unitname]
    return
  
  def check_unit(self,unitname,unit,pattern,text="included/excluded"):
    """
    Check 'current_unit' name with rules for exclusion or inclusion. (exclusion is applied first)
    Returns True if unit is to be skipped
    """
    if isinstance(pattern,str): # If rule is a simple string
      if re.match(pattern, unitname):
        self.log.debug(f"Unit {unitname} is {text} due to {pattern} rule\n")
        return True
    elif isinstance(pattern,list): # If list of rules
      for pat in pattern: # loop over list - that can be strings or dictionaries
        if isinstance(pat,str): # If item in list is a simple string
          if re.match(pat, unitname):
            self.log.debug(f"Unit {unitname} is {text} due to {pat} rule in list\n")
            return True
        elif isinstance(pat,dict): # If item in list is a dictionary
          for key,value in pat.items():
            if isinstance(value,str): # if dictionary value is a simple string
              if (key in unit) and re.match(value, unit[key]):
                self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key of list\n")
                return True
            elif isinstance(value,list): # if dictionary value is a list
              for v in value:
                if (key in unit) and re.match(v, unit[key]): # At this point, v in list can only be a string
                  self.log.debug(f"Unit {unitname} is {text} due to {v} rule in list of {key} key of list\n")
                  return True
    elif isinstance(pattern,dict): # If dictionary with rules
      for key,value in pattern.items():
        if isinstance(value,str): # if dictionary value is a simple string
          if (key in unit) and re.match(value, unit[key]):
            self.log.debug(f"Unit {unitname} is {text} due to {value} rule in {key} key\n")
            return True
        elif isinstance(value,list): # if dictionary value is a list
          for v in value:
            if (key in unit) and re.match(v, unit[key]): # At this point, v in list can only be a string
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
    self.log.info(f"Writing LML data to {filename} ... ")
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
          if (value):
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


def get_system_name(options: dict) -> str:
  """
  Get system name from systemname key of options
  Options that are tested (first string, then in the dictionary order):
    - direct string 
      systemname: 'system'
      or
      systemname: '${LLVIEW_SYSTEMNAME}'
    - file containing system name:
      systemname: 
        file: '/path/to/file'
    - environment variable:
      systemname: 
        env: 'LLVIEW_SYSTEMNAME' # Note that there's no ${...} here
  """
  log = logging.getLogger('logger')

  systemname = 'unknown'
  # Checking if systemname key is given in the options
  if 'systemname' in options:
    if isinstance(options['systemname'],str):
      # If it's a string, set it as the systemname
      systemname = os.path.expandvars(options['systemname'])
    elif isinstance(options['systemname'],dict):
      # If it's a dict, loop over the keys (but only 'file' or 'env' are recognized)
      for key,value in options['systemname'].items():
        if key == 'file':
          # If file is given, try to read it
          try:
            with open(value, 'r') as file:
              systemname = file.read()
            break # Stop from trying other ways if file was read
          except FileNotFoundError:
            log.error(f"Could not get system name from file {value}\n")
        elif key == 'env':
          # Trying to get from environment variable
          name = os.environ.get(value)
          if name:
            systemname = name
            break # Stop from trying other ways if envvar was read
          else:
            log.error(f"Could not get system name from environment ${value}\n")
        else:
          log.error(f"System name not recognized from {key}:{value}\n")
    else:
      log.error(f"Cannot obtain system name from 'systemname' given: {options['systemname']}\n")
  else:
    log.error("System name not defined in 'systename'\n")

  systemname = systemname.strip()
  log.info(f'Using system name: {systemname}\n')
  return systemname


def parse_config_yaml(filename):
  """
  YML configuration parser
  """
  import yaml
  with open(filename, 'r') as configyml:
    configyml = yaml.safe_load(configyml)
  return configyml

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
  parser = argparse.ArgumentParser(description="Slurm Plugin for LLview")
  # parser.add_argument("--LMLjobfile",  default="./jumonc_LML.xml", help="Output LML file for information of jobs")
  parser.add_argument("--config",    default=False, help="YAML config file containing the information to be gathered and converted to LML")
  parser.add_argument("--loglevel",  default=False, help="Select log level: 'DEBUG', 'INFO', 'WARNING', 'ERROR' (more to less verbose)")
  parser.add_argument("--singleLML", default=False, help="Merge all sections into a single LML file")
  parser.add_argument("--outfolder", default=False, help="Reference output folder")
  # parser.add_argument("--PAT_NODES", default=False,      help="Pattern of node names to gather information from")

  args = parser.parse_args()

  # Configuring the logger (level and format)
  log_init(args.loglevel)
  log = logging.getLogger('logger')

  if args.config:
    config = parse_config_yaml(args.config)
  else:
    log.critical("Config file not given!\n")
    parser.print_help()
    exit(1)

  unique = SlurmInfo()

  # Start generic timer
  start_time = time.time()

  #####################################################################################
  # Processing config file
  for key,options in config.items():
    if (not args.singleLML) and ('LML' not in options):
      log.error(f"No LML file given for {key} in config file! Skipping section...\n")
      continue

    local_start_time = time.time()

    log.info(f"Collecting {key}...\n")

    # Initializing new object of type given in config
    slurm_info = SlurmInfo()

    # Parsing Slurm output
    if ('cmd' not in options):
      log.warning(f"No 'cmd' key given for Slurm command for {key} in config file! Skipping...\n")
    else:
      if 'prefix' not in options:
        options['prefix'] = 'i'
      if 'type' not in options:
        options['type'] = 'item'
      slurm_info.parse_input(
                        options['cmd'],
                        timestamp=options['timestamp'] if 'timestamp' in options else '',
                        prefix=options['prefix'],
                        stype=options['type'],
                        delimiter=options['delimiter'] if 'delimiter' in options else '|',
                        )

    slurm_info.parse(options)

    # If there are extra metrics to be added on the same LML file
    if 'add' in options:
      # loop over all extra entries
      for extra_entry in options['add']:
        # If the extra commands are to be looped over some quantity
        # the 'foreach' key can be used (it is obtained)
        foreach = [None]
        if extra_entry['foreach']:
          foreach_value = set()
          for name, item in slurm_info.items():
            foreach_value.add(item[extra_entry['foreach']])
          foreach = [{extra_entry['foreach']:_} for _ in foreach_value] 

        # Parsing Slurm output
        if ('cmd' not in extra_entry):
          log.warning(f"No 'cmd' key given for Slurm command for extra option in {key}! Skipping...\n")
        else:
          slurm_info.parse_input(
                            extra_entry['cmd'],
                            foreach=foreach,
                            timestamp=extra_entry['timestamp'] if 'timestamp' in extra_entry else '',
                            prefix=extra_entry['prefix'] if 'prefix' in extra_entry else options['prefix'],
                            stype=extra_entry['type'] if 'type' in extra_entry else options['type'],
                            delimiter=extra_entry['delimiter'] if 'delimiter' in extra_entry else '|',
                            )
        # Mapping should include all entries in original and added, so we gather all in 
        # options['mapping'] and use it as mapping dictionary
        options['mapping'] |= extra_entry['mapping']
        extra_entry['mapping'] = options['mapping']
        slurm_info.parse(extra_entry)

    local_end_time = time.time()
    log.debug(f"Gathering {key} information took {local_end_time - local_start_time:.4f}s\n")

    # When there's an object per entry, the LML and configurations are generated for each of them
    if (not args.singleLML):

      if slurm_info.empty():
        log.warning(f"Object for {key} is empty, output will include only timings...\n")

      # Add timing key
      timing = {}
      name = f'get{key}'
      timing[name] = {}
      timing[name]['startts'] = local_start_time
      timing[name]['datats'] = local_start_time
      timing[name]['endts'] = local_end_time
      timing[name]['duration'] = local_end_time - local_start_time
      timing[name]['nelems'] = len(slurm_info)
      # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
      timing[name][f"__nelems_{options['type'] if 'type' in options else 'item'}"] = len(slurm_info)
      timing[name]['__type'] = 'pstat'
      timing[name]['__id'] = f'pstat_get{key}'
      slurm_info.add(timing)

      slurm_info.to_LML(f"{args.outfolder.rstrip('/')+'/' if args.outfolder else ''}{options['LML']}")

    else:
      # Accumulating for a single LML
      unique = unique + slurm_info

  # End generic timer
  end_time = time.time()

  if (args.singleLML):
    if unique.empty():
      log.warning(f"Unique object is empty, output will include only timings...\n")

    # Add timing key for Unique object
    timing = {}
    name = f'getSlurmInfo'
    timing[name] = {}
    timing[name]['startts'] = start_time
    timing[name]['datats'] = start_time
    timing[name]['endts'] = end_time
    timing[name]['duration'] = end_time - start_time
    timing[name]['nelems'] = len(unique)
    # The __nelems_{type} is used to indicate to DBupdate the number of elements - important when the file is empty
    timing[name][f"__nelems_slurm"] = len(unique)
    timing[name]['__type'] = 'pstat'
    timing[name]['__id'] = f'pstat_getSlurmInfo'
    unique.add(timing)
      
    unique.to_LML(f"{args.outfolder.rstrip('/')+'/' if args.outfolder else ''}{args.singleLML}")
  return

if __name__ == "__main__":
  main()
