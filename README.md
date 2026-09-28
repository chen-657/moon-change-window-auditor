# Moon Change Window Auditor

[![MoonBit checks](https://github.com/chen-657/moon-change-window-auditor/actions/workflows/check.yml/badge.svg)](https://github.com/chen-657/moon-change-window-auditor/actions/workflows/check.yml)

MoonBit 原生的变更窗口审计库：离线检查维护窗口之间的重叠、依赖顺序和缺失依赖，并从给定时间段计算还能安排新变更的空档。输入是易审阅的文本记录，输出是结构化结果和可以直接贴进变更工单的报告。

## 目标与边界

- 一个纯 MoonBit 包，无第三方依赖，native / wasm / wasm-gc / js 四个后端行为一致。
- 审计是离线、确定性的：同样的输入总是给出同样的报告，不需要数据库、网络或时钟。
- 时间按单一未命名时区解释，只接受 `1970-01-01T00:00` 到 `2199-12-31T23:59` 范围内的分钟级时间。
- 不做通用日历、cron、iCalendar、跨时区换算、节假日计算、发布系统、任务调度器或通用图数据库。
- 安全空档只看现有窗口占用的时间，不推导新变更自身的依赖链。

## 环境要求

- MoonBit 工具链，`moonc` 不低于 `0.10.14`（本仓库在 `moonc v0.10.14+7d59c7ec9` 上验证）。
- 无外部包依赖，`moon.pkg` 不导入任何模块。

## 安装

当前从源码使用（尚未发布到 Mooncakes）：

```bash
git clone https://github.com/chen-657/moon-change-window-auditor
cd moon-change-window-auditor
moon check --deny-warn --target all
```

在自己的 MoonBit 模块中作为依赖引用时，按包名导入并取一个别名：

```moonbit
// moon.pkg
import {
  "chen-657/moon-change-window-auditor" @audit,
}
```

## 输入格式

每行一条窗口记录，字段用 `;` 分隔，每个字段写成 `key=value`：

```text
id=database;service=orders-db;start=2026-10-01T22:00;end=2026-10-01T23:00;risk=high;depends=
id=api;service=orders-api;start=2026-10-01T22:45;end=2026-10-01T23:15;risk=medium;depends=database
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 窗口标识。ASCII 字母、数字、`_`、`.`、`-`，不超过 64 字符，全文件唯一 |
| `service` | 否 | 服务名，只用于报告展示，可以为空 |
| `start` | 是 | `YYYY-MM-DDTHH:MM`，也接受用空格代替 `T` |
| `end` | 是 | 同上，必须晚于 `start` |
| `risk` | 否 | `low`、`medium`、`high` 之一，缺省为 `medium`，大小写敏感 |
| `depends` | 否 | 逗号分隔的窗口 ID，空值表示没有依赖 |

空行、以 `#` 开头的注释行和空字段（例如结尾多余的 `;`）都会被忽略，但行号照常计入诊断信息。

## 使用方法

```moonbit
let plan = @audit.parse_plan(source)
let report = @audit.audit(plan)
println(@audit.render_report(report))
```

`plan.diagnostics` 记录解析阶段发现的问题，`report.overlaps` 和 `report.dependency_issues` 记录审计结果，`report.status()` 在存在任一 error 时返回 `FAIL`，否则返回 `PASS`（warning 不影响结论）。

安全空档计算把窗口合并成阻塞区间，只返回长度不小于给定分钟数的空档：

```moonbit
match (@audit.parse_instant("2026-10-01T20:00"), @audit.parse_instant("2026-10-02T02:00")) {
  (Some(from), Some(to)) => {
    let slots = @audit.safe_slots(plan, from, to, 30)
    println(@audit.render_slots(slots))
  }
  _ => println("invalid horizon")
}
```

公开 API（完整签名见 `pkg.generated.mbti`）：

| 函数 | 作用 |
| --- | --- |
| `parse_instant` / `format_instant` | `YYYY-MM-DDTHH:MM` 与分钟数互转 |
| `format_duration` | 把分钟数渲染成 `45m`、`2h`、`1h30m` |
| `parse_plan` | 解析文本计划，返回 `Plan` |
| `audit` | 审计 `Plan`，返回 `AuditReport` |
| `blocked_intervals` / `blocked_minutes` | 合并后的阻塞区间及其总长度 |
| `safe_slots` | 指定时间段内满足最短时长的空档 |
| `render_report` / `render_slots` / `render_diagnostics` | 文本输出 |
| `Plan::find` / `Plan::window_count` / `Plan::has_errors` | 计划查询 |
| `AuditReport::status` / `error_count` / `warning_count` / `has_errors` | 审计结论 |

## 审计规则

- **重叠**：两个窗口共享至少一分钟即为重叠，报告共享的分钟数。首尾相接（一个 23:00 结束、另一个 23:00 开始）不算重叠，但两者会合并成同一段阻塞区间。重叠的严重度由风险等级决定：两个 `high` 为 `critical`，其中一个为 `high` 为 `major`，其余为 `minor`。
- **依赖顺序**：依赖窗口必须在依赖方开始之前结束，否则记 `out-of-order` error，并给出超出的时长。
- **零余量**：依赖恰好在前一个窗口结束的同一分钟开始，记 `back-to-back` warning。它不算失败，但没有任何缓冲。
- **缺失依赖**：`depends` 指向的 ID 不在计划中，记 `missing-dependency` error。
- **自依赖**：窗口依赖自己，记 `self-dependency` error。
- **重复 ID**：重复出现记 `duplicate-id` error，两条记录都保留，依赖解析取第一条。
- **无效记录**：字段缺失、时间非法、结束不晚于开始、ID 或依赖 ID 非法的记录会被丢弃，并记 error；被丢弃的记录不参与重叠和依赖判断。
- **未知字段**：忽略并记 warning，记录保留。

## 最小示例

```bash
moon run examples/demo
```

示例源码见 [`examples/demo`](examples/demo)，它构造一个包含重叠、依赖顺序错误和缺失依赖的计划并打印报告与空档：

```text
Moon Change Window Audit
windows: 3
errors: 3
warnings: 1
overlaps: 1
dependency issues: 3
blocked: 2h15m
status: FAIL

WINDOWS
  database | orders-db | 2026-10-01T22:00 -> 2026-10-01T23:00 | 1h | high | -
  api | orders-api | 2026-10-01T22:45 -> 2026-10-01T23:15 | 30m | medium | database
  cache | session-cache | 2026-10-01T23:15 -> 2026-10-02T00:15 | 1h | low | api, queue

OVERLAPS
  database vs api: 15m (major)

DEPENDENCY ISSUES
  error api -> database: out-of-order (the dependency ends 15m after the dependent starts)
  warning cache -> api: back-to-back (no slack between the dependency end and the dependent start)
  error cache -> queue: missing-dependency (no window with this id exists in the plan)
```

报告文本是稳定格式，可以整段贴进工单，也可以用 `grep` 在流水线里取用；`status:` 行是给审批机器人看的结论。

## 本地检查

```bash
moon version --all
moon check --deny-warn --target all
moon build --target all
moon test --target all
moon fmt
moon info
moon run examples/demo
```

`moon check`、`moon build`、`moon test` 与 `moon run examples/demo` 覆盖四个后端；`moon fmt` 与 `moon info` 之后工作树应当保持干净。测试共有 54 个用例，覆盖时间解析边界、每种诊断、重叠与依赖规则、空档裁剪与报告文本。

## 许可证与来源

项目采用 [MIT 许可证](LICENSE)。算法出处、查重范围和兼容性说明见 [`SOURCES.md`](SOURCES.md)。公开仓库不包含报名或申报材料。
