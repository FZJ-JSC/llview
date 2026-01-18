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

1.  **Global Overview Page:** Lists all configured benchmarks. Columns include Name, First Run Date, Last Run Date, and Counts (Total vs. Valid).
2.  **Benchmark Detail Page:** Shows the summary table and graphs for a specific benchmark.

### Understanding Status & Failures
LLview automatically calculates a `_status` for every data point and uses this to generate the **Status History** sparkline (`...-S-S-F-S-S`) and count valid runs.

*   **S (Successful):** All critical metrics were found.
*   **F (Failed):** A metric required for plotting or a non-string parameter was found to be missing, `NaN`, `None`, or empty.

**How to report failures correctly:**
To ensure failures are tracked in the timeline, your benchmark workflow should generate a result file (e.g., CSV) even if the application crashes.

*   **Correct Approach:** Generate a CSV containing the input parameters (e.g., timestamp, compiler, nodes) but leave the performance metric columns **empty**. LLview will ingest this, mark the run as **FAILED**, and visualize it as a gap in the graph.
*   **Incorrect Approach:** Generating no file at all. LLview cannot track what doesn't exist, so the "Last Status" will remain stale (showing the last successful run).

**Status in the Dashboard:**

*   **Total Runs:** Counts all ingestions (Success + Failed).
*   **Valid Runs:** Counts only `S` runs.
*   **Status History:** Shows the last 5 runs (Oldest $\to$ Newest). A leading dash `-` indicates more history exists.

## 4. Aggregation & Visualization

This section controls how the raw data defined in `metrics` is grouped, aggregated, and displayed on the dashboard.

### The `table` Section (Aggregation)
The metrics listed here will define the **columns** of the summary table on the Benchmark Page.

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

### The `plots` and `plot_settings` Sections (Visualization)

You can define global defaults using `plot_settings` and specific graph definitions using the `plots` list. Settings follow an inheritance hierarchy: **Global < Local**.

```yaml
  # Global Settings (Inherited by all plots)
  plot_settings:
    group_by: [Stage, Modules]
    annotations: ['JobID', 'CommitHash']
    colors:
      colormap: 'Set1'
    styles:
      mode: 'lines+markers'

  # Plot Definitions
  plots:
    # Plot 1: Inherits all global settings
    - x: ts
      y: 'Bandwidth Copy'
    
    # Plot 2: Overrides global settings locally
    - x: ts
      y: 'Bandwidth Scale'
      group_by: [System] 
      styles:
        marker: { size: 10 }
```

### Plot Settings Reference

The following keys can be used inside `plot_settings` (globally) or inside a specific item in `plots` (locally).

| Key | Sub-Key | Description | Default / Options |
| :--- | :--- | :--- | :--- |
| **`group_by`** | | List of metrics used to split data into different curves. | `[]` (Single curve) |
| <span style="white-space:nowrap">**`annotations`**</span> | | List of metrics to display in the tooltip when hovering over data points. | `[]` |
| **`colors`** | `colormap` | Name of the Matplotlib/Plotly colormap to use. | `'tab10'` |
| | <span style="white-space:nowrap">`sort_strategy`</span> | Order in which colors are assigned to traces. Options: `'standard'`, `'reverse'`, `'interleave_even_odd'` | `'standard'` |
| | `skip` | List of HEX color codes to exclude from the colormap. | `[]` |
| **`styles`** | | Dictionary of style properties passed directly to the [Plotly.js Scatter trace](https://plotly.com/javascript/reference/scatter/). | `type: scatter`<br>`mode: markers`<br>`marker: { opacity: 0.9, size: 5 }` |

## 5. Structuring Benchmarks (Tabs)

For complex benchmarks, you can split the views using Tabs.

### A. Benchmark Tabs (Page Level)
Splits the entire page (Table + Footer). This is intended for a single benchmark application that supports different **execution modes** requiring completely different input parameters (columns).

*   **Usage:** Define a `tabs:` dictionary under the root benchmark.
*   **Inheritance:** Configuration defined at the **Root** level (Host, Token, `plot_settings`, etc.) is automatically inherited by the tabs unless explicitly overwritten inside the tab.

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
