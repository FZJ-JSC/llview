import json
import pandas as pd
import numpy as np
import datetime

class ReportDataManager:
  def __init__(self):
    # Dictionary to store the unique data arrays that will be injected into HTML
    self.shared_data = {}
    # Map of (tuple_data) -> key string
    # Used to check if a specific set of data has already been registered
    self.data_map = {} 
    self.counter = 0

  def register(self, data, prefix="col"):
    # Normalize inputs to Python List to ensure consistency across different source types
    if isinstance(data, (pd.Series, pd.Index)):
      # Handle Datetime objects in Pandas Series
      # We convert them to Strings to preserve the Server Time (Wall Clock)
      # This ensures the browser displays the exact time found in the logs, ignoring user timezone
      if pd.api.types.is_datetime64_any_dtype(data):
        data = data.astype(str)
      
      # Handle object-dtype columns that might contain timestamps mixed with other data
      elif data.dtype == 'object' and len(data) > 0 and isinstance(data.values[0], (pd.Timestamp, datetime.datetime)):
        data = data.astype(str)
      
      # Handle Timedelta objects (Durations)
      # Plotly expects numeric values for durations (e.g. milliseconds)
      # json.dumps cannot serialize Timedelta objects, so we convert to float
      elif pd.api.types.is_timedelta64_dtype(data):
        # Use vectorized division to convert to milliseconds
        data = data / np.timedelta64(1, 'ms')

      data = data.tolist()
    
    # Handle Numpy arrays
    elif isinstance(data, np.ndarray):
      if np.issubdtype(data.dtype, np.datetime64):
        data = data.astype(str)
      elif np.issubdtype(data.dtype, np.timedelta64):
        # Convert numpy timedelta to milliseconds (float)
        # We divide by a 1ms timedelta to get the float representation
        data = (data / np.timedelta64(1, 'ms')).tolist()
      
      data = data.tolist()
    
    # Final safety check to ensure we are working with a list
    if not isinstance(data, list):
      data = list(data)

    # Content Type Logic
    # We check the first element to see if we need to convert contents
    if len(data) > 0:
      first_el = data[0]
      
      # Check if the first element is a date/time object
      # If so, convert the entire list to strings to prevent JSON serialization errors
      if isinstance(first_el, (pd.Timestamp, datetime.datetime, np.datetime64)):
        data = [str(x) for x in data]
      
      # Check if the first element is a Timedelta (Duration)
      # Convert to milliseconds (float) so JSON can serialize it
      elif isinstance(first_el, (pd.Timedelta, datetime.timedelta, np.timedelta64)):
        data = [pd.Timedelta(x).total_seconds() * 1000 for x in data]

      # Note: For 2D arrays (lists of lists), we rely on the deduplication logic below
      # to handle the structure. We assume inner contents of 2D arrays are safe (numbers or strings).
    
    # Deduplication Logic
    # We convert the list to a Tuple to make it hashable (usable as a dictionary key)
    # This allows us to check if we have seen this exact dataset before
    try:
      # If data is a list of lists (2D), we must convert inner lists to tuples as well
      # This is required for Heatmap Z data or Hover Text matrices
      if len(data) > 0 and isinstance(data[0], list):
        data_tuple = tuple(tuple(sub) if isinstance(sub, list) else sub for sub in data)
      else:
        # Standard 1D list conversion
        data_tuple = tuple(data)
    except:
      # Fallback for unhashable types (rare, but safe to handle)
      # If we can't hash it, we just store it as a new unique entry
      key = f"{prefix}_{self.counter}"
      self.counter += 1
      self.shared_data[key] = data
      return key

    # Check if this data signature already exists in our map
    if data_tuple in self.data_map:
      # Return the existing key so the graph reuses the stored data
      return self.data_map[data_tuple]

    # If new, generate a unique key
    key = f"{prefix}_{self.counter}"
    self.counter += 1
    
    # Store the actual data for the JSON payload
    self.shared_data[key] = data
    # Map the tuple signature to this key for future lookups
    self.data_map[data_tuple] = key
    
    return key

  def get_json_payload(self):
    # Dumps the dictionary to a JSON string to be injected into the HTML variable
    return json.dumps(self.shared_data)