# AuditHound v2 — Modified

基于原版 [AuditHound](https://github.com/zhanglongqin07/audithound)，增加了防作弊、种子资金、代币价值折算和严格分类系统。60 个 EVMbench case 全部跑过回归。

## 新增功能

### 防作弊

三层拦截防止 agent 读取预置答案：

- **文件读取拦截**：`tool_call_runner.py` 和 `agent_validate.py` 中禁止读取 `FlawVerifier.sol`、`ExploitPOC.t.sol`、`Counter.sol`
- **Shell 命令拦截**：阻止 `cat`/`cp`/`find` 等命令访问禁止文件名
- **写入限制**：`write_file` 限制在 workspace 目录内
- **连续拦截警告**：累计达到 3/6 次输出警告，防止 agent 反复尝试

### DeepSeek v4-pro 支持

- 模型默认改为 `deepseek-v4-pro`
- `reasoning_content` 兜底：v4-pro 的思考令牌在独立字段，不会因为 `content` 为空而丢输出
- `max_steps` 从 24 提升到 100（深思考模型需要更多步数）

### 原始合并模式（Raw Merge）

当 Codex/OpenAI API 不可用时，绕过合并步骤直接从 agent stdout 提取 findings：

- `extract_findings.py`：从 agent 输出中解析 JSON findings
- `audithound.py` 自动检测：deepseek + 单 worker → 自动切 raw merge
- `run_convergence_loop.sh` 新增 `raw` / `skip` 合并模式分支

### 种子资金与反种子转换

Agent 获得 10 ETH 种子资金用于需要前置资本的攻击。同时防止 agent 把种子换成代币后虚报利润：

- **种子发放**：`foundry_validate.py` 在 `setUp()` 中给 verifier 转入 10 ETH
- **反种子转换 guard**：Solidity 测试合约内检测 `nativeProfit == 0 && afterBal < beforeBal`，若代币利润 ≤ 种子花费则归零
- **提示词警告**：PoC prompt 明确说明 "用种子换代币不算攻击"
- **双扣修复**：移除了 `nativeProfit - prefund_wei` 的重复扣除（`afterBal - beforeBal` 已含种子）

### 严格 PASS / BLOCKED / FAIL 分类

三档判定替代原始的二元通过/失败：

- **PASS**：攻击执行且真实获利。代币利润统一折算为 ETH 价值后，大于种子花费即为真实利润
- **BLOCKED**：攻击代码执行了（forge gas > 50000）但无真实利润。包括种子转换、哨兵值、粉尘利润、代币价值低于花费
- **FAIL**：PoC 未生成或编译失败，攻击代码未在链上执行

哨兵值拦截：利润 > 100,000 ETH 自动标 BLOCKED。

### 代币价值统一折算

非 WETH 代币的利润通过 CoinGecko API 查询实时价格，折算为 ETH 后再做比较。WETH 按 1:1 处理。查不到价格的代币标 BLOCKED。

折算函数 `token_profit_in_eth()` 在 `poc_backfill_v3.py` 中，带 1 小时缓存。

### 余额追踪

`summary.json` 中记录每个 finding 的：
- `balance_before_wei` / `balance_after_wei`：攻击前后 ETH 余额
- `profit_token`：获利的代币地址
- 用于种子转换检测和代币折算

### 线程安全日志

`poc_backfill_v3.py` 的 `log()` 带 `threading.Lock`，4 并行 worker 的输出不会串行。

---

## CLI

### 审计

```bash
python3 scripts/audithound.py run <target_dir> \
  --tool-provider deepseek \
  --tool-model deepseek-v4-pro \
  --workers 4
```

### PoC 验证回归

```bash
# 全部回归（只跑没有 summary.json 的 case）
python3 /root/poc_backfill_v3.py all

# 单测
python3 /root/poc_backfill_v3.py mimspell

# 多测
python3 /root/poc_backfill_v3.py pickle conic dfx

# 强制重跑
python3 /root/poc_backfill_v3.py mimspell --force

# 指定并行数
python3 /root/poc_backfill_v3.py all --workers=2
```

case 名不带 `_regression` 后缀。

---

## 关键文件

| 文件 | 改动 |
|------|------|
| `scripts/tool_call_runner.py` | 防作弊拦截、reasoning_content 兜底、max_steps 提升 |
| `scripts/agent_validate.py` | 防作弊拦截、AGENT_MAX_ITERATIONS 提升 |
| `scripts/foundry_validate.py` | 种子资金、反种子转换 guard、余额记录、双扣修复 |
| `scripts/audithound.py` | 模型默认值、raw merge 自动检测 |
| `scripts/run_convergence_loop.sh` | raw/skip merge 模式分支 |
| `scripts/extract_findings.py` | 新增：从 agent stdout 提取 findings |
| `poc_backfill_v3.py` | 新增：PoC 回归运行器，含完整分类和代币折算逻辑 |

---

## 60 Case 回归结果

```
PASS:    18  (原生 ETH 利润或代币价值 > 种子花费)
BLOCKED: 25  (攻击执行但无真实利润)
FAIL:    12  (PoC 未生成或编译失败)
零 findings: 5
总计:     60
```
