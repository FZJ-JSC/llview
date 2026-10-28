# Server Installation Instructions

## Dependencies

The dependencies of LLview Server are:

- **Cron** (`crontab`)
- **SQLite 3**
- **Perl (>= 5.0)**  
  Install all required modules in one command:
  ```bash
  cpan Archive::Tar Compress::Zlib Config::IniFiles Cwd Data::Dumper DBD::SQLite DBD::SQLite::BundledExtensions DBI Exporter File::Monitor File::Spec FindBin Getopt::Long IO::File JSON LWP::Protocol::https LWP::Simple LWP::UserAgent Parallel::ForkManager POSIX Storable SVG SVG::TT::Graph::Line Text::CSV_XS Time::HiRes Time::Local Time::Zone Tk Tk::NoteBook Tk::Table warnings::unused YAML::XS
  ```
  *(Note: If you plan to connect to an Oracle DB, also install `RPC::PlClient`.)*

- **Python (>= 3.9)** (used by JuRepTool and auxiliary API/log/git plugins)  
  Install all required packages in one command:
  ```bash
  pip install "matplotlib>=3.5.0" numpy pandas pyyaml plotly cmcrameri requests
  ```
  *(Note: If compressed HTML reports are to be generated with `--gzip`, Python must have been built with `gzip` support.)*

