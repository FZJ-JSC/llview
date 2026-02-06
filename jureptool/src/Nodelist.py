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
from matplotlib.colors import colorConverter

from AddPage import AddEmptyPage
from GenerateHTML import CreateNodelist

def AddRectangles(fig,config,numcpu,numgpu,gpus,nl_config,nodedict,error_nodes):
  """
  Creates the rectangles on a page
  """
  # Looping over each node and creating their rectangle and adding information
  patches = []
  idx = 0
  this_line = 0
  while nodedict:

    # Getting row and col index of node
    i = int(idx/nl_config['per_line'])
    j = idx%nl_config['per_line']
    if(j == 0):
      this_line = min(len(nodedict),nl_config['per_line'])

    # Getting first CPU number
    cpu = list(nodedict.keys())[0]
    # Poping it out from the dict
    specs= nodedict.pop(cpu)

    # Getting IC group and checking if it's already on the list
    try: 
      ic_info = specs.pop('IC')
    except KeyError:
      ic_info = {'-':[0.0,0.0,0.0]}
    ic = list(ic_info.keys())[0]
    color = list(ic_info.values())[0]

    # Build rectangle at position (xpos,ypos)
    ypos = nl_config['top']-nl_config['hsize']-(nl_config['hsize']+nl_config['hspace'])*i
    if (ypos < nl_config['bottom']):
      break
    xpos = 0.5-(this_line)*nl_config['wsize']/2-(this_line-1)*nl_config['wspace']/2+(nl_config['wsize']+nl_config['wspace'])*j
    patches.append(Rectangle((xpos, ypos),nl_config['wsize'],nl_config['hsize'],lw=0.5, ec=("red" if cpu in error_nodes else "black"), fc=tuple(color+[0.1]), transform=fig.transFigure, figure=fig))

    numcpu += 1

    # Writing CPU at position (xtext,ytext)
    xtext = xpos + nl_config['wsize']/2.0
    ytext = ypos + nl_config['hsize'] - 0.008
    fig.text(xpos+0.005,ytext, \
                  f"{numcpu:4d}", \
                  ha='left',  \
                  color='dimgray', \
                  fontsize=config['appearance']['tinyfont'],\
                  va='center')
    fig.text(xtext,ytext, \
                  f"{cpu}", \
                  ha='center',  \
                  color='black', \
                  fontweight='bold', \
                  fontsize=config['appearance']['smallfont'],\
                  va='center')

    # Writing GPUs at position (xtext,ytext)
    if gpus:
      ytext -= 0.002
      for gpu, spec in specs.items():
        numgpu += 1
        xtext = xpos
        ytext -= 0.007
        fig.text(xtext,ytext, \
                      f"{numgpu:4d}", \
                      ha='left',  \
                      color='dimgray', \
                      fontsize=config['appearance']['tinyfont']-1,\
                      va='center')
        xtext += 0.050
        fig.text(xtext,ytext, \
                      f"{gpu}: ", \
                      ha='right',  \
                      color='black', \
                      fontsize=config['appearance']['tinyfont']-1,\
                      fontweight='bold',\
                      va='center')
        fig.text(xtext,ytext, \
                      f"{spec}", \
                      ha='left',  \
                      color='black', \
                      fontsize=config['appearance']['tinyfont']-1,\
                      va='center')

    # Writing IC group at position (xtext,ytext)
    xtext = xpos + nl_config['wsize']/2.0
    ytext = ypos + 0.005
    fig.text(xtext,ytext, \
                  f"Interconnect group: {ic}", \
                  ha='center',  \
                  color=color, \
                  fontsize=config['appearance']['tinyfont'],\
                  va='center')
    idx += 1

  fig.patches.extend(patches)
  return numcpu,numgpu


def Nodelist(pdf,data,config,gpus,nl_config,nodedict,error_nodes,page_num):
  """
  Creates Nodelist
  """

  numcpu = 0
  numgpu = 0

  nodelist_html = ""
  if config['html'] or config['gzip']:
    nodelist_html = CreateNodelist(config, gpus, nl_config, nodedict, error_nodes)

  while nodedict:
    with AddEmptyPage(pdf,page_num,config) as page:
      page.add_header(data)

      page.fig.text(0.5,nl_config['top']+0.01, \
                    f"Node List", \
                    ha='center',  \
                    color='black', \
                    fontsize=config['appearance']['normalfont']+1,\
                    fontweight='bold',\
                    va='center')

      numcpu, numgpu = AddRectangles(page.fig,config,numcpu,numgpu,gpus,nl_config,nodedict,error_nodes)
  return nodelist_html
