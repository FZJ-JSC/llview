# Example: Adding CPU Model to LLview
Author: Matthias Lapu - CEA

This is a step-by-step walkthrough from the beginning (collection) to end (visualisation) on how to add an example metric to LLview. Please read it fully to understand. To make this simple, we'll add the CPU model as a new metric. Since the collection is done on Prometheus, this guide will only concern the Server part of LLview.

Let’s start with a quick recap of the workflow needed to add a new metric:

1. Find the metrics you want to add, and write the correct Prometheus query.
2. Add the new metrics to the databases.
3. Create an aggregation with the `jobid` (if not done already).
4. "Link" the databases to the jobreport.
5. Add the data to the visualization.


## Cheat sheet of files to be modified


| Step | File Path                                                                  | Purpose                                                                   |
|------|----------------------------------------------------------------------------|---------------------------------------------------------------------------|
| 1    | `configs/plugins/promet.yml`                                               | Adding your new Prometheus query to generate LML file                     |
| 1    | `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/model_cpu_LML.xml`                | Newly generated LML file (generated automatically by the plugin)          |
| 2    | `configs/server/LLgenDB/conf_cpu/model.yaml`                               | Defining an SQLite table structure for the new metric                     |
| 2    | `configs/server/LLgenDB.yaml`                                              | Including the table in the database config                                |
| 2    | `configs/server/workflows/LML_da_dbupdate.conf`                            | Add LML file to `LMLDBupdate` and `combineLML_all`                        |
| 2    | `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/db/LLmonDB_modelstate.sqlite`    | Testing the new database                                                  |
| 3    | `configs/server/LLgenDB/conf_cpu/model.yaml`                               | Add aggregation by `jobid`                                                |
| 4    | `configs/server/LLgenDB/conf_jobreport/jobreport_databases.yaml`           | Export metric to job report database                                      |
| 4    | `configs/server/LLgenDB/conf_jobreport/data_json/jobreport_datafiles_json_common_joblist.yaml` | Add column(s) to JSON output                          |
| 4    | `${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/db/LLmonDB_jobreport.sqlite`     | Testing if the new metric is in the jobreport database                    |
| 5    | `configs/server/LLgenDB/conf_jobreport/views/`                             | Choosing where you want the data to be displayed                          |
| 5    | `configs/server/LLgenDB/conf_jobreport/data_templates/<template_file>.yaml`| Add column to template                                                    |

> Replace "model" with the corresponding metrics to add

## 1. Adding the CPU Model as a Metric

### What to do

In Prometheus, the query `node_cpu_info` gives you a lot of useful data.
First, if not done already, in your Prometheus `node_exporter` configs, make sure that `--collector.cpu.info` is **enabled**. This flag might change depending on the version you're using.

*For this tutorial, node_exporter version 1.9.1 was used.*

We’ll build the query:
```promql
max by (instance, model_name) (node_cpu_info{job="node-compute"})
```

This gives us the `model_name`, which is the metric we’re interested in.

We’ll need LLview to run this query and create an LML file, which will later be used to update the database.

### Configuration

To create this file, append this part to `configs/plugins/promet.yml`:

```yaml
prometheus:
  hostname: <hostname>
  credentials: <credentials>
  # Different (XML) files to be created can be given here
  files:
################################################################################
## model_name -> .e.g "Intel (R)"
################################################################################
    model_name:
      LML: "./model_cpu_LML.xml"
      prefix: "mdcpu"
      regex: '^(.+):.*$'
      type: "node"
      metrics:
        model:
          query: max by (instance, model_name) (node_cpu_info{job="node-compute"})
          default: 0
          cache: true
      mapping:
        md_ts: "md_ts"
        model_name: "model_name"
```

This creates:

- A new file named: `model_cpu_LML.xml`; 
- With the default type to add any kind of node metrics
- The mapping allows LLview to get the `model_name` from the query and add it to the LML file.

