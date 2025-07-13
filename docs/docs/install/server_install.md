# Server Installation Instructions

## Dependencies

The dependencies of LLview Server are:

- Crontab
- Perl (>5) 
    - Modules (install with `cpan <ModuleName>`)
        - Data::Dumper
        - Getopt::Long
        - Time::Local
        - Time::HiRes
        - Time::Zone
        - FindBin
        - Parallel::ForkManager
        - File::Monitor
        - File::Spec
        - warnings::unused
        - Exporter
        - Storable
        - IO::File
        - POSIX
        - YAML::XS
        - DBI, RPC::PlClient (if OracleDB needs to be used)
        - DBD::SQLite
        - DBD::SQLite::BundledExtensions
        - Config::IniFiles
        - JSON
        - Compress::Zlib
        - Archive::Tar
        - LWP::Simple
        - LWP::UserAgent
        - LWP::Protocol::https
        - SVG
        - SVG::TT::Graph::Line
        - Tk
        - Tk::NoteBook
        - Tk::Table
        - Cwd

- Python (>3.9) (For JuRepTool and plugins for Prometheus and Gitlab)
    - Packages (install with `pip install <PackageName>`)
        - matplotlib (>3.5.0)
        - numpy
        - pandas
        - pyyaml
        - plotly
        - cmcrameri
        - requests
    - gzip (if compressed HTML are to be generated with option --gzip, python must have been installed with `gzip` capacities)
