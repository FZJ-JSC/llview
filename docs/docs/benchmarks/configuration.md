# Configuration Guide

The configuration is defined in YAML file(s) (e.g., `benchmarks.yaml`). 
LLview can accept a single file (with one or more benchmarks) or a folder containing many separate YAML files.
See [examples of configuration files here](examples.md).


## 1. Defining the Benchmark and its Sources

On the top-level, you can define a **description** (supports HTML) to document your benchmark.

```yaml
MyBenchmark:
  description: 'General benchmark suite. See <a href="https://example.com">Documentation</a>.'
  host: '...'
  ...
```

LLview collects the data directly from a Git repository (e.g., GitLab).
To indicate from where (and how) the information should be obtained, you have to define the `host` (repository address), a `token` with "read_repo" access at a minimum Reporter level, and optionally a `branch` where the results are stored. 
Then, the `folders` or `files` list should be given as `sources` (also accepting regex patterns).

```yaml
MyBenchmark:
  # Git Repository Configuration
  host: 'https://git.example.com/project/benchmarks.git'
  branch: 'main'          # (Optional) Branch where result files are committed. Default: main
  token: "<token>"        # Access Token (requires read_repo / reporter level)

  # File Collection Rules (Applied inside the repo)
  # At least one of 'folders' or 'files' must be provided.
  sources:
    folders:
      - 'Results/'        # Recursively scans these folders in the repo
    files:                # Specific files or patterns to match
      - '.*\.csv'
    include: '.*_gcc_.*'  # (Optional) Regex: Only process files matching this pattern
    exclude: '.*_tmp.*'   # (Optional) Regex: Ignore files matching this pattern
```

## 2. Defining Metrics

The `metrics` section defines every data point you want to track. A metric can be obtained from the file content, filename, metadata, or calculated from other metrics.

```yaml
  metrics:
    # 1. From CSV Content (Default)
    # If 'header' is omitted, the key name ('mpi-tasks') is used as the CSV header.
    mpi-tasks:
      type: int
      header: 'MPI Tasks'
      description: 'Number of MPI Tasks used' # Shows as tooltip in the table header

    # 2. From Filename (using Regex)
    Compiler:
      from: filename
      regex: '.*_(gcc|intel)_.*'
      description: 'Compiler used for the build'

    # 3. From Metadata
    # Looks for a JSON object in comment lines inside the file (e.g. # {"job_id": 1234})
    # Note: Only top-level keys in the JSON structure are supported.
    JobID:
      from: metadata
      key: 'job_id'
      type: int
      description: 'Slurm Job ID'

    # 4. Derived Metrics (Formulas)
    # Calculates values based on other CSV headers.
    # Supported operators: +, -, *, /
    # Headers must be quoted if they contain spaces or special characters.
    Efficiency:
      type: float
      from: "'Performance' / 'Peak_Flops'"
      unit: '%'
      description: 'Calculated efficiency ratio'
```

!!! Warning
    Due to internal manipulation of the tables and databases, the following keys are forbidden (case-insensitive):
    `dataset`, `name`, `ukey`, `lastts_saved`, `checksum`, `status`, `mts`


### Metric Options Reference

| Option | Description |
| :------ | :--- |
| `type` | (Optional) Data type. Options: `str` (default), `int`, `float`, `ts` (timestamp). |
| `from` | (Optional) Source of data. Options: `content` (default), `filename`, `metadata`, `static`. If containing math operators, it acts as a formula. |
| `header` | (Optional) The column name in the CSV. Defaults to the metric key name if omitted. |
| `key` | (Required for `from: metadata`) The key name in the JSON metadata. |
| `regex` | (Required for `from: filename`) Regular expression to extract data from filenames. |
| `unit` | (Optional) String to display in graph axis labels (e.g., 'ns/d', 'GB/s'). |
| `description` | (Recommended) Brief text describing the metric. Used as a tooltip in the table. |
|  <span style="white-space:nowrap">`include`/`exclude`</span> | (Optional) List of values or Regex patterns to filter specific data rows based on this metric. |

