#!/usr/bin/env python3
# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Disclaimer: This file was created with the help of Gemini AI by Google.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH)

"""
File Parsing Plugin for LLview

This plugin processes log files by extracting metrics based on regular expressions
defined in a YAML configuration file. It supports optional transformations and
filters for these metrics and generates structured output files in CSV or LML (XML) format.
The output format and content are highly customizable through the configuration.

Core Functionality:
1.  Reads a YAML configuration file specifying metrics to extract and output formats.
2.  Scans specified directories for log files, potentially filtering by timeframe
    and tracking already processed files using a tracker file.
3.  For each group of files:
    a.  Identifies "file context" metrics (e.g., job ID from filename or content)
        that apply to all records from a single file.
    b.  Parses each new log file line by line using regular expressions to extract
        raw metric values (line-specific and file-context).
    c.  Merges file-context data into each line-specific record.
    d.  Applies defined transformation functions (e.g., string to timestamp)
        to the extracted values.
    e.  Applies include/exclude filters to the values.
    f.  Aggregates all processed records from all new files within the group.
4.  Generates output files based on the aggregated records, supporting different
    modes:
    - 'file' mode: Aggregates records by an index key, producing summary rows.
                   Supports direct `source` mapping, `static` values, and aggregations
                   (`count`, `min`, `max`, `avg`) specified via an `aggregate` key.
    - 'entry' mode: Outputs each processed log record as a separate row.
    - Custom modes: Allows defining custom output handler functions named
                    `_output_<mode_name>(aggregator, spec)`.
5.  Output files can be CSV or XML (for LML, determined by file extension).
    LML output includes additional metadata.
6.  Output files can be directed to a specific folder using `--outfolder`.

--------------------------------------------------------------------------------
YAML Configuration Schema:
--------------------------------------------------------------------------------

The configuration file is a YAML dictionary where keys are group names.
Each group defines a set of files to process and how to output data.

Example:
  my_log_group:
    folder: "/var/log/my_app/%Y/%m/%d/"
    timeframe: 7
    processed_files: "/opt/myapp_parser/seen_files.txt"
    metrics:
      - # ... (see Metrics Section) ...
    output:
      - # ... (see Output Section) ...

--------------------------------------------------------------------------------
Group Configuration Options (under each group name):
--------------------------------------------------------------------------------
  folder: (str, required)
    Path template for input log files. Supports `strftime`, env vars, `~`.

  timeframe: (int, optional, default: 0)
    Number of past days (including today) to scan. `0` for discovery/literal.

  processed_files: (str, optional)
    Path to tracker file for processed logs.

  metrics: (list, required)
    List of metric definitions. See "Metrics Section".

  output: (list, required)
    List of output specifications. If empty or not provided, the group is skipped.
    See "Output Section".

--------------------------------------------------------------------------------
Metrics Section (each item in the `metrics` list):
--------------------------------------------------------------------------------
  Common fields:
    regex: (str, required) Python regex. Unnamed group for simple, named for grouped.
    scope: (str, optional, default: "line") "line" or "file_context".
           "file_context" metrics merge into all line records from that file.
    from: (str, optional, default: "content") "content" or "filename".
          "filename" applies regex to the base filename.
    apply: (dict, optional) {<metric_or_group_name>: "<transform_func_name>"}.
    include: (str, list, or dict, optional) Regex rules to keep record.
    exclude: (str, list, or dict, optional) Regex rules to discard record.
    default: (any or dict, optional) Default value(s) for metric/groups.

  Simple metrics only:
    name: (str, required) Unique name for the simple metric.

--------------------------------------------------------------------------------
Output Section (each item in the `output` list):
--------------------------------------------------------------------------------
  Common fields:
    file: (str, required) Path to output file (e.g., 'data.csv', 'report.xml').
          Extension determines format.
    mode: (str, required) "file", "entry", or custom (e.g., "my_handler").
    index: (str, required) Metric name used as key for grouping/ID generation.
    fields: (dict, required) Column definitions.
            Keys are output column names. Values define source or aggregation:
            - `source: <metric_name>`:
              - If `aggregate` key is NOT present: Data from this metric.
                - In "file" mode for line-scoped metrics: `unique`, `wrap`, `joiner` apply.
                - In "file" mode for `index` key or `file_context` metrics: Value is singular;
                  `wrap` applies, `joiner`/`unique` ignored.
              - If `aggregate` key IS present: This `<metric_name>` is the one to be aggregated.
            - `aggregate: "<type>"` (file mode only): Specifies the aggregation type.
              Requires `source: <metric_name>` to define the metric to aggregate.
              Possible `<type>` values:
              - `"count"`: Count of occurrences of the `source` metric.
                - Can also include `unique: true` to count only unique non-null values.
              - `"min"`: Calculate the minimum numeric value from the `source` metric.
                         Non-numeric values are skipped. `wrap` formatting applies.
              - `"max"`: Calculate the maximum numeric value. Similar to `min`.
              - `"avg"`: Calculate the average of numeric values. Similar to `min`.
            - `static: <value>`: Fixed value for the column.
            - If column name matches `index` and no `source`, `static`, or `aggregate`
              is defined: contains index value (file mode) or generated ID (entry mode).

  XML (LML) Output Specifics (when `file` ends with `.xml`):
    Additional top-level keys in the output specification:
    prefix: (str, optional, default: "i") Prefix used for automatically generated `id`
            attributes in the `<object>` tags (e.g., if "msg", IDs: "msg001").
    type: (str, optional, default: "item") The `type` attribute for `<object>` tags.

    LML Structure:
      - `<objects>` list: `name` from `index` value (suffixed if not unique),
        `id` from `prefix` + counter, `type` from `type` config.
      - `<information>`: `<info oid="..." type="short">` for each object.
      - `<data key="..." value="..."/>` for each field.
      - Automatic 'pstat' object with timing/count metadata for the group processing.

--------------------------------------------------------------------------------
Command-Line Arguments & Transformation Functions: (See previous detailed docstring)
--------------------------------------------------------------------------------
"""

import argparse
import logging
import time
import datetime
import re
import os
import sys
import csv
import yaml
import math # For LML ID generation
from typing import Any, List, Dict, Tuple, Set, Callable, Optional, Union
from pathlib import Path
from collections import defaultdict

# --- Transformation Functions ---
def to_timestamp(val: str) -> Optional[int]:
  if val is None:
    return None
  try:
    dt = datetime.datetime.strptime(val, "%Y-%m-%dT%H:%M:%S%z")
    return int(dt.timestamp())
  except (ValueError, TypeError):
    try:
      dt = datetime.datetime.fromisoformat(str(val).replace('Z', '+00:00'))
      return int(dt.timestamp())
    except (ValueError, TypeError):
      pass
  return None

