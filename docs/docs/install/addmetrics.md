# Adding new metrics

When a new source of metrics become available, there are a few steps that must be done to start collecting them and make it available on the front-end.

1. The first step is to create a plugin that will read the metrics from its source and generate an LML file with the desired quantities. One of the existing plugins in the folder `${LLVIEW_HOME}/da/rms/` (e.g., SLURM, Prometheus or Git) can be used as examples or as a starting point.
2. Add a step to run the plugin on every loop of LLview. If the plugin must be run on the system to be monitored (as, for example, the Slurm plugin that needs access to the `scontrol` and `sacct` commands), then this step should be added in the [Remote configuration](remote_install.md#configuration). Otherwise (which is generally the case), it should be added to the [`dbupdate` action of the Server configuration](server_install.md#dbupdate-action). Once again, the steps to run existing plugins can be used as examples.

    2.1. If the plugin is not supposed to run on every update, the script `${LLVIEW_HOME}/da/utils/exec_every_n_step_or_empty.pl` may be useful.

    2.2. If the collection should be done asynchronously, it can be added as an [action](server_install.md#actions) instead, and the generated file can be copied with the script `${LLVIEW_HOME}/da/utils/cp_if_newer_or_empty.pl`.

3. The new generated LML file should be added to the [`LMLDBupdate`](server_install.md#lmldbupdate-step) and [`combineLML_all`](server_install.md#combinelml_all-step) steps.
4. How the file is distributed in the databases (i.e., if the metrics will be put into existing DBs or into new ones) must be then described in the YAML configuration files in the `${LLVIEW_CONF}` folders. There are many existing DBs and tables that may be used as examples.
5. To add new metrics to the web portal, configurations on `${LLVIEW_CONF}/server/LLgenDB/conf_jobreport` can be added or modified. Metrics can be added to new or existing tables, graphs, footer, etc.

    5.1. The configuration of the existing pages are located in `${LLVIEW_CONF}/server/LLgenDB/conf_jobreport/views`

    5.2. Adding new metrics to the PDF and HTML reports may require extra configurations, as the metrics are put into `.dat` files that are used by JuRepTool. For example:

    * the `GPU_<jobid>_node.dat` containing the GPU metrics are defined in the dataset `GPU_node_dat` in `${LLVIEW_CONF}/server/LLgenDB/conf_jobreport/data_csv_dat/jobreport_datafiles_gpu.yaml`;
    * The filenames themselves need to be put into a database, which is defined in the table `jobfiles` in the configuration file `${LLVIEW_CONF}/server/LLgenDB/conf_jobreport/jobreport_databases.yaml`;
    * Then the filenames (together with aggregated metrics) are passed to JuRepTool via a (per-job) json file defined in `${LLVIEW_CONF}/server/LLgenDB/conf_jobreport/data_json/jobreport_datafiles_json_jureptool.yaml`;
    * Finally, when the information is available to JuRepTool for each job, the metrics can be added on the job reports via their configuration in `${LLVIEW_CONF}/jureptool/plots.yml`


See an [Example on how to add a new metric here](./addmetrics_example.md).