# JURI Releases

Since the JURI (Jülich Reporting Interface) module is the same for the internal and the public versions, a single and separated page describe its changelog.

### 2.4.1 (November 1, 2025)

With the separation of the releases of LLview and JURI, their versions may differ in the future. This will allow a more dynamic development of both codes.

New on this version of JURI: Possibility to have tabs on pages (now used for History on production systems, and to be used for Continuous Benchmarks), plus many other internal improvements and fixes.

<h4> Added </h4>

- Added JUNIQ image
- Added possibility of tabs on pages (used also for History)

<h4> Changed </h4>

- Improved how tabs (and history) is created: new entry in refs, variable for separator (now set to '.') and single call to function
- Separated main element from `#main_content`, which is now a child of main and allows more flexibility
- Improved tabs visual
- Updated plotly to 3.1.0
- Improved margin of plots after update
- Improved selection of pages and cleaning up of pages
- Improved collection of functions, doing a single time at the beginning
- Removed focus outline on main_content
- Completely rewrite loading of templates using workers (in parallel)
- Scroll job into view after reload
- Make tabs accessible while loading pages, to be able to change tabs and avoid waiting unwanted pages
- Forced non-overflow-y of body
- Defer calling of functions after applying templates to keep responsiveness (also resize and remove of loading screen)

<h4> Fixed </h4>

- Fixed timezone on check of view_status_info (now expecting ISO format)
- Fixed profile div to avoid displaying html codes
- Fixed deletion of key of scripts and styles
- Fixed cleaning of footer graphs
- Fixed selection of grid rows when footer is not present
- Footer must be recreated when changing subpage (graphs may be different on different tabs)


### 2.4.0 (June 16, 2025)

Further improvements on JURI, including Queue Analysis and Queue View.

<h4> Added </h4>

- Added quick buttons to filter RUNNING, COMPLETED and FAILED jobs
- Added queue view using bar-plots (including calendar and fixed hoverinfo)
- Added jquery-ui for calendar
- Added quickfilter to URL to be able to restore it after refresh or link sharing
- Added JUPITER logo

<h4> Changed </h4>

- Make background color of colored cells stay in selected rows
- Improved mouse resizing of footer (including preventDefault to avoid selecting text when resizing)
- Improved CB tables with links
- Automatically show column that are used for sorting
- Updated plotly.js to 3.0.0
- Removed d3.csv parsing for plots
- Improved async plots when jobs are quickly selected
- Improved slider plots in 'Queue Analysis'
- 'username' in project page now clickable (to the user page on that given project)
- Generalised parsing of timestamps
- Other minor improvements

<h4> Fixed </h4>

- Fixed adding filter options to page
- Unified system names on login page
- Added `.js.gz` to `.htaccess`
- Slider bar with steps are updated directly with the event (plotly would not update all traces)
- Added 'id' to 'floatingFilters'
- Clean up the plots when plotting fails (when selecting a job, the wrong plots could be shown)
- Fixed fonts of the core patterns on Chrome
- Other minor fixes


### 2.3.2 (December 16, 2024)

<h4> Added </h4>

- Added possibility for links to status page (and current status) on all headers (file containing status should be updated externally, e.g. via cronjob)
- Added possibility to link to user profile (e.g.: JuDoor)
- Added parsing of pre-set filter options and button besides the top search (max. filters per column: 3)
- Added possibility to open login page in another window/tab when using middle mouse or ctrl+click on "home" button
- Add a check if user of 'loginasuser' exists or not
- Added 'jump to project' field on login
- Added helper function to convert number to hhmm
- Added graph for slider (used at the moment for coming 'Queue Analysis')

<h4> Changed </h4>

- Improved grid columns sizing
- Automatically open grid column group when a hidden column uses a filter
- Compressed external js libraries and added js.gz to `.htaccess`
- Removed deflate from `.htaccess`
- Turned off cache on `.htaccess` to avoid large memory consumption
- Improved style when viewwidth is reduced
- Improved filters (especially for dates)
- Made username in project page clickable
- Other small improvements

