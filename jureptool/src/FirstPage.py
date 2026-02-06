# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

from matplotlib.dates import DateFormatter                 # Library to format date
from matplotlib.patches import Rectangle                   # Rectangle shapes
from matplotlib.lines import Line2D                        # 2D lines

from tools import format_float_string
from AddPage import AddEmptyPage
from Nodelist import AddRectangles

from GenerateHTML import CreateFirstTables,CreateNodelist
from PlotlyFigs import CreateOverviewFig

def AverageUsageBar(x,y,str,fig,config,avg):
  """
  Average usage bar
  """
  fig.text(x+0.01,y+0.20,f"Average\n{str} Usage", ha='center', color='black', va='center', fontweight='bold')
  fig.patches.append(Rectangle((x,y),0.020,0.180,lw=0.5, ec="black", fc="None",transform=fig.transFigure))
  ax = fig.add_axes([x,y, 0.020,min(0.00180*max(avg,0),0.180)])
  ax.set_axis_off()
  fig.text(x+0.005,y+0.13,f"\n{avg:.1f}%", ha='center', fontsize=config['appearance']['smallfont'], fontweight='bold', rotation=90)
  ax.imshow(config['appearance']['gradient'],aspect='auto',cmap=config['appearance']['traffic_light_cmap'], origin='lower', vmin=0.0, vmax=(100.0/avg if avg>=1.0 else 100.0))
  return


