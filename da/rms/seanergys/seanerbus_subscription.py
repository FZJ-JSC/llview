#!/usr/bin/env python3
# Copyright (c) 2026 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

import argparse
import asyncio
import capnp
import json
import logging
import os
import sys
import time
import uuid
import yaml
import pwd
import re
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Union, Optional

import seanerbus.client
from seanerbus.msg import FluxLifecycleEventV1, TimeValueV1

class CustomFormatter(logging.Formatter):
  """
  Colors are added to log output based on the severity level.
  """
  def __init__(self, fmt: str, datefmt: str = "") -> None:
    """
    The formatter is initialized with a specific format string and date format.

    Args:
      fmt (str): The log message format string.
      datefmt (str): The date format string.

    Returns:
      None
    """
    super().__init__()
    self.fmt = fmt
    self.datefmt = datefmt
    # ANSI Color Codes
    self.grey = "\x1b[38;20m"
    self.yellow = "\x1b[93;20m"
    self.blue = "\x1b[94;20m"
    self.magenta = "\x1b[95;20m"
    self.cyan = "\x1b[96;20m"
    self.red = "\x1b[91;20m"
    self.bold_red = "\x1b[91;1m"
    self.reset = "\x1b[0m"

    self.FORMATS = {
      logging.DEBUG: self.cyan + self.fmt + self.reset,
      logging.INFO: self.grey + self.fmt + self.reset,
      logging.WARNING: self.yellow + self.fmt + self.reset,
      logging.ERROR: self.red + self.fmt + self.reset,
      logging.CRITICAL: self.bold_red + self.fmt + self.reset
    }
    
  def format(self, record: logging.LogRecord) -> str:
    """
    Log records are formatted with the appropriate ANSI color codes applied.

    Args:
      record (logging.LogRecord): The log record to be formatted.

    Returns:
      str: The formatted log string with color codes.
    """
    log_fmt = self.FORMATS.get(record.levelno)
    formatter = logging.Formatter(fmt=log_fmt, datefmt=self.datefmt)
    return formatter.format(record)

class _ExcludeErrorsFilter(logging.Filter):
  """
  Log messages with a severity level below ERROR are permitted through this filter.
  """
  def filter(self, record: logging.LogRecord) -> bool:
    """
    The severity level of the log record is evaluated.

    Args:
      record (logging.LogRecord): The log record to be evaluated.

    Returns:
      bool: True if the record level is below ERROR, False otherwise.
    """
    return record.levelno < logging.ERROR

def log_init(level: str) -> None:
  """
  The logger is initialized with separate handlers for standard output and error.

  Args:
    level (str): The desired logging level (e.g., 'DEBUG', 'INFO', 'WARNING', 'ERROR').

  Returns:
    None
  """
  log_config = {
    'format': "%(asctime)s %(funcName)-18s(%(lineno)-3d): [%(levelname)-8s] %(message)s",
    'datefmt': "%Y-%m-%d %H:%M:%S",
    'level': "INFO"
  }
  
  log = logging.getLogger('logger')
  log.setLevel(level)

  # Standard output handler for non-error messages
  oh = logging.StreamHandler(sys.stdout)
  oh.setLevel(level if level else log_config['level'])
  oh.setFormatter(CustomFormatter(log_config['format'], datefmt=log_config['datefmt']))
  oh.addFilter(_ExcludeErrorsFilter())
  oh.terminator = ""
  log.addHandler(oh)

  # Standard error handler for error and critical messages
  eh = logging.StreamHandler(sys.stderr)
  eh.setLevel('ERROR')
  eh.setFormatter(CustomFormatter(log_config['format'], datefmt=log_config['datefmt']))
  eh.terminator = ""
  log.addHandler(eh)

def expand_NodeList(nodelist: Union[str, List[str]]) -> str:
  """
  Node lists are converted into a space-separated string.

  Args:
    nodelist (Union[str, List[str]]): The node list, either as a single string or a list of strings.

  Returns:
    str: A space-separated string containing all nodes.
  """
  # The incoming value is converted to a string if it arrives as a list
  if isinstance(nodelist, list):
    nodelist = ",".join(str(n) for n in nodelist)
  elif not isinstance(nodelist, str):
    nodelist = str(nodelist)

  expandedlist = ""
  
  # Find all distinct node strings, whether they are single nodes or bracketed groups
  for node_group in re.findall(r'([^,\[\]]+(?:\[[\d,-]+\])?)', nodelist):
    
    # Check if the current node string contains a bracketed grouping
    match = re.match(r"(.+?)\[(.*?)\]", node_group)
    if not match:
      # single node without brackets (e.g., 'jpbo-049-35')
      expandedlist += f"{node_group} "
      continue
      
    # extract the prefix and the inner bracket contents
    prefix = match.group(1)
    inner_bracket = match.group(2)
    
    # Process multiple nodes inside the grouping like "node-[a,b,m-n,x-y]"
    for item in inner_bracket.split(','):
      # splitting eventual consecutive nodes with '-'
      bounds = item.split('-', 1)
      if len(bounds) == 1:
        # single node inside bracket (e.g., '08')
        expandedlist += f"{prefix}{bounds[0]} "
      else:
        # multi-node range inside bracket (e.g., '21-31')
        start, end = bounds
        
        # Maintain zero-padding dynamically (e.g., '08' to '10' -> 08, 09, 10)
        width = len(start)
        for i in range(int(start), int(end) + 1):
          expandedlist += f"{prefix}{i:0{width}d} "  
          
  return expandedlist.rstrip()

