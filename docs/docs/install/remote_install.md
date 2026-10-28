# Remote Installation Instructions

## Dependencies

The dependencies of LLview Remote are:

- **Cron** (`crontab`)
- **Perl (>= 5.0)**  
  Install all required modules in one command:
  ```bash
  cpan Config::IniFiles Data::Dumper DBD::SQLite DBI Exporter File::Monitor File::Spec FindBin Getopt::Long IO::File JSON Parallel::ForkManager POSIX Storable Time::HiRes Time::Local warnings::unused YAML::XS
  ```
- **Python (>= 3.9)** (used by the workload manager data collection plugin)  
  Install the required package:
  ```bash
  pip install pyyaml
  ```

---

## Configuration

LLview Remote requires an environment file (`~/.llview_remote_rc`) and a configuration directory containing workflows and plugin settings (available in the [llview-config](https://github.com/FZJ-JSC/llview-config) repository).

### The `.llview_remote_rc` File

The primary configuration file for LLview Remote is `~/.llview_remote_rc`. It defines environment variables used across the Remote scripts:

- `LLVIEW_SYSTEMNAME`: Unique identifier for the monitored HPC cluster.
- `LLVIEW_HOME`: Installation path where the `llview` repository was cloned.
- `LLVIEW_CONF`: Path to your configuration folder (containing `remote/`, `plugins/`, etc.).
- `LLVIEW_DATA`: Path to the directory where runtime and intermediate data are stored.
- `LLVIEW_SHARED`: Shared directory accessible by both LLview Remote and [LLview Server](server_install.md#configuration). Remote writes output files here, and the Server ingests them. **This path must match `$LLVIEW_SHARED` in `.llview_server_rc`.**
- `LLVIEW_SHUTDOWN`: Path to a trigger file used to pause execution without modifying cron (if this file exists, workflows exit immediately).
- `LLVIEW_LOG_DAYS`: Number of days to retain log files.

> **Tip:** You can also use `.llview_remote_rc` to load environment modules (e.g., `module load perl python`) or set system-specific environment variables required by [dependencies](#dependencies).

---

## Installation Steps

### 1. Prerequisites and Source Code
1. Verify that all [dependencies](#dependencies) are installed.
2. Clone the core repository to your chosen `$LLVIEW_HOME`:
   ```bash
   git clone https://github.com/FZJ-JSC/llview.git
   ```

### 2. Configure LLview Remote
Example configuration files are provided in the [llview-config](https://github.com/FZJ-JSC/llview-config) repository (see the [Configuration Overview](index.md#configuration) for an explanation of `common/` vs. `example_system/`):

1. **Obtain the configurations:**
   Clone the configuration repository to a reference directory:
   ```bash
   git clone https://github.com/FZJ-JSC/llview-config.git ~/repos/llview-config
   ```
   Copy either `common/` or `example_system/` outside of the repository to your dedicated configuration directory (e.g., `~/my_remote_config`). This path will be your `$LLVIEW_CONF`.
   > **Note:** Preserve the internal folder structure (`plugins/`, `remote/`, etc.), as internal scripts rely on standard subfolder paths.

2. **Deploy `~/.llview_remote_rc`:** Copy the template from `$LLVIEW_CONF/remote/.llview_remote_rc` to your home directory (`~/.llview_remote_rc`) and update the paths to match your system.

3. **Set the execution host pattern:**
   Open `$LLVIEW_CONF/remote/workflows/LML_da_slurm.conf` and set:
   ```ini
   executehostpattern = <hostname_or_regex>
   ```
   *Why this is needed:* If home directories are shared across multiple nodes (e.g., login or head nodes), this setting ensures the cron job only runs on the designated monitoring node, preventing duplicate runs and data race conditions.

4. **(Optional) Review plugin settings:** Check `$LLVIEW_CONF/plugins/slurm.yml`. The default configuration works out of the box for standard Slurm installations (and Flux systems using the Slurm compatibility layer), but you can adjust query limits or timeouts if needed.

### 3. Schedule the Cron Job

LLview Remote does not run as a persistent daemon; instead, it executes periodically (every minute) via `cron`.

Append the Remote job safely to your crontab:
```bash
(crontab -l 2>/dev/null; cat "$LLVIEW_HOME/da/workflows/remote/crontab/crontab.add") | crontab -
```

Verify that the cron job was installed correctly:
```bash
crontab -l
# Expected output:
* * * * * . ~/.llview_remote_rc ; perl "$LLVIEW_HOME/da/workflows/remote/crontab/remoteAll.pl"
```

---

## Operation

- **Pause processing:** Run `touch $LLVIEW_SHUTDOWN` (as defined in `.llview_remote_rc`). The cron job will continue to trigger each minute, but the script will immediately exit without querying the workload manager.
- **Resume processing:** Remove the shutdown file: `rm $LLVIEW_SHUTDOWN`.
- **Stop permanently:** Remove or comment out the line in `crontab -e`.
