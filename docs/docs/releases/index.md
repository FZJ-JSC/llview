# LLview Internal Releases

A simplified package of LLview is also available Open Source on GitHub. [See more](public.md)

Developments on the internal releases of LLview are not following the new implementations as the public one. New fixes and improvements done on the internal releases are brought periodically to the public release, but not vice-versa. The versions of the internal "releases" are kept in place for simplicity.
A single version of JURI is used for both internal and public versions of LLview. [See here the changelog for JURI](juri.md).

### 2.4.2-base (December 19, 2025)

<h4> Added </h4>

- Added KontView link to the top navigation bar


### 2.4.1 (November 1, 2025)

<h4> Added </h4>

- Added IO rates to tables;
- Added PagePool metrics (only for JUSUF for now)
- Added missing `loadmemnode` to `LML_DBupdate_file.pm`

<h4> Changed </h4>

- Improved `waittime` after a job has started or is in the queue
- Changed date format of `DATE_NOW` (`info_str` on JURI) to ISO including timezone


### 2.3.2 (December 16, 2024)

<h4> Added </h4>

- Automatic archiving (in tests, not yet ported to the public release)
- Possibility to give system status information to be shown on the webportal
- JuRepTool: Added 'link failure' error recognition

<h4> Changed </h4>

- Internal improvements
- JuRepTool: Activated Core metrics by default for JuRepTool reports (must be deactivated if those metrics are not available)


<h4> Fixed </h4>

- Fixed filter for admin jobs on `plotlists.dat` (files were not created, but jobs were being added for JuRepTool)
- JuRepTool: Fixed 'CPU Usage' in Overview graph
- JuRepTool: Removed rows containing 'inf' values


### 2.2.4 (April 3, 2024)

<h4> Added </h4>

- Added generation of DBgraphs to automatically create dependency graphs (shown as mermaid graphs on the "Dependency Graphs" of Support View)

<h4> Fixed </h4>

- JuRepTool: Fixed favicon 
- JuRepTool: Fixed timeline zoom sync
- JuRepTool: Removed external js libraries versions


### 2.2.2 (January 16, 2024)

<h4> Added </h4>

- Added new queue on JuRepTool
- Possibility to use more than one helper function via `data_pre` (from right to left)
- Core pattern usage (Support only)

<h4> Changed </h4>

- Changed images on Web Portal to svg


### 2.2.0 (November 13, 2023)

<h4> Added </h4>

- Annotations and gray area to indicate NUMA domains and direct GPU connections
- Support for Workflow Manager (WFM) (DEEP only)
- Updated IOI-adapter for v5 (DEEP only)
- Added [JuMonC](https://pypi.org/project/jumonc/) adapter so users can define custom graphs in reports
- HetJobs are now shown as workflows, connecting different jobIDs
- New Projects page (Support View only)
- Time aggregation automatic tables (replacing `_hourly` and `_daily` tables)

<h4> Changed </h4>

- New adapter for GPU metrics from Prometheus (not yet active)
- JuRepTool: Liberation Fonts are now primarily used in reports

<h4> Fixed </h4>

- Link to documentation (Help tab) is now shown on all views
- Moved map jobid-to-day file to folder where all users have access (such filtering suggestions work in all views)


### 2.1.0 (August 4, 2023)

LLview got constant updates in the last months. Apart from the general improvements, an important recent adition was the inclusion of new [core usage metrics](../jobreport/metrics_list.md). New values are added to the tables of active and finished jobs, graphs were added to the footer when a job is selected (including a new footer tab `Cores`), and new graphs were added to the PDF and HTML reports. 

The new metrics can help users, admins and support staff to find wrong configuration or pinning on jobs - as discussed in [this example](../jobreport/examples.md#high-cpu-load-with-low-cpu-usage).

Full Changelog:

* Added IOI information (DEEP only)
* Increased max_entries per table to 5000
* Fixed wrong 1M factor on Open/Close operations
* Improved display of "wait time" and "walltime" to hh:mm
* Fixed missing steps and stuck "Running" state
* Improved "Comments" and "Job Names" collection 
* Improved REASON annotations on footer graph of Queued jobs
* Added column "Reservation" on the tables of the Job Reporting portal
* Added more information when hovering on each step of the timeline on HTML reports
* Added Queue Date and Wait Time to the PDF and HTML reports
* Added Slurm script to PDF and HTML reports
* Added more internal information: LLview usage, Step timings, complexity, timelines, statistics, usage histograms (Support View only)
* Added new pages and graph pages for System Information: IO, Fabric, Environment, Overview (Support View only)
* Added Core usage metrics, including new columns and footer graphs on Job Reporting portal, and new graphs on PDF and HTML reports
* Improved table column names and descriptions
* Total score use now CPU Usage instead of CPU Load
* Added Workflow Manager information (DEEP only)
* Added GPU information from DCDB (DEEP only)
* `CANCELLED by <id>` is now shown as `CANCELLED by <username>`
* Internal fixes and improvements

### 2.0.0 (December 22, 2022)

The new version of LLview, released in the end of 2022, has many new features.
Besides a major internal restructure - the kernel of LLview was completely re-written - and a redesign of the page, here are some of the new features:

<h4> General </h4>

* Easier to configure, generalise and add new and aggregated metrics
* More stable updates, with less missing points
* Improved values for `Interconnect` metrics

<h4> Web portal </h4>

* Workflow tab, currently containing information about SLURM workflows (chains and arrays)
* Improved bottom graphs when selecting a job
* Option to change the colorscale on the job tables
* Auto-refresh button on the top right of LLview web portal
* System information and graphs `(available for support and admins)`
* Internal monitoring of LLview database and timings `(available for support and admins)`
* Searching for a job ID will search all running and history `(available for support and admins)`

<h4> Detailed reports </h4>

* Option to change the colorscale (colors and limits) on interactive reports
* Timeline on the detailed reports (both interactive and PDF)
* Click-to-focus Timeline: on the interactive reports, clicking on a step changes the time-interval to the respective range
* Improved zoom-lock, that can be controled also from the interactive timeline
