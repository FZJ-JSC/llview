# LLview Public Releases

### 2.4.0-base (June 16, 2025)

New file-parser plugin and extensions to the Prometheus one (more generic for REST-API now). Large rewrite on JuRepTool to generalise plots. Further improvements on JURI, including Queue Analysis and Queue View.

<h4> Added </h4>

- Slurm plugin: Added query for Slurm accounts from running jobs (still to be added in DB)
- Added YAML-linter
- Added plugin to parse files using regex definitions (e.g., for healthchecker logs)
- Added example configuration for healthchecker (to be used with the file-parser plugin)
- Added example configuration for job error (`joberr.yaml`) and node error (`nodeerr.yaml`) tables
- Added new envvar variable `LLVIEW_DEMO_MODE` to activate demo mode
- JuRepTool: possibility to add red lines to mark graphs (to be used with calibrate)
- JuRepTool: added "Download Data" button for timeline
- JURI: Added quick buttons to filter RUNNING, COMPLETED and FAILED jobs
- JURI: Added queue view using bar-plots (including calendar and fixed hoverinfo)
- JURI: Added jquery-ui for calendar
- JURI: Added quickfilter to URL to be able to restore it after refresh or link sharing
- JURI: Added JUPITER logo

<h4> Changed </h4>

- Improved and extended documentation
- Added logo for dark mode in README
- Improved Apache header files
- Changed ActiveSM to percentage
- Extended the 'prometheus' plugin to handle more generic REST-API (possibility to give endpoints, client secret, and more)
- Generalisations on Slurm plugin (unlimited time in queue, format of Gres, empty responses)
- Generalisation on `get_hostnodename.py` to allow multiple expansions
- Changed `remoteAll.pl` and `serverAll.pl` scripts to use same envvars names
- Increased timeout on Prometheus plugin
- Improved and optimized workflow on Prometheus plugin (much faster now)
- Changes from production: improved logging, bug fixes, small improvements
- JuRepTool: changed the way the overview graph is defined (now configurable)
- JuRepTool: major rewriting to allow graphs inside the same section get data from different dat files
- JuRepTool: improved CI tests, that should be now faster and include their own configuration
- JuRepTool: added energy values on header, when present on the json file
- JURI: Make background color of colored cells stay in selected rows
- JURI: Improved mouse resizing of footer (including preventDefault to avoid selecting text when resizing)
- JURI: Improved CB tables with links
- JURI: Automatically show column that are used for sorting
- JURI: Updated plotly.js to 3.0.0
- JURI: Removed d3.csv parsing for plots
- JURI: Improved async plots when jobs are quickly selected
- JURI: Improved slider plots in 'Queue Analysis'
- JURI: 'username' in project page now clickable (to the user page on that given project)
- JURI: Generalised parsing of timestamps
- Other minor improvements in LLview, JuRepTool and JURI

<h4> Fixed </h4>

- Fixed `.htaccess` files to require valid user
- Fix for "unparseable" line in slurm output
- Fixed escape sequence for Python>=3.13
- Fixed check of modification date of files, that led to pdf and html reports not being synced.
- JuRepTool: Fixed zoom-lock for new Plotly version
- JURI: Fixed adding filter options to page
- JURI: Unified system names on login page
- JURI: Added `.js.gz` to `.htaccess`
- JURI: Slider bar with steps are updated directly with the event (plotly would not update all traces)
- JURI: Added 'id' to 'floatingFilters'
- JURI: Clean up the plots when plotting fails (when selecting a job, the wrong plots could be shown)
- JURI: Fixed fonts of the core patterns on Chrome
- Other minor fixes in LLview, JuRepTool and JURI


### 2.3.2-base (December 16, 2024)

<h4> Added </h4>

- Improved Gitlab plugin (that runs now by default only every 15min), including possibility to give units of metric
- Improvements on Prometheus plugin: possibility to authenticate with token, added min/max to metrics, possibility to turn off verification on requests
- Possibility to give system status information to be shown on the webportal
- Added pre-set options for grid
- JuRepTool: Added 'link failure' error recognition
- JURI: Added possibility for links to status page (and current status) on all headers (file containing status should be updated externally, e.g. via cronjob)
- JURI: Added possibility to link to user profile (e.g.: JuDoor)
- JURI: Added parsing of pre-set filter options and button besides the top search (max. filters per column: 3)
- JURI: Added possibility to open login page in another window/tab when using middle mouse or ctrl+click on "home" button
- JURI: Add a check if user of 'loginasuser' exists or not
- JURI: Added 'jump to project' field on login
- JURI: Added helper function to convert number to hhmm
- JURI: Added graph for slider (used at the moment for coming 'Queue Analysis')