- SQLite3
- [Fonts for JuRepTool](#jureptool_fonts)
    - sans-serif: Liberation Sans or Arial
    - monospace: Liberation Mono or Courier New

## Configuration

### `.llview_server_rc`

The main configuration file of LLview Server is `.llview_server_rc`, that should be put on the home folder `~`.
This file export environment variables that will be used by the different scripts of LLview.
The existing variables are:

- `$LLVIEW_SYSTEMNAME`: Defines the system name.
- `$LLVIEW_HOME`: LLview's home folder, where the repo was cloned.
- `$LLVIEW_DATA`: Folder in which the data will be stored. It is also possible to use another hard drive or file system (depending on the amount of metrics, this may be recommended). Either the driver is directly mounted and defined in `$LLVIEW_DATA`, or a symbolic link is created:
    ```
    ln -s /externalvolume/ $LLVIEW_DATA
    ```
- `$LLVIEW_CONF`: Folder with the configuration files (example configuration files is given in `$LLVIEW_HOME/configs`).
- `$LLVIEW_SHARED`: A shared folder between LLview Server and [LLview Remote](remote_install.md#configuration), where the generated files from Remote will be written and read by the Server (therefore, it must be the same set up in `.llview_remote_rc` in the Remote part).
- `$LLVIEW_SHUTDOWN`: File to be used to stop LLview's workflow (the cronjob runs, but immediately stops).
- `$LLVIEW_LOG_DAYS`: Number of days to keep the logs.
- `$JUREPTOOL_NPROCS`: Number of processors used by JuRepTool. As JuRepTool runs in parallel to the main LLview workflow, it is recommended to initially use `export JUREPTOOL_NPROCS=0` to deactivate JuRepTool and only activate it when the full LLview cycle is already working.
- `$LLVIEW_WEB_DATA`: Folder on the Web Server (accessible via https) where the `data` will be copied to.
- `$LLVIEW_WEB_IMAGE`: Path of image to be used on the login page, relative to DocumentRoot (starting with `/`) or relative to `$LLVIEW_WEB_DATA` (default: `img/$LLVIEW_SYSTEMNAME.jpg`).
- `$PYTHON`: This variable is used to launch [JuRepTool](#jureptool). It is important to set the PYTHON variable to use the version with the [dependencies](#dependencies) satisfied.
- `$LLVIEW_CONF_FILE`: This variable is used to export the location of the file `.llview_server_rc` itself to be monitored for changes.

Extra definitions can be also exported or modules loaded in this file (for example, to satisfy the [Dependencies](#dependencies)).

### Actions

The collection and processing of data is done via actions (the first workflow level), which can contain many steps (second workflow level) each.
**It is recommended to activate actions and steps inside actions little by little**, and follow the `errlog` files, to find eventual issues and solve them as they appear.

- Edit action file `$LLVIEW_CONF/server/workflows/actions.inp` to the relevant actions to be used. It is recommended to start with `active=0` for all actions and activate them one by one.
- Edit the configuration options for each action (e.g. `$LLVIEW_CONF/server/workflows/LML_da_dbupdate.conf`), when needed. It is recommended to start all steps with `active="0"` and activate them little by little. (**Note**: a step may have dependencies that must be activated before or together with it.)
- Important reminders:
    - <a name="updatedb"></a> After making changes on the configurations that afect the databases (i.e., adding or removing tables), they must be updated. To avoid corrupting the databases or losing data, this step must be done manually. To simplify the task of updating the databases according to the new configurations, we provide the script `updatedb` in `$LLVIEW_HOME/scripts`, which can be run as:
        ```
        updatedb         [updates the db with output on screen]
        updatedb log     [updates the db appending the output to the log file $LLVIEW_DATA/$LLVIEW_SYSTEMNAME/logs/checkDB.`date +%Y.%m.%d`.log]
        updatedb viewlog [to view the logfile]
        ```
    `updatedb viewlog` can be used to check for errors (as `updatedb log` appends the output to the same log file, there may be more than one output accumulated in the same file). There is no problem running this command when the change in the configuration does not affect the databases, so it is recommended to run it after changes in the YAML files.
    - <a name="taillog"></a> To check the log and error files, we also provide a script `taillog` in `$LLVIEW_HOME/scripts` that can be used to simplify following these files with a `tail -f` command. It can be used by running
        ```
        taillog [monitor | (actionname)]
        ```
    - <a name="listerrors"></a> Another script provided in `$LLVIEW_HOME/scripts` that can be used to list all error files in the folders is `listerrors`.




#### `dbupdate` action

The `dbupdate` action mainly performs the collection of metrics into SQLite databases (plus other tasks such as archiving). The configuration of the different databases and their columns, types and values are done via the YAML files inside the `$LLVIEW_CONF/server/LLgenDB` folder.

##### `webservice` step

**This is an important step that should be edited in each installation.**

To be able to set up the correct permissions for the role-based access of LLview (where users will have access only to their own jobs and projects, while mentors can see jobs on all mentored projects and support can see all jobs), information on the user accounts and projects are needed. This is obtained in the `webservice` step of the `dbupdate` action. In the provided example configuration, this information is generated by `$LLVIEW_HOME/da/rms/JSCinternal/get_webservice_accounts.pl` (**not-included**) that is run at every 15th update via the script `$LLVIEW_HOME/da/utils/exec_every_n_step_or_empty.pl` (included), to avoid too many connections to the database. The output of this step should be put in the file `$LLVIEW_DATA/$LLVIEW_SYSTEMNAME/perm/wservice/accountmap.xml` that contains information to be added in the database. LLview will then use this information to generate the folders and `.htaccess` for the correct setting of permissions.

If needed, information about the users with support access can be obtained also via the [`supportinput` action](#supportinput-action).

More information about how to create this file [here](accountmap.md).

##### `LMLDBupdate` step

This is where all generated LMLs are processed and put into the databases, as defined in the configurations.

Note: For the SQL commands to work, the databases and tables must exist. They are created according to the configurations using the [`updatedb`](#updatedb) script.

##### `trigger_JobRep` step

Immediately after the data is inserted into the database, the [`jobreport` action](#jobreport-action) is triggered by this step, such that the generation of the files in that action can be done in parallel to the remaining steps of the current one.

##### `combineLML_all` step

In this step, all generated LMLs are combined into a single one to be archived (and they may also be used for a replay feature). This step is done after the [LMLDBupdate step](#lmldbupdate-step) to be done in parallel to the [`jobreport` action](#jobreport-action).




#### `jobreport` action

The `jobreport` action maily creates the data to be presented to the user and copies them to the Web Server. Its configuration is also done via the YAML files inside the `$LLVIEW_CONF/server/LLgenDB` folder.

##### `transferreports` step

The `transferreports` step inside the `jobreport` action is used to transfer data securely from the LLview Server to the Web Server. To use this step as it is by default, it is necessary to create an ssh-key pair:
    ```
    cd $LLVIEW_DATA/$SYSTEMNAME/perm/
    mkdir keys
    cd keys
    ssh-keygen -a 100 -t ed25519 -C 'LLview job report transport from LLview-Server' -f www_llview_system_jobreport
    ```
This must be created without any passphrase.
Then, on the Web Server, the public part of the key must be added in `~/.ssh/authorized_keys` as:
    ```
    from="<ip of LLview server>",command="<path to rrsync>/rrsync.pl -wo <folder where data will be copied into>",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding <complete public part of the ssh-key>
    ```
**Note:** the line above must be adapted to include the correct IP where the LLview Server part is running, the path to `rrsync.pl` on the web server (this tool is packed with JURI in the folder `$JURI_HOME/utils`), and the public part of the key created above.
Finally, the command itself must be updated with the correct values for:
    ```            
    -sshkey $permdir/keys/www_llview_system_jobreport
    -login <login on the web server>
    -port <port used>
    -desthost <webserver address>
    ```
**Note:** An initial login may be needed to accept the authenticity of the host (`ssh <login>@<webserver address>` and then `yes` is enough, even if you get "Permission denied" afterwards)



#### `liveview`

The `liveview` action uses the LLview client to create a live view of the jobs running on the system.

### JuRepTool

The `liveview` action uses the LLview client to create a live view of the jobs running on the system.



#### `icmap` action

To color the nodes in the detailed job reports according to their interconnect group, the information of their cell/rack can be given in an `icmap` file (by default, expected to be in the ``${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm` folder) containing a list of nodes with the following format:
    ```
    # nodelist_range[:str]  cell[:int]
    nd[0001-0005,0015-0020]  1
    nd[0006-0015]  2
    (...)
    ```
When this file is updated, the `icmap` is triggered and the information is then converted into an XML file `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/icnodemap.xml` via the `$LLVIEW_HOME/da/utils/get_hostnodemap.py` script. This XML file is then copied in the `da_icmap` step (defined in `$LLVIEW_CONF/server/workflows/LML_da_dbupdate.conf`) and then imported to the database in the `LMLDBupdate` step, to be used by the reports. 

Note: If the `icmap` action and/or the `da_icmap` copying step are not active or fail and the `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/icnodemap.xml` does not exist, there will be errors when trying to import it.


#### `supportinput` action

One of the options to set the users that have "Support" access on LLview is via the `supportinput` action. This action watches a file (default in `${LLVIEW_SHARED}/../config/support_input.dat`) that contains a simple list of usernames (one per line). When this file is changed, the file is copied to `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/wservice`. This file is then used in the [`webservice` step of the `dbupdate` action](#webservice-step).




#### `compress`, `archive` and `delete` actions

The actions `compress`, `archive` and `delete` perform maintenance actions that are created on the previous steps on the folder `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/jobreport/tmp/mngtactions`. They are important to keep the `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/jobreport/data` folder clean.






#### JuRepTool

JuRepTool is the LLview module that generates the PDF and HTML detailed reports. It runs as an action triggered by the file `${LLVIEW_SYSTEMNAME}/tmp/plotlists.dat`, which contains the list of jobs that needs to have their report created. The generated reports are automatically copied and made available on the LLview portal.
To setup and use JuRepTool:

- Update the config files located under `$LLVIEW_CONF/jureptool`. The configuration of the script and plots are given in 4 YAML files:
    - `config.yml`: General configuration such as fontsize, page size, colors, etc. (env vars can be used here)
    **Important**: Here it is important to check the `timezone` and `hostname` options.
    - `system_info.yml`: Information on the system names, queues and sizes (cores, CPU and GPU memory)
    **Important**: For the reports to be generated, the system name (as defined for LLview) and its queues should be listed here.
    - `plots.yml`: Configuration of sections and the graphs to be plotted in each of them. Keywords from `system_info.yml` may be used in `ylim`.
    - `logging.yml`: Logging information (filename, format, level)
- <a name="jureptool_fonts"></a>Add required fonts (Liberation Sans or Arial, Liberation Mono or Courier New). Liberation fonts are Open Source and can be downloaded from [Liberation Fonts' GitHub](https://github.com/liberationfonts/liberation-fonts/releases).
Fonts can be installed with:
    ```
    mkdir ~/.local/share/fonts/
    cp <fonts_folder>/*.ttf ~/.local/share/fonts/
    fc-cache -f
    rm -fr ~/.cache/matplotlib
    ```
- Give a non-zero value for the number of processes to be used by JuRepTool via the variable `$JUREPTOOL_NPROCS` in `.llview_server_rc`.

## Installation

- Make sure the [dependencies](#dependencies) are satisfied
- Get LLview:
    ```
    git clone https://github.com/FZJ-JSC/llview.git
    ```
This is where the `$LLVIEW_HOME` should be defined below, and the instructions use this notation.


- Configuration:
    - **[Optional]** Copy and update config folder in `$LLVIEW_CONF` (an example is given in `$LLVIEW_HOME/configs`)
    This folder contains all the configuration files which defines the specific configuration of what is collected and what will be presented to the users.
    **Note:** The folder structure should be kept, as some scripts use `$LLVIEW_CONF/server/(...)`.
    - Edit `.llview_server_rc` (an example is given in `$LLVIEW_HOME/configs/server`) and put it in the home folder `~/`, as this is the basic configuration file and it is the only way to guarantee it is a known folder at this point. The possible options are listed [here](#llview_server_rc).
    - Edit the `$LLVIEW_CONF/LLgenDB`: here is the whole configuration of metrics, databases, etc. This can also be adapted later, but changes here may require the [`updatedb`](#updatedb) command to be run to update the databases.
- Source the main configuration file, to be able to use the variable in the next steps: 
    ```
    . ~/.llview_server_rc
    ```
- Add cronjob to crontab:
    ```
    crontab $LLVIEW_HOME/da/workflows/server/crontab/crontab.add
    ```
Check if the cronjob is added correctly:
    ```
    $ crontab -l
    # start monitor daemon
    * * * * * . ~/.llview_server_rc ; perl "$LLVIEW_HOME/da/workflows/server/crontab/serverAll.pl"
    ```

The server part of LLview involves a daemon that starts to run the first time the `serverAll.pl` script is called. Further calls will check if it is already running, and will restart it in case it is not. This script will then run the different [actions](#actions), which can be triggered in different ways (as an example, the basic [`dbupdate` action](#dbupdate-action) monitors when a signal file was changed to start the process of copying and processing the data, and then touches a signal file to trigger the [`jobreport` action](#jobreport-action)).

The monitor daemon of LLview Server can be stopped either by `touch $LLVIEW_SHUTDOWN` (this file should be defined in `.llview_server_rc`) or killing the `monitor_file.pl` process. Note that the cronjob still restarts every minute - if `$LLVIEW_SHUTDOWN` exists, the process immediately stops without starting the daemon. To remove it altogether, additionally delete/comment out the cronjob (editing with `crontab -e`).