def modify_date(timestamp: Any) -> str:
  """
  Unix timestamps are converted to ISO format without the 'T' separator.

  Args:
    timestamp (Any): The raw timestamp value to be converted.

  Returns:
    str: The formatted date string, or the original input if conversion is not possible.
  """
  try:
    ts = float(timestamp)
    return datetime.fromtimestamp(ts).isoformat(sep=' ')
  except (ValueError, TypeError):
    return str(timestamp)

def id_to_username(uid: int|str) -> str:
  """
  Convert user id to username (must be run in the computer where the information is obtainable by `id <uid>`)
  """
  log = logging.getLogger('logger')

  ret = uid
  # Converting uid to username is attempted, otherwise the original input is returned
  try:
    ret = pwd.getpwuid(int(uid)).pw_name
  except KeyError:
    log.error(f"User not found for uid {uid}")
  return ret


def coreinfo(processed: Dict[str, Dict[str, Any]], output_spec: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
  """
  Specific function to generate per-core idle strings for coreinfo.
  """
  log = logging.getLogger('logger')
  # log.info("Adding extra information for cores...\n")

  coressextra = {}
  
  for node, metrics in processed.items():
    # Only the desired keys are retained in the new dictionary
    coressextra[node] = {
      'name': node,  # Explicitly mapping the node name
      'ci_ts': metrics.get('ts', time.time()),
      '__prefix': metrics.get('__prefix', 'ci'),
      '__type': metrics.get('__type', 'coreinfo')
    }
    
    # Core idle values are extracted from the flattened metrics dictionary
    coreidle_map = {}
    for key, value in metrics.items():
      if key.startswith('cpu') and key.endswith('idle'):
        try:
          core_id = int(key[3:-4])
          coreidle_map[core_id] = float(value)
        except ValueError:
          pass

    # The usage string (1 - idle) is calculated and formatted
    if coreidle_map:
      coressextra[node]['percore'] = ','.join(
        [f"{core}:{1-coreidle:g}" for core, coreidle in sorted(coreidle_map.items())]
      )

  return coressextra

def cpuinfo(processed: Dict[str, Dict[str, Any]], output_spec: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
  """
  Specific function to aggregate physical and logical core usages for cpuinfo.
  """
  log = logging.getLogger('logger')
  # log.info("Adding extra information for cpus...\n")

  nsmts = output_spec.get('smt', 2)
  nsockets = output_spec.get('sockets', 1)
  topology = output_spec.get('topology', 'blocked')
  usage_threshold = 1 - output_spec.get('usage_threshold', 0.25)

  cpusextra = {}
  logical_cores_per_scope = {}

  for node, metrics in list(processed.items()):
    
    # Core idle values are extracted
    coreidle_map = {}
    for key, value in metrics.items():
      if key.startswith('cpu') and key.endswith('idle'):
        try:
          core_id = int(key[3:-4])
          coreidle_map[core_id] = float(value)
        except ValueError:
          pass
          
    total_cores = len(coreidle_map)
    if total_cores == 0:
      continue

    # Required data for core mapping on each topology is calculated
    total_physical_cores, logical_cores_per_socket = 0, 0
    if topology == 'blocked':
      total_physical_cores = max(int(total_cores / nsmts), 1)
      phys_cores_per_socket = max(int(total_physical_cores / nsockets), 1)
    elif topology == 'interleaved':
      phys_cores_per_socket = max(int(total_cores / nsmts / nsockets), 1)
      logical_cores_per_socket = phys_cores_per_socket * nsmts
    else:
      raise ValueError(f"Unknown topology: '{topology}'. Supported values are 'blocked', 'interleaved'.")

    normalization_factor = phys_cores_per_socket

    for coreid, coreidle in coreidle_map.items():
      if topology == 'blocked':
        smt = int(coreid / total_physical_cores)
        effective_coreid = coreid % total_physical_cores
        socket = int(effective_coreid / phys_cores_per_socket)
      else:
        socket = int(coreid / logical_cores_per_socket)
        effective_coreid = coreid % logical_cores_per_socket
        smt = effective_coreid % nsmts

      node_name = f"{node}{'' if nsockets == 1 else f'_{socket:02d}'}"

      # The clean dictionary is initialized per node/socket
      socket_data = cpusextra.setdefault(node_name, {
          'name': node_name,  # Explicitly mapping the node name
          'cpu_ts': metrics.get('ts', time.time()),
          '__prefix': metrics.get('__prefix', 'cpu'),
          '__type': metrics.get('__type', 'cpuinfo'),
          'usage': 0,
          'physcoresused': 0,
          'logiccoresused': 0,
      })

      # The raw idle value is inverted (assuming factor: 0.0001 was applied in YAML to scale to 0-1)
      socket_data['usage'] += (1 - coreidle)
      is_used = int(coreidle < usage_threshold)

      if smt == 0:
        socket_data['physcoresused'] += is_used
      else:
        socket_data['logiccoresused'] += is_used

      logical_cores_per_scope[node_name] = normalization_factor

  # Total usage is normalized across the logical cores
  for node_name, data in cpusextra.items():
    num_cpus = logical_cores_per_scope.get(node_name, 0)
    if num_cpus > 0:
      data['usage'] /= num_cpus

  return cpusextra

def nodepwr(processed: Dict[str, Dict[str, Any]], output_spec: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
  """
  The derived 'memU' metric is calculated for nodes that contain both total and free memory.

  Args:
    processed (Dict[str, Dict[str, Any]]): The raw processed metrics, natively grouped by node ID.
    output_spec (Dict[str, Any]): The configuration specification for the current output.

  Returns:
    Dict[str, Dict[str, Any]]: The dictionary with the newly calculated 'memU' metric appended.
  """
  for node_id, metrics in processed.items():
    if "energy" in metrics:
      try:
        metrics["power"] = float(metrics["energy"])*0.01666666667 # Divided by 60 to transform to power (in Watts)
          
      except (ValueError, TypeError):
        pass
  return processed


def nodes(processed: Dict[str, Dict[str, Any]], output_spec: Dict[str, Any]) -> Dict[str, Dict[str, Any]]:
  """
  The derived 'memU' metric is calculated for nodes that contain both total and free memory.

  Args:
    processed (Dict[str, Dict[str, Any]]): The raw processed metrics, natively grouped by node ID.
    output_spec (Dict[str, Any]): The configuration specification for the current output.

  Returns:
    Dict[str, Dict[str, Any]]: The dictionary with the newly calculated 'memU' metric appended.
  """
  for node_id, metrics in processed.items():
    if "memtotal" in metrics and "memfree" in metrics:
      try:
        metrics["memU"] = float(metrics["memtotal"]) - float(metrics["memfree"])
        
        # A timestamp for the derived metric is assigned based on the free memory timestamp
        if "memfree_ts" in metrics:
          metrics["memU_ts"] = metrics["memfree_ts"]
          
      except (ValueError, TypeError):
        pass
  return processed


class EventCollector:
  """
  Events are collected in memory and aggregated periodically for LML output.
  """
  def __init__(self, prefix: str, stype: str) -> None:
    """
    The event collector is initialized with a specific prefix and type.

    Args:
      prefix (str): The prefix used for LML object IDs.
      stype (str): The type category for the collected objects.

    Returns:
      None
    """
    self.prefix = prefix
    self.stype = stype
    self.data: Dict[str, Dict[str, List[Any]]] = {}
    self.start_time: float = time.time()
    # Tracked objects are persisted across intervals if they haven't finished
    self.running_objects: Dict[str, Dict[str, Any]] = {}

  def add_metrics(self, object_id: str, metrics: Dict[str, Any]) -> None:
    """
    Non-null metric values are appended to the internal storage for a specific object.

    Args:
      object_id (str): The unique identifier for the object being tracked.
      metrics (Dict[str, Any]): A dictionary mapping metric names to their values.

    Returns:
      None
    """
    if object_id not in self.data:
      self.data[object_id] = {}
    
    for key, value in metrics.items():
      # Valid values are appended to the metric lists
      if value is not None:
        if key not in self.data[object_id]:
          self.data[object_id][key] = []
        self.data[object_id][key].append(value)

  def aggregate(
    self, 
    values: List[Any], 
    method: str, 
    separator: str = ",", 
    template: str = "{value}",
    split_by: Optional[str] = None
  ) -> Any:
    """
    A list of collected values is reduced to a single representative value.

    Args:
      values (List[Any]): The list of collected values for a single metric.
      method (str): The aggregation strategy to be applied ('sum', 'avg', 'max', 'min', 'count', 'concatenate', 'last').
      separator (str): The separator string to be used when concatenating values.
      template (str): The formatting template applied to individual values during concatenation.
      split_by (Optional[str]): A character used to split string values before concatenation.

    Returns:
      Any: The aggregated result.
    """
    if not values:
      return None
    
    if method == "sum":
      return sum(v for v in values if isinstance(v, (int, float)))
    elif method == "avg":
      nums = [v for v in values if isinstance(v, (int, float))]
      return sum(nums) / len(nums) if nums else values[-1]
    elif method == "max":
      return max(values)
    elif method == "min":
      return min(values)
    elif method == "count":
      return len(values)
    elif method == "concatenate":
      flat_values = []
      for v in values:
        # Lists and splittable strings are flattened to apply the template to individual items
        if isinstance(v, list):
          flat_values.extend(v)
        elif split_by is not None and isinstance(v, str):
          flat_values.extend(v.split(split_by))
        else:
          flat_values.append(v)
          
      # Empty strings are ignored, and the template is applied to each valid element
      return separator.join(template.format(value=str(v).strip()) for v in flat_values if str(v).strip())
    
    # The last recorded value is returned as a fallback default
    return values[-1]

  def flush_data(self) -> Dict[str, Dict[str, List[Any]]]:
    """
    The current stored data is returned and the internal dictionary is reset atomically.

    Returns:
      Dict[str, Dict[str, List[Any]]]: A complete snapshot of the collected raw data.
    """
    current_data = self.data
    self.data = {}
    return current_data

  def _parse_time(self, t_val: Any) -> float:
    """
    Time values (timestamps or ISO strings) are parsed into float timestamps.

    Args:
      t_val (Any): The time value to be parsed.

    Returns:
      float: The parsed timestamp, or 0.0 if parsing fails.
    """
    if isinstance(t_val, (int, float)):
      return float(t_val)
    try:
      return float(t_val)
    except ValueError:
      pass
    try:
      # ISO formats modified by modify_date are reverted to standard ISO for parsing
      return datetime.fromisoformat(str(t_val).replace(' ', 'T')).timestamp()
    except ValueError:
      return 0.0

  def _clean_stuck_objects(self, now: float, fallback_ttl: float, log: logging.Logger) -> None:
    """
    Stuck objects are identified and purged from the tracking dictionary if they exceed their expected lifetime.

    Args:
      now (float): The current Unix timestamp.
      fallback_ttl (float): The default time-to-live in seconds if no walltime is available.
      log (logging.Logger): The logger instance.

    Returns:
      None
    """
    for obj_id, data in list(self.running_objects.items()):
      expire_time = now + fallback_ttl  # Default far future expiration
      
      start_t = self._parse_time(data.get('starttime', 0))
      submit_t = self._parse_time(data.get('submittime', 0))
      wall_t = self._parse_time(data.get('walltime', 0))
      
      if start_t > 0:
        if wall_t > 0:
          # A 300-second buffer is added to allow for graceful finish events
          expire_time = start_t + wall_t + 300
        else:
          expire_time = start_t + fallback_ttl
      elif submit_t > 0:
        expire_time = submit_t + fallback_ttl
      else:
        # Fallback is based on the last time the object was updated, checking both public and internal timestamps
        ts_t = self._parse_time(data.get('ts', data.get('__ts', 0)))
        expire_time = ts_t + fallback_ttl
        
      if now > expire_time:
        log.warning(f"Object '{obj_id}' exceeded its TTL. Removing from tracking.\n")
        del self.running_objects[obj_id]


  def process_raw_data(self, raw_data: Dict[str, Dict[str, List[Any]]], output_spec: Dict[str, Any], fallback_ttl: float) -> Dict[str, Dict[str, Any]]:
    """
    Extracted raw data is processed into a flat dictionary, integrated with running jobs, 
    and output metrics are calculated.

    Args:
      raw_data (Dict[str, Dict[str, List[Any]]]): The raw, multi-value metric data.
      output_spec (Dict[str, Any]): The configuration specifying how metrics should be aggregated.
      fallback_ttl (float): The maximum allowed age for tracked objects without a known walltime.

    Returns:
      Dict[str, Dict[str, Any]]: The processed data ready for LML export.
    """
    log = logging.getLogger('logger')
    processed: Dict[str, Dict[str, Any]] = {}
    now = time.time()

    for obj_id, metrics_map in raw_data.items():
      processed[obj_id] = {
        "__prefix": self.prefix,
        "__type": self.stype
      }
      current_processed = processed[obj_id]
      for sub in output_spec.get("subscriptions", []):
        for metric_name, metric_cfg in sub.get("metrics", {}).items():
          if metric_name in metrics_map:
            agg_method = metric_cfg.get("agg", "last")
            sep = metric_cfg.get("separator", ",")
            tmpl = metric_cfg.get("template", "{value}")
            split_char = metric_cfg.get("split_by")
            current_processed[metric_name] = self.aggregate(
              metrics_map[metric_name], agg_method, sep, tmpl, split_char
            )
            
      # An internal timestamp is maintained for TTL tracking without forcing it into the LML output
      if 'ts' not in current_processed and '__ts' not in current_processed:
        current_processed['__ts'] = now
        
      if 'rc_state' in current_processed:
        current_processed['state'] = current_processed['rc_state']
        del current_processed['rc_state']

    # Tracked jobs are merged into the current processed batch so historical fields are preserved
    for obj_id, running_data in list(self.running_objects.items()):
      if obj_id in processed:
        # Missing historical fields (like starttime) are carried over to the current batch
        for key, val in running_data.items():
          if key not in processed[obj_id]:
            processed[obj_id][key] = val
        # The tracked memory is updated with the newest batch data
        self.running_objects[obj_id].update(processed[obj_id])
      else:
        # If the job didn't broadcast this interval, its last known state is injected
        log.debug(f"Injecting tracked job '{obj_id}' into current output batch.\n")
        processed[obj_id] = running_data.copy()
        
    # Any completely new jobs are added to tracking
    for obj_id, current_processed in processed.items():
      if obj_id not in self.running_objects:
        if ('submittime' in current_processed or 'starttime' in current_processed) and 'finishtime' not in current_processed:
          log.debug(f"Tracking new queued/running job '{obj_id}'.\n")
          self.running_objects[obj_id] = current_processed.copy()
        
    # The waittime and runtime are calculated, and finished jobs are removed from tracking
    for obj_id, current_processed in list(processed.items()):
      
      # Waittime calculation
      if 'submittime' in current_processed:
        submit_t = self._parse_time(current_processed['submittime'])
        if 'starttime' in current_processed:
          start_t = self._parse_time(current_processed['starttime'])
          current_processed['waittime'] = max(0.0, start_t - submit_t)
        elif 'finishtime' in current_processed:
          # Edge case: Job was canceled or failed before it ever started
          finish_t = self._parse_time(current_processed['finishtime'])
          current_processed['waittime'] = max(0.0, finish_t - submit_t)
        else:
          current_processed['waittime'] = max(0.0, now - submit_t)

      # Runtime calculation
      if 'starttime' in current_processed:
        start_t = self._parse_time(current_processed['starttime'])
        if 'finishtime' in current_processed:
          finish_t = self._parse_time(current_processed['finishtime'])
          current_processed['runtime'] = max(0.0, finish_t - start_t)
        else:
          current_processed['runtime'] = max(0.0, now - start_t)
          
      # Clean up tracking once the job finishes completely
      if 'finishtime' in current_processed and obj_id in self.running_objects:
        log.debug(f"Job '{obj_id}' finished. Removed from tracking.\n")
        del self.running_objects[obj_id]

    # Stale or missed completion jobs are cleaned up
    self._clean_stuck_objects(now, fallback_ttl, log)

    apply_func_name = output_spec.get("apply_function")
    if apply_func_name and apply_func_name in globals():
      func = globals()[apply_func_name]
      # The function is expected to return the modified processed dictionary
      processed = func(processed, output_spec)

    return processed

def get_nested_value(data: Any, path: str) -> Any:
  """
  Values are extracted from nested dictionaries using dot-notation paths.

  Args:
    data (Any): The root dictionary structure.
    path (str): The dot-separated path to the desired value.

  Returns:
    Any: The extracted value, or None if the path is invalid.
  """
  keys = path.split(".")
  current = data
  try:
    for key in keys:
      if isinstance(current, dict):
        current = current.get(key)
      else:
        return None
    return current
  except (AttributeError, KeyError):
    return None

async def subscribe_to_bus(
  target_uuid_str: str,
  targets: List[tuple],
  bus_host: str, 
  bus_port: int,
  log: logging.Logger
) -> None:
  """
  A single multiplexed listener task is maintained for a UUID, distributing events to multiple collectors.

  Args:
    target_uuid_str (str): The UUID string to subscribe to.
    targets (List[tuple]): A list of tuples containing (EventCollector, subscription_config).
    bus_host (str): The host address of the SeanerBUS server.
    bus_port (int): The port number of the SeanerBUS server.
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  target_uuid = uuid.UUID(target_uuid_str)
  
  # The interpreter is assumed to be identical for the same UUID across different outputs
  interpreter_name = targets[0][1].get("interpreter", "TimeValueV1")

  # Reconnections are attempted continuously if the bus connection drops
  while True:
    try:
      connection = await seanerbus.client.Connection.connect(bus_host, bus_port)
      await connection.subscribe(target_uuid)
      log.info(f"Subscribed to {target_uuid} interpreting as {interpreter_name}\n")

      while True:
        raw_msg = await connection.read_msg()
        
        # The originating UUID is extracted from the message address
        msg_uuid = str(uuid.UUID(int=(raw_msg.address.upper << 64) + raw_msg.address.lower))
        
        # Message payloads are unpacked based on the configured interpreter
        if interpreter_name == "FluxLifecycleEventV1":
          ev = FluxLifecycleEventV1.from_capnp(raw_msg)
          payload = json.loads("".join(ev.data))
          
          # Specific payload adjustments are applied before metric extraction
          if 'finish_info' in payload and 'rc_state' in payload['finish_info']:
            payload['state'] = payload['finish_info']['rc_state']
            del payload['finish_info']['rc_state']
            
        elif interpreter_name == "TimeValueV1":
          tv = TimeValueV1.from_capnp(raw_msg)
          # The UUID is injected into the payload so it can be targeted by index_key or metrics
          payload = {"time": tv.time, "value": tv.value, "uuid": msg_uuid}
        else:
          continue

        # A timestamp is injected into every payload
        if 'ts' not in payload:
          payload['ts'] = time.time()

        # The decoded payload is distributed to all interested collectors
        for collector, sub_cfg in targets:
          index_key_path = sub_cfg.get("index_key", "id")

          # Metrics are extracted first so statically defined values can be used as the index key
          extracted_metrics = {}
          for metric_name, metric_cfg in sub_cfg.get("metrics", {}).items():
            # A static value is assigned directly if configured, otherwise the path is extracted
            if "static" in metric_cfg:
              val = metric_cfg["static"]
            else:
              val = get_nested_value(payload, metric_cfg.get("path", ""))
              
            # A default fallback is applied if the extracted value is missing or strictly empty
            if (val is None or val == "") and "default" in metric_cfg:
              val = metric_cfg["default"]
              
            # A mathematical factor is applied if configured
            if val is not None and "factor" in metric_cfg:
              try:
                val = float(val) * float(metric_cfg["factor"])
              except (ValueError, TypeError):
                pass
                
            # Values are substituted according to a predefined mapping dictionary
            if val is not None and "map" in metric_cfg:
              val_map = metric_cfg["map"]
              if isinstance(val_map, dict):
                if val in val_map:
                  val = val_map[val]
                elif str(val) in val_map:
                  val = val_map[str(val)]
                  
            # Modification functions are applied dynamically if specified
            if val is not None and "modify" in metric_cfg:
              func_name = metric_cfg["modify"]
              if func_name in globals():
                val = globals()[func_name](val)
                
            extracted_metrics[metric_name] = val
          
          # The object ID is determined from the extracted metrics first, falling back to the raw payload
          obj_id_val = extracted_metrics.get(index_key_path)
          if obj_id_val is None:
            obj_id_val = get_nested_value(payload, index_key_path)
            
          obj_id = str(obj_id_val or "unknown")
          
          log.debug(f"Parsed event for '{obj_id}' into collector '{collector.stype}': {extracted_metrics}\n")
          collector.add_metrics(obj_id, extracted_metrics)
        
    except Exception as e:
      log.warning(f"Connection lost or error for {target_uuid}: {e}. Reconnecting in 5 seconds...\n")
      await asyncio.sleep(5)

def write_lml(
  filename: str, 
  data_dict: Dict[str, Dict[str, Any]], 
  timing_info: Dict[str, Any],
  log: logging.Logger
) -> None:
  """
  Data is exported safely to an LML XML file structure using a temporary file to prevent corruption.

  Args:
    filename (str): The final destination path for the LML file.
    data_dict (Dict[str, Dict[str, Any]]): The aggregated metrics mapped by object IDs.
    timing_info (Dict[str, Any]): The metadata containing process duration and element counts.
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  log.info(f"Writing LML data to {filename}...\n")
  os.makedirs(os.path.dirname(filename), exist_ok=True)
  temp_filename = f"{filename}.tmp"
  
  try:
    with open(temp_filename, "w") as f:
      f.write('<?xml version="1.0" encoding="UTF-8"?>\n')
      f.write('<lml:lgui xmlns:lml="http://eclipse.org/ptp/lml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n')
      f.write('    xsi:schemaLocation="http://eclipse.org/ptp/lml http://eclipse.org/ptp/schemas/v1.1/lgui.xsd"\n')
      f.write('    version="1.1">\n')
      
      f.write("<objects>\n")
      idx = 0
      for name, item in data_dict.items():
        if "__id" not in item:
          item["__id"] = f"{item.get('__prefix', 'i')}{idx}"
          idx += 1
        f.write(f'  <object id="{item["__id"]}" name="{name}" type="{item.get("__type", "item")}"/>\n')
      f.write(f'  <object id="{timing_info["__id"]}" name="pstat" type="pstat"/>\n')
      f.write("</objects>\n")
      
      f.write("<information>\n")
      for name, item in data_dict.items():
        f.write(f'  <info oid="{item["__id"]}" type="short">\n')
        for k, v in item.items():
          if not k.startswith("__"):
            val_str = str(v).replace('"', "'")
            f.write(f'    <data key="{k}" value="{val_str}"/>\n')
        f.write("  </info>\n")
      
      # The timing info object is attached as a special internal record
      f.write(f'  <info oid="{timing_info["__id"]}" type="short">\n')
      for k, v in timing_info.items():
        if k != "__id":
          f.write(f'    <data key="{k}" value="{v}"/>\n')
      f.write("  </info>\n")
      f.write("</information>\n")
      f.write("</lml:lgui>\n")
      
    log.debug(f"Temporary file '{temp_filename}' written successfully. Swapping files.\n")
    # Atomic replace prevents corrupted files from being parsed by other processes
    os.replace(temp_filename, filename)
    
  except Exception as e:
    log.error(f"Error writing LML {filename}: {e}\n")

def load_checkpoint(filepath: str, collectors: Dict[str, EventCollector], log: logging.Logger) -> None:
  """
  Tracked state is restored from a JSON checkpoint file on disk.

  Args:
    filepath (str): The path to the checkpoint file.
    collectors (Dict[str, EventCollector]): The instantiated collectors to be populated.
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  if not filepath or not os.path.exists(filepath):
    log.info("No checkpoint file found. Starting fresh.\n")
    return
    
  try:
    with open(filepath, "r") as f:
      state = json.load(f)
      
    log.info(f"Checkpoint loaded. Last successful operation timestamp: {state.get('last_timestamp', 'Unknown')}\n")
    
    col_state = state.get("collectors", {})
    for key, collector in collectors.items():
      if key in col_state:
        collector.running_objects = col_state[key].get("running_objects", {})
        
  except Exception as e:
    log.error(f"Failed to load checkpoint file '{filepath}': {e}\n")

def save_checkpoint(
  filepath: str, 
  collectors: Dict[str, EventCollector], 
  outputs_cfg: Dict[str, Any], 
  log: logging.Logger
) -> None:
  """
  The memory state of specified collectors is serialized to a JSON file.

  Args:
    filepath (str): The path to the checkpoint file.
    collectors (Dict[str, EventCollector]): The collectors holding the current state.
    outputs_cfg (Dict[str, Any]): The output specification rules to check for the checkpoint flag.
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  if not filepath:
    return
    
  state = {
    "last_timestamp": time.time(),
    "collectors": {}
  }
  
  for key, collector in collectors.items():
    spec = outputs_cfg.get(key, {})
    # The collector state is only serialized if explicitly requested in the configuration
    if spec.get("checkpoint", False):
      state["collectors"][key] = {
        "running_objects": collector.running_objects
      }
    
  try:
    os.makedirs(os.path.dirname(filepath), exist_ok=True)
    temp_filepath = f"{filepath}.tmp"
    with open(temp_filepath, "w") as f:
      json.dump(state, f, indent=2)
    os.replace(temp_filepath, filepath)
  except Exception as e:
    log.error(f"Failed to save checkpoint file '{filepath}': {e}\n")


async def periodic_writer(
  collectors: Dict[str, EventCollector], 
  outputs_cfg: Dict[str, Any], 
  general_cfg: Dict[str, Any],
  log: logging.Logger
) -> None:
  """
  Outputs are generated at a regular interval and the trigger file is updated safely.

  Args:
    collectors (Dict[str, EventCollector]): A mapping of output keys to their respective collector instances.
    outputs_cfg (Dict[str, Any]): The output specification rules from the configuration file.
    general_cfg (Dict[str, Any]): General plugin configuration (intervals, triggers, etc.).
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  interval = general_cfg.get("interval", 60)
  fallback_ttl = float(general_cfg.get("fallback_ttl", 86400)) # Default 24 hours
  checkpoint_file = general_cfg.get("checkpoint_file")
  
  while True:
    await asyncio.sleep(interval)
    
    for key, spec in outputs_cfg.items():
      collector = collectors[key]
      
      # Raw data is flushed atomically to prevent losing events arriving during processing
      raw_data = collector.flush_data()
      log.debug(f"Processing '{key}': Flushed {len(raw_data)} raw events from collector.\n")
      
      processed_data = collector.process_raw_data(raw_data, spec, fallback_ttl)
      
      num_elems = len(processed_data)
      log.debug(f"Preparing to write {num_elems} elements to LML for '{key}'.\n")
      now = time.time()
      
      timing = {
        "startts": collector.start_time,
        "datats": collector.start_time,
        "endts": now,
        "duration": round(now - collector.start_time, 3),
        "nelems": num_elems,
        f"__nelems_{spec.get('type', 'item')}": num_elems,
        "__type": "pstat",
        "__id": f"pstat_get{key}"
      }
      
      write_lml(os.path.expandvars(spec["LML"]), processed_data, timing, log)
      collector.start_time = now

    # State is serialized after all outputs are successfully written
    if checkpoint_file:
      save_checkpoint(os.path.expandvars(checkpoint_file), collectors, outputs_cfg, log)

    # The trigger file is touched to notify downstream processes that new LML files are ready
    if "trigger" in general_cfg:
      trigger_path = os.path.expandvars(general_cfg["trigger"])
      trigger_dir = os.path.dirname(trigger_path)
      if trigger_dir:
        os.makedirs(trigger_dir, exist_ok=True)
      Path(trigger_path).touch()
      log.info(f"Trigger file {trigger_path} touched.\n")

async def config_watcher(
  config_path: str,
  general_cfg: Dict[str, Any],
  outputs_cfg: Dict[str, Any],
  collectors: Dict[str, EventCollector],
  subscription_registry: Dict[str, List[tuple]],
  active_tasks: Dict[str, asyncio.Task],
  bus_host: str,
  bus_port: int,
  log: logging.Logger
) -> None:
  """
  The configuration file is monitored for modifications, and updates are applied dynamically without stopping the daemon.

  Args:
    config_path (str): The path to the YAML configuration file.
    general_cfg (Dict[str, Any]): The current general configuration dictionary.
    outputs_cfg (Dict[str, Any]): The current outputs configuration dictionary.
    collectors (Dict[str, EventCollector]): The dictionary of active event collectors.
    subscription_registry (Dict[str, List[tuple]]): The registry mapping UUIDs to target collectors.
    active_tasks (Dict[str, asyncio.Task]): The dictionary of currently running bus listener tasks.
    bus_host (str): The host address of the SeanerBUS server.
    bus_port (int): The port number of the SeanerBUS server.
    log (logging.Logger): The logger instance.

  Returns:
    None
  """
  try:
    last_mtime = os.path.getmtime(config_path)
  except OSError:
    last_mtime = 0

  while True:
    await asyncio.sleep(5)
    try:
      try:
        current_mtime = os.path.getmtime(config_path)
      except OSError:
        continue

      if current_mtime <= last_mtime:
        continue
        
      log.info("Configuration file modification detected. Reloading...\n")
      last_mtime = current_mtime
      
      # The file is safely read. If the YAML is invalid, an exception is caught and the script safely skips this cycle
      with open(config_path, "r") as f:
        new_config = yaml.safe_load(f)
        
      if not new_config:
        continue
        
      new_general_cfg = new_config.get("config", {})
      new_outputs_cfg = new_config.get("outputs", {})
      
      # Configuration dictionaries are updated in-place so other running tasks see the new values instantly
      general_cfg.clear()
      general_cfg.update(new_general_cfg)
      
      outputs_cfg.clear()
      outputs_cfg.update(new_outputs_cfg)
      
      # Missing collectors are created if new outputs were defined
      for key, spec in outputs_cfg.items():
        if key not in collectors:
          collectors[key] = EventCollector(spec.get("prefix", "i"), spec.get("type", "item"))
          
      # A new registry blueprint is built from the updated outputs configuration
      new_registry: Dict[str, List[tuple]] = {}
      for key, spec in outputs_cfg.items():
        collector = collectors[key]
        for sub in spec.get("subscriptions", []):
          uuid_str = sub.get("uuid")
          if uuid_str:
            if uuid_str not in new_registry:
              new_registry[uuid_str] = []
            new_registry[uuid_str].append((collector, sub))
            
      # Existing target lists are updated and entirely new UUID subscriptions are spawned
      for uuid_str, targets in new_registry.items():
        if uuid_str in subscription_registry:
          # The list is modified in-place. The running 'subscribe_to_bus' loop will seamlessly use these new rules on the next message
          subscription_registry[uuid_str].clear()
          subscription_registry[uuid_str].extend(targets)
        else:
          log.info(f"Dynamically starting new listener for UUID {uuid_str}\n")
          subscription_registry[uuid_str] = targets
          active_tasks[uuid_str] = asyncio.create_task(
            subscribe_to_bus(uuid_str, subscription_registry[uuid_str], bus_host, bus_port, log)
          )
          
      # Obsolete tasks are elegantly cancelled if their UUIDs were removed from the configuration
      for uuid_str in list(subscription_registry.keys()):
        if uuid_str not in new_registry:
          log.info(f"Cancelling obsolete listener for UUID {uuid_str}\n")
          if uuid_str in active_tasks:
            active_tasks[uuid_str].cancel()
            del active_tasks[uuid_str]
          del subscription_registry[uuid_str]
          
      log.info("Configuration successfully reloaded and tasks updated.\n")
      
    except Exception as e:
      log.error(f"Error while attempting to reload configuration: {e}\n")


async def main() -> None:
  """
  Execution parameters are parsed and asynchronous collection tasks are initiated.

  Returns:
    None
  """
  parser = argparse.ArgumentParser(description="SeanerBUS Event-Based LML Plugin")
  parser.add_argument("--config", required=True, help="YAML configuration file path")
  parser.add_argument("--loglevel", default="INFO", help="Logging level (DEBUG, INFO, WARNING, ERROR)")
  args = parser.parse_args()

  log_init(args.loglevel)
  log = logging.getLogger('logger')

  with open(args.config, "r") as f:
    config = yaml.safe_load(f)

  general_cfg = config.get("config", {})
  outputs_cfg = config.get("outputs", {})
  bus_host = general_cfg.get("bus_host", "localhost")
  bus_port = general_cfg.get("bus_port", 5398)

  # A configuration validation is performed to ensure requested checkpoints have a designated file
  checkpoint_file = general_cfg.get("checkpoint_file")
  if not checkpoint_file:
    for spec in outputs_cfg.values():
      if spec.get("checkpoint", False):
        log.error("A checkpoint file is not configured, but 'checkpoint: true' is requested by an output. State will not be saved!\n")
        break

  collectors: Dict[str, EventCollector] = {}
  subscription_registry: Dict[str, List[tuple]] = {}
  active_tasks: Dict[str, asyncio.Task] = {}
  
  for key, spec in outputs_cfg.items():
    collector = EventCollector(spec.get("prefix", "i"), spec.get("type", "item"))
    collectors[key] = collector
    
    # Subscriptions are grouped by UUID into the registry to enable multiplexing
    for sub in spec.get("subscriptions", []):
      uuid_str = sub.get("uuid")
      if uuid_str:
        if uuid_str not in subscription_registry:
          subscription_registry[uuid_str] = []
        subscription_registry[uuid_str].append((collector, sub))
        
  # Exactly one network task is spawned per unique UUID and safely tracked
  for uuid_str, targets in subscription_registry.items():
    active_tasks[uuid_str] = asyncio.create_task(
      subscribe_to_bus(uuid_str, targets, bus_host, bus_port, log)
    )
      
  # Existing state is loaded into the collectors before processing begins
  if checkpoint_file:
    load_checkpoint(os.path.expandvars(checkpoint_file), collectors, log)
      
  # The core daemon operations are scheduled to run indefinitely
  daemon_tasks = []
  
  daemon_tasks.append(asyncio.create_task(
    periodic_writer(collectors, outputs_cfg, general_cfg, log)
  ))
  
  daemon_tasks.append(asyncio.create_task(
    config_watcher(
      args.config, general_cfg, outputs_cfg, collectors, 
      subscription_registry, active_tasks, bus_host, bus_port, log
    )
  ))
  
  await asyncio.gather(*daemon_tasks)

if __name__ == "__main__":
  try:
    asyncio.run(capnp.run(main()))
  except KeyboardInterrupt:
    pass