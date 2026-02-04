# Copyright (c) 2023 Forschungszentrum Juelich GmbH.
# This file is part of LLview. 
#
# This is an open source software distributed under the GPLv3 license. More information see the LICENSE file at the top level.
#
# Contributions must follow the Contributor License Agreement. More information see the CONTRIBUTING.md file at the top level.
#
# Contributors:
#    Filipe Guimarães (Forschungszentrum Juelich GmbH) 

from matplotlib.figure import Figure       # Figure object
from matplotlib.lines import Line2D        # 2D lines
from matplotlib.gridspec import GridSpec   # Create and manipulate subplots in grid
from matplotlib.axes import Axes           # Import the Axes type
import numpy as np

class AddEmptyPage:
  """Adds an empty page to pdf"""
  counter = 0
  def __init__(self, pdf, page_num, config, first=False):
    self.fw = config['appearance']['page_width']
    self.fh = config['appearance']['page_height']
    self.pdf = pdf
    self.page_num = page_num
    self.ax1: Axes | None = None
    self.ax2: Axes | None = None
    if first:
      AddEmptyPage.counter = 0
    AddEmptyPage.counter += 1
    self.fig = Figure(figsize=(self.fw,self.fh))
    self.add_footer(config)

  def __enter__(self):
    return self

  def __exit__(self, exc_type, exc_val, exc_tb):
    # Return exception
    if exc_type is not None:
      return False
    self.pdf.savefig(self.fig) 
    return self

  def add_header(self,data):
    self.fig.add_artist(Line2D([0.030, 0.970], [0.960, 0.960], color='k', lw=0.3, ls='-'))


    self.fig.text(0.07,0.980,f"{data['job']['system'].replace('_',' ')}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.275,0.980,"Queue: ", ha='right',  color='black', va='center')
    self.fig.text(0.275,0.980,f"{data['job']['queue']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.470,0.980,"#Nodes: ", ha='right',  color='black', va='center')
    self.fig.text(0.470,0.980,f"{data['job']['numnodes']}", ha='left',  color='black', va='center', fontweight='bold')

    if (int(data['job']['numgpus'])>0):
      self.fig.text(0.580,0.980,"#GPUs: ", ha='right',  color='black', va='center')
      self.fig.text(0.580,0.980,f"{data['job']['numgpus']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.750,0.980,"Last Update: ", ha='right',  color='black', va='center')
    self.fig.text(0.750,0.980,f"{data['job']['lastupdate']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.120,0.968,"Job ID: ", ha='right',  color='black', va='center')
    self.fig.text(0.120,0.968,f"{data['job']['jobid']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.275,0.968,"User: ", ha='right',  color='black', va='center')
    self.fig.text(0.275,0.968,f"{data['job']['owner']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.470,0.968,"Project: ", ha='right',  color='black', va='center')
    self.fig.text(0.470,0.968,f"{data['job']['account']}", ha='left',  color='black', va='center', fontweight='bold')

    self.fig.text(0.750,0.968,"Job Name: ", ha='right',  color='black', va='center')
    self.fig.text(0.750,0.968,f"{str(data['job']['name']):.26s}", ha='left',  color='black', va='center', fontweight='bold')

  def add_footer(self,config):
    self.fig.add_artist(Line2D([0.030, 0.970], [0.040, 0.040], color='k', lw=0.3, ls='-'))

    self.LLview_logo(0.97,0.030,self.fig)
    self.fig.text(0.97,0.022,\
            "Created by              \n\nllview.fz-juelich.de", \
            ha='right',  \
            color='black', \
            fontsize=config['appearance']['tinyfont'],\
            style='italic',\
            va='center')
    self.fig.text(0.5, 0.022, f"Page {AddEmptyPage.counter}/{self.page_num}", ha='center', va='center', fontsize=config['appearance']['smallfont'])

  def LLview_logo(self,x,y,fig,fontsize=8,color=(2/255,61/255,107/255)):
    """
    Build LLview logo at position x,y 
    (only works for the A4 fig size)
    """
    fig.text(x,y,f"view", fontsize=fontsize,ha='right', color=color, va='center')
    fig.text(x-0.0024375*fontsize,y-0.00037*fontsize,f"L", fontsize=int(1.67*fontsize),ha='right', color=color, va='center')
    fig.text(x-0.002875*fontsize,y-0.000075*fontsize,f"L",fontsize=int(1.67*fontsize), ha='right', color=color, va='center')
    return



class AddFullPage(AddEmptyPage):
  """
  Adds a page with naxes groups of 2x2 axes to pdf
  """
  def __init__(self, pdf, naxes, data, page_num, config, *args, left=0.10, right=0.900, bottom=0.085, top=0.935, **kwargs):
    super().__init__(pdf, page_num, config, *args, **kwargs)

    n = naxes # number of double-rows
    m = 2 # number of columns

    t = top # 1-t == top space 
    b = bottom # bottom space      (both in figure coordinates)

    msp = 0.1 # minor spacing
    sp = 0.18/n  # major spacing


    self.axes = np.empty(shape=(2*n,m),dtype=object)
    for row in range(n):
      gs = GridSpec(2,m, left=left, right=right, bottom=b+(t-b+sp)*(n-row-1)/n, top=t-(t-b+sp)*row/n, wspace=0.08, hspace=msp, height_ratios=[1, 2.5], width_ratios=[3.5, 1])
      i = row*2
      self.axes[i+1,0] = self.fig.add_subplot(gs[m])
      self.axes[i  ,0] = self.fig.add_subplot(gs[0]  )
      self.axes[i  ,0].get_xaxis().set_visible(False)
      for col in range(1,m):
        self.axes[i+1,col] = self.fig.add_subplot(gs[m+col])#, sharey=self.axes[i+1,0])
        self.axes[i  ,col] = self.fig.add_subplot(gs[col], sharex=self.axes[i+1,col])
        self.axes[i  ,col].get_xaxis().set_visible(False)
        self.axes[i+1,col].get_yaxis().set_visible(False)
        self.axes[i  ,col].get_yaxis().set_visible(False)

    super().add_header(data)
  def __enter__(self):
    return self

  def __exit__(self, exc_type, exc_val, exc_tb):
    # Return exception
    if exc_type is not None:
      return False
    super().__exit__(exc_type, exc_val, exc_tb)
    return self

  def add_name_to_ax(self, x, y, s, ax, config, **kwargs):
    self.axes[ax,1].text(x, y, s, **kwargs, transform=self.fig.transFigure, ha='left',  color='blue', va='center', bbox=dict(lw=0.5, facecolor='none', edgecolor='black', pad=2.0),zorder=1000)
    return

  def add_note_to_ax(self, x, y, s, ax, config, **kwargs):
    self.axes[ax,1].text(x, y, s, **kwargs, transform=self.fig.transFigure, ha='center',  color='black', va='center', style='italic', fontsize=config['appearance']['tinyfont'],zorder=10000)
    return


class AddAxesPage(AddEmptyPage):
  """
  Adds a page with 'naxes' axes to pdf
  """
  def __init__(self, pdf, naxes, data, page_num, config, *args, header=False, left=0.080, right=0.920, bottom=0.070, top=0.92, **kwargs):
    super().__init__(pdf, page_num, config, *args, **kwargs)
    # Create subplots
    axs = self.fig.subplots(naxes, 1)

    # Linter-safe conversion:
    # 1. Check if it's iterable (an array). If so, flatten it.
    # 2. If not (it's a single Axes object), wrap it in a list.
    if isinstance(axs, np.ndarray):
      self.axes = axs.flatten()
    else:
      self.axes = np.array([axs])

    self.fig.subplots_adjust(left=left, right=right, bottom=bottom, top=top, hspace=0.12*(naxes-1))
    if header:
      super().add_header(data)

  def __enter__(self):
    return self

  def __exit__(self, exc_type, exc_val, exc_tb):
    # Return exception
    if exc_type is not None:
      return False
    super().__exit__(exc_type, exc_val, exc_tb)
    return self

  def add_name_to_ax(self, x, y, s, ax, config, **kwargs):
    current_ax = self.axes[ax]
    if isinstance(current_ax, Axes):
      current_ax.text(x, y, s, **kwargs, transform=self.fig.transFigure, ha='left',  color='blue', va='center', bbox=dict(lw=0.5, facecolor='none', edgecolor='black', pad=2.0),zorder=1000)
    return

  def add_note_to_ax(self, x, y, s, ax, config, **kwargs):
    current_ax = self.axes[ax]
    if isinstance(current_ax, Axes):
      current_ax.text(x, y, s, **kwargs, transform=self.fig.transFigure, ha='center',  color='black', va='center', style='italic', fontsize=config['appearance']['tinyfont'],zorder=10000)
    return


