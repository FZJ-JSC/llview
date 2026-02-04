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
# Library to format log scale and force integers
from matplotlib.ticker import MaxNLocator, FuncFormatter #,LogLocator, ScalarFormatter, LogFormatterSciNotation
from matplotlib.collections import LineCollection
from matplotlib.colors import Normalize, LogNorm
from matplotlib import colormaps
from copy import copy
import numpy as np
import pandas as pd
import cmcrameri  # Used for cmap of colorbar, coming from config

from AddPage import AddFullPage
from PlotlyFigs import CreatePlotlyFig

def _annotate(ax, x, y):
  """
  Plot 2D grid where points are located 
  Can be used for debug but is very heavy
  """
  X, Y = np.meshgrid(x, y)
  ax.plot(X.flat, Y.flat, 'o',ms=1, color='k')

def CreateFullReport(pdf,data,config,page_num,report,files,time_range,data_manager):
  """
  Creates page with full reports including:
  bottom,0: time and node dependent-colorplot,
  top,0: their average over the y values (usually avg over nodes, time-dependent),
  bottom,1: their average over x values (usually avg over time, node-dependent),
  top,1: min/avg/max values
  """
  # GETTING NUMBER OF GRAPHS ON CURRENT PAGE
  num_graphs=len(report['graphs'])
  # Plotly figs
  figs = {}
  with AddFullPage(pdf,num_graphs,data,page_num,config) as page:
    for graph in range(num_graphs):

      # HEADER NAMES
      x_header = report['x'][graph]
      y_header = report['y'][graph]
      z_header = report['headers'][graph]
      # HEADERS FOR DATABASE NEEDED FOR CURRENT GRAPH
      cols = [x_header,y_header,z_header]
      if x_header == 'ts':
        cols.append('datetime')
      df_current = files[report['data'][graph]]['data'][cols].copy()
      df_current.drop(df_current[df_current[y_header]=='zzz'].index,inplace=True)
      # CALCULATING AVERAGE, MINIMUM AND MAXIMUM CURVES
      df_x_avg = df_current.groupby([x_header, 'datetime'] if x_header == 'ts' else [x_header], as_index=False).mean(numeric_only=True)
      if x_header == 'ts':
        x = df_x_avg['datetime']
      else:
        x = df_x_avg[x_header]
      df_y_avg = df_current.groupby([y_header], as_index=False).mean(numeric_only=True)
      df_x_min = df_current.groupby([x_header], as_index=False).min()
      df_y_min = df_current.groupby([y_header], as_index=False).min()
      df_x_max = df_current.groupby([x_header], as_index=False).max()
      df_y_max = df_current.groupby([y_header], as_index=False).max()

      top = 2*graph
      bottom = 2*graph+1
      # CALCULATING AVERAGE, MINIMUM AND MAXIMUM FOR CURRENT GRAPH
      avg_value = df_y_avg[report['headers'][graph]].astype(float).mean()
      min_value = df_y_min[report['headers'][graph]].min()
      max_value = df_y_max[report['headers'][graph]].max()
      diff = max_value-min_value
      if diff != diff: diff = 0.0 # Fix NaN values

      # SETTING MIN AND MAX FOR COLORBAR WITHOUT EXTRA SPACE
      if not report['lim'][graph]:
        report['lim'][graph] = [min_value,max_value]
      else:
        report['lim'][graph] = [min(min_value,report['lim'][graph][0]) if isinstance(report['lim'][graph][0], (int, float)) else min_value,max(max_value,report['lim'][graph][1]) if isinstance(report['lim'][graph][1], (int, float)) else max_value]

      ##############################################################################################################################
      # FULL NODE COLORPLOT
      ##############################################################################################################################
      # MAIN SURFACE TO PLOT
      y_names = files[report['data'][graph]]['data'][y_header].unique()
      y = np.arange(len(y_names))
      z = np.array(files[report['data'][graph]]['data'][report['headers'][graph]])
      z.shape = (len(y),len(x))

      if data['colorplot'] and report['colorplot'][graph]:
        # PLOTTING COLORMAP:
        # Use pcolor instead of pcolormesh in the case of GPU throttle reason, because it renders better (mentioned here https://stackoverflow.com/a/59461396/3142385), but it's slower
        if report['log'][graph]:
          cbar = page.axes[bottom, 0].pcolor( x, y, z, shading='nearest', cmap=report['cmap'][graph], 
                                              rasterized=True, norm=LogNorm(report['lim'][graph][0], report['lim'][graph][1]))
        else:
          cbar = page.axes[bottom, 0].pcolormesh(x, y, z, shading='nearest', cmap=report['cmap'][graph],
                                                  rasterized=True, vmin=report['lim'][graph][0], vmax=report['lim'][graph][1])

        # SETTING UP AXES:
        page.axes[bottom,0].set_ylabel(report['ylabel'][graph],fontsize=config['appearance']['smallfont'])
        page.axes[bottom,0].set_xlabel(report['xlabel'][graph],fontsize=config['appearance']['smallfont'])

        # maximum in one less, to remove duplicated last line
        page.axes[bottom,0].set_ylim(y.min()-0.5,y.max()-0.5)

        # SETTING TICK POSITIONS (MAXIMUM OF 16)
        if (len(y_names)-1) < 16:
          page.axes[bottom,0].set_yticks(np.arange(len(y_names)-1))
          page.axes[bottom,0].set_yticklabels(y_names[0:-1])
        else:
          def format_fn(tick_val, tick_pos):
            if int(tick_val) in y:
              return y_names[int(tick_val)]
            else:
              return ''
          page.axes[bottom,0].yaxis.set_major_formatter(format_fn)
          page.axes[bottom,0].yaxis.set_major_locator(MaxNLocator(int(64/num_graphs),integer=True))  # Add if too many labels (i.e. for GPUs)

        # ADD COLORBAR AXIS, AND ATTACH COLORBAR TO IT
        bbox = page.axes[bottom,0].get_window_extent().transformed(page.fig.transFigure.inverted())
        cax = page.fig.add_axes((1.32*bbox.x1, bbox.y0, 0.02*(bbox.x1-bbox.x0), (bbox.y1-bbox.y0)))
        
        page.fig.colorbar(cbar, cax=cax)
        if report['log'][graph]:
          cax.set_yscale('log', base=report['log'][graph])
          formatter = FuncFormatter(lambda y, _: '{:.0f}'.format(y))
          cax.yaxis.set_major_formatter(formatter)
        else:
          cax.ticklabel_format(style='plain')
        # cax.yaxis.set_major_formatter(ScalarFormatter(useMathText=True)) 
        # page.fig.canvas.draw()
        # offset = cax.yaxis.get_major_formatter().get_offset()
        # cax.yaxis.offsetText.set_visible(False)

        cax.set_title(f"{report['unit'][graph]}")

        # Getting limits from colorbar
        clim = cbar.get_clim()
        setlim = (clim[0]!=clim[1]) or (diff!=0.0) # Flag to avoing set limits when they are the same
        # Getting ticks from colorbar
        cticks = cax.get_yticks()

      else:
        # PLOTTING LINES:
        for i in range(len(y_names)-1):
          page.axes[bottom, 0].step(x, z[i, :], lw=0.8, label=y_names[i], where='mid', marker='o',ms=1)

        # Getting limits from y axis
        clim = report['lim'][graph]
        setlim = (clim[0]!=clim[1]) or (diff!=0.0) # Flag to avoing set limits when they are the same

        if report['log'][graph]:
          page.axes[bottom, 0].set_yscale('log', base=report['log'][graph])
          formatter = FuncFormatter(lambda y, _: '{:.0f}'.format(y))
          page.axes[bottom, 0].yaxis.set_major_formatter(formatter)
        else:
          if setlim:
            page.axes[bottom,0].set_ylim([clim[0]-0.05*diff,clim[1]+0.05*diff])

        # Getting ticks from y axis
        cticks = page.axes[bottom,0].get_yticks()

        page.axes[bottom,0].legend(fontsize=config['appearance']['tinyfont'],loc='lower right', ncol=(1 if len(y_names)-1 <9 else 2),labelspacing=0.3, handletextpad=0.2, columnspacing=0.4, framealpha=0.5)

      if x_header == 'ts': 
        page.axes[bottom,0].set_xlim(time_range)
        page.axes[bottom,0].xaxis.set_major_formatter(DateFormatter('%d/%m/%y\n%H:%M:%S'))
      else:
        page.axes[bottom,0].set_xlim([x.min(),x.max()])

      cticks = [tick for tick in cticks if clim[0] <= tick <= clim[1]]  # cticks may have extra ticks (see https://stackoverflow.com/q/69074967/3142385). This assures getting only the one inside limits
      # _annotate(page.axes[bottom,0],x,y)

      ##############################################################################################################################
      # AVERAGE PER TIME
      ##############################################################################################################################
      # SET TITLE OF THE PLOT
      page.axes[top,0].set_title(f"{report['type']}: {report['graphs'][graph]}", fontweight='bold')#, pad=3.0)

      # MAIN CURVE TO PLOT
      x_time = df_x_avg[x_header].astype(np.int64)
      y_time = df_x_avg[report['headers'][graph]]

      # SEPARATE INTO SEGMENTS TO COLOR THEM
      # Adapted from https://stackoverflow.com/questions/64051454/how-to-create-a-step-plot-with-a-gradient-based-on-y-value
      # and: https://matplotlib.org/stable/gallery/lines_bars_and_markers/multicolored_line.html
      # Create a set of line segments so that we can color them individually
      # This creates the points as a N x 1 x 2 array so that we can stack points
      # together easily to get the segments. The segments array for line collection
      # needs to be (numlines) x (points per line) x 2 (for x and y)
      if report['log'][graph]:
        norm = LogNorm(vmin=clim[0], vmax=clim[1])
      else:
        norm = Normalize(vmin=clim[0], vmax=clim[1])
      mid = pd.Series(np.concatenate((x_time.iloc[0],[(x_time[1:].iloc[i]+x_time[:-1].iloc[i])/2.0 for i in range(len(x_time)-1)],x_time.iloc[-1]),axis=None).astype(np.int32 if x_header == 'ts' else np.float16))
      segments = np.array([mid[:-1], y_time[:], mid[1:], y_time[:]]).T.reshape(-1, 2, 2)
      # Create a continuous norm to map from data points to colors
      lc = LineCollection(list(segments), cmap=report['cmap'][graph],norm=norm,zorder=3)
      # Set the values used for colormapping
      lc.set_array(y_time)
      lc.set_linewidth(1)
      p1 = page.axes[top,0].add_collection(lc)

      # PLOT MIN/MAX RANGE AND SCATTER POINTS
      errmin_time = df_x_min[report['headers'][graph]] # df.iloc[:,plot_cols[graph]+1]*renorm[graph]
      errmax_time = df_x_max[report['headers'][graph]] # df.iloc[:,plot_cols[graph]+2]*renorm[graph]
      p2 = page.axes[top,0].fill_between(x_time, errmin_time,errmax_time, color=config['appearance']['minmax_color'], step='mid', zorder=2)
      ps = page.axes[top,0].scatter(x_time,y_time,marker='o',s=1,c=y_time,cmap=report['cmap'][graph],norm=norm,zorder=4)

      # GETTING COLOR FOR AVERAGE VALUE TO USE IN THE LEGEND
      cmap = colormaps[report['cmap'][graph]]
      rgba = cmap(norm(avg_value))
      # Copying legend handles to change their color without changing the plots
      p1c = copy(p1)
      p1c.set_color(rgba)
      psc = copy(ps)
      psc.set_color(rgba)
      handles, labels = page.axes[top,0].get_legend_handles_labels()
      page.axes[top,0].legend([(p2, p1c, psc) ], ["max\navg\nmin"],fontsize=config['appearance']['tinyfont'], facecolor='white', loc='lower right', fancybox=True,scatteryoffsets=[0.5])

      # Adding horizontal line(s)
      for line in report['lines'][graph]:
        page.axes[top,0].axhline(y=line,color='r', linestyle='--')

      # SETTING LIMITS AND TICKS (Y FROM COLORBAR)
      if x_header == 'ts':
        page.axes[top,0].set_xlim([ts.timestamp()+config['appearance']['timezonegap'] for ts in time_range])
      else:
        page.axes[top,0].set_xlim([x.min(),x.max()])

      if report['log'][graph]:
        page.axes[top, 0].set_yscale('log', base=report['log'][graph])
        formatter = FuncFormatter(lambda y, _: '{:.0f}'.format(y))
        page.axes[top, 0].yaxis.set_major_formatter(formatter)
        if setlim:
          page.axes[top, 0].set_ylim([max(0.9,clim[0]-0.05*diff), clim[1]+0.05*diff]) # Can't use the same, since negative numbers mess with the plot
        page.axes[top, 0].set_yticks(cticks)
      else:
        if setlim:
          page.axes[top,0].set_ylim([clim[0]-0.05*diff,clim[1]+0.05*diff])
        page.axes[top,0].ticklabel_format(axis='y',style='plain')
        page.axes[top,0].set_yticks(cticks)
      page.axes[top,0].set_ylabel(f"{report['unit'][graph]}",fontsize=config['appearance']['smallfont'])
      page.axes[top,0].set_axisbelow(False)
      # page.axes[top,0].yaxis.offsetText.set_visible(False)

      ##############################################################################################################################
      # AVERAGE PER NODE
      ##############################################################################################################################
      # MAIN CURVE TO PLOT
      x_node = df_y_avg[report['headers'][graph]] # df_aggr.iloc[:,plot_cols_aggr[graph]]*renorm[graph]
      y_node = np.arange(len(df_y_avg[y_header]))

      # SEPARATE INTO SEGMENTS TO COLOR THEM
      # Adapted from https://stackoverflow.com/questions/64051454/how-to-create-a-step-plot-with-a-gradient-based-on-y-value
      # and: https://matplotlib.org/stable/gallery/lines_bars_and_markers/multicolored_line.html
      # Create a set of line segments so that we can color them individually
      # This creates the points as a N x 1 x 2 array so that we can stack points
      # together easily to get the segments. The segments array for line collection
      # needs to be (numlines) x (points per line) x 2 (for x and y)
      segments = np.array([x_node[:], y_node[:]-0.5, x_node[:], y_node[:]+0.5]).T.reshape(-1, 2, 2)
      # Create a continuous norm to map from data points to colors
      lc = LineCollection(list(segments), cmap=report['cmap'][graph],norm=norm,zorder=3)
      # Set the values used for colormapping
      lc.set_array(x_node)
      lc.set_linewidth(1)
      p1 = page.axes[bottom,1].add_collection(lc)

      # PLOT MIN/MAX RANGE AND SCATTER POINTS
      errmin_node = df_y_min[report['headers'][graph]] # df_aggr.iloc[:,plot_cols_aggr[graph]+1]*renorm[graph]
      errmax_node = df_y_max[report['headers'][graph]] # df_aggr.iloc[:,plot_cols_aggr[graph]+2]*renorm[graph]
      p2 = page.axes[bottom,1].fill_betweenx(np.concatenate((y_node[0]-1,y_node,y_node[-1]+1), axis=None), np.concatenate((errmin_node.iloc[0],errmin_node,errmin_node.iloc[-1]), axis=None),np.concatenate((errmax_node.iloc[0],errmax_node,errmax_node.iloc[-1]), axis=None), color=config['appearance']['minmax_color'],step='mid',zorder=2)
      ps = page.axes[bottom,1].scatter(x_node,y_node,marker='o',s=1,c=x_node,cmap=report['cmap'][graph],norm=norm,zorder=4)

      # Adding vertical line(s)
      for line in report['lines'][graph]:
        page.axes[bottom,1].axvline(x=line,color='r', linestyle='--')

      # SETTING LIMITS AND TICKS (X FROM COLORBAR)
      page.axes[bottom,1].set_ylim(y_node.min()-0.5,y_node.max()+0.5)
      if report['log'][graph]:
        # Can't use the same, since negative numbers mess with the plot
        page.axes[bottom, 1].set_xscale('log', base=report['log'][graph])
        formatter = FuncFormatter(lambda y, _: '{:.0f}'.format(y))
        page.axes[bottom, 1].xaxis.set_major_formatter(formatter)
        if setlim:
          page.axes[bottom, 1].set_xlim([max(0.9, clim[0]-0.05*diff), clim[1]+0.05*diff])
        page.axes[bottom, 1].set_xticks(cticks)
      else:
        if setlim:
          page.axes[bottom, 1].set_xlim([clim[0]-0.05*diff, clim[1]+0.05*diff])
        page.axes[bottom, 1].ticklabel_format(style='plain')
        page.axes[bottom, 1].set_xticks(cticks)

      page.axes[bottom,1].set_xlabel(f"{report['unit'][graph]}",fontsize=config['appearance']['smallfont'])
      # page.axes[bottom,1].xaxis.offsetText.set_visible(False)
      page.axes[bottom,1].tick_params(axis='x', labelrotation=45)
      page.axes[bottom,1].set_axisbelow(False)

      if not (data['colorplot'] and report['colorplot'][graph]):
        # SETTING UP AXES:
        page.axes[bottom,1].get_yaxis().set_visible(True)
        page.axes[bottom,1].yaxis.set_label_position("right")
        page.axes[bottom,1].yaxis.tick_right()
        # page.axes[bottom,1].tick_params(axis='y', which='both', labelleft='off', labelright='on')
        page.axes[bottom,1].set_ylabel(report['ylabel'][graph],fontsize=config['appearance']['smallfont'])
        page.axes[bottom,1].set_xlabel(report['xlabel'][graph],fontsize=config['appearance']['smallfont'])

        # SETTING TICK POSITIONS (MAXIMUM OF 16)
        if (len(y_names)-1) < 16:
          page.axes[bottom,1].set_yticks(np.arange(len(y_names)-1))
          page.axes[bottom,1].set_yticklabels(y_names[0:-1])
        else:
          def format_fn(tick_val, tick_pos):
            if int(tick_val) in y_node:
              return y_names[int(tick_val)]
            else:
              return ''
          page.axes[bottom,1].yaxis.set_major_formatter(format_fn)
          page.axes[bottom,1].yaxis.set_major_locator(MaxNLocator(int(64/num_graphs),integer=True))  # Add if too many labels (i.e. for GPUs)

      ##############################################################################################################################
      # AVERAGE NUMBERS
      ##############################################################################################################################
      # if report['log'][graph]:
      if report['note'][graph] != "":
        page.axes[top,1].text(0.5, 0.50,f"{report['note'][graph]}", ha='center', va='center', fontsize=config['appearance']['tinyfont'],transform=page.axes[top,1].transAxes)
      else:
        page.axes[top,1].text(0.5, 0.85,f"max: {max_value:.1f} {report['unit'][graph]}", ha='center', va='center', fontsize=config['appearance']['smallfont'],transform=page.axes[top,1].transAxes)
        page.axes[top,1].text(0.5, 0.50,f"avg: {avg_value:.1f} {report['unit'][graph]}", ha='center', va='center', fontsize=config['appearance']['bigfont'], fontweight='bold',transform=page.axes[top,1].transAxes)
        page.axes[top,1].text(0.5, 0.15,f"min: {min_value:.1f} {report['unit'][graph]}", ha='center', va='center', fontsize=config['appearance']['smallfont'],transform=page.axes[top,1].transAxes)


      if (config['html'] or config['gzip']) and (not report['unified'][graph]):
        figs[report['graphs'][graph]] = {}
        figs[report['graphs'][graph]]['x'] = x_header
        figs[report['graphs'][graph]]['graph'] = CreatePlotlyFig( config,
                                                                  graph,
                                                                  report,
                                                                  time_range,
                                                                  y_names[:-1],
                                                                  cticks,
                                                                  x,
                                                                  y[:-1],
                                                                  z[:-1,:],
                                                                  y_time,
                                                                  errmin_time,
                                                                  errmax_time,
                                                                  x_node,
                                                                  errmin_node,
                                                                  errmax_node,
                                                                  min_value,
                                                                  avg_value,
                                                                  max_value,
                                                                  data_manager)

  return figs