# --- Core Parsing Class (Single File) ---
class FileParser:
  def __init__(self, filepath: Path, group_config: Dict[str, Any], logger: logging.Logger):
    self.filepath = filepath
    self.group_config = group_config
    self.metrics_definitions = group_config.get('metrics', [])
    self.log = logger
    self._compiled_metrics: List[Dict[str, Any]] = []
    self._precompile_metrics()

  def _precompile_metrics(self):
    for i, m_def_orig in enumerate(self.metrics_definitions):
      m_def = m_def_orig.copy()
      if 'regex' not in m_def:
        self.log.warning(
          f"Metric definition #{i} (name: {m_def.get('name', 'N/A')}) "
          f"in file {self.filepath.name} is missing 'regex'. Skipping."
        )
        continue
      try:
        m_def['_compiled_regex'] = re.compile(m_def['regex'])
        m_def.setdefault('scope', 'line')
        m_def.setdefault('from', 'content')
        self._compiled_metrics.append(m_def)
      except re.error as e:
        self.log.error(
          f"Invalid regex for metric (name: {m_def.get('name', 'N/A')}, "
          f"pattern: '{m_def['regex']}') in file {self.filepath.name}: {e}. Skipping."
        )

  def _extract_metric_values(self, m_def: Dict[str, Any], match_obj: re.Match) -> Dict[str, Any]:
    extracted = {}
    if 'name' in m_def:
      metric_name = m_def['name']
      try:
        extracted[metric_name] = match_obj.group(1)
      except IndexError:
        self.log.warning(
          f"Regex for simple metric '{metric_name}' in {self.filepath.name} "
          f"matched, but capture group 1 is missing. Regex: '{m_def['regex']}'"
        )
    else:
      default_values = m_def.get('default', {})
      extracted = default_values.copy()
      for group_name, group_value in match_obj.groupdict().items():
        if group_value is not None:
          extracted[group_name] = group_value
    return extracted

  def parse_file_content(self) -> List[Dict[str, Any]]:
    self.log.debug(f"Starting raw parse of {self.filepath}")
    if not self._compiled_metrics:
      self.log.warning(f"No valid, compiled regexes for {self.filepath.name}. Skipping.")
      return []

    file_context_data: Dict[str, Any] = {}
    processed_records: List[Dict[str, Any]] = []

    filename_to_match = self.filepath.name
    for m_def in self._compiled_metrics:
      if m_def['from'] == 'filename':
        compiled_rx = m_def['_compiled_regex']
        match_obj = compiled_rx.search(filename_to_match)
        if match_obj:
          extracted_values = self._extract_metric_values(m_def, match_obj)
          if m_def['scope'] == 'file_context':
            file_context_data.update(extracted_values)
            self.log.debug(f"Updated file context from filename '{filename_to_match}' via metric "
                           f"'{m_def.get('name', m_def['regex'])}': {extracted_values}")
        elif m_def['scope'] == 'file_context':
          self.log.warning(
            f"File context metric '{m_def.get('name', m_def['regex'])}' "
            f"defined for 'from: filename' did not match filename '{filename_to_match}'."
          )
    self.log.debug(f"Initial file context for {self.filepath.name} (after filename parse): {file_context_data}")

    try:
      with self.filepath.open('r', encoding='utf-8', errors='replace') as f:
        for line_num, line_content in enumerate(f, 1):
          text = line_content.rstrip('\n')
          if not text: continue

          current_line_specific_metrics: Dict[str, Any] = {}
          line_updated_file_context = False
          for m_def in self._compiled_metrics:
            if m_def['from'] == 'filename': continue
            compiled_rx = m_def['_compiled_regex']
            match_obj = compiled_rx.search(text)
            if not match_obj: continue
            extracted_values = self._extract_metric_values(m_def, match_obj)
            if not extracted_values and not m_def.get('default'): continue

            if m_def['scope'] == 'file_context':
              self.log.debug(f"Line {line_num}: Updating file context with: {extracted_values} from metric '{m_def.get('name', m_def['regex'])}'")
              file_context_data.update(extracted_values)
              line_updated_file_context = True
            else:
              current_line_specific_metrics.update(extracted_values)
          
          if current_line_specific_metrics:
            final_record = file_context_data.copy()
            final_record.update(current_line_specific_metrics)
            processed_records.append(final_record)
          elif line_updated_file_context:
            self.log.debug(f"Line {line_num} in {self.filepath.name} only updated file context.")
    except FileNotFoundError:
      self.log.error(f"Input file not found during content parse: {self.filepath}")
      return []
    except Exception as e:
      self.log.error(f"Error reading or parsing content of {self.filepath}: {e}", exc_info=True)
      return []

    if not processed_records and file_context_data:
      self.log.info(f"File {self.filepath.name} provided context data {file_context_data} but no line-specific records were generated.")
    
    if processed_records:
      first_record_keys = processed_records[0].keys()
      for m_def in self._compiled_metrics:
        if m_def['scope'] == 'file_context':
          context_keys_from_def = []
          if 'name' in m_def: context_keys_from_def.append(m_def['name'])
          else: # Grouped metric
            if '_compiled_regex' in m_def and hasattr(m_def['_compiled_regex'], 'groupindex'):
              context_keys_from_def.extend(m_def['_compiled_regex'].groupindex.keys())
          for key in context_keys_from_def:
            if key not in first_record_keys:
              self.log.debug(
                f"Defined file context key '{key}' (metric: {m_def.get('name', m_def['regex'])}) "
                f"was not found in the final file context for {self.filepath.name}."
              )
    self.log.debug(f"Finished raw parse of {self.filepath.name}, generated {len(processed_records)} raw records.")
    return processed_records

  def _apply_filter_pattern(self, metric_name: str, value_to_filter: Any,
                           rules: Union[str, List[str], None], rule_type: str,
                           exclusions_tracker: Dict[str, Set[str]]) -> bool:
    if rules is None: return True
    value_str = str(value_to_filter)
    patterns_to_check = [rules] if isinstance(rules, str) else rules
    if not patterns_to_check:
      if rule_type == "include":
        reason = f"empty {rule_type} rule list for metric '{metric_name}'"
        exclusions_tracker.setdefault(reason, set()).add(value_str)
        return False
      return True

    match_found = False
    matched_pattern_str = ""
    for p_str in patterns_to_check:
      try:
        if re.search(p_str, value_str):
          match_found = True; matched_pattern_str = p_str; break
      except re.error as e:
        self.log.warning(f"Invalid regex pattern in {rule_type} rule for {metric_name}: '{p_str}'. Error: {e}. Skipping.")
    
    if rule_type == "exclude":
      if match_found:
        reason = f"exclude rule '{matched_pattern_str}' for metric '{metric_name}'"
        exclusions_tracker.setdefault(reason, set()).add(value_str); return False
      return True
    if rule_type == "include":
      if not match_found:
        reason = f"include rule(s) '{','.join(patterns_to_check)}' for metric '{metric_name}' (no match)"
        exclusions_tracker.setdefault(reason, set()).add(value_str); return False
      return True
    self.log.error(f"Internal error: _apply_filter_pattern called with unknown rule_type '{rule_type}'")
    return False

  def process_transformed_records(self, raw_records: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    if not raw_records: return []
    final_records: List[Dict[str, Any]] = []
    file_exclusions_tracker: Dict[str, Set[str]] = defaultdict(set)

    for raw_rec_idx, raw_rec in enumerate(raw_records):
      current_record_values = raw_rec.copy()
      keep_this_record_overall = True

      for m_def in self._compiled_metrics: # Transformations
        if not keep_this_record_overall: break
        apply_config = m_def.get('apply', {});
        if not apply_config: continue
        
        metric_keys_in_def = []
        if 'name' in m_def: metric_keys_in_def.append(m_def['name'])
        elif m_def.get('_compiled_regex') and hasattr(m_def['_compiled_regex'], 'groupindex'):
            metric_keys_in_def.extend(list(m_def['_compiled_regex'].groupindex.keys()))
        
        for metric_key in metric_keys_in_def:
          if metric_key not in current_record_values: continue
          original_value = current_record_values[metric_key]
          transform_func_name = apply_config.get(metric_key)
          if transform_func_name:
            transform_func = globals().get(transform_func_name)
            if callable(transform_func):
              try:
                transformed_value = transform_func(original_value)
                if transformed_value is None and original_value is not None and transform_func_name == 'to_timestamp':
                  self.log.debug(f"Rec #{raw_rec_idx}: Transform '{transform_func_name}' for '{metric_key}' in {self.filepath.name} "
                                 f"returned None from non-None '{original_value}'. Record dropped.")
                  keep_this_record_overall = False; break
                current_record_values[metric_key] = transformed_value
              except Exception as e:
                self.log.warning(f"Rec #{raw_rec_idx}: Transform '{transform_func_name}' for '{metric_key}' in {self.filepath.name} "
                                 f"failed on '{original_value}'. Error: {e}. Record dropped.")
                keep_this_record_overall = False; break
            else:
              self.log.warning(f"Rec #{raw_rec_idx}: Transform func '{transform_func_name}' for '{metric_key}' in {self.filepath.name} "
                               f"not found/callable. Record dropped.")
              keep_this_record_overall = False; break
        if not keep_this_record_overall: break
      if not keep_this_record_overall: continue

      for m_def in self._compiled_metrics: # Filters
        if not keep_this_record_overall: break
        is_simple = 'name' in m_def
        
        metric_keys_for_filtering = []
        if is_simple: metric_keys_for_filtering.append(m_def['name'])
        elif m_def.get('_compiled_regex') and hasattr(m_def['_compiled_regex'], 'groupindex'):
            metric_keys_for_filtering.extend(list(m_def['_compiled_regex'].groupindex.keys()))

        for metric_key in metric_keys_for_filtering:
          if metric_key not in current_record_values: continue
          value_for_filter = current_record_values[metric_key]
          
          exclude_src = m_def.get('exclude')
          current_exclude_rules = exclude_src if is_simple else (exclude_src.get(metric_key) if isinstance(exclude_src, dict) else None)
          if not self._apply_filter_pattern(metric_key, value_for_filter, current_exclude_rules, "exclude", file_exclusions_tracker):
            self.log.debug(f"Rec #{raw_rec_idx} in {self.filepath.name} dropped: EXCLUDE on '{metric_key}' (val: '{value_for_filter}')")
            keep_this_record_overall = False; break

          include_src = m_def.get('include')
          current_include_rules = include_src if is_simple else (include_src.get(metric_key) if isinstance(include_src, dict) else None)
          if not self._apply_filter_pattern(metric_key, value_for_filter, current_include_rules, "include", file_exclusions_tracker):
            self.log.debug(f"Rec #{raw_rec_idx} in {self.filepath.name} dropped: INCLUDE on '{metric_key}' (val: '{value_for_filter}')")
            keep_this_record_overall = False; break
        if not keep_this_record_overall: break
      
      if keep_this_record_overall and current_record_values:
        final_records.append(current_record_values)

    if file_exclusions_tracker:
      self.log.debug(f"Exclusion summary for file {self.filepath.name}:")
      for reason, items in file_exclusions_tracker.items():
        sample = list(items)[:3]; ellipsis = "..." if len(items) > 3 else ""
        self.log.debug(f"  - Filter Reason: {reason}, Count: {len(items)}, Sample: {sample}{ellipsis}")
    self.log.debug(f"Finished transforming/filtering for {self.filepath.name}, {len(final_records)} records kept.")
    return final_records

# --- Output Aggregation and Generation Class ---
class OutputAggregator:
  def __init__(self, group_name: str, group_config: Dict, metrics_definitions: List[Dict], 
               outfolder: Optional[Path], logger: logging.Logger):
    self.group_name = group_name
    self.group_config = group_config
    self.output_specs = group_config.get('output', [])
    self.metrics_definitions = metrics_definitions 
    self.outfolder = outfolder
    self.all_records: List[Dict[str, Any]] = []
    self.log = logger
    self.default_map: Dict[str, Any] = {}
    for m_def in self.metrics_definitions:
      default_cfg = m_def.get('default')
      if default_cfg is None: continue
      if 'name' in m_def: self.default_map[m_def['name']] = default_cfg
      elif isinstance(default_cfg, dict) and m_def.get('_compiled_regex') and hasattr(m_def['_compiled_regex'], 'groupindex'):
        for gk, dv in default_cfg.items():
          if gk in m_def['_compiled_regex'].groupindex: self.default_map[gk] = dv
    self.log.debug(f"OutputAggregator for '{group_name}' initialized with default_map: {self.default_map}")

  def add_records(self, records: List[Dict[str, Any]]): self.all_records.extend(records)
  def has_records(self) -> bool: return bool(self.all_records)

  def _resolve_output_path(self, path_from_config: str) -> Path:
    path_obj = Path(os.path.expanduser(os.path.expandvars(path_from_config)))
    return self.outfolder / path_obj if self.outfolder and not path_obj.is_absolute() else path_obj

  def _get_value_with_default(self, record: Dict, key: str) -> Any:
    return record.get(key, self.default_map.get(key))

  def _is_metric_file_context(self, metric_name: str) -> bool:
    for m_def in self.metrics_definitions:
      if m_def.get('scope') == 'file_context':
        if 'name' in m_def and m_def['name'] == metric_name: return True
        if m_def.get('_compiled_regex') and hasattr(m_def['_compiled_regex'], 'groupindex') \
           and metric_name in m_def['_compiled_regex'].groupindex: return True
    return False

  def _output_mode_file(self, spec: Dict) -> Tuple[List[Dict], List[str]]:
    index_key = spec['index']
    grouped_by_index: Dict[Any, List[Dict]] = defaultdict(list)
    for rec in self.all_records:
      key_val = self._get_value_with_default(rec, index_key)
      if key_val is None:
        self.log.debug(f"Record skipped for 'file' mode (group: {self.group_name}, output: {spec.get('file')}) "
                       f"due to missing index '{index_key}': {rec}")
        continue
      grouped_by_index[key_val].append(rec)

    output_rows: List[Dict] = []
    headers = list(spec['fields'].keys())
    for idx_val, group_records in grouped_by_index.items():
      row: Dict[str, Any] = {}
      for col_name, instruction in spec['fields'].items():
        # --- MODIFIED SECTION: Aggregation Logic ---
        if 'aggregate' in instruction:
          agg_type = instruction['aggregate']
          metric_to_aggregate = instruction.get('source') # Metric name comes from 'source'

          if not metric_to_aggregate:
            self.log.error(
              f"Column '{col_name}' in output '{spec.get('file')}' for group '{self.group_name}' "
              f"specifies 'aggregate: {agg_type}' but is missing the 'source' key for the metric name. Skipping."
            )
            row[col_name] = "" # Or a specific placeholder like "ERR:NO_SOURCE"
            continue

          if agg_type == 'count':
            if instruction.get('unique', False): # Count unique occurrences
              unique_vals = set(self._get_value_with_default(r, metric_to_aggregate) for r in group_records)
              unique_vals.discard(None) # Don't count None as a unique value
              row[col_name] = len(unique_vals)
            else: # Count all non-null occurrences
              row[col_name] = sum(1 for r in group_records if self._get_value_with_default(r, metric_to_aggregate) is not None)
            
            # Apply wrap to count result if specified
            wrap_format = instruction.get('wrap')
            if wrap_format:
              try: row[col_name] = wrap_format.format(row[col_name])
              except (ValueError, TypeError): 
                self.log.warning(f"Wrap format '{wrap_format}' for count column '{col_name}' failed. Using raw value.")


          elif agg_type in ['min', 'max', 'avg']:
            numeric_values: List[float] = []
            non_numeric_count = 0
            for r_idx, r_rec in enumerate(group_records):
              raw_val = self._get_value_with_default(r_rec, metric_to_aggregate)
              if raw_val is not None:
                try:
                  numeric_values.append(float(raw_val))
                except (ValueError, TypeError): # Added TypeError for robustness
                  non_numeric_count +=1
                  if non_numeric_count <= 3: # Log first few instances per group/metric/index
                       self.log.warning(
                          f"Column '{col_name}' (aggregate: '{agg_type}' on source: '{metric_to_aggregate}') for index '{idx_val}' "
                          f"in output '{spec.get('file')}': Value '{raw_val}' is not numeric and was skipped."
                       )
                  if non_numeric_count == 4: # Suppress further similar warnings
                       self.log.warning(
                          f"Column '{col_name}' (aggregate: '{agg_type}' on source: '{metric_to_aggregate}') for index '{idx_val}' "
                          f"in output '{spec.get('file')}': Further non-numeric warnings for this combination will be suppressed."
                       )
            
            if not numeric_values:
              row[col_name] = "" # Or a specific placeholder like "N/A"
              self.log.debug(
                f"Column '{col_name}' (aggregate: '{agg_type}' on source: '{metric_to_aggregate}') for index '{idx_val}' "
                f"in output '{spec.get('file')}': No numeric values found for aggregation."
              )
            else:
              result_val: Optional[Union[float, str]] = None
              if agg_type == 'min': result_val = min(numeric_values)
              elif agg_type == 'max': result_val = max(numeric_values)
              elif agg_type == 'avg': result_val = sum(numeric_values) / len(numeric_values)
              
              if result_val is not None:
                wrap_format = instruction.get('wrap')
                if wrap_format:
                  try: 
                    row[col_name] = wrap_format.format(result_val)
                  except (ValueError, TypeError): 
                    self.log.debug(
                      f"Wrap format '{wrap_format}' for column '{col_name}' failed on numeric result {result_val}. "
                      "Applying to its string representation instead."
                    )
                    row[col_name] = wrap_format.format(str(result_val))
                else: # No wrap, just convert number to string
                  row[col_name] = str(result_val)
              else: # Should not happen if numeric_values was populated
                row[col_name] = ""
          else: # Unknown aggregation type
            self.log.error(
                f"Column '{col_name}' in output '{spec.get('file')}' for group '{self.group_name}' "
                f"has an unknown 'aggregate' type: '{agg_type}'. Skipping."
            )
            row[col_name] = "" # Or "ERR:UNKNOWN_AGG"
        # --- END MODIFIED SECTION ---

        elif 'source' in instruction: # No 'aggregate', so direct source mapping
          source_metric = instruction['source']
          is_singular = (source_metric == index_key) or self._is_metric_file_context(source_metric)
          if is_singular:
            value = self._get_value_with_default(group_records[0], source_metric)
            row[col_name] = instruction.get('wrap', '{}').format(str(value)) if value is not None else ''
          else:
            vals = [v for r in group_records if (v := self._get_value_with_default(r, source_metric)) is not None]
            if instruction.get('unique', False): # 'unique' here applies to joining multiple values
              try: vals = list(dict.fromkeys(vals))
              except TypeError: vals = [v for i, v in enumerate(vals) if v not in vals[:i]]
            row[col_name] = instruction.get('joiner', '').join(instruction.get('wrap', '{}').format(str(v)) for v in vals)
        
        elif 'static' in instruction: 
          row[col_name] = instruction['static']
        
        elif col_name == index_key and not any(k in instruction for k in ['source', 'static', 'aggregate']): # Added 'aggregate'
          row[col_name] = idx_val
      output_rows.append(row)
    return output_rows, headers

  def _output_mode_entry(self, spec: Dict) -> Tuple[List[Dict], List[str]]:
    index_key = spec['index'] # This is the key from data to form part of the LML object name or CSV row ID
    entry_id_counters: Dict[Any, int] = defaultdict(int) # For CSV generated ID, not LML <object name>
    output_rows: List[Dict] = [] # This will store the rows for output
    headers = list(spec['fields'].keys())

    for rec_idx, rec in enumerate(self.all_records):
      # Get the raw value of the index key for LML object naming
      idx_val_for_lml_name = self._get_value_with_default(rec, index_key)
      
      if idx_val_for_lml_name is None and Path(spec.get('file','')).suffix.lower() != '.xml': # XML might still work if other fields are present
        self.log.debug(f"Record #{rec_idx} skipped for 'entry' mode (group: {self.group_name}, output: {spec.get('file')}) "
                       f"due to missing index '{index_key}' for ID/name: {rec}")
        continue
      
      # This unique_entry_id is primarily for CSV or if a column explicitly asks for a generated ID
      entry_id_counters[idx_val_for_lml_name] += 1
      unique_csv_entry_id = f"{idx_val_for_lml_name}_{entry_id_counters[idx_val_for_lml_name]}"

      # This 'row' dictionary will only contain keys defined in spec['fields']
      # plus our special key for the LML object name.
      row: Dict[str, Any] = {}
      # Store the intended LML object name value under a special, non-colliding key.
      # This ensures the LML writer can access it without polluting the data fields.
      row["__lml_object_name__"] = idx_val_for_lml_name

      # Populate the row based on the 'fields' specification
      for col_name, instruction in spec['fields'].items():
        if 'source' in instruction: 
            # Note: 'aggregate' is not typically used in 'entry' mode, as it's per-record.
            # If 'aggregate' were present here, it would operate on a single value from 'rec'.
            # Current logic assumes 'aggregate' is primarily for 'file' mode.
            row[col_name] = self._get_value_with_default(rec, instruction['source'])
        elif 'static' in instruction: 
            row[col_name] = instruction['static']
        elif col_name == index_key and not any(k in instruction for k in ['source', 'static']):
            # If an output column is explicitly named after the index_key itself,
            # and it's not sourced or static, it gets the unique_csv_entry_id.
            # This is primarily for CSV. For LML, the object name comes from "__lml_object_name__".
            row[col_name] = unique_csv_entry_id
        # If the index_key (e.g., 'node') is NOT an explicit col_name in spec['fields'],
        # it won't be added to the 'row' here, so it won't become a <data> element by default.
            
      output_rows.append(row)
    return output_rows, headers

  def _write_lml_output(self, final_output_path: Path, data_rows: List[Dict[str, Any]], 
                        spec: Dict[str, Any], group_start_time: float, group_end_time: float):
    self.log.info(f"Preparing LML data for {final_output_path}...")
    lml_dict: Dict[str, Dict[str, Any]] = {}
    output_config_prefix = spec.get('prefix', 'i') 
    output_config_type = spec.get('type', 'item')     
    
    index_key_for_name_attribute = spec.get('index') # Key in data_rows for LML object name attribute
    name_counts = defaultdict(int)
    
    # These are the keys that should appear as <data key="..."> elements
    # defined in the YAML output spec's 'fields'.
    defined_output_field_names = spec['fields'].keys()

    for i, row_data in enumerate(data_rows): # row_data comes from _output_mode_entry or _output_mode_file
      # Retrieve the LML object name from the special key
      base_name_val: Optional[Any] = None
      # Determine the source of the LML object name value
      if "__lml_object_name__" in row_data:
        # This row came from _output_mode_entry with specific LML name handling
        base_name_val = row_data.get("__lml_object_name__")
      elif index_key_for_name_attribute is not None:
        # This row likely came from _output_mode_file or a custom handler.
        # The LML object name is the value of the 'index' field directly from the row.
        # Check added to ensure index_key_for_name_attribute is a string and not None
        base_name_val = row_data.get(index_key_for_name_attribute)
        
      if base_name_val is None: # Should ideally not happen if _output_mode_entry always adds it
        base_name = f"unnamed_object_{i+1}"
        # Create a clean dict for logging, excluding internal keys
        loggable_row_data = {k:v for k,v in row_data.items() if not k.startswith('__')}
        self.log.warning(
          f"Missing value for LML object name (index: '{index_key_for_name_attribute}', row index: {i}) "
          f"in LML output {final_output_path}. Using generated name '{base_name}'. "
          f"Row data (debug): {loggable_row_data}"
        )
      else:
        base_name = str(base_name_val)
      
      current_count = name_counts[base_name]
      name_counts[base_name] += 1
      # For LML <object name="...">, ensure uniqueness if base_name repeats
      object_list_name = f"{base_name}_{current_count + 1}" if current_count > 0 else base_name
      
      # Construct lml_item_data:
      # For rows from _output_mode_entry, we iterate through defined_output_field_names.
      # For rows from _output_mode_file, all keys in row_data (which are the output columns)
      # are candidates for <data> elements, *except* the index key itself if it was only for naming.
      # However, to be consistent and robust: only include what's in defined_output_field_names.
      # This also means that if the index key (e.g. "node") is *also* an output field, it will be included.
      lml_item_data = {}
      for field_key in defined_output_field_names:
        if field_key in row_data and row_data[field_key] is not None:
          lml_item_data[field_key] = row_data[field_key]

      lml_item_data["__type"] = output_config_type 
      lml_dict[object_list_name] = lml_item_data

    num_data_elements = len(data_rows) # Count based on input rows, pstat is extra
    timing_obj_name = f"get{self.group_name}"
    timing_data_key = f"pstat_{timing_obj_name}"
    timing_values: Dict[str, Any] = {
      'startts': group_start_time, 'datats': group_start_time,
      'endts': group_end_time, 'duration': round(group_end_time - group_start_time, 3),
      'nelems': num_data_elements, f"__nelems_{output_config_type}": num_data_elements,
      '__type': 'pstat', '__id': timing_data_key
    }
    if timing_obj_name in lml_dict : 
      original_timing_obj_name = timing_obj_name
      timing_obj_name += "_pstat"
      timing_data_key = f"pstat_{timing_obj_name}" 
      timing_values['__id'] = timing_data_key
      self.log.warning(f"Timing object name '{original_timing_obj_name}' clashed with a data object. Renamed to '{timing_obj_name}'.")

    lml_dict[timing_obj_name] = timing_values
    self._perform_lml_write(final_output_path, lml_dict, output_config_prefix, output_config_type)

  def _perform_lml_write(self, filename: Path, data_dict: Dict[str, Dict[str, Any]], 
                         id_prefix_cfg: str, default_type_cfg: str): # Renamed params to avoid confusion
    self.log.info(f"Writing LML (XML) data to {filename} ... ")
    filename.parent.mkdir(parents=True, exist_ok=True)
    with filename.open("w", encoding="utf-8") as file:
      file.write("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n" )
      file.write("<lml:lgui xmlns:lml=\"http://eclipse.org/ptp/lml\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n" )
      file.write("    xsi:schemaLocation=\"http://eclipse.org/ptp/lml http://eclipse.org/ptp/schemas/v1.1/lgui.xsd\"\n" )
      file.write("    version=\"1.1\">\n" )
      file.write("<objects>\n" )
      num_items_for_id_gen = sum(1 for item_data in data_dict.values() if item_data.get("__type") != "pstat")
      digits = int(math.log10(num_items_for_id_gen)) + 1 if num_items_for_id_gen > 0 else 1
      i = 0
      for obj_list_name, item_data in data_dict.items():
        current_id = item_data.get("__id")
        # PSTAT objects should have __id pre-set. Data objects get it generated if missing.
        if not current_id and item_data.get("__type") != "pstat":
          current_id = f'{id_prefix_cfg}{i+1:0{digits}d}'; item_data["__id"] = current_id; i += 1
        elif not current_id: # Should be a pstat object that somehow missed its ID
          self.log.error(f"LML object '{obj_list_name}' of type '{item_data.get('__type')}' is missing __id. This is unexpected."); current_id = f"error_id_{obj_list_name}"
        
        obj_type = item_data.get("__type", default_type_cfg) # Use item's __type if set (e.g. pstat), else config's type
        file.write(f'  <object id="{current_id}" name="{obj_list_name}" type="{obj_type}"/>\n')
      file.write("</objects>\n")
      file.write("<information>\n")
      for obj_list_name, item_data in data_dict.items():
        oid = item_data.get("__id", f"error_missing_id_for_{obj_list_name}") # Should always be there now
        file.write(f'  <info oid="{oid}" type="short">\n') # type="short" is hardcoded
        for data_key, data_value in item_data.items():
          if data_key.startswith('__nelems'):
            file.write(f'   <data key="{data_key}" value="{data_value}"/>\n')
          elif data_key.startswith('__'): continue # Skip __id, __type
          elif data_value is not None:
            formatted_value = str(data_value).replace('"', "&quot;") if isinstance(data_value, str) else data_value # XML escape quotes
            file.write(f'   <data key="{data_key}" value="{formatted_value}"/>\n')
        file.write(f"  </info>\n")
      file.write("</information>\n</lml:lgui>\n" )
    self.log.info(f"Finished writing LML (XML) to {filename}!")

  def output_specs_contain_lml(self) -> bool: # LML is .xml
    for spec in self.output_specs:
      f_cfg = spec.get('file')
      if f_cfg and Path(f_cfg).suffix.lower() == ".xml": return True
    return False

  def generate_outputs(self, group_start_time: float):
    group_process_end_time = time.time()
    is_any_xml_output_defined = self.output_specs_contain_lml() 

    # If no records AND no XML output is defined, then truly skip.
    # XML output might need to write a pstat object even with no data records.
    if not self.has_records() and not is_any_xml_output_defined: # MODIFIED THIS CONDITION
      self.log.info(
        f"No data records for group '{self.group_name}' and no XML output is defined. "
        "Skipping all output file generation for this group."
      )
      return
    
    if not self.output_specs:
      self.log.info(f"No output specifications defined for group '{self.group_name}'.")
      return

    for spec in self.output_specs:
      mode = spec.get('mode'); output_filepath_config = spec.get('file')
      if not mode or not output_filepath_config:
        self.log.warning(f"Output spec for '{self.group_name}' missing 'mode' or 'file'. Skipping: {spec}")
        continue
      
      final_output_path = self._resolve_output_path(output_filepath_config)
      file_extension = final_output_path.suffix.lower()

      # Early check for supported output extensions
      if file_extension not in [".csv", ".xml"]:
        self.log.warning(
          f"Unsupported file extension '{file_extension}' for output file "
          f"'{final_output_path}'. Skipping this output specification."
        )
        continue
      
      self.log.debug(f"Generating output for '{self.group_name}', mode '{mode}', target '{final_output_path}'.")
      rows: List[Dict] = []; headers: List[str] = []
      try:
        if mode == "file": rows, headers = self._output_mode_file(spec)
        elif mode == "entry": rows, headers = self._output_mode_entry(spec)
        else: # Custom mode
          handler_func_name = f"_output_{mode}"; handler_func = globals().get(handler_func_name)
          if callable(handler_func): 
            # Capture the result of the custom handler call
            handler_result = handler_func(self, spec)
            # Check if the result is a sequence of the expected length
            # and prevent errors
            if isinstance(handler_result, (list, tuple)) and len(handler_result) == 2:
              rows, headers = handler_result
            else:
              self.log.warning(f"Custom handler '{handler_func_name}' did not return (rows, headers). Skipping.")
              continue
          else: self.log.warning(f"Custom handler '{handler_func_name}' not found/callable. Skipping."); continue
        
        # If no data rows generated, and it's not XML (which might still write pstat)
        if not rows and file_extension != ".xml":
          self.log.info(f"No data rows generated for non-XML output '{final_output_path}'.")
          if headers and file_extension == ".csv": # Write header-only CSV if requested
            final_output_path.parent.mkdir(parents=True, exist_ok=True)
            with final_output_path.open('w', newline='', encoding='utf-8') as f_csv:
              csv.DictWriter(f_csv, fieldnames=headers).writeheader()
            self.log.info(f"Wrote header-only CSV to '{final_output_path}'.")
          continue # Skip to next output spec

        final_output_path.parent.mkdir(parents=True, exist_ok=True)
        if file_extension == ".csv":
          with final_output_path.open('w', newline='', encoding='utf-8') as f_csv:
            if not headers: headers = list(rows[0].keys()) if rows else list(spec.get('fields', {}).keys())
            writer = csv.DictWriter(f_csv, fieldnames=headers, extrasaction='ignore')
            writer.writeheader()
            if rows: writer.writerows(rows)
          self.log.info(f"Wrote {len(rows)} CSV rows to '{final_output_path}'.")
        elif file_extension == ".xml": # LML output
          self._write_lml_output(final_output_path, rows, spec, group_start_time, group_process_end_time)
        # No 'else' needed due to early extension check
      except Exception as e:
        self.log.error(f"Error during output generation for '{final_output_path}': {e}", exc_info=True)

# --- Logging Utilities ---
# (CustomFormatter, _ExcludeErrorsFilter, LOG_CONFIG_DEFAULTS, log_init - remain the same as previous full version)
class CustomFormatter(logging.Formatter):
  def __init__(self, fmt: str, datefmt: str = ""):
    super().__init__(); self.fmt_template = fmt; self.datefmt = datefmt
    self.colors = { logging.DEBUG: "\x1b[96m", logging.INFO: "\x1b[37m", logging.WARNING: "\x1b[93m",
                    logging.ERROR: "\x1b[91m", logging.CRITICAL: "\x1b[91;1m" }
    self.reset_color = "\x1b[0m"; self.formatters = {}
    for level, color in self.colors.items():
      self.formatters[level] = logging.Formatter(fmt=color + self.fmt_template + self.reset_color, datefmt=self.datefmt)
    self.default_formatter = logging.Formatter(fmt=self.fmt_template, datefmt=self.datefmt)
  def format(self, record: logging.LogRecord) -> str:
    return self.formatters.get(record.levelno, self.default_formatter).format(record)

class _ExcludeErrorsFilter(logging.Filter):
  def filter(self, record: logging.LogRecord) -> bool: return record.levelno < logging.ERROR

LOG_CONFIG_DEFAULTS = {'format': "%(asctime)s %(name)s %(funcName)-22s(%(lineno)-3d): [%(levelname)-8s] %(message)s",
                       'datefmt': "%Y-%m-%d %H:%M:%S", 'level': "INFO"}

def log_init(logger_name: str, level_str: Optional[str]) -> logging.Logger:
  log = logging.getLogger(logger_name)
  log.setLevel(getattr(logging, (level_str or LOG_CONFIG_DEFAULTS['level']).upper(), logging.INFO))
  if log.hasHandlers(): log.handlers.clear()
  stdout_h = logging.StreamHandler(sys.stdout)
  stdout_h.setFormatter(CustomFormatter(LOG_CONFIG_DEFAULTS['format'], datefmt=LOG_CONFIG_DEFAULTS['datefmt']))
  stdout_h.addFilter(_ExcludeErrorsFilter()); stdout_h.terminator = "\n"; log.addHandler(stdout_h)
  stderr_h = logging.StreamHandler(sys.stderr); stderr_h.setLevel(logging.ERROR)
  stderr_h.setFormatter(CustomFormatter(LOG_CONFIG_DEFAULTS['format'], datefmt=LOG_CONFIG_DEFAULTS['datefmt']))
  stderr_h.terminator = "\n"; log.addHandler(stderr_h)
  log.propagate = False; return log


# --- File Discovery Utilities ---
# (expand_path_template, discover_files - remain the same as previous full version)
def expand_path_template(path_template_str: str, base_date: Optional[datetime.date] = None) -> Path:
  expanded_str = os.path.expanduser(os.path.expandvars(path_template_str))
  if base_date and '%' in expanded_str:
    try: expanded_str = base_date.strftime(expanded_str)
    except ValueError as e: raise 
  return Path(expanded_str)

def discover_files(folder_template_str: str, timeframe_days: int, log: logging.Logger) -> Set[Path]:
  discovered_files: Set[Path] = set()
  if timeframe_days > 0:
    today = datetime.date.today()
    for i in range(timeframe_days):
      current_date = today - datetime.timedelta(days=i)
      try:
        base_expanded_template = os.path.expanduser(os.path.expandvars(folder_template_str))
        dir_path = Path(current_date.strftime(base_expanded_template))
        if dir_path.is_dir():
          for item in dir_path.rglob('*'):
            if item.is_file(): discovered_files.add(item.resolve()) # Added .resolve()
      except ValueError as e: log.warning(f"strftime error for template '{folder_template_str}' with date {current_date}: {e}.")
      except Exception as e: log.error(f"Error processing timeframe path for date {current_date}, template '{folder_template_str}': {e}")
  else:
    base_path_str = os.path.expanduser(os.path.expandvars(folder_template_str))
    if '%' not in base_path_str:
      literal_path = Path(base_path_str).resolve() # Added .resolve()
      if literal_path.is_file(): discovered_files.add(literal_path)
      elif literal_path.is_dir():
        for item in literal_path.rglob('*'):
          if item.is_file(): discovered_files.add(item.resolve()) # Added .resolve()
      else: log.debug(f"Literal path '{literal_path}' not found or not file/dir.")
    else: # Discovery mode with strftime
      log.debug(f"Attempting discovery for pattern '{base_path_str}'. This has simplified logic.")
      parts = base_path_str.split(os.sep); fixed_prefix_parts = []; pattern_start_idx = -1
      for i, part in enumerate(parts):
        if '%' in part: pattern_start_idx = i; break
        fixed_prefix_parts.append(part)
      
      current_search_paths = [Path(os.sep.join(fixed_prefix_parts)).resolve() if fixed_prefix_parts else Path('.').resolve()] # Added .resolve()
      if base_path_str.startswith(os.sep) and not fixed_prefix_parts: current_search_paths = [Path(os.sep).resolve()] # Added .resolve()

      if pattern_start_idx != -1:
        date_pattern_parts = parts[pattern_start_idx:]
        q = list(current_search_paths); final_level_dirs = []
        for depth, p_segment in enumerate(date_pattern_parts):
          next_q = []; is_last_segment = (depth == len(date_pattern_parts) - 1)
          while q:
            base = q.pop(0)
            if not base.is_dir(): continue
            try:
              for item_name in os.listdir(base):
                item_path = base / item_name
                if item_path.is_dir():
                  try:
                    datetime.datetime.strptime(item_name, p_segment) # Validate segment
                    if is_last_segment: final_level_dirs.append(item_path)
                    else: next_q.append(item_path)
                  except ValueError: pass 
            except OSError as e_ls: log.warning(f"Cannot list dir {base} during discovery: {e_ls}")
          q = next_q
          if not q and not is_last_segment and date_pattern_parts: break
        for final_dir in final_level_dirs:
          if final_dir.is_dir():
            for item in final_dir.rglob('*'):
              if item.is_file(): discovered_files.add(item.resolve()) # Added .resolve()
  if not discovered_files:
      log.info(f"No files discovered for template '{folder_template_str}' (timeframe: {timeframe_days}).")
  return discovered_files


################################################################################
# MAIN PROGRAM:
################################################################################
def main():
  parser = argparse.ArgumentParser(
    description="File Parsing Plugin for LLview: Parses and aggregates log data based on YAML configuration.",
    formatter_class=argparse.RawTextHelpFormatter
  )
  parser.add_argument("--config", required=True, type=Path, help="Path to YAML config file.")
  parser.add_argument("--loglevel", default=LOG_CONFIG_DEFAULTS['level'],
                      choices=['DEBUG', 'INFO', 'WARNING', 'ERROR', 'CRITICAL'],
                      type=str.upper, help="Set logging level (default: INFO).")
  parser.add_argument("--outfolder", type=Path, default=None,
                      help="Base output folder for relative output paths.")
  args = parser.parse_args()

  main_logger_name = "llview_fpp" 
  log = log_init(main_logger_name, args.loglevel)
  log.info(f"Starting File Parsing Plugin for LLview with config: {args.config}")

  if args.outfolder:
    try:
      args.outfolder.mkdir(parents=True, exist_ok=True)
      log.info(f"Using output folder for relative paths: {args.outfolder.resolve()}")
    except OSError as e:
      log.error(f"Could not create/access output folder '{args.outfolder}': {e}. Exiting.")
      sys.exit(1)

  try:
    with args.config.open('r', encoding='utf-8') as f: full_config = yaml.safe_load(f)
  except FileNotFoundError: log.critical(f"Config file '{args.config}' not found. Exiting."); sys.exit(1)
  except yaml.YAMLError as e: log.critical(f"Error parsing YAML '{args.config}': {e}. Exiting."); sys.exit(1)
  except Exception as e: log.critical(f"Error reading config '{args.config}': {e}. Exiting.", exc_info=True); sys.exit(1)

  if not full_config or not isinstance(full_config, dict):
    log.critical("Config is empty or not a valid top-level dictionary. Exiting."); sys.exit(1)

  # Looping over the different outer-level file groups defined in the configuration
  for group_name, group_config in full_config.items():
    if not isinstance(group_config, dict):
      log.warning(f"Skipping group '{group_name}': config is not a dictionary."); continue

    log.info(f"Processing group: '{group_name}'")
    group_start_time = time.time()

    source_folder_template = group_config.get('folder')
    metrics_defs = group_config.get('metrics')
    output_defs = group_config.get('output')

    if not source_folder_template: log.warning(f"Group '{group_name}' missing 'folder'. Skipping."); continue
    if not metrics_defs: log.warning(f"Group '{group_name}' missing 'metrics'. Skipping."); continue
    if not output_defs: log.warning(f"Group '{group_name}' missing 'output'. Skipping processing for this group."); continue

    timeframe_days = group_config.get('timeframe', 0) 
    all_discoverable_files: Set[Path] = set()
    try: all_discoverable_files = discover_files(source_folder_template, timeframe_days, log)
    except Exception as e: log.error(f"Error discovering files for '{group_name}': {e}. Skipping group.", exc_info=True); continue
    log.info(f"Discovered {len(all_discoverable_files)} potential files for '{group_name}'.")

    processed_files_tracker_path_str = group_config.get('processed_files')
    seen_files: Set[Path] = set(); expanded_tracker_path: Optional[Path] = None
    if processed_files_tracker_path_str:
      try: # Ensure tracker path expansion itself doesn't crash
        expanded_tracker_path = expand_path_template(processed_files_tracker_path_str).resolve() # Added .resolve()
        if expanded_tracker_path.exists():
          try:
            with expanded_tracker_path.open('r', encoding='utf-8') as sf:
              # Resolve paths from tracker for accurate comparison
              paths_in_tracker = {Path(line.strip()).resolve() for line in sf if line.strip()}
            seen_files = paths_in_tracker & all_discoverable_files # Intersect with current reality
            log.debug(f"Loaded {len(paths_in_tracker)} from tracker '{expanded_tracker_path}'. {len(seen_files)} are still discoverable.")
          except Exception as e_read: # More specific error for reading tracker content
            log.error(f"Error reading tracker file content '{expanded_tracker_path}': {e_read}. Assuming no files seen.", exc_info=True)
            seen_files = set()
        else: log.info(f"Tracker file '{expanded_tracker_path}' not found. All discovered files are new.")
      except Exception as e_path: # Error related to tracker path itself (e.g., invalid template)
          log.error(f"Error with tracker path '{processed_files_tracker_path_str}': {e_path}. Assuming no files seen.", exc_info=True)
          seen_files = set() # Reset seen_files if tracker path is problematic
          expanded_tracker_path = None # Ensure it's None if path expansion failed

    new_files_to_process = sorted(list(all_discoverable_files - seen_files))
    log.info(f"Found {len(new_files_to_process)} new files to process for '{group_name}'.")

    # Instantiate aggregator once per group, regardless of new files for LML pstat generation
    output_aggregator = OutputAggregator(group_name, group_config, metrics_defs, args.outfolder, log)
    # files_processed_ok_this_run will store files that complete parsing without critical errors.
    files_processed_ok_this_run: Set[Path] = set() 

    if not new_files_to_process:
      log.info(f"No new files to process for group '{group_name}'.")
      # Even if no new files, update tracker if `all_discoverable_files` (current reality)
      # is different from what `seen_files` implies was tracked.
      # This prunes tracker of files that no longer exist or match discovery criteria.
      if expanded_tracker_path: # Check if tracker is configured
        # Determine what should be in the tracker: only files that were seen AND are still discoverable
        files_to_keep_in_tracker = seen_files & all_discoverable_files
        # Only write if the effective content of the tracker for this group would change
        if files_to_keep_in_tracker != seen_files: # `seen_files` is already `initial_tracker_content & all_discoverable_files`
            try:
                expanded_tracker_path.parent.mkdir(parents=True, exist_ok=True)
                with expanded_tracker_path.open('w', encoding='utf-8') as sf_update:
                    for fname_path in sorted(list(files_to_keep_in_tracker)): 
                        sf_update.write(str(fname_path) + '\n')
                log.debug(f"Tracker '{expanded_tracker_path}' updated (pruned non-discoverable entries) for '{group_name}'.")
            except Exception as e: 
                log.error(f"Error updating tracker '{expanded_tracker_path}' during pruning: {e}", exc_info=True)
        else:
            log.debug(f"Tracker '{expanded_tracker_path}' content for '{group_name}' effectively unchanged. No pruning write needed.")
      # Skip the file processing loop, but output generation will still occur later
    else: # There ARE new files to process
      log.info(f"Found {len(new_files_to_process)} new files to process for '{group_name}'.") # This log was already there
      for filepath in new_files_to_process:
        log.info(f"Processing file: {filepath}")
        try:
          parser_instance = FileParser(filepath, group_config, log)
          raw_file_records = parser_instance.parse_file_content()
          if raw_file_records:
            processed_records_from_file = parser_instance.process_transformed_records(raw_file_records)
            if processed_records_from_file: output_aggregator.add_records(processed_records_from_file)
          files_processed_ok_this_run.add(filepath.resolve()) 
        except Exception as e: 
          log.error(f"Unexpected error processing file {filepath}: {e}. Skipping this file for outputs and tracker update.", exc_info=True)
          continue 














    #   if expanded_tracker_path and all_discoverable_files != seen_files:
    #     try:
    #       expanded_tracker_path.parent.mkdir(parents=True, exist_ok=True)
    #       with expanded_tracker_path.open('w', encoding='utf-8') as sf_update:
    #         # Write only files that are *both* in 'seen_files' (from tracker) AND 'all_discoverable_files'
    #         files_to_keep_in_tracker = seen_files & all_discoverable_files
    #         for fname_path in sorted(list(files_to_keep_in_tracker)): sf_update.write(str(fname_path) + '\n')
    #       log.debug(f"Tracker '{expanded_tracker_path}' updated (pruned non-discoverable entries) for '{group_name}'.")
    #     except Exception as e: log.error(f"Error updating tracker '{expanded_tracker_path}' during pruning: {e}", exc_info=True)
    #   log.info(f"Finished group '{group_name}' in {time.time() - group_start_time:.2f}s."); continue

    # # Instantiate aggregator once per group
    # output_aggregator = OutputAggregator(group_name, group_config, metrics_defs, args.outfolder, log)
    
    # for filepath in new_files_to_process:
    #   log.info(f"Processing file: {filepath}")
    #   try:
    #     parser_instance = FileParser(filepath, group_config, log)
    #     raw_file_records = parser_instance.parse_file_content()
    #     if raw_file_records:
    #       processed_records_from_file = parser_instance.process_transformed_records(raw_file_records)
    #       if processed_records_from_file: output_aggregator.add_records(processed_records_from_file)
    #     files_processed_ok_this_run.add(filepath.resolve()) # Mark as processed for tracker update, use resolved path
    #   except Exception as e: 
    #     log.error(f"Unexpected error processing file {filepath}: {e}. Skipping this file for outputs and tracker update.", exc_info=True)
    #     # Do not add to files_processed_ok_this_run, so it's not added to tracker as "seen" if it critically failed.
    #     # It might be retried in a subsequent run if it's still discoverable.
    #     continue # Skip to next file














    
    # Generate outputs REGARDLESS of whether new files were processed (for LML pstat)
    output_aggregator.generate_outputs(group_start_time) 

    # Update tracker with all files that should now be considered "seen"
    # This covers both initial `seen_files` and `files_processed_ok_this_run`
    if expanded_tracker_path:
      try:
        # Files to be in tracker:
        #   1. Files already seen from previous runs that are still discoverable (`seen_files`).
        #   2. New files successfully processed in *this* run (`files_processed_ok_this_run`).
        # All paths should be resolved.
        updated_seen_files = seen_files | files_processed_ok_this_run
        
        # Prune against current discoverability one last time, although `files_processed_ok_this_run`
        # should already be from `all_discoverable_files`, and `seen_files` was intersected at start.
        # This is more of a safeguard.
        final_files_for_tracker = updated_seen_files & all_discoverable_files

        # Only write if the content would actually change compared to initial `seen_files`
        # plus the newly processed ones.
        # The initial `seen_files` were those from tracker AND discoverable.
        # `final_files_for_tracker` is the new complete set.
        if final_files_for_tracker != seen_files: # If set of tracked files changed
            expanded_tracker_path.parent.mkdir(parents=True, exist_ok=True)
            with expanded_tracker_path.open('w', encoding='utf-8') as sf_write:
              for fname_path in sorted(list(final_files_for_tracker)): 
                sf_write.write(str(fname_path) + '\n')
            log.info(f"Updated tracker '{expanded_tracker_path}' with {len(final_files_for_tracker)} entries for '{group_name}'.")
        else:
            log.debug(f"Tracker '{expanded_tracker_path}' content for '{group_name}' remains effectively unchanged. No write performed.")
      except Exception as e: 
        log.error(f"Error during tracker update for '{expanded_tracker_path}' for '{group_name}': {e}", exc_info=True)

    log.info(f"Finished group '{group_name}' in {time.time() - group_start_time:.2f}s.")
  log.info("File Parsing Plugin for LLview finished all groups.")

if __name__ == "__main__":
  main()