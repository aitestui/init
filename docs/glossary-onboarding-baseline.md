# Glossary — 接入基线用例自动生成域（Onboarding Baseline Autocase）

> grill-with-docs 的 domain-modeling 产物，范围限定在**「从系统手册自动生成一套能跑通的基线用例、帮新系统降低接入 aitestui 的冷启动成本」**这一子域。
> 产品级语义仍以 `CONTEXT.md` 为权威；用例编写规范见 `aitestui-user-manual.md` §6.2；执行模型术语见 `docs/glossary-execution-model.md`；模型与计费见 `docs/glossary.md`。
> 全部裁决见 `docs/adr/0075-onboarding-baseline-autocase.md`（Status: Accepted）。承载物是全局（用户级）skill `~/.workbuddy/skills/aitestui/`。

## 概念

| 中文 | English | 定义 | 载体 |
|---|---|---|---|
| 接入基线用例集 | Onboarding Baseline Case Set | 为被测系统**首次接入** aitestui 生成的第一批、覆盖主干、可直接执行的自然语言用例。目的不是发现缺陷，而是让新系统开箱即可跑。 | `output/<run>/pool.json` / `pool.xlsx`；灌入 `qa_test_case` |
| 接入基线用例自动生成 | Onboarding Baseline Autocase | 本域能力：文档 → 人工辅助登录 → AI 实地探索 → 生成三批用例 → 平台执行并按真实行为改用例到全过，全链路闭环。 | 全局（用户级）skill `aitestui`，位于 `~/.workbuddy/skills/`（本地名与对外发布名一致；旧名 `aitestui-onboarding-autocase` 已停用） |
| 实地探索 | Field Exploration | 带着登录态在真实浏览器里走查功能点，确认入口路径与可见文案、修正文档缺漏的过程。是「文档落后」能够被识别的前提。 | skill 阶段 3；Playwright + storageState |
| 文档落后 | Stale Document | 手册描述与被测系统实际行为不符。遇到失败时的**首选归因之一**，处理是按系统实际行为改用例，并把差异记入变更清单，绝不判系统 bug。 | `changes.md` 的「文档差异」节 |
| 三批分层 | Three-tier Layering | 同一用例集按标签形成的三个筛选视图：冒烟 ⊂ 核心 ⊂ 全量（全量 = 核心 ∪ 负向）。是视图，不是三份独立用例。 | `tags`：`冒烟` / `核心` / `负向` |
| 改到全过 | Converge-to-Pass | 失败即用例问题或文档落后，按系统真实行为改用例并重跑，直到该用例通过。目标不是发现缺陷；系统默认正常是前提。 | skill 阶段 5 的失败归因循环 |
| 熔断转人工 | Circuit-break to Human | 同一用例连续 3 次修正仍不过时标 `needs_human`、跳过继续其他用例、批次不算全过并暂停报告的保险机制。 | `needs_human` 标记；`summary.md` |
| 人工辅助登录 | Assisted Login | 一次性采集两类登录态：被测系统的 `storageState`（供探索与执行）+ aitestui 的 API token（供灌库）。失效时暂停提示重登，不自动重登。 | `.auth/state.json`（本地）；`AITESTUI_TOKEN` |
| 变更清单 | Change List | 收口产物，分「文档差异」与「接口需求」两节；确需改造 aitestui 的点也记在这里，最后统一开发，本期 skill 不改平台代码。 | `output/<run>/changes.md` |
| 灌回平台 | Import-back | 用现有 `POST /test-cases/import` 把通过用例批量写入 aitestui；按 code 覆盖，不新增平台接口。 | `test-cases.controller.ts` / `test-cases.service.ts` |

## 关系

```
系统手册(DOC)
   │ 解析
   ▼
功能点清单(spec.md) ──人工辅助登录──▶ storageState + API token
   │ 实地探索(Field Exploration)          │
   ▼                                     │
接入基线用例集(pool) ──tags 分层──▶ 冒烟 ⊂ 核心 ⊂ 全量(含负向)
   │ 三批串行自执行
   ▼
失败 → 归因(用例问题 | 文档落后) → 按真实行为改用例 → 重跑(改到全过)
   │ 3 次不过 → 熔断转人工(needs_human)
   ▼
灌回平台(POST /test-cases/import) + 变更清单(changes.md 最后统一开发)
```

## 命名约束（_Avoid_）

- **_Avoid_「初始化测试用例」** 作为精确术语：它混淆了「新建空用例」「导入现成用例」「从文档生成用例」。规范名用 **接入基线用例集 / Onboarding Baseline Case Set**。
- **_Avoid_「自动测试/智能测试工具」**：本域不发现缺陷、不判系统 bug；那是「找 bug 的测试工具」。本域是**接入初始化能力**。
- **_Avoid_「自愈 / 自修复」**：平台 ADR-0063 已删除用例级 AI 自愈；这里的「改到全过」是**生成期校准**，发生在灌库前的 skill 内部，与平台执行链的自愈无关，勿混用。
- **_Avoid_「平台改造」** 指代本期动作：本期零平台改造；「接口需求/平台改造点」只进 `changes.md`，留待未来统一开发时另起 ADR。
