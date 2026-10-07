#!/usr/bin/env python3
"""
monitor_node.py — Login-node process monitor.

Output is formatted as machine-readable LML XML, intended as input for a downstream
system (LLview) that parses it, stores it in its own database, and renders the
web portal. Every value is therefore stored as a discrete, typed key —
never as a raw text blob that bundles multiple metrics together.

Intended to be deployed as a cron job on each login node independently.
The hostname is resolved at runtime via socket.gethostname(), so no
iteration over nodes is required or present.

Output is written to:
  <outfolder>/<prefix><hostname>.xml

Crontab entry (every minute; %% escapes the percent sign for cron):
  * * * * * /usr/bin/python3 /opt/monitor/monitor_node.py \
            --config /opt/monitor/monitor_config.yaml \
            --outfolder /opt/monitor/output \
            --prefix login_ \
            >> /opt/monitor/logs/monitor.$(date +%%Y.%%m.%%d).log \
            2>> /opt/monitor/logs/monitor.$(date +%%Y.%%m.%%d).errlog

Dependencies:
  Python >= 3.6
  PyYAML      pip install pyyaml --user
"""

import argparse
import json
import logging
import math
import os
import shlex
import socket
import subprocess
import sys
import time
import re
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple, Union

try:
  import yaml
except ImportError:
  sys.exit("PyYAML is required: pip install pyyaml --user")


# ── Logging ───────────────────────────────────────────────────────────────────

class CustomFormatter(logging.Formatter):
  """
  Log formatter with ANSI colour coding per log level.
  Adapted from https://stackoverflow.com/a/56944256/3142385
  """
  def __init__(self, fmt: str, datefmt: str = "") -> None:
    super().__init__()
    self.fmt     = fmt
    self.datefmt = datefmt
    grey       = "\x1b[38;20m"
    yellow     = "\x1b[93;20m"
    cyan       = "\x1b[96;20m"
    red        = "\x1b[91;20m"
    bold_red   = "\x1b[91;1m"
    reset      = "\x1b[0m"
    self.FORMATS = {
      logging.DEBUG:    cyan     + self.fmt + reset,
      logging.INFO:     grey     + self.fmt + reset,
      logging.WARNING:  yellow   + self.fmt + reset,
      logging.ERROR:    red      + self.fmt + reset,
      logging.CRITICAL: bold_red + self.fmt + reset,
    }

  def format(self, record: logging.LogRecord) -> str:
    """The colour format matching the record's log level is applied."""
    formatter = logging.Formatter(
      fmt=self.FORMATS.get(record.levelno), datefmt=self.datefmt
    )
    return formatter.format(record)


class _ExcludeErrorsFilter(logging.Filter):
  def filter(self, record: logging.LogRecord) -> bool:
    """Only log records below ERROR level are passed (for the stdout handler)."""
    return record.levelno < logging.ERROR


log_config: Dict[str, str] = {
  "format":  "%(asctime)s %(funcName)-18s(%(lineno)-3d): [%(levelname)-8s] %(message)s",
  "datefmt": "%Y-%m-%d %H:%M:%S",
  "level":   "INFO",
}


def log_init(level: Optional[str] = None) -> None:
  """
  The shared logger is initialised with stdout and stderr handlers.

  Records below ERROR are routed to stdout; ERROR and above to stderr.
  This allows log forwarding with >> for info and 2>> for errors.

  Args:
    level: Log level string (DEBUG, INFO, WARNING, ERROR).
           When None, the default from log_config is utilized.
  """
  log = logging.getLogger("logger")
  log.setLevel(level or log_config["level"])

  fmt = log_config["format"]
  dfmt = log_config["datefmt"]

  oh = logging.StreamHandler(sys.stdout)
  oh.setLevel(level or log_config["level"])
  oh.setFormatter(CustomFormatter(fmt, datefmt=dfmt))
  oh.addFilter(_ExcludeErrorsFilter())
  oh.terminator = ""
  log.addHandler(oh)

  eh = logging.StreamHandler(sys.stderr)
  eh.setLevel("ERROR")
  eh.setFormatter(CustomFormatter(fmt, datefmt=dfmt))
  eh.terminator = ""
  log.addHandler(eh)


def log_continue(log: logging.Logger, message: str) -> None:
  """
  The formatter is temporarily modified to write a continuation message on the logger,
  and then reverted to its original format.
  """
  for handler in log.handlers:
    handler.setFormatter(CustomFormatter("%(message)s (%(lineno)-3d)[%(asctime)s]\n", datefmt=log_config['datefmt']))

  log.info(message)

  for handler in log.handlers:
    handler.setFormatter(CustomFormatter(log_config['format'], datefmt=log_config['datefmt']))


