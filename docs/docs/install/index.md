# LLview

The public version of LLview can be downloaded from [GitHub](https://github.com/FZJ-JSC/LLview).
It currently contains a simplified workload including all the necessary
scripts and plugins for a basic functioning. This version includes

- Core structure to process the configurations, create SQLite databases and process data for presentation on the web portal
- JuRepTool to create PDF and interactive HTML reports
- Plugins for:
    - Slurm
    - Prometheus and other REST-API
    - Flat files (via regex)
    - Git repos

It still does not cover:

- Client and live view (the schematic view of the jobs on the nodes)
- JuFo (Jülich Forecast) (Queue Prediction)
- Other plugins
- Logger (module that collects LLview's access metrics)

These features will be added in future updates.

## Software Structure

As an HPC monitoring tool, LLview needs to (1) collect and (2) process the data from the system, and then (3) present them to the end-user.
These three components are usually done in three separate places:

- Collection of data: This is done (partly) on the HPC system to be monitored, where the user running LLview must have permissions to information of all jobs. This part is called [Remote](remote_about.md) on LLview.
- Processing of data: Data is processed (and extra metrics may be also collected) every minute for all running jobs. To avoid perturbing the nodes of the HPC system, this is usually done in a separate server. This part is called [Server](server_about.md) on LLview.
- Presentation of data: The information is presented to the end-user as a web portal. Therefore, a separate Web Server is recommended. The portal is based on the Jülich Reporting Interface [JURI](juri_about.md).

## Installation Instructions

The three components mentioned above need to be installed in that order, as each depends on data from the previous one.
The installation instructions are then separated for each of the parts:

1. [Remote](remote_install.md)
2. [Server](server_install.md)
3. [JURI](juri_install.md)
