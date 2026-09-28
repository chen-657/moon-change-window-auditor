# Moon Change Window Auditor

[![MoonBit checks](https://github.com/chen-657/moon-change-window-auditor/actions/workflows/check.yml/badge.svg)](https://github.com/chen-657/moon-change-window-auditor/actions/workflows/check.yml)

MoonBit 原生的变更窗口审计与排期库：解析多服务维护变更记录，审计窗口重叠、依赖顺序、循环依赖与变更冻结期冲突，按运维策略判定计划能否放行，并计算可插入新变更的安全空档与最早可行排期。输入是易审阅的文本记录，输出是结构化结果以及文本、JSON、Markdown、CSV 和 ASCII 时间线五种报告。

## 目标与边界

- 纯 MoonBit 包，无第三方依赖，`native` / `wasm` / `wasm-gc` / `js` 四个后端行为一致。
- 离线且确定性：同样的输入总是给出逐字节相同的报告，不访问数据库、网络或系统时钟。
- 时间按单一未命名时区解释，只接受 `1970-01-01T00:00` 到 `2199-12-31T23:59` 范围内的分钟级时间。
- 不做通用日历、cron、iCalendar、跨时区换算、节假日计算、发布系统、任务调度器或通用图数据库。
- 安全空档只看现有记录占用的时间；它不推导新变更自身的依赖链，也不做多目标优化。
- 规模按离线单机设计：审计按窗口两两比较，适合数百条记录量级的变更计划。

## 环境要求

- MoonBit 工具链，`moonc` 不低于 `0.10.14`（本仓库在 `moonc v0.10.14+7d59c7ec9` 上验证）。
- 无外部包依赖：`moon.pkg` 不导入任何模块。

## 安装

已发布到 Mooncakes：`chen-657/moon-change-window-auditor`（当前版本 `0.2.0`，MIT）。需要 MoonBit 工具链，`moonc` 不低于 `0.10.14`：

```bash
moon add chen-657/moon-change-window-auditor
```

包页面：<https://mooncakes.io/docs/chen-657/moon-change-window-auditor>

在自己的包中导入并取一个别名：

```moonbit
// moon.pkg
import {
  "chen-657/moon-change-window-auditor" @audit,
}
```

从源码开发或复现本文档中的检查：

```bash
git clone https://github.com/chen-657/moon-change-window-auditor
cd moon-change-window-auditor
moon check --deny-warn --target all
```

## 输入格式

每行一条记录，字段用 `;` 分隔，每个字段写成 `key=value`：

```text
id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high;depends=
id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database
id=blackout;service=company;kind=freeze;start=2026-12-24T00:00;end=2026-12-27T00:00
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 记录标识。ASCII 字母、数字、`_`、`.`、`-`，不超过 64 字符，全文件唯一 |
| `service` | 否 | 服务名，只用于报告与汇总，可以为空 |
| `start` | 是 | `YYYY-MM-DDTHH:MM`，也接受用空格代替 `T` |
| `end` | 是 | 同上，必须晚于 `start` |
| `risk` | 否 | `low`、`medium`、`high` 之一，缺省 `medium`，大小写敏感；冻结期忽略此字段 |
| `depends` | 否 | 逗号分隔的记录 ID，空值表示没有依赖；冻结期不允许声明依赖 |
| `kind` | 否 | `change`（缺省，也接受 `window`）或 `freeze`，后者表示变更冻结期 |

空行、以 `#` 开头的注释行和空字段（例如结尾多余的 `;`）都会被忽略，但行号照常计入诊断信息。

## 快速开始

```moonbit
// 1. 解析
let plan = @audit.parse_plan(source)

// 2. 审计：重叠、依赖顺序、冻结期冲突
let report = @audit.audit(plan)
println(@audit.render_report(report))

// 3. 按策略判定能否放行
let policy_report = @audit.audit_with_policy(plan, @audit.Policy::strict())
println(@audit.render_policy_report(policy_report))

// 4. 找可安排新变更的空档，并检查候选窗口
match (@audit.parse_instant("2026-10-01T20:00"), @audit.parse_instant("2026-10-02T02:00")) {
  (Some(from), Some(to)) => {
    println(@audit.render_slots(@audit.safe_slots(plan, from, to, 30)))
    let candidate = @audit.candidate_slot(from, from + 60)
    println(@audit.can_schedule(plan, candidate, [], 30).to_line())
  }
  _ => println("invalid horizon")
}
```

## 公开 API 一览

完整签名见生成的 [`pkg.generated.mbti`](pkg.generated.mbti)（138 个公开函数、26 个公开类型）。

| 领域 | 主要接口 |
| --- | --- |
| 时间 | `parse_instant`、`format_instant`、`format_duration` |
| 解析与模型 | `parse_plan`、`Plan::find`、`Plan::changes`、`Plan::freezes`、`Plan::windows_of_kind`、`Window::duration`、`Window::is_freeze` |
| 审计 | `audit`、`freeze_conflicts`、`freezes_hit_by`、`AuditReport::status`、`AuditReport::error_count` |
| 区间代数 | `merge_slots`、`sort_slots`、`clip_slot`、`invert_slots`、`intersect_slots`、`subtract_slots`、`total_duration`、`slot_at`、`Slot::contains`、`Slot::overlaps`、`Slot::touches`、`Slot::intersect`、`Slot::merge_with` |
| 阻塞与空档 | `blocked_intervals`、`blocked_minutes`、`safe_slots` |
| 并发负载 | `concurrency_at`、`service_concurrency_at`、`peak_concurrency`、`busiest_intervals`、`max_concurrency_in`、`load_profile`、`change_minutes`、`freeze_minutes` |
| 依赖图 | `dependencies_of`、`dependents_of`、`transitive_dependencies`、`dependency_depth`、`find_cycles`、`graph_roots`、`graph_leaves`、`execution_order` |
| 排期 | `can_schedule`、`earliest_start`、`slack_minutes`、`earliest_schedule`、`next_slots`、`candidate_slot` |
| 策略 | `Policy::standard`、`Policy::strict`、`Policy::relaxed`、`Policy::describe`、`audit_with_policy`、`PolicyReport::status` |
| 汇总与对比 | `summarize`、`find_service`、`diff_plans`、`PlanDiff::is_empty` |
| 渲染 | `render_report`、`render_slots`、`render_policy_report`、`render_summary`、`render_diff`、`render_execution_order`、`render_schedule_result`、`render_timeline`、`render_report_json`、`render_plan_json`、`render_slots_json`、`render_report_markdown`、`render_windows_markdown`、`render_slots_markdown`、`render_windows_csv`、`render_overlaps_csv`、`render_freeze_conflicts_csv`、`render_dependency_issues_csv`、`render_slots_csv` |

## 审计规则

- **重叠**：两条记录共享至少一分钟即为重叠，报告共享分钟数。首尾相接（一条 23:00 结束、另一条 23:00 开始）不算重叠，但会合并为同一段阻塞区间。严重度由风险等级决定：两个 `high` 为 `critical`，其中一个为 `high` 为 `major`，其余为 `minor`。
- **依赖顺序**：依赖必须在依赖方开始之前结束，否则记 `out-of-order` error 并给出超出的时长。
- **零余量**：依赖恰好在前一条记录结束的同一分钟开始，记 `back-to-back` warning，不算失败但没有缓冲。
- **缺失依赖 / 自依赖**：分别记 `missing-dependency`、`self-dependency` error。
- **循环依赖**：`find_cycles` 按“从最小 ID 起”规范化的顺序报告每个环一次；`execution_order` 对有环计划返回 `None`。
- **冻结期冲突**：变更落在 `kind=freeze` 记录内记 `freeze-conflict` error。冻结期之间互相重叠不算冲突。
- **重复 ID**：记 `duplicate-id` error，两条记录都保留，依赖解析取第一条。
- **无效记录**：字段缺失、时间非法、结束不晚于开始、ID 或依赖 ID 非法、`kind` 非法的记录会被丢弃并记 error；被丢弃的记录不参与重叠与依赖判断。
- **未知字段**：忽略并记 warning，记录保留。

## 策略规则

`audit_with_policy` 在审计之上叠加运维策略，违规明细按固定顺序输出：

| code | 严重度 | 触发条件 | `subject` |
| --- | --- | --- | --- |
| `max-concurrent` | error | 同时运行的变更数超过 `max_concurrent`（先全计划，再逐服务） | `all` 或服务名 |
| `max-change-minutes` | error | 单条变更时长超过 `max_change_minutes`（不计冻结期） | 记录 ID |
| `min-dependency-slack` | warning | 依赖结束到依赖方开始的余量小于 `min_dependency_slack_minutes` | 记录 ID |
| `high-risk-overlap` | error | `forbid_high_risk_overlap` 为真且高风险变更与其他变更重叠（每对一次） | 高风险记录 ID |
| `max-high-risk-per-day` | error | 某一天的高风险变更数超过 `max_high_risk_per_day` | 当天 00:00 |
| `freeze-conflict` | error | `forbid_freeze_conflicts` 为真且变更落在冻结期内 | 记录 ID |
| `service-missing` | warning | `require_service` 为真且变更没有服务名 | 记录 ID |

`0` 表示不限，`false` 表示关闭该规则，因此 `Policy::relaxed()` 不产生任何违规。只有 warning 时 `status` 仍为 `PASS`。

## 输出格式

同一次审计可以渲染成五种形式，全部为确定性输出：

- **文本**：`render_report` / `render_policy_report` / `render_summary` / `render_diff`，可直接贴进工单或用 `grep` 取用。`status:` 行是给审批机器人看的结论。
- **JSON**：`render_report_json` / `render_plan_json` / `render_slots_json`，两空格缩进、字段间有逗号、空数组内联为 `[]`，已用真实 JSON 解析器验证。
- **Markdown**：`render_report_markdown` / `render_windows_markdown` / `render_slots_markdown`，GitHub 风格表格，单元格内的 `|` 转义为 `\|`。
- **CSV**：`render_windows_csv` / `render_overlaps_csv` / `render_freeze_conflicts_csv` / `render_dependency_issues_csv` / `render_slots_csv`，含逗号、引号或换行的字段按 RFC 4180 风格加引号并转义。
- **ASCII 时间线**：`render_timeline(plan, from, to, columns)`，`. ` 空闲、`#` 变更、`=` 冻结期、`!` 落在冻结期内的变更：

```text
Timeline 2026-10-01T21:00 -> 2026-10-02T04:00 (7h, 28 columns, 1 column = 15m)
database |....####....................|
api      |......########..............|
blackout |................====!!!!....|
cache    |....................!!!!##..|
legend: . free, # change, = freeze, ! change inside freeze
```

## 示例

```bash
moon run examples/demo          # 审计一个含重叠、依赖错误、缺失依赖的计划
moon run examples/policy-gate   # 按严格策略判定计划，并输出汇总、排期与时间线
```

`examples/policy-gate` 的输出（节选）：

```text
POLICY VIOLATIONS
  warning min-dependency-slack (api): overlaps database and misses the minimum slack of 30m by 30m
  error high-risk-overlap (database): high risk database overlaps api for 30m
  error freeze-conflict (cache): runs inside freeze blackout for 1h
policy: FAIL

Plan summary
changes: 3
freezes: 1
blocked: 5h
workload: 4h30m
peak: 2 changes at 2026-10-01T22:30

Earliest dependency aware schedule (3 changes)
  database 2026-10-01T22:00 -> 2026-10-01T23:00 (+0m)
  api 2026-10-01T23:00 -> 2026-10-02T01:00 (+30m)
  cache 2026-10-02T02:00 -> 2026-10-02T03:30 (+0m)
```

## 本地检查

```bash
moon version --all
moon check --deny-warn --target all
moon build --target all
moon test --target all
moon fmt
moon info
moon run examples/demo
moon run examples/policy-gate
```

`check`、`build`、`test` 与两个示例覆盖四个后端；`fmt` 与 `info` 之后工作树应保持干净（CI 用 `git diff --exit-code` 校验）。测试覆盖时间解析边界、每一种诊断与违规码、重叠与依赖规则、冻结期、区间代数、并发负载、依赖图、排期压缩、汇总与 diff，以及五种渲染格式的完整文本。

## 项目结构

| 文件 | 职责 |
| --- | --- |
| `moon.mod` / `moon.pkg` | 模块元数据；库包不导入任何依赖 |
| `text.mbt` | 数字解析、补齐、拼接、标识符校验、字符串比较与排序 |
| `time.mbt` | 分钟轴、`YYYY-MM-DDTHH:MM` 解析与格式化、时长渲染 |
| `types.mbt` | 数据模型：`Plan`、`Window`、`Slot`、`Overlap`、`FreezeConflict`、`DependencyIssue`、`AuditReport` 等 |
| `parse.mbt` | 文本格式解析与全部解析诊断 |
| `intervals.mbt` | 半开区间代数、合并、取反、交、差 |
| `audit.mbt` | 重叠检测、依赖顺序检查、冻结期冲突 |
| `concurrency.mbt` | 并发计数、峰值、拥挤时段、负载采样 |
| `graph.mbt` | 依赖图查询、环检测、拓扑执行顺序 |
| `schedule.mbt` | 候选窗口检查、最早开始、依赖感知排期 |
| `policy.mbt` | 策略模型、违规推导、策略报告 |
| `summary.mbt` | 计划汇总与按服务统计 |
| `diff.mbt` | 两版计划对比 |
| `report.mbt` | 文本报告 |
| `render_json.mbt` / `render_markdown.mbt` / `render_csv.mbt` / `render_timeline.mbt` | 其余四种输出 |
| `examples/demo` / `examples/policy-gate` | 可运行示例 |
| `*_test.mbt` | 测试包 |
| `.github/workflows/check.yml` | CI：check、build、test、示例、格式与接口一致性 |

## 许可证与来源

项目采用 [MIT 许可证](LICENSE)。算法出处、查重范围、确定性做法与后端兼容性见 [`SOURCES.md`](SOURCES.md)。公开仓库、Release 与 Mooncakes 包都不包含报名或申报材料。