# ── Helpers ───────────────────────────────────────────────────────────────────

def utc_now_str() -> str:
  """The current UTC time is returned formatted as an ISO-8601 string."""
  return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def run(cmd: Union[str, List[str]], timeout: int = 20) -> Tuple[str, str, int]:
  """
  A shell command is executed and its output is returned.

  Commands are passed directly to the bash shell natively, enabling the direct 
  use of pipelines (|) and command substitutions ($()) without complex escaping.

  Args:
    cmd:     A command string or list of arguments.
    timeout: Maximum seconds allowed before the process is killed.

  Returns:
    A tuple containing stdout, stderr, and the returncode.
  """
  log = logging.getLogger("logger")
  cmd_str = cmd if isinstance(cmd, str) else " ".join(cmd)
  log.debug(f"Running: {cmd_str}\n")
  try:
    result = subprocess.run(
      cmd_str,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      universal_newlines=True,
      timeout=timeout,
      shell=True,
      executable='/bin/bash'
    )
    log.debug(f"Exit code {result.returncode} for: {cmd_str}\n")
    return result.stdout, result.stderr, result.returncode
  except subprocess.TimeoutExpired:
    return "", "timed out after {}s".format(timeout), -1
  except Exception as exc:
    return "", str(exc), -1


def read_proc_file(path: str) -> str:
  """
  A /proc virtual file is read and its contents are returned as text.

  An empty string is returned, rather than an exception raised, when the file cannot
  be read, as some /proc entries require elevated privileges.

  Args:
    path: Absolute path under /proc.

  Returns:
    The file contents, or an empty string on failure.
  """
  log = logging.getLogger("logger")
  try:
    return Path(path).read_text()
  except OSError as exc:
    log.debug(f"Could not read {path}: {exc}\n")
    return ""


# ── Process collection ────────────────────────────────────────────────────────

_FLOAT_FIELDS: frozenset = frozenset({"cpu_pct", "mem_pct"})
_INT_FIELDS:   frozenset = frozenset({"pid", "ppid", "threads", "priority", "nice", "cpu_time_secs"})
_KB_TO_MB:     frozenset = frozenset({"mem_rss_mb", "mem_vsz_mb"})


