# Configuration Releases

Ready-to-use template configurations are maintained in the [llview-config](https://github.com/FZJ-JSC/llview-config) repository.

> For setup instructions and details on using the inheritance pattern, see the [Configuration Overview](../install/index.md#configuration).

---

### 1.0 (October 29, 2026)

Initial release of the modular LLview configuration repository.

<h4> Added </h4>

- **Repository Structure:** Introduced the separation between `common/` (default baseline templates) and `example_system/` (cluster-specific overrides).
- **Plugins:** Example configurations for data collection plugins located under `plugins/` (Slurm, generic APIs, log files, and Git repositories).
- **Remote:**
  - Base workflow configuration for Slurm (`LML_da_slurm.conf`).
  - Example `.llview_remote_rc` environment file.
- **Server:**
  - Modular workflows for data collection (`collect`), database ingestion (`dbupdate`), and web export (`jobreport`).
  - Baseline `LLgenDB` YAML definitions for SQLite metric schemas and web presentation templates.
  - Interconnect topology mapping template (`icmap`).
  - Example `.llview_server_rc` environment file.
- **JuRepTool:**
  - Default YAML configurations for PDF and HTML detailed report generation (`config.yml`, `system_info.yml`, `plots.yml`, `logging.yml`).