def FirstPage(pdf,data,config,df_overview,time_range,page_num,tocentries,num_cpus,num_gpus,gpus,nl_config,nodedict,error_nodes,data_manager):
  """
  Creates first page in job report
  """
  overview_fig = ""
  first_page_html = ""
  navbar = ""
  with AddEmptyPage(pdf,page_num,config,first=True) as page:
    page.fig.text(0.50,0.960,f"{data['job']['system'].upper().replace('_',' ')} Job Report", fontsize=config['appearance']['hugefont'], color='black', fontweight='bold', va='center', ha='center')

    patches = []          # (x0, y0)(lower left), width, height
    patches.append(Rectangle((0.060, 0.918), 0.880, 0.022,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Jobid
    patches.append(Rectangle((0.060, 0.827), 0.360, 0.091,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Job runtime
    patches.append(Rectangle((0.060, 0.785), 0.360, 0.042,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Queue
    patches.append(Rectangle((0.420, 0.785), 0.520, 0.133,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Job performance metrics
    patches.append(Rectangle((0.060, 0.763), 0.880, 0.022,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Command
    patches.append(Rectangle((0.060, 0.691), 0.880, 0.072,lw=0.5, ec="black", fc="None", transform=page.fig.transFigure, figure=page.fig)) # Job I/O statistics
    gpu_section_size = 0.0
    if gpus:
      gpu_section_size = 0.041
      patches.append(Rectangle((0.060, 0.650),0.880,gpu_section_size,lw=0.5, ec="black", fc="None",transform=page.fig.transFigure, figure=page.fig)) # Job GPU statistics
    ierr = 0
    if config['finished']:
      if config['error']:
        ierr = 1
      patches.append(Rectangle((0.060, 0.651-gpu_section_size-ierr*0.018-config['energy']*0.018),0.880,0.040+ierr*0.018+config['energy']*0.018,lw=0.5, ec="black", fc="None",transform=page.fig.transFigure, figure=page.fig)) # Job finalization report
    patches.append(Rectangle((0.060, 0.315-0.011*len(tocentries)),0.880,0.008+0.011*len(tocentries),lw=0.5, ec="black", fc="None",transform=page.fig.transFigure, figure=page.fig)) # Table of contents
    page.fig.patches.extend(patches)

    page.fig.text(0.110,0.929,"Job ID: ", ha='right',  color='black', va='center')
    page.fig.text(0.110,0.929,data['job']["jobid"], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.225,0.929,"User: ", ha='right',  color='black', va='center')
    page.fig.text(0.225,0.929,data['job']["owner"], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.470,0.929,"Project: ", ha='right',  color='black', va='center')
    page.fig.text(0.470,0.929,f"{str(data['job']['account']):.26s}", ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.730,0.929,"Job Name: ", ha='right',  color='black', va='center')
    page.fig.text(0.730,0.929,f"{str(data['job']['name']):.26s}", ha='left',  color='black', va='center', fontweight='bold')

    page.fig.text(0.070,0.907,"Runtime: ", ha='left',  color='black', va='center', style='italic', fontweight='bold')
    page.fig.text(0.160,0.907,data['job']['runtimehm'], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.226,0.907,r"$\rightarrow$ {}% of Wall: {}".format(data['job']['runtimeperc'],data['job']['wallhm']), ha='left',  color='black', va='center')

    page.fig.text(0.070,0.892,"Submit Time: ", ha='left',  color='black', va='center')
    page.fig.text(0.200,0.892,data['job']["queuedate"], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.375,0.892,f"{data['job']['waittime'].strip()}\nin queue", ha='center',  color='black', va='top')

    page.fig.text(0.070,0.878,"Start Time: ", ha='left',  color='black', va='center')
    page.fig.text(0.200,0.878,data['job']["starttime"], ha='left',  color='black', va='center', fontweight='bold')

    if config['finished']:
      page.fig.text(0.070,0.864,"End Time: ", ha='left',  color='black', va='center')
      page.fig.text(0.200,0.864,data['job']['updatetime'], ha='left',  color='black', va='center', fontweight='bold')
    else:
      page.fig.text(0.200,0.864,"(Running)", ha='left',  color='darkgoldenrod', va='center', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.070,0.850,"Last Update: ", ha='left',  color='black', va='center')
    page.fig.text(0.200,0.850,data['job']['lastupdate'], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.070,0.836,"Estimated End Time: ", ha='left',  color='black', va='center')
    page.fig.text(0.200,0.836,data['job']['estendtime'], ha='left',  color='black', va='center')

    page.fig.text(0.070,0.820,"Queue: ", ha='left',  color='black', va='center')
    page.fig.text(0.190,0.820,data['job']['queue'], ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.070,0.806,"Job Size, #Nodes: ", ha='left',  color='black', va='center')
    page.fig.text(0.200,0.806,num_cpus, ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.270,0.806,"#Data Points: ", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.350,0.806,data["num_datapoints"]["ld_ndps"], ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
    if gpus:
      page.fig.text(0.070,0.792,"Job Size, #GPUs: ", ha='left',  color='black', va='center')
      page.fig.text(0.200,0.792,num_gpus, ha='left',  color='black', va='center', fontweight='bold')
      page.fig.text(0.270,0.792,"#Data Points: ", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.350,0.792,data["num_datapoints"]["gpu_ndps"], ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])

    page.fig.text(0.435,0.907,"Job Performance Metrics", ha='left',  color='black', va='center', fontweight='bold')
    page.fig.text(0.690,0.907,"Min.", ha='right',  color='black', va='center', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.780,0.907,"Avg.", ha='right',  color='black', va='center', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.870,0.907,"Max.", ha='right',  color='black', va='center', fontsize=config['appearance']['smallfont'])

    if data['num_datapoints']['cores_ndps']>0:
      # If core usage metrics is available
      data['cpu']['usage'] = data['cpu']['usage_avg']
    else:
      # If no core usage metrics is available, use CPU Load
      data['cpu']['usage_min'] = "-"
      data['cpu']['usage_avg'] = "-"
      data['cpu']['usage_max'] = "-"
      # Values to use on the colorbar on the left of the overview plot
      data['cpu']['usage'] = float(data['cpu']['load_avg'])*100.0/config['system'][data['job']['system'].upper()][data['job']['queue']]['cores']
    page.fig.text(0.450,0.894,"CPU Usage:", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.894,format_float_string(data['cpu']['usage_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.894,format_float_string(data['cpu']['usage_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.894,format_float_string(data['cpu']['usage_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.893,"%", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])

    page.fig.text(0.450,0.879,"Load (CPU-Nodes):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.879,format_float_string(data['cpu']['load_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.879,format_float_string(data['cpu']['load_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.879,format_float_string(data['cpu']['load_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.450,0.865,"Memory (CPU-Nodes):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.865,format_float_string(data['cpu']['used_mem_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.865,format_float_string(data['cpu']['used_mem_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.865,format_float_string(data['cpu']['used_mem_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.864,"MiB", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])

    page.fig.text(0.450,0.851,"Interconnect Traffic (in):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.851,format_float_string(data['fabric']['mbin_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.851,format_float_string(data['fabric']['mbin_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.851,format_float_string(data['fabric']['mbin_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.85,"MiB/s", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.450,0.836,"Interconnect Traffic (out):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.836,format_float_string(data['fabric']['mbout_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.836,format_float_string(data['fabric']['mbout_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.836,format_float_string(data['fabric']['mbout_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.835,"MiB/s", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.450,0.822,"Interconnect Packets (in):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.822,format_float_string(data['fabric']['pckin_min'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.822,format_float_string(data['fabric']['pckin_avg'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.822,format_float_string(data['fabric']['pckin_max'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.821,"pck/s", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.450,0.807,"Interconnect Packets (out):", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.807,format_float_string(data['fabric']['pckout_min'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.807,format_float_string(data['fabric']['pckout_avg'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.807,format_float_string(data['fabric']['pckout_max'],"0f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.806,"pck/s", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])

    page.fig.text(0.450,0.792,"Node Power:", ha='left',  color='black', va='center')
    page.fig.text(0.690,0.792,format_float_string(data['energy']['pwr_nd_min'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.780,0.792,format_float_string(data['energy']['pwr_nd_avg'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.870,0.792,format_float_string(data['energy']['pwr_nd_max'],"2f"), ha='right',  color='black', va='center', fontweight='bold')
    page.fig.text(0.880,0.791,"W", ha='left',  color='black', va='center', style='italic', fontsize=config['appearance']['smallfont'])

    if data['job']['command']=="(null)":
      page.fig.text(0.190,0.773,"Interactive Job", ha='left',  color='black', va='center', fontweight='bold')
    else:
      page.fig.text(0.070,0.773,"Submission Script:", ha='left',  color='black', va='center')
      page.fig.text(0.190,0.773,f"{data['job']['command'][:98] + '...' if len(data['job']['command'])>101 else data['job']['command']}", ha='left',  color='black', va='center', fontweight='bold')

    page.fig.text(0.071,0.752,"Job I/O Statistics", ha='left', fontweight='bold')
    page.fig.text(0.320,0.750,"Total Data Write", ha='right', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.450,0.750,"Total Data Read", ha='right', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.610,0.750,"Max. Data Rate/Node Write", ha='right', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.770,0.750,"Max. Data Rate/Node Read", ha='right', fontsize=config['appearance']['smallfont'])
    page.fig.text(0.930,0.750,"Max. Open-Close Rate/Node", ha='right', fontsize=config['appearance']['smallfont'])
    posy = 0.738
    
    for fs in ['home','project','scratch','fastdata']:
      page.fig.text(0.100,posy,f"${fs.upper()}:", ha='left')
      page.fig.text(0.295,posy,format_float_string(data['fs'][f'fs_{fs}_Mbw_sum'],"2f"), ha='right', fontweight='bold')
      page.fig.text(0.320,posy,"MiB", ha='right', style='italic', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.425,posy,format_float_string(data['fs'][f'fs_{fs}_Mbr_sum'],"2f"), ha='right', fontweight='bold')
      page.fig.text(0.450,posy,"MiB", ha='right', style='italic', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.575,posy,format_float_string(data['fs'][f'fs_{fs}_MbwR_max'],"2f"), ha='right', fontweight='bold')
      page.fig.text(0.610,posy,"MiB/s", ha='right', style='italic', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.735,posy,format_float_string(data['fs'][f'fs_{fs}_MbrR_max'],"2f"), ha='right', fontweight='bold')
      page.fig.text(0.770,posy,"MiB/s", ha='right', style='italic', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.900,posy,format_float_string(data['fs'][f'fs_{fs}_ocR_max'],"2f"), ha='right', fontweight='bold')
      page.fig.text(0.930,posy,"op./s", ha='right', style='italic', fontsize=config['appearance']['smallfont'])
      posy -= 0.012

    if gpus:
      if 'gpu_active_avg' in data['gpu']:
        # If ActiveSM metrics is available
        data['gpu']['usage_avg'] = data['gpu']['gpu_active_avg']
        data['gpu']['usage_or_util_text'] = 'Avg. GPU Active SM'
      else:
        # Values to use on the colorbar on the right of the overview plot
        data['gpu']['usage_avg'] = data['gpu']['gpu_util_avg']
        data['gpu']['usage_or_util_text'] = 'Avg. GPU Utilization'
      page.fig.text(0.071,0.680,"Job GPU Statistics", ha='left', fontweight='bold')
      page.fig.text(0.190,0.667,f"{data['gpu']['usage_or_util_text']}:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.190,0.667,f"{data['gpu']['usage_avg']:.2f}", ha='left', fontweight='bold')
      page.fig.text(0.245,0.667,"%", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.410,0.667,"Avg. Mem. Usage Rate:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.410,0.667,f"{float(data['gpu']['gpu_memur_avg']):.2f}", ha='left', fontweight='bold')
      page.fig.text(0.460,0.667,"%", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.610,0.667,"Avg. GPU Temp.:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.610,0.667,f"{float(data['gpu']['gpu_temp_avg']):.2f}", ha='left', fontweight='bold')
      page.fig.text(0.670,0.667,"°C", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.830,0.667,"Avg. GPU Power:  ", ha='right', fontsize=config['appearance']['smallfont']) 
      page.fig.text(0.830,0.667,f"{float(data['gpu']['gpu_pu_avg'])/1000.0:.2f}", ha='left', fontweight='bold')
      page.fig.text(0.899,0.667,"W", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.190,0.655,"Max. Clk Stream/Mem:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.190,0.655,f"{float(data['gpu']['gpu_sclk_max']):.0f}/{float(data['gpu']['gpu_clk_max']):.0f}", ha='left', fontweight='bold')
      page.fig.text(0.284,0.655,"MHz", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.410,0.655,"Max. Mem. Usage:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.410,0.655,f"{float(data['gpu']['gpu_memu_max'])/1024.0/1024.0:.2f}", ha='left', fontweight='bold')
      page.fig.text(0.492,0.655,"MiB", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.610,0.655,"Max. GPU Temp.:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.610,0.655,f"{float(data['gpu']['gpu_temp_max']):.2f}", ha='left', fontweight='bold')
      page.fig.text(0.670,0.655,"\260C", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.830,0.655,"Max. GPU Power:  ", ha='right', fontsize=config['appearance']['smallfont'])
      page.fig.text(0.830,0.655,f"{float(data['gpu']['gpu_pu_max'])/1000.0:.2f}", ha='left', fontweight='bold')
      page.fig.text(0.899,0.655,"W", ha='right', fontsize=config['appearance']['smallfont'])
    if config['finished']:
      if (data['rc']['rc_state'] == "COMPLETED"):
        color = 'green'
      elif ('FAIL' in data['rc']['rc_state']):
        color = 'red'
      else:
        color = 'goldenrod'
      page.fig.text(0.071,0.676-gpu_section_size,"Job Finalization Report", ha='left', fontweight='bold')
      page.fig.text(0.320,0.676-gpu_section_size,"Job State: ", ha='right',  color='black')
      page.fig.text(0.320,0.676-gpu_section_size,data['rc']['rc_state'], ha='left', color=color,fontweight='bold')
      page.fig.text(0.600,0.676-gpu_section_size,"Return Code: ", ha='right',  color='black')
      page.fig.text(0.600,0.676-gpu_section_size,data['rc']['rc_rc'], ha='left', color=color,fontweight='bold')
      page.fig.text(0.750,0.676-gpu_section_size,"Signal Number: ", ha='right',  color='black')
      page.fig.text(0.750,0.676-gpu_section_size,data['rc']['rc_signr'], ha='left', color=color,fontweight='bold')
      if ierr == 1:
        page.fig.text(0.071,0.659-gpu_section_size,"Node System Error Report", ha='left', fontweight='bold')
        page.fig.text(0.320,0.659-gpu_section_size,"# Msgs: ", ha='right',  color='black')
        page.fig.text(0.320,0.659-gpu_section_size,data['rc']['nummsgs'], ha='left', color='red',fontweight='bold')
        page.fig.text(0.450,0.659-gpu_section_size,"# Nodes: ", ha='right',  color='black')
        page.fig.text(0.450,0.659-gpu_section_size,data['rc']['numerrnodes'], ha='left', color='red',fontweight='bold')
        if data['rc']['err_type']:
          page.fig.text(0.480, 0.659-gpu_section_size, data['rc']['err_type'], ha='left', color='red', fontweight='bold')
        page.fig.text(0.600,0.659-gpu_section_size,r"$\rightarrow$ detailed list of error messages at end of report", ha='left', color='black',fontsize=config['appearance']['tinyfont'])
      page.fig.text(0.500,0.659-gpu_section_size-ierr*0.017,r"This job has used approximately: {} nodes $\times$ {} cores $\times$ {:.3f} hours $=$ {:.2f} core-h".format(num_cpus,config['system'][data['job']['system'].upper()][data['job']['queue']]['cores'],float(data['job']['runtime']),num_cpus*config['system'][data['job']['system'].upper()][data['job']['queue']]['cores']*float(data['job']['runtime'])), ha='center', fontweight='bold', color='black')
      if config['energy']:
        page.fig.text(0.500,0.644-gpu_section_size-ierr*0.017,f"Estimated energy used by this job, integrated from the node power snapshots: {data['energy']['en_nd_all_sum']:.2f} M-Joules = {data['energy']['en_nd_all_sum']*0.2778:.2f} kWh", ha='center', fontweight='bold', color='black')
    else: # if job is still running:
      if data['job']['wallh'] != 'UNLIMITED':
        page.fig.text(0.500,0.676-gpu_section_size,r"This job will use approximately {} nodes $\times$ {} cores $\times$ {:.3f} hours $=$ {:.2f} core-h for the specified walltime (up to now: {:.2f})".format(num_cpus,config['system'][data['job']['system'].upper()][data['job']['queue']]['cores'],float(data['job']['wallh']),num_cpus*config['system'][data['job']['system'].upper()][data['job']['queue']]['cores']*float(data['job']['wallh']),num_cpus*config['system'][data['job']['system'].upper()][data['job']['queue']]['cores']*float(data['job']['runtime']) ), ha='center', fontweight='bold', color='black')
      else:
        page.fig.text(0.500,0.676-gpu_section_size,r"This job has used approximately {} nodes $\times$ {} cores $\times$ {:.3f} hours $=$ {:.2f} core-h up to now".format(num_cpus,config['system'][data['job']['system'].upper()][data['job']['queue']]['cores'],float(data['job']['runtime']),num_cpus*config['system'][data['job']['system'].upper()][data['job']['queue']]['cores']*float(data['job']['runtime']) ), ha='center', fontweight='bold', color='black')
      if config['energy']:
        page.fig.text(0.500,0.661-gpu_section_size,f"Estimated energy used by this job up to now, integrated from the node power snapshots: {data['energy']['en_nd_all_sum']:.2f} M-Joules = {data['energy']['en_nd_all_sum']*0.2778:.2f} kWh", ha='center', fontweight='bold', color='black')

    # Graphic on first page
    if df_overview:
      # CPU Average usage bar
      AverageUsageBar(0.060,0.365,"CPU",page.fig,config,data['cpu']['usage'])
      if gpus:
        # GPU Average usage bar
        AverageUsageBar(0.920,0.365,"GPU",page.fig,config,data['gpu']['usage_avg'])

      # Overview plot:
      legends = {}

      p1 = False
      p2 = False

      # left graph
      overview_fig = None
      if 'left' in df_overview and df_overview['left']:
        page.ax1 = page.fig.add_axes((0.130,0.365, 0.740,0.180), zorder=4)
        page.ax1.set_title("Job-Usage Overview", fontweight='bold')
        page.ax1.yaxis.tick_left()
        page.ax1.yaxis.set_label_position('left') 

        # Setting up left axis
        if '_label' in config['plots']['_overview']['left']:
          page.ax1.set_ylabel(config['plots']['_overview']['left']['_label'],fontsize=config['appearance']['smallfont'], color=config['appearance']['colors_cmap'][7])
        page.ax1.tick_params(axis='y', colors=config['appearance']['colors_cmap'][7])
        
        # Plotting
        miny = float('inf')
        maxy = float('-inf')
        for x,y,legend in zip(df_overview['left']['x'],df_overview['left']['y'],df_overview['left']['legend']):
          p1 = page.ax1.step(x,y, color=config['appearance']['colors_cmap'][7], marker='o', ms=2, where='mid', zorder=5)
          legends[legend] = p1[0]
          miny = min(*y,miny)
          maxy = max(*y,maxy)

        # Defining range
        if '_range' in config['plots']['_overview']['left']:
          config['plots']['_overview']['left']['_range'] = [
            miny*1.1 if miny < config['plots']['_overview']['left']['_range'][0] else config['plots']['_overview']['left']['_range'][0],
            maxy*1.1 if maxy > config['plots']['_overview']['left']['_range'][1] else config['plots']['_overview']['left']['_range'][1]
          ]
          page.ax1.set_ylim(config['plots']['_overview']['left']['_range'])

      # right graph
      if 'right' in df_overview and df_overview['right']:
        page.ax2 = page.fig.add_axes((0.130,0.365, 0.740,0.180), frame_on=False, sharex=page.ax1, zorder=4)
        if not df_overview['left']: page.ax2.set_title("Job-Usage Overview", fontweight='bold')
        page.ax2.yaxis.tick_right()
        page.ax2.yaxis.set_label_position('right')
        if '_label' in config['plots']['_overview']['right']:
          page.ax2.set_ylabel(config['plots']['_overview']['right']['_label'],fontsize=config['appearance']['smallfont'], color=config['appearance']['colors_cmap'][0])
        page.ax2.tick_params(axis='y', colors=config['appearance']['colors_cmap'][0])

        # Plotting
        miny = float('inf')
        maxy = float('-inf')
        for x,y,legend in zip(df_overview['right']['x'],df_overview['right']['y'],df_overview['right']['legend']):
          p2 = page.ax2.step(x,y, color=config['appearance']['colors_cmap'][0], marker='o', ms=2, where='mid', zorder=5)
          legends[legend] = p2[0]
          miny = min(*y,miny)
          maxy = max(*y,maxy)

        # Defining range
        if '_range' in config['plots']['_overview']['right']:
          config['plots']['_overview']['right']['_range'] = [
            miny*1.1 if miny < config['plots']['_overview']['right']['_range'][0] else config['plots']['_overview']['right']['_range'][0],
            maxy*1.1 if maxy > config['plots']['_overview']['right']['_range'][1] else config['plots']['_overview']['right']['_range'][1]
          ]
          page.ax2.set_ylim(config['plots']['_overview']['right']['_range'])

      # Add legends
      if (p1 or p2):
        ax = (page.ax2 if p2 else page.ax1)
        assert ax is not None
        leg = ax.legend(legends.values(), legends.keys(),fontsize=config['appearance']['smallfont'],ncol=1,loc=('center right' if gpus and (data['gpu']['usage_avg'] > 60) else 'lower center'), facecolor='white', labelspacing=0.3, handletextpad=0.2, columnspacing=0.4)
        leg.set_zorder(100)
        assert page.ax1 is not None
        page.ax1.set_xlim(time_range)
        page.ax1.xaxis.set_major_formatter(DateFormatter('%d/%m/%y\n%H:%M:%S'))
        if config['html'] or config['gzip']:
          overview_fig = CreateOverviewFig(config,data,time_range,df_overview,gpus,data_manager)
    
    # Table of contents
    posy = 0.330
    page.fig.text(0.5,posy,f"Table of Contents ({page_num} {('Pages' if page_num != 1 else 'Page')})", ha='center', va='center', fontweight='bold')
    posy -=0.020
    for entry, pg in tocentries.items():
      page.fig.add_artist(Line2D([0.08, 0.90], [posy, posy], color='k', lw=0.3, ls='dotted'))
      page.fig.text(0.07,posy,f"{entry}", ha='left', style='italic',bbox=dict(edgecolor='none', facecolor='white',pad=0))
      page.fig.text(0.925,posy,f"{pg}", ha='right', style='italic')
      posy -= 0.011

    posy -= 0.03
    # Add nodelistTable of contents
    nodelist_html = ""
    if nl_config['firstpage']:
      nl_config['top']=posy

      page.fig.text(0.5,nl_config['top']+0.01, \
                    f"Node List", \
                    ha='center',  \
                    color='black', \
                    fontsize=config['appearance']['normalfont']+1,\
                    fontweight='bold',\
                    va='center')

      numcpu = 0
      numgpu = 0

      if config['html'] or config['gzip']:
        nodelist_html = CreateNodelist(config,gpus,nl_config,nodedict,error_nodes)

      AddRectangles(page.fig,config,numcpu,numgpu,gpus,nl_config,nodedict,error_nodes)

  if config['html'] or config['gzip']:
    first_page_html,navbar = CreateFirstTables(data,config,num_cpus,num_gpus,gpus,ierr)

  return first_page_html,overview_fig,navbar,nodelist_html