def collect_processes(cfg: Dict[str, Any], hostname: str) -> List[Dict[str, Any]]:
  """
  A snapshot of running processes is collected via ps(1).

  Every row carries a fixed set of typed fields, ensuring downstream consumers 
  can independently identify heavy processes. Elapsed wall-clock time is 
  mathematically converted into pure seconds. Furthermore, an explicit count 
  of threads stuck in the Uninterruptible Sleep (D) state is injected into 
  each process entity to monitor severe I/O bottlenecks.
  """
  log = logging.getLogger("logger")

  field_map: Dict[str, str] = cfg.get("field_map") or {}
  if not field_map:
    log.error("processes.field_map is empty or missing — no fields to collect.\n")
    return []

  sort_by:       str           = cfg.get("sort_by", "cpu_pct")
  top_n:         Optional[int] = cfg.get("top_n") or None
  min_cpu:       float         = float(cfg.get("min_cpu_pct") or 0.0)
  min_mem:       float         = float(cfg.get("min_mem_pct") or 0.0)
  
  # Generic inclusion and exclusion dictionaries are extracted
  exclude_rules: Dict[str, Union[str, List[str]]] = cfg.get("exclude", {})
  include_rules: Dict[str, Union[str, List[str]]] = cfg.get("include", {})

  output_names: List[str] = list(field_map.keys())
  ps_keywords:  List[str] = list(field_map.values())

  args_index: Optional[int] = None
  for i, kw in enumerate(ps_keywords):
    if kw.split(":")[0] == "args":
      args_index = i
      break

  if args_index is not None and args_index != len(ps_keywords) - 1:
    output_names.append(output_names.pop(args_index))
    ps_keywords.append(ps_keywords.pop(args_index))

  has_args = args_index is not None
  n_fixed  = len(output_names) - (1 if has_args else 0)
  ps_fmt   = ",".join(ps_keywords)
  sort_kw  = field_map.get(sort_by, sort_by).split(":")[0]

  log.info(f"Collecting processes (sort_by={sort_by}, top_n={top_n})...\n")
  stdout, stderr, rc = run(
    "ps -eo {} --sort=-{} --no-headers --cols 512".format(ps_fmt, sort_kw)
  )
  if rc not in (0, 1):
    log.error(f"ps exited with code {rc}: {stderr.strip()}\n")
    return []

  # An ultra-fast, pre-calculated map of D-state threads grouped by parent PID is generated
  d_state_stdout, _, _ = run("ps -eTo ppid,stat --no-headers")
  d_state_map: Dict[int, int] = defaultdict(int)
  for line in d_state_stdout.splitlines():
    parts = line.split()
    if len(parts) >= 2 and parts[1].startswith('D'):
      try: d_state_map[int(parts[0])] += 1
      except ValueError: pass

  processes: List[Dict[str, Any]] = []

  for line in stdout.splitlines():
    line = line.strip()
    if not line:
      continue

    parts = line.split(None, n_fixed) if has_args else line.split()
    if len(parts) < len(output_names):
      log.debug(f"Skipping malformed ps line: {line!r}\n")
      continue

    proc: Dict[str, Any] = {"hostname": hostname}

    for i, out_name in enumerate(output_names):
      raw = parts[i]
      if out_name == "elapsed":
        # Elapsed string formats ([DD-]HH:MM:SS) are converted into raw seconds securely
        try:
          days = 0
          if "-" in raw:
            d_str, time_str = raw.split("-")
            days = int(d_str)
          else:
            time_str = raw
            
          time_parts = [int(p) for p in time_str.split(":")]
          if len(time_parts) == 3:  # HH:MM:SS
            secs = days * 86400 + time_parts[0] * 3600 + time_parts[1] * 60 + time_parts[2]
          elif len(time_parts) == 2:  # MM:SS
            secs = days * 86400 + time_parts[0] * 60 + time_parts[1]
          else:
            secs = None
          val = secs
        except ValueError:
          val = None
      elif out_name in _FLOAT_FIELDS:
        try:    val: Any = float(raw)
        except: val = None
      elif out_name in _INT_FIELDS:
        try:    val = int(raw)
        except: val = None
      elif out_name in _KB_TO_MB:
        try:    val = round(int(raw) / 1024.0, 1)
        except: val = None
      else:
        val = raw
      proc[out_name] = val

    if min_cpu and (proc.get("cpu_pct") or 0.0) < min_cpu:
      continue
    if min_mem and (proc.get("mem_pct") or 0.0) < min_mem:
      continue

    # A helper function evaluates the process dictionary against a set of regex rules
    def matches_rules(rules: Dict[str, Union[str, List[str]]]) -> bool:
      for k, patterns in rules.items():
        if k in proc:
          val_str = str(proc[k])
          pat_list = [patterns] if isinstance(patterns, str) else patterns
          for pat in pat_list:
            try:
              if re.search(str(pat), val_str):
                return True
            except re.error:
              pass
      return False

    # Rows matching exclusion rules or failing inclusion rules are actively bypassed
    if exclude_rules and matches_rules(exclude_rules):
      continue
    if include_rules and not matches_rules(include_rules):
      continue

    # The accumulated count of D-state threads is injected securely
    pid = proc.get("pid")
    proc["d_state_threads"] = d_state_map.get(pid, 0) if pid else 0

    processes.append(proc)

  if top_n:
    processes = processes[:top_n]

  log.info(f"Collected {len(processes)} process rows.\n")
  return processes


# ── /tmp collector ────────────────────────────────────────────────────────────