### Test

Let’s see if everything works:

```sh
# ${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/tmp/<xml_file>
cat /data/system/tmp/model_cpu_LML.xml
```

Gives the following:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<lml:lgui xmlns:lml="http://eclipse.org/ptp/lml" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://eclipse.org/ptp/lml http://eclipse.org/ptp/schemas/v1.1/lgui.xsd"
    version="1.1">
<objects>
<object id="mdcpu0" name="c1" type="node"/>
<object id="mdcpu1" name="c2" type="node"/>
<object id="mdcpu2" name="c3" type="node"/>
<object id="pstat_getmodel_name" name="getmodel_name" type="pstat"/>
</objects>
<information>
<info oid="mdcpu0" type="short">
 <data key="model_name"             value="11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz"/>
</info>
<info oid="mdcpu1" type="short">
 <data key="model_name"             value="11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz"/>
</info>
<info oid="mdcpu2" type="short">
 <data key="model_name"             value="11th Gen Intel(R) Core(TM) i5-1135G7 @ 2.40GHz"/>
</info>
<info oid="pstat_getmodel_name" type="short">
 <data key="startts"                value="1763646003.88155"/>
 <data key="datats"                 value="1763646003.88155"/>
 <data key="endts"                  value="1763646003.8865278"/>
 <data key="duration"               value="0.004977703094482422"/>
 <data key="nelems"                 value="3"/>
 <data key="nelems_node"            value="3"/>
</info>
</information>
</lml:lgui>

```

As we can see, data are updated with the CPU model and the recent timestamp (`ts`).

## 2. Adding a New Metric to the Databases

### What to do

This new metric is now available as an LML file. To add this file to the databases, we’ll need to add it to `configs/server/LLgenDB.yaml`. This file contains all the SQLite databases.

We’ll create a new file named `model.yaml` with three columns: the nodeid, the timestamp, and the model. This will allow us to have the CPU model for each node in our Prometheus cluster.

### Configuration

```yaml
modelstate:
  tables:
    - table:
        name: model
        options:
          update:
            LML: node
            mode: add
          archive:
            limit: max(ts)-25h
          index: nodeid,ts
        columns:
          - { name: nodeid, type: nodeid_t, LML_from: id, LML_default: 'unknown' }
          - { name: ts,     type: ts_t,     LML_from: ts, LML_default: -1, LML_minlastinsert: mintsinserted }
          - { name: model,  type: longstr_t, LML_from: model_name, LML_default: 'unknown' }
```
With the file created, we need to add it to `LLgenDB.yaml`. This will cause `updatedb` to actually create this database:
> Always run the `updatedb` script after making any changes to the database configuration.

```yaml
databases:
...

  # load, memory, status of nodes
  %include "conf_cpu/loadmem.yaml"
  %include "conf_cpu/model.yaml"
```

Finally, add the LML file to the steps `LMLDBupdate` and `combineLML_all` in the action `dbupdate` located in the file `configs/server/workflows/LML_da_dbupdate.conf`.

```conf
  <!-- --------------------------------------- -->
  <!--   add data to database                  -->
  <!-- --------------------------------------- -->
  <!-- Depending on the plugins used above, more files should be added
  <!-- to the steps 'LMLDBupdate' and 'combineLML_all' below, for example: -->
  <!--                                      $tmpdir/gpus_LML.xml           -->
  <!--                                      $tmpdir/ibms_LML.xml           -->
  <!--                                      $tmpdir/cores_LML.xml          -->
  <!--                                      $tmpdir/cores.percore_LML.xml  -->
  <!--                                      $tmpdir/CB.xml                 -->
  <!-- STEP: This step should include all xml files to be included in the database -->
  <step active="1" id="LMLDBupdate" exec_after="rawdataready" type="execute">
    <cmd  exec="$perl $instdir/LML_DBupdate/LML_DBupdate.pl --dbdir=$permdir/db/
                                                            --config $configdir/server/LLgenDB/LLgenDB.yaml
                                                            --updatealways='reservation,classes'
                                                            --maxprocesses 6

                                                            ...

                                                            $tmpdir/model_cpu_LML.xml
                                                            "/>