- <a name="jureptool_fonts"></a>**Fonts for JuRepTool:**
  - Sans-serif: *Liberation Sans* or *Arial*
  - Monospace: *Liberation Mono* or *Courier New*  
  *(See [JuRepTool Font Installation](#jureptool-font-installation) below for setup instructions.)*

---

## Configuration Overview

### The `.llview_server_rc` File

The primary environment configuration file for LLview Server is `~/.llview_server_rc`. It defines environment variables used across the server workflows:

- `$LLVIEW_SYSTEMNAME`: Unique identifier for the monitored HPC cluster.
- `$LLVIEW_HOME`: Path where the core `llview` repository was cloned.
- `$LLVIEW_CONF`: Path to your active configuration folder (outside the git repo).
- `$LLVIEW_DATA`: Storage folder for databases, temporary files, and logs. To use dedicated storage, either mount it directly here or link it:
  ```bash
  ln -s /path/to/external/volume $LLVIEW_DATA
  ```
- `$LLVIEW_SHARED`: Shared folder between [LLview Remote](remote_install.md#configuration) and LLview Server where files are staged. **Must match `$LLVIEW_SHARED` in `.llview_remote_rc`.**
- `$LLVIEW_SHUTDOWN`: Path to a trigger file used to pause execution without modifying cron (managed automatically via `llview start` and `llview stop`).
- `$LLVIEW_LOG_DAYS`: Number of days to retain server logs.
- `$LLVIEW_CONF_FILE`: Path to `.llview_server_rc` itself (allows the daemon to detect changes).
- `$PYTHON`: Absolute path to the Python interpreter satisfying the [dependencies](#dependencies).
- `$JUREPTOOL_NPROCS`: Worker processes for JuRepTool. **Recommendation:** Set `export JUREPTOOL_NPROCS=0` during initial setup, and only enable it once the main LLview cycle is verified.
- `$LLVIEW_WEB_DATA`: Destination folder on the Web Server where generated files will be copied.
- `$LLVIEW_WEB_IMAGE`: Path to the system image on the login page (default: `img/$LLVIEW_SYSTEMNAME.jpg`).

---

## Installation Steps

### 1. Clone the Code Repository
Clone the LLview code repository to your designated `$LLVIEW_HOME`:
```bash
git clone https://github.com/FZJ-JSC/llview.git
```

### 2. Set Up Configurations (`$LLVIEW_CONF`)
Configuration templates are maintained in the [llview-config](https://github.com/FZJ-JSC/llview-config) repository. 

> **Important:** Do **not** work directly inside the cloned `llview-config` repository. Working in a separate folder allows you to run `git pull` on the repo in the future to receive upstream updates cleanly.

1. **Clone the configuration template repository:**
   ```bash
   git clone https://github.com/FZJ-JSC/llview-config.git ~/repos/llview-config
   ```

2. **Deploy your configuration directory:**
   - **Recommended (Inheritance method):** Copy `example_system/` out of the repository into your own directory (e.g., `~/my_cluster_config`). This path becomes your `$LLVIEW_CONF`. Because `example_system/server/LLgenDB/LLgenDB.yaml` references `common/server/LLgenDB/LLgenDB_common.yaml` inside the repo, your installation automatically inherits upstream updates whenever you `git pull` the repo.
   - **Standalone method:** Copy the entire `common/` folder out of the repository to your target directory and modify all files locally.

3. **Deploy `.llview_server_rc`:** Copy `$LLVIEW_CONF/server/.llview_server_rc` to your home folder (`~/.llview_server_rc`) and customize the paths.

4. **Source your environment:**
   ```bash
   . ~/.llview_server_rc
   ```

### 3. Customize Actions and Permissions
LLview Server processes data using **actions** (first-level workflows) made up of **steps** (second-level tasks).

1. Edit `$LLVIEW_CONF/server/workflows/actions.inp` to enable required actions.
   > **Tip:** Start with all actions set to `active=0` and activate them one by one while checking log files.
2. Edit individual action files under `$LLVIEW_CONF/server/workflows/` (e.g., `LML_da_collect.conf`, `LML_da_dbupdate.conf`).
3. Set up the [webservice step](#webservice-step) under the `collect` action to map project and user permissions.
4. Set up the [transfer key pair](#transferreports-step) for sending data to the Web Server.

### 4. Initialize Database Tables
Before launching the server, SQLite databases and tables must be initialized from your YAML configurations in `$LLVIEW_CONF/server/LLgenDB/`:

```bash
$LLVIEW_HOME/scripts/updatedb
```
> <a name="updatedb"></a>**Reminder:** Run `updatedb` whenever you make changes to YAML configuration files in `LLgenDB/`.

### 5. Schedule the Server Daemon
LLview Server uses a monitor daemon launched periodically via cron to ensure high availability. If the daemon is already running, the cron script simply exits.

Append the cron entry safely:
```bash
(crontab -l 2>/dev/null; cat "$LLVIEW_HOME/da/workflows/server/crontab/crontab.add") | crontab -
```

Verify the entry:
```bash
crontab -l
# Expected output:
* * * * * . ~/.llview_server_rc ; perl "$LLVIEW_HOME/da/workflows/server/crontab/serverAll.pl"
```

---

## Detailed Workflow Actions and Modules

### `collect` Action
The `collect` action runs first. It retrieves raw data generated by Remote from `$LLVIEW_SHARED` and runs auxiliary server-side data collection plugins to assemble the LML files.

- <a name="webservice-step"></a>**`webservice` step:**  
  **This is a critical step to configure for each installation.**  
  To establish role-based access in LLview (restricting users to their own jobs/projects, mentors to mentored projects, and support to all jobs), user and account mapping data is required.  
  In the example configuration, this is generated every 15th cycle via `$LLVIEW_HOME/da/utils/exec_every_n_step_or_empty.pl` running an account script (such as JSC's internal `get_webservice_accounts.pl`). The output is written to `$LLVIEW_DATA/$LLVIEW_SYSTEMNAME/perm/wservice/accountmap.xml`. LLview uses this file to build folder structures and `.htaccess` access lists.  
  See [Account Mapping Documentation](accountmap.md) for details on creating this file. Support users can also be supplied via the [`supportinput` action](#supportinput-action).

### `dbupdate` Action
The `dbupdate` action ingests the collected LML files into SQLite databases and triggers post-processing workflows.

- **`LMLDBupdate` step:** Inserts processed LML records into SQLite tables according to definitions in `$LLVIEW_CONF/server/LLgenDB/`. (Requires tables to be initialized via [`updatedb`](#updatedb)).
- **`trigger_JobRep` step:** Signals the [`jobreport` action](#jobreport-action) to generate web reports in parallel.
- **`combineLML_all` step:** Merges individual LML snapshots into a single archive file (used for historical review and replay).

### `jobreport` Action
Creates web data and exports it to the Web Server according to definitions in `$LLVIEW_CONF/server/LLgenDB/`.

- <a name="transferreports-step"></a>**`transferreports` step:**  
  Transfers data securely from the LLview Server to the Web Server using SSH and `rrsync`.
  1. Generate a dedicated SSH key pair without a passphrase on the LLview Server:
     ```bash
     mkdir -p $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/perm/keys
     cd $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/perm/keys
     ssh-keygen -a 100 -t ed25519 -C 'LLview job report transport' -f www_llview_system_jobreport
     ```
  2. On the Web Server, append the public key to `~/.ssh/authorized_keys` with restricted options:
     ```bash
     from="<LLVIEW_SERVER_IP>",command="<path_to_rrsync>/rrsync.pl -wo <destination_data_folder>",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding <public_key_string>
     ```
     *(Note: `rrsync.pl` is bundled with JURI under `$JURI_HOME/utils/`)*.
  3. Update the step parameters with your Web Server SSH settings:
     ```ini
     -sshkey $permdir/keys/www_llview_system_jobreport
     -login <web_login_user>
     -port <ssh_port>
     -desthost <web_server_hostname>
     ```
  4. Perform an initial connection from the LLview Server to accept the host key:
     ```bash
     ssh -i $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/perm/keys/www_llview_system_jobreport <web_login_user>@<web_server_hostname>
     ```

### `icmap` Action (Interconnect Mapping)
Used to color compute nodes in detailed reports based on network rack or cell topology.
- Provide node-to-cell mappings in an `icmap` file located in `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/icmap`:
  ```text
  # nodelist_range[:str]  cell[:int]
  nd[0001-0005,0015-0020]  1
  nd[0006-0015]            2
  ```
  *(An example `icmap` file is available in the `llview-config` repository under `server/`)*.
- When updated, it triggers `$LLVIEW_HOME/da/utils/get_hostnodemap.py` to create `icnodemap.xml`, which is then imported into the database by `dbupdate`.

### `supportinput` Action
Watches a user file (default: `${LLVIEW_SHARED}/../config/support_input.dat`) containing support usernames (one per line). When updated, it syncs the list to `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/wservice` to assign portal-wide support permissions.

### Maintenance Actions (`compress`, `archive`, `delete`)
Manages historical temporary files in `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/jobreport/tmp/mngtactions` to prevent excessive disk space consumption.

### JuRepTool (PDF and HTML Job Reports)
JuRepTool generates standalone job metric reports when triggered by `${LLVIEW_SYSTEMNAME}/tmp/plotlists.dat`.

- **Configuration:** Edit YAML files under `$LLVIEW_CONF/jureptool/`:
  - `config.yml`: Visual styling, page size, timezone, and hostname.
  - `system_info.yml`: Cluster topology, core counts, memory sizes, and queue definitions.
  - `plots.yml`: Plot sections and graph definitions.
  - `logging.yml`: Logging destinations and verbosity.
- <a name="jureptool-font-installation"></a>**Install Fonts:**  
  Install Liberation or Arial/Courier fonts (see [Dependencies](#dependencies)):
  ```bash
  mkdir -p ~/.local/share/fonts/
  cp <fonts_folder>/*.ttf ~/.local/share/fonts/
  fc-cache -f
  rm -fr ~/.cache/matplotlib
  ```
- **Enable Processing:** Set `$JUREPTOOL_NPROCS` to a value greater than `0` in `~/.llview_server_rc`.

---

## Service Control and Monitoring

### Service Commands (`llview`)

You can control LLview Server execution using the built-in control commands:

- **Pause processing:**
  ```bash
  llview stop
  ```
  *(This creates `$LLVIEW_SHUTDOWN`. The cron task continues to trigger each minute, but immediately halts without starting actions).*
- **Resume processing:**
  ```bash
  llview start
  ```
  *(This removes `$LLVIEW_SHUTDOWN` and allows the daemon to resume processing).*
- **Stop permanently:** Kill the daemon and remove the cron job:
  ```bash
  pkill -f monitor_file.pl
  crontab -e  # Remove or comment out serverAll.pl
  ```

### Helper Scripts (`$LLVIEW_HOME/scripts/`)

- <a name="updatedb-script"></a>**`updatedb`:** Updates the database schema according to changes in YAML configurations without losing data.
  ```bash
  updatedb         # Update schema and print output to screen
  updatedb log     # Update schema and append output to log file
  updatedb viewlog # View the latest checkDB log file
  ```
- <a name="taillog"></a>**`taillog`:** Simplifies following active workflow logs via `tail -f`.
  ```bash
  taillog monitor       # Follow monitor daemon log
  taillog <actionname>  # Follow specific action log (e.g., taillog dbupdate)
  ```
- <a name="listerrors"></a>**`listerrors`:** Scans all log directories and displays all current error logs.
```
