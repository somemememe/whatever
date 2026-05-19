# AuditHound v2


- `code_map.md`
- 并行 agent 审计
- `merge + review`
- `findings_acc.json`
- 连续两轮无新增 finding 收敛


## CLI

```bash
python3 AuditHoundV2/scripts/audithound.py run <target_dir>
```

常用参数：

```bash
python3 AuditHoundV2/scripts/audithound.py run <target_dir> \
  --agent codex \
  --model gpt-5.4 \
  --reasoning-effort medium \
  --max-rounds 3 \
  --converge-after 2 \
  --workers 2
```

恢复一个被中断的 run：

```bash
python3 AuditHoundV2/scripts/audithound.py run <target_dir> \
  --output-dir AuditHoundV2/output/<existing_run_dir> \
  --resume
```

排除某些目录不作为直接审计目标，但保留为上下文：

```bash
python3 AuditHoundV2/scripts/audithound.py run <target_dir> \
  --exclude interfaces/** \
  --workers 2
```

只审计某些目录（白名单）：

```bash
python3 AuditHoundV2/scripts/audithound.py run <target_dir> \
  --include LayerZero/** \
  --exclude interfaces/** \
  --workers 2
```

也可以直接喂一个 materialized EVMbench case 目录或 `manifest.json`：

```bash
python3 AuditHoundV2/scripts/audithound.py run \
  evmbench/frontier-evals/project/evmbench/materialized_cases/2024-03-abracadabra-money
```

使用 OpenCode：

```bash
python3 AuditHoundV2/scripts/audithound.py run majeur/src \
  --agent opencode \
  --model opencode/minimax-m2.5-free \
  --workers 2
```

当前默认：

- agent: `codex`
- merge mode: `codex`
- map: 自动生成 `code_map.md`
- workers: 默认 `1`，可改成 `2` 或更多并行 `codex`
- model: `gpt-5.4`
- `model_reasoning_effort`: `medium`

当 `--agent opencode` 时：

- 默认模型切到 `opencode/minimax-m2.5-free`
- agent 侧会自动使用 worker-local `.opencode_xdg/`，避免全局数据库路径权限问题
- merge 仍然默认走 `codex`

当前 `merge` 会在目标源码目录中运行，而不是只在 round 目录里盲合并。
它会做：

- dedup
- consolidation / composite synthesis
- 轻量 review（severity / confidence 调整）

每轮 `summary` 会生成 `round_summary.md`，并维护一个轻量的 `global_summary.md`。
后续 audit prompt 只提供该文件路径，作为可选历史记忆，不作为覆盖证明或强制执行计划。

可以通过 `--exclude` 或环境变量 `AUDITHOUND_EXCLUDE_GLOBS='["interfaces/**"]'`
把某些相对 target 的路径 glob 从直接审计 scope 中排除。被排除的文件仍可作为上下文读取，但不应作为独立 finding 的根因位置。

也可以通过 `--include` 或环境变量 `AUDITHOUND_INCLUDE_GLOBS='["LayerZero/**"]'`
限定直接审计 scope 只在白名单路径中。白名单外文件可读作上下文，但不应作为 finding 根因位置。

可以通过 `--resume` 在已有 `--output-dir` 上继续一个被中断的 run：

- 复用已有 `code_map.md` 和 `findings_acc.json`
- 从上次完成的下一轮继续，而不是从 round 1 重跑
- 未完成轮次留下的旧目录会先移动到 `round_N.resume_backup_<timestamp>/`
- 若是老 run 没有 `loop_state.json`，会 best-effort 推断最后完成轮次，但连续空轮计数会重置

当前仍然不做外部 known-finding 过滤。

## 兼容的旧入口

底层 runner 仍然保留：

```bash
bash AuditHoundV2/scripts/run_convergence_loop.sh <target_dir>
```

但建议以后统一走 `audithound.py run ...`，参数更清楚。