```


```conf
  <!-- --------------------------------------- -->
  <!--   combine all data                      -->
  <!-- --------------------------------------- -->
  <!-- Create a single xml file with the combined data of all xml files (for archiving and replay) -->
  <step active="1" id="combineLML_all" exec_after="rawdataready" type="execute">
    <cmd  exec="$perl $instdir/LML_combiner/LML_combine_obj.pl  -noupdate
                                                                -nopstat 
                                                                -o $permdir/LMLraw_all.xml

                                                                ...

                                                                $tmpdir/model_cpu_LML.xml
                                                                "/>
  </step>
```

### Test

Now the metric should be in the SQLite database after applying the script `llview/scripts/updatedb`. To test this, go to:

```sh
cd ${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/db
```

And search for your new database, with our example, this gives us:

```sh
ls -l|grep "model"
-rw-r--r--. 1 root root  49152 Nov 20 14:10 LLmonDB_modelstate.sqlite
```

By opening the file using sqlite3, we can see that the columns are there and filled with the data coming from the LML file:

```sql
sqlite3

ATTACH 'LLmonDB_modelstate.sqlite' AS test;
SELECT name FROM test.sqlite_master WHERE type='table'; -- we can see here all the databases
SELECT * FROM test.model LIMIT 10;
PRAGMA test.table_info('model'); -- to see the column name
```

For our example, the result of the query is the following:

```
sqlite> SELECT * FROM test.model LIMIT 10;

c1|1763647801|XXth Gen Intel(R) Core(TM) iX-XXXXXX
c2|1763647801|XXth Gen Intel(R) Core(TM) iX-XXXXXX
c2|1763647862|XXth Gen Intel(R) Core(TM) iX-XXXXXX
```

## 3. Creating an Aggregation with the Jobid


### What to do

In step 2 we created a databases that gets data from the node itself, they are in no case related to the job. But for the job reporting to work we need to have the `id` of the job, .ie `jobid`. To do so we'll create an aggregation with other tables from LLview and the table `model`.

### Configuration

We’ll change the file `model.yaml`:

```yaml
modelstate:
  tables:
    %include "../conf_common/jobmap_tables.yaml"
    %include "../conf_common/nodeinfo_tables.yaml"

    - table:
        name: model
        options:
          update:
            LML: node
            mode: add
          update_trigger:
            - model_aggr_by_jobid
          archive:
            limit: max(ts)-25h
          index: nodeid,ts
        columns:
          - { name: nodeid, type: nodeid_t, LML_from: id, LML_default: 'unknown' }
          - { name: ts,     type: ts_t,     LML_from: ts, LML_default: -1, LML_minlastinsert: mintsinserted }
          - { name: model,  type: longstr_t, LML_from: model_name, LML_default: 'unknown-from-db' }

    - table:
        name: model_aggr_by_jobid
        options:
          update:
            sql_update_contents:
              vars: mintsinserted
              sql: |
                DELETE FROM model_aggr_by_jobid
                WHERE jobid IN (
                  SELECT DISTINCT jt.jobid
                  FROM jobtsmap jt, jobnodemap jn, model m
                  WHERE jt.ts >= mintsinserted AND jt.jobid = jn.jobid AND jn.nodeid = m.nodeid
                );

                INSERT INTO model_aggr_by_jobid
                  (jobid, md_ndps, mdlastts, model)
                SELECT
                  jt.jobid,
                  COUNT(DISTINCT m.nodeid) AS md_ndps,
                  MAX(m.ts) AS mdlastts,
                  GROUP_CONCAT(m.model, ', ') AS model
                FROM jobtsmap jt, jobnodemap jn, model m
                WHERE
                  jt.ts >= mintsinserted AND
                  jt.jobid = jn.jobid AND
                  jn.nodeid = m.nodeid AND
                  jt.ts = m.ts
                GROUP BY jt.jobid;
          archive:
            limit: max(mdlastts)-25h
        columns:
          - { name: jobid,    type: jobid_t }
          - { name: md_ndps,  type: count_t }
          - { name: mdlastts, type: ts_t }
          - { name: model,    type: longstr_t }

```
In this file:

1. We import two files `jobmap_tables.yaml` and `nodeinfo_tables.yaml`, which contain all the data related to the nodeid and the jobid.
2. Creates a new table named `model_aggr_by_jobid` that will contain the aggregation by jobid. The column **must** contains `jobid` otherwise it will not work.
3. Finally, the query gets the data from the three databases to connect the jobid with the nodeid from the model table.

Following the same query template should work, no matter what metrics you're using.

## 4. Updating the jobreport action

### What to do
Now that the database that aggregates the jobid works, you can export the column you’re interested in to the file `configs/server/LLgenDB/conf_jobreport/jobreport_databases.yaml`:

### Configuration

Add to `jobreport_databases.yaml`:

```yaml
jobreport:
  tables:
  - table:
      name: joblist
      options:
        update:
          LLjobreport: update_from_other_db(jobid,tabstat,updatedjobs)
        update_trigger:
            ...
          limit:      max(ts_start)-21d,max(ts)-21d
          limit_save: max(ts_start)-25h,max(ts)-25h
        index: jobid,lastts
      columns:
        ...
        - { name: model, type: longstr_t, LLDB_from: modelstate/model_aggr_by_jobid, LL_default: "unknown-from-yaml" }
```
Now the metric should be available in the `joblist` database. Before going any further, check that your metric is indeed there in the file:

```sh
${LLVIEW_DATA}/${LLVIEW_SYSTEMNAME}/perm/db/LLmonDB_jobreport.sqlite
```

Adapt the command from [here](#test_1).

Finally export the column in `configs/server/LLgenDB/conf_jobreport/data_json/jobreport_datafiles_json_common_joblist.yaml`.

```yaml
data_database:   jobreport
data_table:      "joblist, jobmetrics, jobscores, pdffiles_reg, htmlfiles_reg"
data_table_join_col: jobid
stat_database:   jobreport_json_stat
column_convert: 'firstts->hhmmss_sincenow,lastts->hhmmss_sincenow,ts->todate_std_hhmm,
                ...
columns: 'jobid, ts, owner, wall, queue, account, mentor, runtime,
        ...
         model, nummsgs, numerrnodes,
...
```

## 5. Adding the Metric to the Visualization

You’ll need to decide where you want the data to be displayed. I wanted to add it to the support page. All the visualization configs are located in `configs/server/LLgenDB/conf_jobreport/views`.

The support page uses a datatables template. We can see that in the file `configs/server/LLgenDB/conf_jobreport/views/jobreport_view_support.yaml`:

```yaml
  - page:
            name: "Jobs"
            section: "jobs"
            description: "This page contains all jobs (with more than 1-min of runtime) that are running or finished running on the system in the last three weeks."
            template: "/data/LLtemplates/datatable"
```
So we’ll need to add a new value to the datatables. The template is located in `configs/server/LLgenDB/conf_jobreport/data_templates/jobreport_datafiles_datatable_template_joblist_columns.yaml`. Add this in any section:

```yaml

# Load/Memory
- {
    headerName: "Load/Memory",
    groupId: "Load/Memory",
    children: [
        ...
      {
        field: "model",
        cellDataType: "text",
        headerName: "Model",
        headerTooltip: "Model name of the CPU used by the job",
        valueFormatter: "(params) => params.value ? params.value : 'unknown'"
      }
    ]
  }
```

Your changes are now in place -> Check LLview to confirm everything is working as expected.
