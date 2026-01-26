# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

from matplotlib.patches import Rectangle                   # Rectangle shapes
from matplotlib.dates import DateFormatter                 # Library to format date
from matplotlib.ticker import AutoMinorLocator
import matplotlib.transforms as transforms

from AddPage import AddEmptyPage
from GenerateHTML import CreateSystemErrorReport
from PlotlyFigs import CreateTimeline

def add_error_header(page,posy,data,config):
  """
  Adds initial error lines containin number or errors
  Returns final position to continue with error messages
  """
  page.fig.text(0.071,posy,"Node System Error Report", ha='left', fontweight='bold')
  posy -=0.012
  page.fig.text(0.300,posy,"# Msgs: ", ha='right',  color='black', fontsize=config['appearance']['smallfont'])
  page.fig.text(0.300,posy,data['rc']['nummsgs'], ha='left', color='red',fontweight='bold')
  page.fig.text(0.450,posy,"# Nodes: ", ha='right', color='black',fontsize=config['appearance']['smallfont'])
  page.fig.text(0.450,posy,data['rc']['numerrnodes'], ha='left', color='red',fontweight='bold')
  posy -=0.012
  page.fig.text(0.121,posy,"Error Messages:", ha='left', style='italic')
  posy -=0.020
  return posy, False

def write_error_line(page,error_line,posy,i,config):
  """
  Writes the error line in given y position and adds up the counter
  """
  page.fig.text(0.065,posy,error_line[:144], ha='left', family='monospace', fontsize=config['appearance']['tinyfont'], wrap=True)
  i += 1 # adds up number of printed lines
  posy -=0.012
  if len(error_line)>142:
    page.fig.text(0.065,posy,error_line[144:].lstrip(), ha='left', family='monospace', fontsize=config['appearance']['tinyfont'], wrap=True)
    i += 1 # adds up number of printed lines
    posy -=0.012
  return posy, i


def LastPages(pdf,data,config,page_num,timeline_df,time_range,error_lines,data_manager):
  """
  Creates Last pages (Finalization, Error messages)
  """
  system_report_html = ""
  if (config['html'] or config['gzip']) and config['error']:
    system_report_html = CreateSystemErrorReport(error_lines,data)
  error_header = True
  last_step_prev_page = -1
  for pg in range(config['timeline']['npages']):
    last_step_this_page = min( (pg+1)*config['timeline']['steps_per_page']-1,config['timeline']['nsteps']-1 )
    nsteps_this_page = last_step_this_page-last_step_prev_page
    timeline_df_this_page = timeline_df.iloc[last_step_prev_page+1:last_step_this_page+1]
    with AddEmptyPage(pdf,page_num,config) as page:
      page.add_header(data)
      # Adding Job timeline to illustrate different steps detailed in timeline_df
      size = min(nsteps_this_page*config['timeline']['barsize'],config['appearance']['max_timeline_size'])
      posy = 0.930 - size
      page.ax = page.fig.add_axes([0.100,posy, 0.607,size], zorder=4)
      page.ax.set_title("Timeline", fontweight='bold')
      # Configuring axes ticks, ranges and labels
      page.ax.yaxis.set_minor_locator(AutoMinorLocator(2))
      page.ax.yaxis.grid(color='gray', linestyle='-', alpha=0.4, which='minor')
      page.ax.tick_params(which='minor', left=False)
      page.ax.set_ylabel('Step')
      page.ax.set_ylim([nsteps_this_page-0.5,-0.5])
      page.ax.set_yticks(range(nsteps_this_page))
      # page.ax.set_yticklabels(timeline_df_this_page['step'])
      page.ax.tick_params(top=False, bottom=True, left=False, right=False, labelleft=True, labelbottom=True)
      page.ax.set_xlim(time_range)
      page.ax.xaxis.set_major_formatter(DateFormatter('%d/%m/%y\n%H:%M:%S'))
      for index, row in timeline_df_this_page.iterrows():
        # Plotting alternate lines
        # page.ax.axhspan(index-0.5,index+0.5, color=['black','white'][index%2], alpha=0.1, zorder=0)
        # Adding state 'st' as text at the right of the bar  
        page.ax.text(0.99, index-last_step_prev_page-1+0.05, row['name'], color='black', ha='right', va='center',fontsize=(config['appearance']['smallfont'] if nsteps_this_page<=90 else config['appearance']['tinyfont'] ), transform=page.ax.get_yaxis_transform())
        page.ax.text(1.01, index-last_step_prev_page-1+0.05, row['st'].replace("CANCELLED by","CANCELLED\nby"), color=row['edgecolor'], ha='left', va='center',fontsize=(config['appearance']['normalfont'] if nsteps_this_page<=90 else config['appearance']['smallfont'] ), fontweight='bold', transform=page.ax.get_yaxis_transform())
        # if (row['rc'] != 0) or (row['sig'] != 0):
        page.ax.text(0.94, index-last_step_prev_page-1+0.05, f"Return Code: {row['rc']}, Signal: {row['sig']}", ha='right', va='center', fontsize=config['appearance']['tinyfont'], color='k', transform=transforms.blended_transform_factory(page.fig.transFigure, page.ax.transData)) 
      page.ax.barh(timeline_df_this_page['step'], timeline_df_this_page['duration'], left=timeline_df_this_page['start_time'], color=timeline_df_this_page['color'], edgecolor=timeline_df_this_page['edgecolor'], linewidth=0.5)
      posy -= 0.030
      last_step_prev_page = last_step_this_page

      # If there is still space on the page, add error messages
      if config['error'] and config['empty_error_page'] and (pg == config['timeline']['npages']-1):
        posy -=0.012
        posy, error_header = add_error_header(page,posy,data,config)
        i = 0
        while error_lines:
          posy,i = write_error_line(page,error_lines.pop(0),posy,i,config)
          if posy < 0.070:
            break
        patches = []
        patches.append(Rectangle((0.060, posy),0.880,0.056+0.012*i,lw=0.5, ec="black", fc="None",transform=page.fig.transFigure, figure=page.fig)) # Jobid
        page.fig.patches.extend(patches)
  
  timeline_html = ""
  if (config['html'] or config['gzip']) and not timeline_df.empty:
    timeline_html = CreateTimeline(config,timeline_df,time_range,data_manager)

  # Add remaining error pages, if needed
  while error_lines:
    with AddEmptyPage(pdf,page_num,config) as page:
      page.add_header(data)
      posy = 0.928
      if error_header:
        posy,error_header = add_error_header(page,posy,data,config)
        i = 0
      while posy >= 0.070:
        posy,i = write_error_line(page,error_lines.pop(0),posy,i,config)
        if(len(error_lines) == 0):
          posy +=0.012
          break
      patches = []
      patches.append(Rectangle((0.060, posy),0.880,0.948-posy,lw=0.5, ec="black", fc="None",transform=page.fig.transFigure, figure=page.fig)) # Jobid
      page.fig.patches.extend(patches)
  
  return timeline_html,system_report_html
