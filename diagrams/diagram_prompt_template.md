# Maintain Agent Architecture Diagram

**Task**: Update the system architecture diagram based on my recent code changes.

**Rules for D2 Diagram Modification**:
1. You must read the main orchestration scripts (e.g., `audithound.py`, `run_convergence_loop.sh`, `merge.py`, `summarize_round.py`) to infer the updated pipeline.
2. Edit `AuditHoundV2/diagrams/agent_architecture.d2` using the D2 declarative language.
3. Keep the visual styling (classes, colors) consistent and academic. We use:
   - `harness` (red dashed)
   - `agent` (blue, solid, shadow)
   - `merge` (green, solid, shadow)
   - `storage` (orange cylinder)
   - `data` (gray solid)
4. Ensure relationships follow a logical left-to-right (`direction: right`) or top-to-bottom flow. Use ELK layout paths implicitly by grouping into containers accurately.
5. After modifying the core, run `./AuditHoundV2/diagrams/render_arch.sh` to generate the updated `SVG` and `PDF`.