<h4> Fixed </h4>

- Fixed grid filter size
- Fixed link of 'jump to jobid' field
- Fixed buttons when loginasuser is used
- Fixed column show/hide
- Fixed grid filter containing '-' that is not a range
- Other small fixes



### 2.3.1 (July 10, 2024)

<h4> Added </h4>

- Possibility to filter graph data from CSV (with 'where' key)
- Added hoverinfo from 'onhover' also on scatter plots
- Added possibility to pass trace.line from LLview to plotly graphs

<h4> Changed </h4>

- Changed the storing of headers to save them for each page

<h4> Fixed </h4>

- Fix the size of the footer, to avoid table be under it
- Fix the escape of the column group names
- Fixes for some gridApi calls that return warnings or errors
- Removed autoSizeStrategy and minWidth from column defs, as that breaks their sizing and flexbox
- Fixed small bugs when columns or grids are not present


### 2.3.0 (May 21, 2024)

Faster tables! Using now ag-grid to virtualise the tables, now many more jobs can be shown on the tables. It also provides a "Quick Filter" (or Global Search) that is applied over all columns at once.

<h4> Added </h4>

- Added grid (faster tables) support using [ag-grid-community](https://github.com/ag-grid/ag-grid) library 
- Helper functions for grid
- Grid filters (including custom number filter, which accepts greater '>#', lesser '<#' and InRange '#-#'; and 'clear filter' per column)
- Quick filter (on header bar)
- Now data can be loaded from csv (usually much smaller than json)

<h4> Changed </h4>

- Adapted to grid:
    - Buttons on infoline (column groups show/hide, entries, clear filter, download csv)
    - Presentation mode
    - Refresh button
    - Link from jobs on workflows

<h4> Fixed </h4>

- Small issues on helpers
- Fixed color on 'clear filter' link


### 2.2.4 (April 3, 2024)

<h4> Added </h4>

- Added CorePattern fonts and style
- Added `.htpasswd` and OIDC examples and general improvements on `.htaccess`
- Added system selector when given on setup
- Added 'RewriteEngine on' to `.htaccess` (required for `.gz` files)
- Added buttons on fields in `login.php`
- Added home button
- Added mermaid graphs and external js
- Added svg-pan-zoom to zoom on graphs
- Added option to pass image in config
- Added "DEMO" on system name when new option `demo: true` is used

<h4> Changed </h4>

- Adapted `login.php` to handle also OIDC using REMOTE_USER
- Improved favicon
- Changed how versions of external libraries are modified (now via links, such that future versions always work with old reports)
- Updated plotly.js
- Improvements in column group names, with special characters being escaped
- Changed footer filename (as it does not include only plotly anymore)

<h4> Fixed </h4>

- Fix `graph_footer_plotly.handlebar` to have a common root (caused an error in Firefox)
- Fix `.pdf.gz` extension on `.htaccess` example
- Removed some anchors `href=#` as it was breaking the fragment of the page
- Fixed forwarding to job report when using jump to jobID
- Removed external js libraries versions

### 2.2.3 (February 13, 2024)

<h4> Added </h4>

- Added CorePattern fonts and style

<h4> Changed </h4>

- Changed how versions of external libraries are modified (now via links, such that future versions always work with old reports)
- Removed old plotly library
- Changed login.php to use REMOTE_USER (compatible with OIDC too)
- Improved favicon SVG

<h4> Fixed </h4>

- Fix graph_footer_plotly.handlebar to have a common root (to avoid xml error)
- Fix .pdf.gz extension on .htaccess


### 2.2.2 (January 16, 2024)

<h4> Added </h4>

- Added info button on the top right when a page has a 'description' attribute

<h4> Changed </h4>

- Improve footer resize
- Implemented suggestions from Lighthouse for better accessibility
- Colorscales improved, and changed default to RdYlGr


### 2.2.1 (November 29, 2023)

<h4> Added </h4>

- Added Presentation mode

### 2.2.0 (November 13, 2023)

JURI was released Open Source on [GitHub](https://github.com/FZJ-JSC/juri)!
