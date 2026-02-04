# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

from math import floor,log10               # Ceiling, floor of integer division, and log in base 10
import datetime 
import gc
import sys
import re

def replace_vars(string,config_dict):
  """
  This function replaces string-keys between '#<key>#' with
  values given in config_dict[<key>] and returns the new string. 
  It has the possibility to remove pieces inside 
  '(<to_remove>)' and to substitute strings between '["from","to"]', e.g.:
  - string = http://address.de/#system(-dc)#/
  For config_dict['system']='jureca-dc', the returned string 
  will be:
  http://address.de/jureca/
  - string = http://address.de/#system[ ,_]]#/
  For config_dict['system']='juwels booster', the returned string 
  will be:
  http://address.de/juwels_booster/
  """
  # Getting all keywords in-between '#(...)#'
  keywords = re.findall(r'#(.*?)#',string)
  for keyword in keywords:
    # Getting all words in-between '(...)' to remove
    remove_keys = re.findall(r'\((.*?)\)',keyword)
    key = keyword
    # Removing the 'remove items' from the 'key' string
    for remove_key in remove_keys:
      key = keyword.replace(f"({remove_key})","")
    replace_keys = re.findall(r'\[(.*?)\]',key)
    # Removing the 'replace items' from the 'key' string and splitting string in the `,`
    for i,replace_key in enumerate(replace_keys):
      key = key.replace(f"[{replace_key}]","")
      replace_keys[i] = replace_key.split(",")
    # Getting the original element to replace
    to_substitute = config_dict[key].lower()
    # Removing strings
    for remove_key in remove_keys:
      to_substitute = to_substitute.replace(f"{remove_key}","")
    # Replacing strings
    for replace_key in replace_keys:
      to_substitute = to_substitute.replace(replace_key[0],replace_key[1])
    string = string.replace(f"#{keyword}#",to_substitute)
  return string


def get_obj_size(obj):
  """ 
  Tool to get object size
  Obtained from:
  https://stackoverflow.com/a/53705610/3142385 
  """
  marked = {id(obj)}
  obj_q = [obj]
  sz = 0

  while obj_q:
      sz += sum(map(sys.getsizeof, obj_q))

      # Lookup all the object referred to by the object in obj_q.
      # See: https://docs.python.org/3.7/library/gc.html#gc.get_referents
      all_refr = ((id(o), o) for o in gc.get_referents(*obj_q))

      # Filter object that are already marked.
      # Using dict notation will prevent repeated objects.
      new_refr = {o_id: o for o_id, o in all_refr if o_id not in marked and not isinstance(o, type)}

      # The new obj_q will be the ones that were not marked,
      # and we will update marked with their ids so we will
      # not traverse them again.
      obj_q = new_refr.values()
      marked.update(new_refr.keys())

  return sz


def format_float_string(string,fmt):
  """ 
  Return a formatted string from a float, or an empty string if it fails
  """
  try:
    return ("{"+f"s:.{fmt}"+"}").format(s=float(string))
  except:
    return string


def floor_to_power2(x):
  """ 
  Return the highest power of 2 below x
  """
  return 1<<(x-2).bit_length()-1

def floor_to_power10(x):
  """ 
  Return the highest power of 10 below x
  """
  return 10**floor(log10(x))

def round_time(dt=None, date_delta=datetime.timedelta(minutes=1), to='average'):
  """
  Round a datetime object to a multiple of a timedelta
  dt : datetime.datetime object, default now.
  dateDelta : timedelta object, we round to a multiple of this, default 1 minute.
  from:  http://stackoverflow.com/questions/3463930/how-to-round-the-minute-of-a-datetime-object-python
  """
  round_to = date_delta.total_seconds()
  if dt is None:
      dt = datetime.datetime.now()
  seconds = (dt - dt.min).seconds

  if seconds % round_to == 0 and dt.microsecond == 0:
      rounding = (seconds + round_to / 2) // round_to * round_to
  else:
      if to == 'up':
          # // is a floor division, not a comment on following line (like in javascript):
          rounding = (seconds + dt.microsecond/1000000 + round_to) // round_to * round_to
      elif to == 'down':
          rounding = seconds // round_to * round_to
      else:
          rounding = (seconds + round_to / 2) // round_to * round_to
  return dt + datetime.timedelta(0, rounding - seconds, - dt.microsecond)
