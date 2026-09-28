# 查重、来源与兼容性记录

记录日期：2026-09-28（最后核对同上）。

## 查重范围

- Mooncakes 模块清单：查询 `https://mooncakes.io/api-new/v0/modules?search=x`，按名称、描述和关键词筛查 `maintenance`、`change-window`、`blackout`、`deployment-window`、`safe-slot`、`window-audit`。
- GitHub 仓库搜索：查询 `moon-change-window`、`moon-window-auditor`、`maintenance-window-auditor`、`deployment-window-auditor`、`blackout-window-planner`。
- 本地工作区：确认已有项目是 OFX、vCard、TUF 预检、PDF417 和检索，功能边界不重叠。

## 结果与边界

查重范围内没有发现与本项目同名或同功能的 MoonBit 项目。Mooncakes 中存在 cron、日历、法律截止日期、发布管理和 canary rollout 工具，但它们不提供本项目的“变更窗口记录 + 依赖顺序审计 + 重叠冲突报告 + 安全空档计算”组合能力。

“不与任何开源项目重合”无法通过有限的公开搜索证明为全网事实。本项目因此采用窄而可核验的边界：不实现通用日历、cron、iCalendar、跨时区换算、发布系统、任务调度器或通用图数据库；只处理本项目定义的变更窗口文本格式和离线审计算法。

## 参考规范

- **时间格式**：输入输出使用 ISO 8601 的日历日期与本地时刻写法 `YYYY-MM-DDTHH:MM`，不附带时区偏移，按单一未命名时区解释。
- **日期算法**：`time.mbt` 中的 `days_from_civil` / `civil_from_days` 依据 Howard Hinnant 的公开文章 “chrono-Compatible Low-Level Date Algorithms” 描述的算法改写（该文章将该算法置于公有领域）。本项目只使用了把公历日期与 1970 起算的天数互转的部分，没有复制任何源码文件；闰年规则 `(year % 4 == 0 && year % 100 != 0) || year % 400 == 0` 是公历定义本身。
- **变更窗口语义**：依赖必须在依赖方开始前结束、零缓冲记 warning、重叠按共享分钟数计量，均按运维变更管理的通行做法定义，并在 README 的“审计规则”中逐条写明。
- **输出格式**：文本报告、JSON、Markdown 表格、CSV 与 ASCII 时间线都由本项目手写实现，只遵循各自的公开格式约定（JSON 转义规则、GitHub 风格 Markdown 表格、RFC 4180 风格 CSV 引号规则），没有引入任何序列化库或模板引擎。
- **确定性**：为了让四个后端输出逐字节一致，排序一律使用自写的稳定插入排序（`sort_slots`、`sort_windows_by_start`、`sorted_strings`、`sorted_ints`、`sort_cycles`），代码点比较使用 `compare_strings`，全程不依赖库排序、哈希顺序或本地化规则。

## 第三方代码与数据

- 本仓库不包含任何第三方源代码、测试数据或二进制资源。
- 测试用例中的服务名、窗口时间和依赖关系都是为本项目编写的示例数据，不含真实系统信息或个人信息。
- 无外部包依赖：`moon.pkg` 不导入任何模块，仅使用 MoonBit 核心语言与预置类型。

## 兼容性

- 工具链：`moonc v0.10.14+7d59c7ec9`、`moon 0.1.20260920`。
- 目标：`native`、`wasm`、`wasm-gc`、`js` 均通过 `moon check --deny-warn`、`moon build`、`moon test`。
- 时间轴使用 `Int` 分钟数，取值上限约 1.21 亿分钟，对应 2199-12-31T23:59，在 32 位 `Int` 后端上也不会溢出，因此四个后端行为一致。
- 规模上限：审计按窗口两两比较，依赖图按窗口数线性遍历，均为离线、单机、数百条记录量级的设计；没有为百万级输入做索引，README 未声称支持该规模。