<h4> Changed </h4>

- Improved default columns shown on tables (description, conversions, etc)
- Decrease the default amount of cores used in different steps, to avoid using too much memory
- Deactivated all but basic Slurm queries by default (and commented out CB in config)
- Unified 'monitor' logs now also located in the 'logs' folder
- Improved documentation (including a first version of how to add new metrics)
- Changed `onhover` to use list/array instead of dict/object in gitlab plugin (so order is kept)
- Adapted `serverAll` search command to be able to use 2 systems in one server
- Changes from production: internal improvements
- JuRepTool: Activated Core metrics by default for JuRepTool reports (must be deactivated if those metrics are not available)
- JURI: Improved grid columns sizing
- JURI: Automatically open grid column group when a hidden column uses a filter
- JURI: Compressed external js libraries and added js.gz to `.htaccess`
- JURI: Removed deflate from `.htaccess`
- JURI: Turned off cache on `.htaccess` to avoid large memory consumption
- JURI: Improved style when viewwidth is reduced
- JURI: Improved filters (especially for dates)
- JURI: Made username in project page clickable
- Other small improvements

<h4> Fixed </h4>

- Fixes for absent logic cores (for systems without SMT)
- Fixed columns when grid is not used (including defaults)
- Fixed filter for admin jobs on `plotlists.dat` (files were not created, but jobs were being added for JuRepTool)
- Create temporary `.htgroups_all` user to avoid building up support when there's a problem
- Fixes in `monitor_file.pl`:  folders not recognized in when given with 2 slashes, folders not created when slash at the end missing
- JuRepTool: Fixed error output to be also .errlog, to be listed in `listerrors`
- JuRepTool: Fixed 'CPU Usage' in Overview graph
- JuRepTool: Removed rows containing 'inf' values
- JURI: Fixed grid filter size
- JURI: Fixed link of 'jump to jobid' field
- JURI: Fixed buttons when loginasuser is used
- JURI: Fixed column show/hide
- JURI: Fixed grid filter containing '-' that is not a range
- Other small fixes



### 2.3.1-base (July 10, 2024)

Prometheus plugin and GitLab plugin for Continuous Benchmarks! Many fixes and improvements, some of which are listed below.

<h4> Added </h4>

- Prometheus and Gitlab (for Continuous Benchmark) plugins
- Brought changes from production version, mainly rsync list of files
- JuRepTool: Added hash for each graph to URL (also automatically while scrolling)
- JuRepTool: Added link in plotly graphs to copy the link
- JURI: Possibility to filter graph data from CSV (with 'where' key)
- JURI: Added hoverinfo from 'onhover' also on scatter plots
- JURI: Added possibility to pass trace.line from LLview to plotly graphs

<h4> Changed </h4>

- Improved README, with thumbnail
- Usage->Utilization for GPU
- Added ActiveSM in GPU metrics
- JURI: Changed the storing of headers to save them for each page

<h4> Fixed </h4>

