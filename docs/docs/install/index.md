# LLview

The public release of LLview is available on [GitHub](https://github.com/FZJ-JSC/LLview).
It provides a streamlined distribution containing all the core scripts, databases, and plugins required for a fully functional HPC monitoring environment.

This version includes:

- Core framework to process configurations, manage SQLite databases, and prepare data for web presentation
- JuRepTool to generate detailed PDF and interactive HTML job reports
- Plugins for:
  - Slurm workload manager (also works for the flux workload manager)
  - Generic APIs (HTTP requests, REST APIs, Prometheus, etc.)
  - Flat log files (via regular expressions)
  - Git repositories

Planned for future updates:

- Client and live view (schematic cluster node view of running jobs)
- JuFo (Jülich Forecast / queue wait-time prediction)
- Additional workload manager and hardware metric plugins
- Access Logger (monitoring LLview portal traffic and usage metrics)

---

## Software Structure

As an HPC monitoring system, LLview operates in three distinct phases: **(1) collecting** raw metrics, **(2) processing and storing** them, and **(3) presenting** the results to users. 

To minimize overhead on compute resources, these tasks are typically distributed across three separate environments:

- **Data Collection ([Remote](remote_about.md)):** Runs directly on the monitored HPC system (e.g., on a login or management node) where the LLview service account has permissions to inspect system-wide job data.
- **Data Processing ([Server](server_about.md)):** Runs on an independent server outside the HPC cluster. It collects additional external metrics, aggregates data every minute, updates SQLite databases, and formats output tables and plots without placing load on compute nodes.
- **Presentation ([JURI Web Server](juri_about.md)):** Hosts the user-facing web portal using the Jülich Reporting Interface (JURI).

---

## Installation Instructions

Because each stage depends on output from the previous one, components should be set up in the following order:

1. [Remote Installation](remote_install.md)
2. [Server Installation](server_install.md)
3. [JURI Web Portal Installation](juri_install.md)

---

## Configuration

Both the **Remote** and **Server** components require configuration files to orchestrate their workflows:

- **Remote:** Minimal workflow configuration to execute the workload manager plugin (e.g., Slurm) and stage generated files for the Server.
- **Server:** Comprehensive configuration covering:
  - Workflow orchestrations (`collect`, `dbupdate`, `jobreport`)
  - Secondary data collection plugins
  - Database definitions, schemas, and web export templates (`LLgenDB`)
  - Detailed report templates (PDF and HTML via JuRepTool)

### The `llview-config` Repository

Ready-to-use template configurations are maintained in the [llview-config](https://github.com/FZJ-JSC/llview-config) repository. The repository contains two top-level directories:

- `common/`: Base templates and default definitions used across systems.
- `example_system/`: A practical, working cluster configuration demonstrating how to override base defaults.

Both directories share a standardized subfolder structure:

- `jureptool/`: Settings, system limits, and styling for PDF/HTML reports.
- `plugins/`: Configuration files for data collection plugins.
- `remote/`: The `.llview_remote_rc` environment file and Remote workflow definitions.
- `server/`: The `.llview_server_rc` environment file, `icmap`, Server workflows, and the `LLgenDB/` directory (database definitions and web export configurations).

### Configuration Inheritance (Defaults vs. Overrides)

The key difference between `common/` and a system-specific directory (such as `example_system/`) lies in `server/LLgenDB/`.

In `example_system/server/LLgenDB/LLgenDB.yaml`, the configuration imports `common/server/LLgenDB/LLgenDB_common.yaml` by reference. This treats the files in `common/` as the default baseline—meaning your system folder only needs to define files that **extend or override** those defaults.

### Setup Strategies

To keep your deployment maintainable, we recommend keeping your active configuration directory **outside** of the cloned `llview-config` git repository:

1. **Inheritance Method (Recommended):**  
   Clone `llview-config` to a reference location, then copy `example_system/` to your own dedicated configuration directory (e.g., `~/my_cluster_config/`). Keep the references pointing to `common/` in the cloned repo.  
   *Why this is recommended:* When new metric definitions or bug fixes are published to `llview-config`, you can simply run `git pull` in the repository to receive updates in `common/` automatically, without merge conflicts in your custom configuration.

2. **Standalone Method:**  
   Copy the entire `common/` directory out of the repository to your custom folder and modify all files locally. Upstream updates must then be merged manually.

> Step-by-step setup guides for each component are provided in the [Remote Installation](remote_install.md) and [Server Installation](server_install.md) documentation.