def collect_tmp(cfg: Dict[str, Any], hostname: str) -> Dict[str, Any]:
  """
  Disk usage statistics for one or more temporary directories are collected.
  Overall filesystem capacity is evaluated via df(1), while per-user storage 
  consumption is estimated via a bounded find(1) directory traversal.

  Args:
    cfg:      The 'tmp' section of the loaded YAML configuration.
    hostname: The hostname of the current node, embedded in the result.

  Returns:
    A dict containing parsed filesystem metrics and per-user storage distributions.
  """
  log = logging.getLogger("logger")
  depth: int = int(cfg.get("per_user_find_depth", 4))
  
  # Target paths are extracted from the configuration, maintaining backward compatibility
  raw_targets = cfg.get("targets")
  if raw_targets and isinstance(raw_targets, list):
    targets = raw_targets
  else:
    targets = [{"path": cfg.get("path", "/tmp"), "prefix": "tmp"}]

  result: Dict[str, Any] = {"hostname": hostname, "filesystems": {}}

  for target in targets:
    path: str = target.get("path", "/tmp")
    prefix: str = target.get("prefix", "tmp")
    
    fs_data: Dict[str, Any] = {"path": path}
    log.info(f"Collecting temporary filesystem usage for {path} (prefix: {prefix})...\n")

    stdout, _, rc = run("df -B1 --output=size,used,avail,pcent {}".format(path))
    if rc == 0:
      lines = stdout.strip().splitlines()
      if len(lines) >= 2:
        parts = lines[1].split()
        if len(parts) >= 4:
          def to_mb(raw: str) -> Optional[float]:
            """A byte count string is converted to megabytes."""
            try:    return round(int(raw) / 1_048_576, 1)
            except: return None
          fs_data["total_mb"] = to_mb(parts[0])
          fs_data["used_mb"]  = to_mb(parts[1])
          fs_data["avail_mb"] = to_mb(parts[2])
          fs_data["used_pct"] = parts[3]
          log.debug(
            f"{path}: total={fs_data['total_mb']} MB used={fs_data['used_mb']} MB "
            f"({fs_data['used_pct']})\n"
          )
    else:
      log.error(f"df failed for {path}\n")

    log.info(f"Running find for per-user breakdown on {path} (maxdepth={depth})...\n")
    per_user_bytes: Dict[str, int] = defaultdict(int)
    stdout, _, _ = run(
      "find {} -maxdepth {} -printf '%u %s\n'".format(path, depth),
      timeout=30,
    )
    for line in stdout.splitlines():
      parts = line.split(None, 1)
      if len(parts) == 2:
        try:
          per_user_bytes[parts[0]] += int(parts[1])
        except ValueError:
          pass

    if per_user_bytes:
      fs_data["per_user_mb"] = {
        user: round(size / 1_048_576, 1)
        for user, size in sorted(
          per_user_bytes.items(), key=lambda kv: kv[1], reverse=True
        )
      }
      log.debug(f"Per-user entries found on {path}: {list(fs_data['per_user_mb'].keys())}\n")

    result["filesystems"][prefix] = fs_data

  return result


# ── Load average collector ────────────────────────────────────────────────────

def collect_load(hostname: str) -> Dict[str, Any]:
  """
  System load averages are collected from /proc/loadavg.

  Each value is stored as its own numeric field, rather than as a raw
  space-separated line, ensuring a downstream parser can consume each metric
  independently.

  Args:
    hostname: The hostname of the current node, embedded in the result.

  Returns:
    A dict with load statistics. Empty aside from 'hostname' if
    /proc/loadavg could not be read.
  """
  log = logging.getLogger("logger")
  log.info("Collecting load average...\n")

  result: Dict[str, Any] = {"hostname": hostname}
  raw = read_proc_file("/proc/loadavg").split()
  if len(raw) < 5:
    log.error("Could not parse /proc/loadavg\n")
    return result

  try:
    running_str, total_str = raw[3].split("/")
    result["load_1m"]        = float(raw[0])
    result["load_5m"]        = float(raw[1])
    result["load_15m"]       = float(raw[2])
    result["running_procs"]  = int(running_str)
    result["total_procs"]    = int(total_str)
    result["last_pid"]       = int(raw[4])
  except (ValueError, IndexError) as exc:
    log.error(f"Could not parse /proc/loadavg fields: {exc}\n")

  return result


# ── Memory collector ──────────────────────────────────────────────────────────

def collect_memory(cfg: Dict[str, Any], hostname: str) -> Dict[str, Any]:
  """
  Memory and swap usage are collected from /proc/meminfo.

  Each requested field is converted from kB to MB and stored under its
  own key. Dynamic subtraction rules can be configured to adjust values 
  using external commands (e.g., deducting GPU unified memory).

  Args:
    cfg:      The 'memory' section of the loaded YAML configuration.
    hostname: The hostname of the current node, embedded in the result.

  Returns:
    A dict mapping "<Field>_mb" to a float for every requested field.
  """
  log = logging.getLogger("logger")
  log.info("Collecting memory usage...\n")

  fields: List[str] = cfg.get("fields") or [
    "MemTotal", "MemFree", "MemAvailable",
    "Buffers", "Cached", "SwapTotal", "SwapFree", "Shmem",
  ]
  field_set = set(fields)
  result: Dict[str, Any] = {"hostname": hostname}

  for line in read_proc_file("/proc/meminfo").splitlines():
    parts = line.split()
    if not parts:
      continue
    key = parts[0].rstrip(":")
    if key in field_set and len(parts) >= 2:
      try:
        result[f"{key}_mb"] = round(int(parts[1]) / 1024.0, 1)
      except ValueError:
        log.debug(f"Could not parse meminfo value for {key}: {line!r}\n")

  # Configured subtraction commands are securely executed and applied dynamically
  subtractions: Dict[str, str] = cfg.get("subtract_from_mb") or {}
  for key, cmd in subtractions.items():
    target_key = f"{key}_mb"
    if target_key in result:
      stdout, stderr, rc = run(cmd, timeout=10)
      if rc == 0 and stdout.strip():
        try:
          val_to_subtract = float(stdout.strip())
          # Subtraction is constrained to prevent negative memory values
          result[target_key] = round(max(0.0, result[target_key] - val_to_subtract), 1)
          log.debug(f"Subtracted {val_to_subtract} MB from {target_key} via external command.\n")
        except ValueError:
          log.error(f"Subtraction command for {key} returned non-numeric output: {stdout.strip()}\n")
      else:
        log.debug(f"Subtraction command for {key} failed or returned empty (RC {rc}). Skipped.\n")

  return result


