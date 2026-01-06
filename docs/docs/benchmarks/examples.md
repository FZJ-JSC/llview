# Configuration Examples

## Example 1: Simple Configuration
A basic setup tracking performance over time, grouping runs by Node count.

```yaml
SimpleBenchmark:
  host: 'https://git.example.com/benchmarks/simple.git'
  token: "<token>"
  
  sources:
    folders: ['results/']

  metrics:
    ts:
      type: ts
      header: 'timestamp'
    Performance:
      type: float
      unit: 'GFlops'
      description: 'Calculated GFlops'
    Nodes:
      from: filename
      regex: 'run_(\d+)nodes_.*'
      type: int
      description: 'Number of compute nodes'

  # Table columns: One row per Node count
  table:
    - Nodes

  # Plot Performance vs Time, with one curve per value of Node count
  plots:
    - x: ts
      y: Performance
      traces:
        - Nodes
```

## Example 2: Complex Configuration (Multi-Mode Application)
This example demonstrates a generic Molecular Dynamics application ("MolecDyn") that runs in two distinct modes: **Simulation** (performance measured in ns/day) and **Energy Minimization** (convergence measured in steps). It also demonstrates using **Derived Metrics** and **Annotations**.

```yaml
MolecDyn_Suite:
  # Root configuration: Inherited by all tabs
  host: 'https://git.example.com/science/molecdyn.git'
  token: "<token>"
  description: "Molecular Dynamics Regression Suite"
  
  # Page-Level Tabs: Separates distinct execution modes
  tabs:
    # Tab 1: Standard Time-Step Simulation
    Simulation:
      description: 'Standard MD Production Run'
      sources:
        folders: ['data/simulation']
        
      metrics:
        # Metrics specific to Simulation
        Performance:
          type: float
          unit: 'ns/day'
          description: 'Simulation throughput'
        Atoms:
          header: num_atoms
          type: int
          description: 'System size'
        Precision:
          header: prec
          type: str
          description: 'Double or Single Precision'
        ts:
          header: timestamp
          type: ts
        System:
          from: static
          value: 'Cluster-A'
          description: 'Cluster Name'
        JobID:
          from: metadata
          key: 'job_id'
          type: int
          description: 'Batch Job ID'
        # Derived Metric: Performance per Atom
        PerfPerAtom:
          type: float
          from: "'Performance' / 'Atoms'"
          description: 'Performance normalized by system size'

      table:
        - System
        - Atoms
        - Precision

      # Global Styles for this tab
      traces:
        colors:
          colormap: 'Set1'
        styles:
          mode: 'markers'

      plots:
        # Plot 1: Raw Performance
        - x: ts
          y: Performance
          traces: 
            - Atoms
            - Precision
          annotations:
            - JobID  # Show JobID when hovering over points

        # Plot 2: Derived Metric
        - x: ts
          y: PerfPerAtom
          traces:
            - Precision
          annotations:
            - JobID

    # Tab 2: Energy Minimization (Different metrics entirely)
    Minimization:
      description: 'Energy Minimization Convergence Tests'
      sources:
        folders: ['data/minimization']
        
      metrics:
        Steps:
          type: int
          description: 'Steps to converge'
        Algorithm:
          from: filename
          regex: 'min_(steep|cg)_.*'
          description: 'Steepest Descent or Conjugate Gradient'
        Tolerance:
          type: float
          header: tol
          description: 'Convergence tolerance criteria'
        ts:
          header: timestamp
          type: ts

      table:
        - Algorithm
        - Tolerance
      
      # Footer Tabs: Organize plots into categories
      plots:
        tabs:
          Convergence:
            - x: ts
              y: Steps
              # One curve per Algorithm
              traces:
                - Algorithm
              # Local Style Override: Lines + Markers
              styles:
                 mode: 'lines+markers'
                 marker:
                   size: 8
          History:
            # Viewing convergence relative to input tolerance
            - x: Tolerance
              y: Steps
              traces:
                - Algorithm
```