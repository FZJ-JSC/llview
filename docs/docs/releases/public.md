# LLview Public Releases


### 2.4.5-base (June 19, 2026)

New SeanerBus-subscriptions plugin (already mature and with many functionalities!), many generalisations and fixes!

<h4> Added </h4>

- Added ASCII output (for step timings)
- Added check on race condition in generation of datasets
- Added small utility script to handle lock files
- Added check for empty table names in DB config files
- Added more step timing information
- Added handling of generic objects in LML (easier to collect generic metrics)
- Added cache option for CSV and DAT files, to be used when multiple files use the same DB contents
- Added SeanerBus plugin ([SEANERGYS Project](https://seanergys.eu)): asynschronous subscription to the Bus where data is published
- Added config file to collect information from [Flux](http://flux-framework.org/) (using the Slurm plugin, that will probably change name in the future)
- Added more energy conversion functions
- Git plugin: Configuration files can *include* contents from another file (main o
ne must contain 'host', 'token', optional 'branch', and 'include' file)
- Git plugin: Errors are now stored and passed to the portal, shown as console.error (so the user can see the error and fix by themselves)
- Git plugin: New 'name' key to allow users to change displayed name on overview table and tab, without modifying the database
- Git plugin: Added possibility to change CSV delimiter using 'csv_delimiter' inside 'sources'
- Git plugin: Added regression and outlier validation functions (full reformulation of the validation scheme
- Git plugin: Added option to aggregate metric values
- JuRepTool: Added better and more error handling
- JuRepTool: Added check to see if file is being written before reading it (try a few times before giving up)
- Documentation: Added information about new validations,  errors in the console and aggregations

<h4> Changed </h4>

- Improved and extended internal logging (to simplify debugging)
- Improved `monitor_file` to accept multiple watch files
- Improved 'listerrors` script
- Modifications for improved collection of error messages
- Improved reservation tables to store historical entries (example config)
- Improved checks on the tables in `checkDB` and fixed sign
- Improving report of YAML error
- Automaticaly adds `demo` key to support view (according to envvar) to indicate JURI this mode
- Improved checks when generating CSV files
- Improved crontab server script (`serverAll.pl`): configurable automatic start of `mmpmon` daemon with env-var `LLVIEW_MMPMON_MAX_DAEMON_NR`
- Improved log handling to avoid race conditions and filling cache
- Adapted to new version of ag-grid (new API)
- Improved timelines of actions
- Internal generalisations: fallbacks for `step`->`jobid` and `id`->`nodeid`, states to accept also flux states (`sched`, `run`, etc.), `reason` not mandatory, `accountmap` accept suffixes
- Improved `increase_counter.pl` script to create counter file when not existent
- Added possibility to give `nodelist_pattern` to change the current format `(nodeid,ncores)`
- On the DBs, we now Keep previous data from entries of a job that receives incomplete new entries (as in the case of Flux events)
- Changed `waittime` handling: use from LML when existing, or calculate in a more generic way
- Git plugin: Strings used in SQL and commands are sanitized for safety
- Git plugin: validator can now return layout additions (shapes/annotations) for plotly
- Git plugin: Changed definition of column templates to use new ag-grid types defined on JURI
- Slurm plugin: Improved config for account info
- Slurm plugin: Improved accounting tables to merge data from Slurm
- Slurm plugin: Added config options for support accounts
- Slurm plugin: Added function for `reason` node is down

<h4> Fixed </h4>

- Added missing case on file management (files with `state=FSTATUS_COMPRESSED`)
- Fixed escaping of delimiter only for CSV (it was breaking md files)
- Fixed parsing list of tables in csv (worked only for json)
- Fixed JuRepTool's table (that store jobs to be put on `plotlists.dat` file) to avoid stuck jobs (example config)
- Fixed race conditions on tables (example config)
- Fixed the way running processes are checked on `monitor_file` (to avoid error messages when day changes)
- Git plugin: allow dots on branch names
- Git plugin: Fixed generation of empty yaml files not to break full workflow;
- Slurm plugin: Force overlapping window on `sacct` to avoid having jobs with stuck information (e.g., state)
- Slurm plugin: Improved parsing of Slurm blocks (including line breaks on values)
- Slurm plugin: Fixed accumulation of values into string
- Slurm plugin: Fixed folder concatenation for mkdir
- Slurm plugin: Fixed objects for support users with projects and support
- File plugin: Added type on pstat object to avoid duplication
- JuRepTool: fixed reading error in pandas with `float16`


### 2.4.4-base (March 11, 2026)

Important bug fixes, improvements on plugins (Prometheus plugin is now GenericAPI, as it is much more general), and more!

<h4> Added </h4>

- Added possibility to give unique indices for the SQL tables via `unique_index` key (to avoid adding duplicated data)
- JuRepTool: Added dependency on `pytz`
- Added autocompletion for `listerrors` script
- Git plugin: New `default` and `validation` metric keys ([See here for more details](../benchmarks/configuration.md))
- Git plugin: New layout option under plot_settings, that is passed to plotly.js layout directly
- Git plugin: Added possibility to define benchmark tab name via argument
- Example config: Use `unique_index` on some tables
- Example config: Included checkMK example config (that is used with `generic_api.py` plugin)
- Example config: Added statistics of application names (table on DB, and website)
- Example config: Added job distribution graph page

<h4> Changed </h4>

- Updated SQLite queries and checks to allow also changing of capilatisation without errors
- Improved quotation of tables
- Fixed reporting of errors and fixes in `checkDB`/`updatedb`
- Improved substitution of envvars to emit meaningful error messages
- Changed plugin folder names: `SLURM` to `Slurm`, and `Prometheus` to `GenericAPI` (the plugin is more general than prometheus)
- Git plugin: now traverse folders and subfolders recursively
- Git plugin: stores 'host' in folder using tab name too, to allow one page to collect data from different hosts; 
- Git plugin: Added sorts to make colors consistent, replace spaces into '_' on `_timestamps` tables
- GenericAPI plugin: Extended plugin to use wildcards to traverse json
- GenericAPI plugin: Define time multipliers to automatically generate timestamps
- GenericAPI plugin: Generalised REST API to handle Argos (without breaking checkMK)
- JuRepTool: Collect data that should be put on the HTML reports in a single variable, and use them for the different plots and avoid duplicated data (use less space)
- JuRepTool: Removed custom hovertext in favour of hovertemplate, since that increases considerably the HTML report size
- Example config: Fixed `pcpucores` tables, to prevent it exploding

<h4> Fixed </h4>

- Added replacement of slashes to `%2F` on FORALL variables that are used in paths, to avoid breaking the file creations
- Fixed `hourfrac` conversion to allow 'UNLIMITED'
- Fixed compression workflow to avoid recompressing
- Git plugin: More safeguards to avoid crashing when wrong configs are given
- Git plugin: Fixed timezone of timestamp
- Git plugin: Added 'stub' to be able to keep some common data when all data is filtered
- Git plugin: Made checks more general for x-axis quantity instead of 'ts'
- Git plugin: Changed type of int to `%s` on the csv files to allow empty strings (missing values)
- Slurm plugin: Fixed plugin to not crash when conversion fails and to return used memory
- Slurm plugin: Fixed expansion of nodelist
- JuRepTool: Further issues fixed, also in `errormessage` example
- JuRepTool: Fix yaxis zoom on timeline when zoomlock is on
- Example config: Fixed queries of the node status to avoid duplicate counting of nodes on the Usage graph
- Example config: Fixed GPU list (had issues when job restarted)
- Example config: Further improvements


### 2.4.3-base (January 18, 2026)

More improvements on Continuous Benchmarks, better XML parsing and improvements on JuRepTool!

<h4> Added </h4>

- Git plugin: Added option to set Benchmarks page as default
- Git plugin: Added 'status history', i.e. '_status' to show the status of the last 5 runs (configurable)
- JuRepTool: Added option to give plotly, jquery and fontawesome libraries locations (https or "local")
- JuRepTool: added JSON structure for expected input files in JuRepTool's README.md
- JuRepTool: Added possibility to give folders
- JuRepTool: Added warning when a configfolder is not given
- JuRepTool: Added option to change the link on the LLview logo

<h4> Changed </h4>

- CB overview table is now sorted by name;
- Improved parsing of LML to accept single or double quotes, and quotes and $ can be escaped to be used inside commands (they are unescaped by then)
- Add SYSTEM_TS when none is available - such that LLview works without having to parse one from e.g. Slurm;
- Improved parsing of datatable column definitions (to be able to give more levels)
- Improved logging of errors, to make it easy to find problems on SQL queries; 
- Git plugin: Removed 'all_empty' check, since configs always need to be generated, also with empty files
- Git plugin: Improved handling of defaults or failed runs
- Git plugin: Improved configuration files for YAML (global 'plot_settings' and 'traces'->'group_by', to make it more intuitive)
- Git plugin: Changed default colors (now tab10) and opacity to 0.9
- Git plugin: Adapted example config and documentation for new config and defaults
- Git plugin: Aggregate LMLs per repo, and not per tab
- Git plugin: Changed order when getting metrics: now we verify the data first, and skip some steps for failed runs (but keep the points)
- Git plugin: Changed table mode to 'replace' (always recreate the whole table), so 'tsfile' is not needed (but kept the possibility to use it, in case benchmarks are too big, that may be the only solution)

<h4> Fixed </h4>

- Fixed usage of quoted table and column names of internal SQL queries and checkDB/`updatedb`
- Fixed possible errors in 'slurm' and 'files' plugins (more robust now)
- Git plugin: Fix for failed runs not to generate new orphan rows in tables
- Git plugin: Fix for null metrics that were not leading to a failed status entry
- Git plugin: Fix for benchmarks with spaces in names
- Git plugin: Fixed linter issues
- Git plugin: Fixed output of git plugin when singleLML is not used (to be used for parallel runs)


### 2.4.2-base (December 19, 2025)

Extensions on Continuous Benchmark, many improvements on plugins, more documentation!

<h4> Added </h4>

- Prometheus plugin: Added 'regex' option, to be applied on the keys (ids) of the dictionary
- Prometheus plugin: Added option 'usage_threshold' for a core to be considered as used
- Prometheus plugin: Added 'topology' for how the sockets/smts are distributed
- Prometheus plugin: Added possibility to get additional data related to the query (PR#13 by @Matth-L on GitHub)
- Git plugin (CB): Added page and graph tabs on CB configuration ([See examples](../benchmarks/examples.md))
- Git plugin (CB): Added status column (for overview and benchmarks) showing the status of the last run
- Git plugin (CB): Added #Runs (Total and Valid) columns
- Added documentation page on [Adding new metrics - Example](../install/addmetrics_example.md) (PR#13 by @Matth-L on GitHub)
- CB: Added [User](../benchmarks/configuration.md) and [Installation](../install/benchmarks.md) documentation pages

<h4> Changed </h4>

- Slurm plugin: Improved memory setting (Fall back to `AllocMem` when `UsedMemory<0` or `FreeMem==N/A`) (PR#9 by @Matth-L on GitHub)
- Git plugin (CB): Improved how metrics are given
- Improved how LLview internally handles column and table names with proper quoting
- Changed plugin name to git.py

<h4> Fixed </h4>

- Prometheus plugin: Fixed division by 0 (PR#8 by @Matth-L on GitHub)
- Prometheus plugin: Fixing mapping of CPUs
- Fixed updatedb script to account for all changes in final message
- More bugfixes


### 2.4.1-base (November 1, 2025)

Possibility to have tabs on pages (now used for History on production systems, and to be used for Continuous Benchmarks), plus many other internal improvements and fixes.

<h4> Added </h4>

- Added IO rates to tables;
- Added ENV vars to `$globalvarref`;
- Added "replay" module (documentation still to be added);
- Added `PRAGMA optimize`
- Added utility script `dumpconfig` to dump YAML config file
- Added envvar expansions also for `pre_rows` and `rows`
- Added archiver scripts to compress, tar and move local archived files to remote arch-dirs (documentation still to be added);
- Added 'tabs' key for views
- Added missing `loadmemnode` to `LML_DBupdate_file.pm` (Should fix GitHub #6)
- Added `maskcomma` convert function

<h4> Changed </h4>

- Improvements on Continuous Benchmark: Added links on names for each benchmark, removed the name column on the benchmark page, made color and style of traces configurable
- Improved documentation, including continuous benchmarks information
- Extended YAML input to allow multiple indices per table
- Improved `waittime` after a job has started or is in the queue
- Changed date format of `DATE_NOW` (`info_str` on JURI) to ISO including timezone

<h4> Fixed </h4>

- Fixed data collection on Prometheus plugin
- Avoid warnings in db-arch if table is empty
- Fix capitalization for Continuous Benchmark titles


### 2.4.0-base (June 16, 2025)

New file-parser plugin and extensions to the Prometheus one (more generic for REST-API now). Large rewrite on JuRepTool to generalise plots.

<h4> Added </h4>

- Slurm plugin: Added query for Slurm accounts from running jobs (still to be added in DB)
- Added YAML-linter
- Added plugin to parse files using regex definitions (e.g., for healthchecker logs)
- Added example configuration for healthchecker (to be used with the file-parser plugin)
- Added example configuration for job error (`joberr.yaml`) and node error (`nodeerr.yaml`) tables
- Added new envvar variable `LLVIEW_DEMO_MODE` to activate demo mode
- JuRepTool: possibility to add red lines to mark graphs (to be used with calibrate)
- JuRepTool: added "Download Data" button for timeline

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
- Other minor improvements

<h4> Fixed </h4>

- Fixed `.htaccess` files to require valid user
- Fix for "unparseable" line in slurm output
- Fixed escape sequence for Python>=3.13
- Fixed check of modification date of files, that led to pdf and html reports not being synced.
- JuRepTool: Fixed zoom-lock for new Plotly version
- Other minor fixes


### 2.3.2-base (December 16, 2024)

<h4> Added </h4>

- Improved Gitlab plugin (that runs now by default only every 15min), including possibility to give units of metric
- Improvements on Prometheus plugin: possibility to authenticate with token, added min/max to metrics, possibility to turn off verification on requests
- Possibility to give system status information to be shown on the webportal
- Added pre-set options for grid
- JuRepTool: Added 'link failure' error recognition

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
- Other small fixes


### 2.3.1-base (July 10, 2024)

Prometheus plugin and GitLab plugin for Continuous Benchmarks! Many fixes and improvements, some of which are listed below.

<h4> Added </h4>

- Prometheus and Gitlab (for Continuous Benchmark) plugins
- Brought changes from production version, mainly rsync list of files
- JuRepTool: Added hash for each graph to URL (also automatically while scrolling)
- JuRepTool: Added link in plotly graphs to copy the link

<h4> Changed </h4>

- Improved README, with thumbnail
- Usage->Utilization for GPU
- Added ActiveSM in GPU metrics

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


### 2.3.0-base (May 21, 2024)

Faster tables! Using now ag-grid to virtualise the tables, now many more jobs can be shown on the tables. It also provides a "Quick Filter" (or Global Search) that is applied over all columns at once.

<h4> Added </h4>

- Support for datatables/grids
- CSV files can be generated 
- New template and Perl script to create grid column definitions
- Added `dc-wai` queue on jureptool system config

<h4> Changed </h4>

- Removed old 'render' field from column definitions (not used)
- Default Support view now has a single 'Jobs' page with running and history jobs using grid

<h4> Fixed </h4>

- Improved README and Contributing pages
- Fixed text of Light/Dark mode on documentation page
- Fixed get_cmap deprecation in new matplotlib version


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

<h4> Fixed </h4>

- Fixed `starttime=unknown`
- Fixed support in `.htgroups` when there's no PI/PA 
- Fixed `'UNLIMITED'` time in conversion
- Fixed creation of folder on SLURM plugin
- Fixed missing `id` on `<input>` element
- Removed export of `.llview_server_rc` from scripts (as it resulted in errors when in a different location)
- JuRepTool: Fixed deprecation messages


### 2.2.3-base (February 13, 2024)

<h4> Added </h4>

- Added [script to convert account mapping from CSV to XML](../install/accountmap.md#csv-format)
- Slurm adapter: Added 'UNKNOWN+MAINTENANCE' state
- Added link to project in Project tab
- Added helper scripts in `$LLVIEW_HOME/scripts` folder and added this folder in PATH

<h4> Changed </h4>

- Added more debug information
- Further improved [installations instructions](../install/index.md)
- Slurm adapter: Removed hardcoded way to give system name and added to options in yaml
- Removed error msg from hhmm_short and hhmmss_short, as they can have values that can't be converted (e.g: wall can also have 'UNLIMITED' argument)
- JuRepTool: Changed log file extension

<h4> Fixed </h4>

- Fixed wall default
- Removed jobs from root and admin also from plotlist.dat (to avoid errors on JuRepTool)
- fixed SQL type for perc_t
- JuRepTool: Fixed loglevel from command line
- JuRepTool: Improved parsing of (key,value) pairs
- JuRepTool: Fixed favicon 
- JuRepTool: Fixed timeline zoom sync
- JuRepTool: Removed external js libraries versions


### 2.2.2-base (January 16, 2024)

<h4> Added </h4>

- Added link to JURI on README
- Added [troubleshooting](../install/troubleshooting.md) page on docs
- Added [description of step `webservice` on the `dbupdate`](../install/server_install.md#webservice-step) action
- Added timings in Slurm adapter's LML
- Added new queue on JuRepTool
- Possibility to use more than one helper function via `data_pre` (from right to left)
- Core pattern example configuration (when information of usage per core is available)

<h4> Changed </h4>

- Changed images on Web Portal to svg
- Improved [installations instructions](../install/index.md)
- Lock PR after merge (CLA action)
- Improved CITATIONS.cff
- Automatically create shareddir in remote Slurm action
- Changed name of crontab logs (to avoid problems in case remote and server run on the same place)

<h4> Fixed </h4>

- Fixed default values of wall, waittime, timetostart, and rc_wallh
- Improved how logs are cleaned to avoid stuck files
- Fixed workflow of jobs with a single step


### 2.2.1-base (November 29, 2023)

<h4> Changed </h4>

- Improved the parsing of values from LML to database

<h4> Fixed </h4>

- Added missing example configuration files


### 2.2.0-base (November 13, 2023)

A new package of the new version of LLview was released Open Source on [GitHub](https://github.com/FZJ-JSC/llview)!
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