# ── Logged-in users collector ─────────────────────────────────────────────────

def collect_logged_in_users(hostname: str) -> Dict[str, Any]:
  """
  Active login sessions are collected via who(1).

  Each session is parsed into discrete fields rather than kept as a raw
  text line, bypassing the need for downstream column splitting.

  Args:
    hostname: The hostname of the current node, embedded in the result.

  Returns:
    A dict containing session counts and a list of structured session
    dictionaries.
  """
  log = logging.getLogger("logger")
  log.info("Collecting logged-in users...\n")

  stdout, stderr, rc = run("who -u")
  if rc != 0:
    log.error(f"who -u failed: {stderr.strip()}\n")
    return {"hostname": hostname, "session_count": 0, "unique_users": 0, "sessions": []}

  sessions: List[Dict[str, Any]] = []
  for line in stdout.splitlines():
    parts = line.split()
    if len(parts) < 5:
      continue
    sessions.append({
      "user":       parts[0],
      "tty":        parts[1],
      "login_time": "{} {}".format(parts[2], parts[3]),
      "idle":       parts[4],
      "pid":        int(parts[5]) if len(parts) > 5 and parts[5].isdigit() else None,
      "from":       parts[6].strip("()") if len(parts) > 6 else None,
    })

  return {
    "hostname":      hostname,
    "session_count": len(sessions),
    "unique_users":  len({s["user"] for s in sessions}),
    "sessions":      sessions,
  }


# ── Extra commands ────────────────────────────────────────────────────────────

def collect_extra(commands_cfg: List[Dict[str, Any]]) -> Dict[str, Any]:
  """
  A list of arbitrary shell commands defined in the configuration is executed.

  Output is processed according to the specified parse method. Commands resulting 
  in non-zero exit codes are logged as errors and securely dropped to prevent 
  malformed data from polluting the downstream LML file.

  Args:
    commands_cfg: The 'extra_commands' list from the loaded YAML configuration.

  Returns:
    A dict mapping each command name to its parsed output.
  """
  log = logging.getLogger("logger")
  results: Dict[str, Any] = {}





  for entry in (commands_cfg or []):
    name:    Optional[str] = entry.get("name")
    cmd:     Optional[str] = entry.get("cmd")
    enabled: bool          = entry.get("enabled", True)

    if not name or not cmd or not enabled:
      continue

    # Conditional execution rules are evaluated prior to running the primary command.
    # Single strings and lists default to logical AND. Dictionaries with 'any' or 'all'
    # provide explicit OR / AND evaluation across multiple shell commands.
    condition_cfg = entry.get("condition_cmd") or entry.get("conditions")
    if condition_cfg:
      def evaluate_condition(cond: Union[str, List[str], Dict[str, Any]]) -> bool:
        if isinstance(cond, str):
          _, _, rc = run(cond, timeout=5)
          return rc == 0

        if isinstance(cond, list):
          # Lists default to logical AND (all commands must exit with 0)
          for c in cond:
            _, _, rc = run(str(c), timeout=5)
            if rc != 0:
              return False
          return True

        if isinstance(cond, dict):
          # Logical OR: at least one command must exit with 0
          if "any" in cond or "or" in cond:
            cmds = cond.get("any") or cond.get("or") or []
            cmd_list = cmds if isinstance(cmds, list) else [cmds]
            for c in cmd_list:
              _, _, rc = run(str(c), timeout=5)
              if rc == 0:
                return True
            return False

          # Logical AND: all commands must exit with 0
          if "all" in cond or "and" in cond:
            cmds = cond.get("all") or cond.get("and") or []
            cmd_list = cmds if isinstance(cmds, list) else [cmds]
            for c in cmd_list:
              _, _, rc = run(str(c), timeout=5)
              if rc != 0:
                return False
            return True

        return True

      if not evaluate_condition(condition_cfg):
        log.debug(f"Conditions for extra command '{name}' were not satisfied. Skipping execution.\n")
        continue

    parse:   str = entry.get("parse", "raw")
    timeout: int = int(entry.get("timeout", 15))

    log.debug(f"Running extra command '{name}': {cmd}\n")
    stdout, stderr, rc = run(cmd, timeout=timeout)

    # Failed commands are actively intercepted and discarded
    if rc != 0:
      log.error(f"Extra command '{name}' failed with code {rc}: {stderr.strip()}\n")
      continue

    if parse == "lines":
      results[name] = {"lines": stdout.splitlines()}
    elif parse == "json":
      try:
        results[name] = json.loads(stdout)
      except ValueError:
        log.error(f"JSON parse failed for extra command '{name}'\n")
        continue
    elif parse == "csv":
      csv_fields: List[str] = entry.get("fields") or []
      if not csv_fields:
        log.error(f"Extra command '{name}' uses parse: csv but has no 'fields' list\n")
        continue
      else:
        rows: List[Dict[str, str]] = []
        for line in stdout.splitlines():
          values = [v.strip() for v in line.split(",")]
          if len(values) == len(csv_fields):
            rows.append(dict(zip(csv_fields, values)))
          else:
            log.debug(f"Skipping malformed csv line for '{name}': {line!r}\n")
        results[name] = {"rows": rows}
    else:
      # For raw parsing, the pure string output is returned without extraneous rc or stderr wrappers
      results[name] = stdout.strip()

  return results


