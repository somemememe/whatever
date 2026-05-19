# AuditHoundV2 Diagram Set

Paper-oriented diagram suite for the current AuditHoundV2 architecture.

## Recommended for main paper

- `01_overview_architecture.d2` (Figure 1)
- `02_round_lifecycle.d2` (Figure 2)
- `03_memory_architecture.d2` (Figure 3)

## Recommended for appendix

- `04_role_and_quality_controls.d2` (Figure A1)
- `05_cli_and_control_surface.d2` (Figure A2)

## Figures

- `01_overview_architecture.d2`  
  End-to-end architecture: scope, convergence pipeline, state, and outputs.

- `02_round_lifecycle.d2`  
  Round execution lifecycle: resume, prompt generation, parallel agents, merge, summary, checkpointing, convergence.

- `03_memory_architecture.d2`  
  Memory model: canonical findings memory vs contextual memory vs runtime state vs trace memory.

- `04_role_and_quality_controls.d2`  
  Role decomposition and quality controls: multi-agent discovery, merge adjudication, and constraints.

- `05_cli_and_control_surface.d2`  
  CLI parameterization path: user flags -> env wiring -> runtime behavior.

## Render

```bash
cd /Users/lu/Desktop/Red_V1G/AuditHoundV2/diagrams
bash render_all.sh
```

Optional PDF render:

```bash
bash render_all.sh --pdf
```

Note: PDF rendering can be slower/hang on some environments; SVG is the default output.