## 3. Dashboard Structure & Status

LLview generates a hierarchy of views for your benchmarks:

1.  **Global Overview Page:** Lists all configured benchmarks. Columns include Name, First Run Date, Last Run Date, Total Data Points, and the Status of the most recent run.
2.  **Benchmark Detail Page:** Shows the summary table and graphs for a specific benchmark.

### Understanding Status & Failures
LLview automatically calculates a `_status` for every data point:

*   **SUCCESSFUL:** All metrics required for plotting (x-axis, y-axis, and trace definitions) are present and valid.
*   **FAILED:** Critical metrics are missing, `NaN`, `None`, or empty.

**How to report failures:**
To correctly track failed runs in the timeline, your benchmark workflow should generate a result file (e.g., CSV) even if the application crashes.

*   **Correct Approach:** Generate a CSV containing the input parameters (e.g., timestamp, compiler, nodes) but leave the performance metric columns **empty**. LLview will ingest this, detect the missing data, and mark the run as **FAILED**.
*   **Incorrect Approach:** Generating no file at all. LLview cannot track what doesn't exist, so the "Last Status" will remain "Successful" (from the previous valid run).

## 4. Aggregation & Visualization Logic

### The `table` Section (Aggregation)
The metrics listed here will define the **columns** of the summary table on the Benchmark Detail Page.

*   **How it works:** Each unique combination of values for these metrics generates one distinct, selectable row.
*   **Best Practice:** Use input parameters (e.g., `System`, `Nodes`, `Compiler`).
*   **Warning:** Do **not** put unique identifiers (like `JobID` or `Timestamp`) here. If you do, the grouped history graphs will contain only a single point per curve, defeating the purpose of a continuous benchmark. Instead, put these identifiers in the **`annotations`** field of the plots.

```yaml
  table:
    - System
    - Nodes
    - Compiler
    # Result: One row for "Cluster-A / 4 Nodes / GCC", another for "Cluster-A / 8 Nodes / Intel", etc.
```

### The `plots` Section (Curves & Annotations)
You can define plots using a simple list (single tab) or a dictionary (footer tabs).

*   **`traces`:** If you list metrics here (e.g., `traces: [Compiler]`), LLview calculates every unique value found for "Compiler" (e.g., "GCC", "Intel") and generates a separate curve for each.
    
*   **`annotations`:** A list of metrics to display in the tooltip when hovering over a specific data point. This is the correct place for unique metadata (Git Commits, Job IDs, Build timestamps) that provide context but do not define the curve itself.

    ```yaml
    plots:
      - x: ts
        y: Performance
        traces: ['Nodes']
        annotations: ['JobID', 'CommitHash'] # Shows ID and Commit on hover
    ```

## 5. Structuring Benchmarks (Tabs)

### A. Benchmark Tabs (Page Level)
Splits the entire page (Table + Footer). This is intended for a single benchmark application that supports different **execution modes** requiring completely different input parameters (columns).

*   **Usage:** Define a `tabs:` dictionary under the root benchmark.
*   **Inheritance:** Configuration defined at the **Root** level (Host, Token, Description, Sources) is automatically inherited by the tabs unless explicitly overwritten inside the tab.

### B. Footer Tabs (Graph Level)
Splits the graphs area into visual tabs. This is useful for organizing many plots (e.g., separating "Performance" graphs from "System Usage" graphs).

*   **Usage:** Instead of a list, `plots` becomes a dictionary where keys are the tab names.

```yaml
  plots:
    tabs:
      Performance:    # Tab Name
        - x: ts
          y: 'Throughput'
      Runtime:        # Tab Name
        - x: ts
          y: 'Total Runtime'
```

## 6. Styling

Styles follow an inheritance hierarchy: **Global < Local**.

1.  **Global Styling (`traces` key):** Sets the default look for *all* plots in the benchmark.
2.  **Local Styling (`styles` key inside `plots`):** Overwrites the global settings for that specific graph.