# ── Object Storage & LML Generation ───────────────────────────────────────────

class NodeInfo:
  """
  Collected metrics are stored and serialized into LML format.
  Object entities representing node stats, processes, and user sessions are
  flattened into a structured internal dictionary compatible with LLview.
  """
  def __init__(self) -> None:
    self._dict: Dict[str, Dict[str, Any]] = {}
    self.log = logging.getLogger("logger")

  def empty(self) -> bool:
    """
    The internal dictionary is checked for emptiness.
    
    Returns:
      True if the dictionary contains no entries.
    """
    return not bool(self._dict)

  def to_LML(self, filename: str, prefix: str = "", stype: str = "") -> None:
    """
    An LML XML output file is created using the accumulated information.
    
    Args:
      filename: The full destination path for the XML file.
      prefix: A string prefixed to the unique ID of every generated object.
      stype: An optional override for the type attribute of the generated objects.
    """
    self.log.info(f"Writing LML data to {filename}... ")
    os.makedirs(os.path.dirname(filename), exist_ok=True)

    with open(filename, "w") as file:
      file.write('<?xml version="1.0" encoding="UTF-8"?>\n')
      file.write('<lml:lgui xmlns:lml="http://eclipse.org/ptp/lml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"\n')
      file.write('    xsi:schemaLocation="http://eclipse.org/ptp/lml http://eclipse.org/ptp/schemas/v1.1/lgui.xsd"\n')
      file.write('    version="1.1">\n')

      file.write("<objects>\n")
      digits = int(math.log10(len(self._dict))) + 1 if len(self._dict) > 0 else 1
      i = 0
      for key, item in self._dict.items():
        if "__id" not in item:
          item_prefix = prefix if prefix else item.get("__prefix", "")
          item["__id"] = f"{item_prefix}{i:0{digits}d}"
          i += 1
        obj_type = stype if stype else item.get("__type", "item")
        file.write(f'<object id="{item["__id"]}" name="{key}" type="{obj_type}"/>\n')
      file.write("</objects>\n")

      file.write("<information>\n")
      for item in self._dict.values():
        file.write(f'<info oid="{item["__id"]}" type="short">\n')
        for key, value in item.items():
          if key.startswith('__nelems'):
            clean_key = str(key.replace(" ", "_"))
            file.write(f' <data key="{clean_key}" value="{value}"/>\n')
            continue
          if key.startswith('__'):
            continue
          if value is not None and value != "":
            clean_key = str(key.replace(" ", "_"))
            clean_val = str(value).replace('"', "'")
            file.write(f' <data key="{clean_key}" value="{clean_val}"/>\n')
        file.write("</info>\n")
      file.write("</information>\n")
      file.write("</lml:lgui>\n")

    log_continue(self.log, "Finished!")


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
  """
  CLI arguments are parsed, the configuration is loaded, collectors are executed, 
  and the resulting snapshot is flattened and written to disk as an LML XML file.
  """
  parser = argparse.ArgumentParser(
    description="LLview login-node plugin"
  )
  parser.add_argument(
    "--config",
    default="monitor_config.yaml",
    help="Path to YAML configuration file (default: monitor_config.yaml)",
  )
  parser.add_argument(
    "--log-level",
    default=None,
    choices=["DEBUG", "INFO", "WARNING", "ERROR"],
    help="Log verbosity (default: INFO). DEBUG enables per-process detail.",
  )
  parser.add_argument(
    "--outfolder",
    default="",
    help="Directory where the output LML file is stored.",
  )
  parser.add_argument(
    "--prefix",
    default="",
    help="Prefix applied to the output filename and internal LML object IDs.",
  )
  args = parser.parse_args()

  log_init(args.log_level)
  log = logging.getLogger("logger")

  if not os.path.isfile(args.config):
    log.error(f"Configuration file not found: {args.config}\n")
    sys.exit(1)

  log.info(f"Reading configuration from {args.config}...\n")
  with open(args.config) as fh:
    cfg: Dict[str, Any] = yaml.safe_load(fh)

  # Getting short hostname (without system suffix)
  raw_hostname = socket.gethostname()
  hostname: str = raw_hostname.split('.')[0]
  log.info(f"Running on host: {hostname}\n")

  out_cfg: Dict[str, Any] = cfg.get("output", {})
  outfolder: str = args.outfolder or out_cfg.get("dir", "~/node_monitor_logs")
  
  log_dir: Path = Path(os.path.expandvars(outfolder)).expanduser()
  log_dir.mkdir(parents=True, exist_ok=True)
  log.debug(f"Output directory: {log_dir}\n")

  # Data collection is executed across all enabled modules
  snapshot: Dict[str, Any] = {
    "hostname":  hostname,
  }

  proc_cfg: Dict[str, Any] = cfg.get("processes", {})
  if proc_cfg.get("enabled", True):
    snapshot["processes"] = collect_processes(proc_cfg, hostname)

  tmp_cfg: Dict[str, Any] = cfg.get("tmp", {})
  if tmp_cfg.get("enabled", True):
    snapshot["tmp"] = collect_tmp(tmp_cfg, hostname)

  load_cfg: Dict[str, Any] = cfg.get("load", {})
  if load_cfg.get("enabled", True):
    snapshot["load"] = collect_load(hostname)

  memory_cfg: Dict[str, Any] = cfg.get("memory", {})
  if memory_cfg.get("enabled", True):
    snapshot["memory"] = collect_memory(memory_cfg, hostname)

  who_cfg: Dict[str, Any] = cfg.get("logged_in_users", {})
  if who_cfg.get("enabled", True):
    snapshot["logged_in_users"] = collect_logged_in_users(hostname)

  extra = collect_extra(cfg.get("extra_commands"))
  if extra:
    snapshot["extra"] = extra

  # The nested snapshot dictionary is flattened and ingested into the NodeInfo container
  node_info = NodeInfo()
  
  # A uniform Unix timestamp is generated to ensure all derived objects share exactly the same temporal baseline
  unix_ts = int(time.time())
  
  node_obj_name = hostname
  node_obj_id = f"{args.prefix}{hostname}"
  
  # The total number of logical CPUs (including SMT) is extracted securely from the OS
  total_cores = os.cpu_count()
  
  node_info._dict[node_obj_name] = {
    "__type": "node_stat",
    "__id": node_obj_id,
    "hostname": hostname,
    "ts": unix_ts,
    "total_cores": total_cores if total_cores is not None else 0
  }

  # Node-level metrics are appended to the core node object
  if "load" in snapshot:
    for k, v in snapshot["load"].items():
      if k != "hostname":
        node_info._dict[node_obj_name][f"load_{k}"] = v
        
  if "memory" in snapshot:
    for k, v in snapshot["memory"].items():
      if k != "hostname":
        node_info._dict[node_obj_name][f"mem_{k}"] = v
        
  # Temporary filesystem metrics are appended directly to the node object using their respective prefixes
  if "tmp" in snapshot and "filesystems" in snapshot["tmp"]:
    for fs_prefix, fs_data in snapshot["tmp"]["filesystems"].items():
      for k in ["total_mb", "used_mb", "avail_mb", "used_pct"]:
        if k in fs_data and fs_data[k] is not None:
          node_info._dict[node_obj_name][f"{fs_prefix}_{k}"] = fs_data[k]

  # Individual processes are registered as distinct objects, inheriting the node's spatial and temporal context
  if "processes" in snapshot:
    for proc in snapshot["processes"]:
      pid = proc.get("pid", "unknown")
      proc_obj_name = f"{hostname}_proc_{pid}"
      proc_obj_id = f"{args.prefix}{proc_obj_name}"
      proc_dict = {"__type": "process", "__id": proc_obj_id, "hostname": hostname, "ts": unix_ts}
      
      for k, v in proc.items():
        if k != "hostname":
          proc_dict[k] = v
      node_info._dict[proc_obj_name] = proc_dict

  # Localized storage boundaries across all configured temporary filesystems are registered as distinct entities
  if "tmp" in snapshot and "filesystems" in snapshot["tmp"]:
    for fs_prefix, fs_data in snapshot["tmp"]["filesystems"].items():
      target_path = fs_data.get("path", "")
      for u, mb in fs_data.get("per_user_mb", {}).items():
        u_obj_name = f"{hostname}_storage_{fs_prefix}_{u}"
        u_obj_id = f"{args.prefix}{u_obj_name}"
        node_info._dict[u_obj_name] = {
          "__type": "user_storage",
          "__id": u_obj_id,
          "hostname": hostname,
          "username": u,
          "target_path": target_path,
          "ts": unix_ts,
          "used_mb": mb
        }

  # Active terminal sessions are isolated into independent entities to prevent 
  # pollution from background storage consumers
  if "logged_in_users" in snapshot:
    # Multiple active terminal windows for the same user are securely aggregated
    session_counts: Dict[str, int] = {}
    for session in snapshot["logged_in_users"].get("sessions", []):
      u = session.get("user")
      if u:
        session_counts[u] = session_counts.get(u, 0) + 1
        
    for u, count in session_counts.items():
      u_obj_name = f"{hostname}_session_{u}"
      u_obj_id = f"{args.prefix}{u_obj_name}"
      node_info._dict[u_obj_name] = {
        "__type": "user_session",
        "__id": u_obj_id,
        "hostname": hostname,
        "username": u,
        "ts": unix_ts,
        "session_count": count
      }

  # Extraneous shell outputs are structurally unpacked and mapped onto LML entities.
  # Structured CSV outputs can be explicitly routed via 'inject_into' to merge their 
  # data securely into existing process or node entities.
  if "extra" in snapshot:
    # A mapping of existing processes by PID is constructed for rapid O(1) injection lookups
    pid_to_obj_name = {}
    if "processes" in snapshot:
      for proc in snapshot["processes"]:
        pid = proc.get("pid")
        if pid is not None:
          pid_to_obj_name[pid] = f"{hostname}_proc_{pid}"

    for ext_name, ext_data in snapshot["extra"].items():
      # The configuration dict for this specific command is retrieved to resolve routing rules
      cmd_cfg = next((c for c in cfg.get("extra_commands", []) if c.get("name") == ext_name), {})
      inject_target = cmd_cfg.get("inject_into")
      
      # Legacy fallback to maintain backward compatibility
      if not inject_target and cmd_cfg.get("inject_into_processes"):
        inject_target = "process"

      if isinstance(ext_data, str):
        node_info._dict[node_obj_name][f"extra_{ext_name}"] = ext_data
        
      elif isinstance(ext_data, dict) and "rows" in ext_data:
        for i, row in enumerate(ext_data["rows"]):
          
          # Routing Target: Process
          if inject_target == "process" and "pid" in row:
            try:
              target_pid = int(row["pid"])
              if target_pid in pid_to_obj_name:
                target_obj = pid_to_obj_name[target_pid]
                for k, v in row.items():
                  if k != "pid":
                    try: val = float(v) if "." in v else int(v)
                    except ValueError: val = v
                    node_info._dict[target_obj][k] = val
                continue
            except ValueError:
              pass
              
          # Routing Target: Node
          elif inject_target in ["node", "node_stat"]:
            for k, v in row.items():
              try: val = float(v) if "." in v else int(v)
              except ValueError: val = v
              # Metrics are naturally namespaced by their row index to prevent multi-device collisions (e.g., multiple GPUs)
              node_info._dict[node_obj_name][f"extra_{ext_name}_{i}_{k}"] = val
            continue
            
          # Fallback: Standalone Entity
          # If routing fails or is disabled, the row is instantiated as an independent LML object
          ext_obj_name = f"{hostname}_extra_{ext_name}_{i}"
          ext_obj_id = f"{args.prefix}{ext_obj_name}"
          ext_dict = {"__type": f"extra_{ext_name}", "__id": ext_obj_id, "hostname": hostname, "ts": unix_ts}
          ext_dict.update(row)
          node_info._dict[ext_obj_name] = ext_dict
          
      elif isinstance(ext_data, dict):
        for k, v in ext_data.items():
          if not isinstance(v, (dict, list)):
            node_info._dict[node_obj_name][f"extra_{ext_name}_{k}"] = v

  # Serialization to LML XML format is executed
  out_path = log_dir / f"{args.prefix}{hostname}.xml"
  node_info.to_LML(str(out_path), prefix=args.prefix)


if __name__ == "__main__":
  main()