- Fixed project link
- Fixed regex pattern for 'CANCELLED by user' to allow more general usernames
- Fix for cases where username is in support but not alluser (previously didn't have access to _queued)
- JuRepTool: Fixed icon sizes in plotly modeBar
- JuRepTool: Fix for horizontal scroll in nav of html report
- JuRepTool: adapt for new slurm 'extern' job name
- JuRepTool: Escape job and step name
- JuRepTool: Ignore '+0' in step id
- JuRepTool: Removed deprecated function 'utcfromtimestamp'
- JuRepTool: Added new tests and fixed old ones (due to new metrics)
- JuRepTool: Added line break in 'Cancelled by username' in PDF timeline to avoid overlapping text
- JURI: Fix the size of the footer, to avoid table be under it
- JURI: Fix the escape of the column group names
- JURI: Fixes for some gridApi calls that return warnings or errors
- JURI: Removed autoSizeStrategy and minWidth from column defs, as that breaks their sizing and flexbox
- JURI: Fixed small bugs when columns or grids are not present


### 2.3.0-base (May 21, 2024)

Faster tables! Using now ag-grid to virtualise the tables, now many more jobs can be shown on the tables. It also provides a "Quick Filter" (or Global Search) that is applied over all columns at once.

<h4> Added </h4>

- Support for datatables/grids
- CSV files can be generated 
- New template and Perl script to create grid column definitions
- Added `dc-wai` queue on jureptool system config
- JURI: Added grid (faster tables) support using [ag-grid-community](https://github.com/ag-grid/ag-grid) library 
- JURI: Helper functions for grid
- JURI: Grid filters (including custom number filter, which accepts greater '>#', lesser '<#' and InRange '#-#'; and 'clear filter' per column)
- JURI: Quick filter (on header bar)
- JURI: Now data can be loaded from csv (usually much smaller than json)

<h4> Changed </h4>

- Removed old 'render' field from column definitions (not used)
- Default Support view now has a single 'Jobs' page with running and history jobs using grid
- JURI: Adapted to grid:
    - Buttons on infoline (column groups show/hide, entries, clear filter, download csv)
    - Presentation mode
    - Refresh button
    - Link from jobs on workflows

<h4> Fixed </h4>

- Improved README and Contributing pages
- Fixed text of Light/Dark mode on documentation page
- Fixed get_cmap deprecation in new matplotlib version
- JURI: Small issues on helpers
- JURI: Fixed color on 'clear filter' link


### 2.2.4-base (April 3, 2024)

<h4> Added </h4>

- Added System tab (usage and statistics) for Support View
- Added option to delete error files on `listerrors` script
- Added `llview` controller in scripts (`llview stop` and `llview start` for now)
- Added power measurements (`CurrentWatts`) (LML, database and JuRepTool)
- Added `LLVIEW_WEB_DATA` option on `.llview_server_rc` (not hardcoded on yaml anymore, as the envvars are expanded for `post_rows`)
- Added `LLVIEW_WEB_IMAGE` option on `.llview_server_rc` to change web image file
- Added `wservice` and `execdir` automatic folder creation
- Added `.llview_server_rc` to monitor (otherwise, changes in that file required "hard" restart)
- Added `icmap` action, configuration and documentation
- Added generation of DBgraphs (from production) to automatically create dependency graphs (shown as mermaid graphs on the "Dependency Graphs" of Support View)
- Added trigger script and step to `dbupdate` action to use on DBs that need triggering
- Added options to dump options as JSON or YAML using envvars (`LLMONDB_DUMP_CONFIG_TO_JSON` and `LLMONDB_DUMP_CONFIG_TO_YAML`)
- Added `CODE_OF_CONDUCT.md`
- JURI: Added CorePattern fonts and style
- JURI: Added `.htpasswd` and OIDC examples and general improvements on `.htaccess`
- JURI: Added system selector when given on setup
- JURI: Added 'RewriteEngine on' to `.htaccess` (required for `.gz` files)
- JURI: Added buttons on fields in `login.php`
- JURI: Added home button
- JURI: Added mermaid graphs and external js
- JURI: Added svg-pan-zoom to zoom on graphs
- JURI: Added option to pass image in config
- JURI: Added "DEMO" on system name when new option `demo: true` is used

<h4> Changed </h4>

- Improved `systemname` in slurm plugin
- Changed order on `.llview_server_rc` to match  `.llview_remote_rc`
- Separated `transferreports` stat step on `dbupdate.conf`
- Moved folder creation msg to log instead of errlog
- Improved documentation about `.htaccess` and `accountmap`
- Improved column group names (now possible with special characters and space)
- Changed name "adapter" to "plugins"
- Improved parsing of envvars (that can now be empty strings) from .conf files
- Further general improvements on texts, logs, error messages and documentation
- JuRepTool: Improvements on documentation and config files
- JuRepTool: Moved config folder outside server folder
- JURI: Adapted `login.php` to handle also OIDC using REMOTE_USER
- JURI: Improved favicon
- JURI: Changed how versions of external libraries are modified (now via links, such that future versions always work with old reports)
- JURI: Updated plotly.js
- JURI: Improvements in column group names, with special characters being escaped
- JURI: Changed footer filename (as it does not include only plotly anymore)

<h4> Fixed </h4>

- Fixed `starttime=unknown`
- Fixed support in `.htgroups` when there's no PI/PA 
- Fixed `'UNLIMITED'` time in conversion
- Fixed creation of folder on SLURM plugin
- Fixed missing `id` on `<input>` element
- Removed export of `.llview_server_rc` from scripts (as it resulted in errors when in a different location)
- JuRepTool: Fixed deprecation messages
- JURI: Fix `graph_footer_plotly.handlebar` to have a common root (caused an error in Firefox)
- JURI: Fix `.pdf.gz` extension on `.htaccess` example
- JURI: Removed some anchors `href=#` as it was breaking the fragment of the page
- JURI: Fixed forwarding to job report when using jump to jobID


### 2.2.3-base (February 13, 2024)

<h4> Added </h4>

- Added [script to convert account mapping from CSV to XML](../install/accountmap.md#csv-format)
- Slurm adapter: Added 'UNKNOWN+MAINTENANCE' state
- Added link to project in Project tab
- Added helper scripts in `$LLVIEW_HOME/scripts` folder and added this folder in PATH
- JURI: Added CorePattern fonts and style

<h4> Changed </h4>

- Added more debug information
- Further improved [installations instructions](../install/index.md)
- Slurm adapter: Removed hardcoded way to give system name and added to options in yaml
- Removed error msg from hhmm_short and hhmmss_short, as they can have values that can't be converted (e.g: wall can also have 'UNLIMITED' argument)
- JuRepTool: Changed log file extension
- JURI: Changed how versions of external libraries are modified (now via links, such that future versions always work with old reports)
- JURI: Removed old plotly library
- JURI: Changed login.php to use REMOTE_USER (compatible with OIDC too)
- JURI: Improved favicon SVG

<h4> Fixed </h4>

- Fixed wall default
- Removed jobs from root and admin also from plotlist.dat (to avoid errors on JuRepTool)
- fixed SQL type for perc_t
- JuRepTool: Fixed loglevel from command line
- JuRepTool: Improved parsing of (key,value) pairs
- JuRepTool: Fixed favicon 
- JuRepTool: Fixed timeline zoom sync
- JuRepTool/JURI: Removed external js libraries versions
- JURI: Fix graph_footer_plotly.handlebar to have a common root (to avoid xml error)
- JURI: Fix .pdf.gz extension on .htaccess


### 2.2.2-base (January 16, 2024)

<h4> Added </h4>

- Added link to JURI on README
- Added [troubleshooting](../install/troubleshooting.md) page on docs
- Added [description of step `webservice` on the `dbupdate`](../install/server_install.md#webservice-step) action
- Added timings in Slurm adapter's LML
- Added new queue on JuRepTool
- Possibility to use more than one helper function via `data_pre` (from right to left)
- Core pattern example configuration (when information of usage per core is available)
- Added info button on the top right when a page has a 'description' attribute (JURI)

<h4> Changed </h4>

- Changed images on Web Portal to svg
- Improved [installations instructions](../install/index.md)
- Lock PR after merge (CLA action)
- Improved CITATIONS.cff
- Automatically create shareddir in remote Slurm action
- Changed name of crontab logs (to avoid problems in case remote and server run on the same place)
- Improve footer resize (JURI)
- Implemented suggestions from Lighthouse for better accessibility (JURI)
- Colorscales improved, and changed default to RdYlGr (JURI)

<h4> Fixed </h4>

- Fixed default values of wall, waittime, timetostart, and rc_wallh
- Improved how logs are cleaned to avoid stuck files
- Fixed workflow of jobs with a single step


### 2.2.1-base (November 29, 2023)

<h4> Added </h4>

- Added Presentation mode (JURI)

<h4> Changed </h4>

- Improved the parsing of values from LML to database

<h4> Fixed </h4>

- Added missing example configuration files


### 2.2.0-base (November 13, 2023)

A new package of the new version of LLview was released Open Source on [GitHub](https://github.com/FZJ-JSC/LLview)!
Although it does not include all the features of the production version of LLview running internally on the JSC systems, it contains all recent updates of version 2.2.0.
On top of that, it was created using a consistent framework collecting all the configurations into few places as possible.

The included features are:

- Slurm adapter (used to collect metrics from Slurm on the system to be monitored)
- The main LLview monitor system that collects and processes the metrics into SQLite3 databases
- JuRepTool, the module to generate HTML and PDF reports
- Example actions and configurations to perform a full workflow of LLview, including:
	- collection of metrics
	- processing metrics
	- compressing and archiving
	- transfer of data to Web Server
	- presenting metrics to the users
- Jülich Reporting Interface (downloaded separately [here](https://github.com/FZJ-JSC/JURI)), the module to create the portal and present the data to the users

Not included are:

- Client (Live view)
- Other adapters (currently only Slurm)

The documentation page was also updated to include the [installation instructions](../install/index.md).

