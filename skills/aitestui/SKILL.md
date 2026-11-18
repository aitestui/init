---
name: aitestui
description: 为「接入 aitestui 的新系统」从系统手册等文档自动生成接入基线用例集，经人工辅助登录后 AI 实地探索、生成三批用例、本地自执行并按下述规则改用例到全过，最后通过现有 API 灌入 aitestui。当用户想「根据文档自动写 aitestui 测试用例」「降低用例初始化工作量」「批量接入系统/铺冒烟用例」「文档生成用例并自动跑通」时使用。决策依据见仓库 docs/adr/0075、术语见 docs/glossary-onboarding-baseline.md。
---

# aitestui 接入基线用例自动生成（Onboarding Baseline Autocase）

补上 aitestui 缺失的那块能力：**用户不必从零手写用例**。给一份被测系统的手册，本 skill 完成「登录 → 实地探索 → 生成三批用例 → 自执行 → 改到全过 → 灌回平台」的全链路。

## 一句话不变量

> 系统默认正常，文档可能落后。凡是失败，优先怀疑用例，不怀疑系统；按系统**实际行为**改用例直到通过。真正需要改平台的地方只记录、不改代码，最后统一开发。

这条决定了本 skill 与「找 bug 的测试工具」的根本区别：目标是**铺一套跑得通的基线**，不是发现缺陷。

## 运行前必读（事实锚点，勿凭记忆）

- 平台现行真相与 10 条用例硬约束：`references/case-rules.md`（全文中文、首行≤20字标题、步骤动词开头、元素按可见文案、`${VAR}` 占位、配了 COOKIE 不写登录、入口只写 `/path`、`断言：` 结尾、不写易变数值、不写平台判不了的步骤）。生成与修改用例逐条对齐，并跑内附校验器。
- 平台 API 端点与字段：`references/api-contract.md`（导入端点、分支、工程最小配置、code 归一规则）。**所有写入只走这些现有端点，不改平台。**
- 决策依据与术语：`docs/adr/0075-onboarding-baseline-autocase.md`、`docs/glossary-onboarding-baseline.md`（仅作背景，执行按上面两份 references）。

## 参数（运行前从用户处取齐）

| 参数 | 必填 | 说明 |
|---|---|---|
| `DOC` | 是 | 被测系统手册/需求文档路径（PDF/DOCX/MD/HTML），可多份 |
| `TARGET_URL` | 是 | 被测站点地址（写入环境 `URL` 变量） |
| `PROJECT_ID` | 否 | 已存在的 aitestui 项目 id；不填则走「接入准备」新建 |
| `AITESTUI_BASE` | 是 | 平台接口基址（生产 `https://aitestui.com/api`） |
| `AITESTUI_TOKEN` | 是 | 调用平台 API 的 token（人工登录 aitestui 后取，见阶段 2） |
| `MODEL_*` | 是 | 执行模型：`MIDSCENE_MODEL_BASE_URL/API_KEY/NAME/FAMILY`；生成模型另配，可同一把 |

缺 `AITESTUI_TOKEN` 或执行模型时**停下来问用户**，不要猜。

## 工作流（严格分阶段，阶段间是门禁）

### 阶段 1 — 文档解析
读 `DOC`，抽取三样东西，写成 `output/<run>/spec.md`：
1. **功能点清单**：每个可独立验证的功能一条（如「购物车结算下单」）。
2. **入口路径**：功能的起始 `/path`（不写域名）。
3. **关键可见文案**：按钮/标题/提示的原文，供步骤与断言使用。
文档里查不到的入口或文案标为「待实地确认」，留给阶段 3。文档与系统不符时**以系统为准**，差异记入变更清单（阶段 6）。

### 阶段 2 — 人工辅助登录（两处登录，一次性采集）
开一个 headful 浏览器，引导用户完成：
1. **登录被测系统**（扫码/账密）→ 导出 Playwright `storageState` 存到 `output/<run>/.auth/state.json`；AI 后续的实地探索与执行都复用它。登录态失效则**暂停提示重登**，不自动重登（可能要验证码/扫码）。
2. **登录 aitestui** → 取 API token 填入 `AITESTUI_TOKEN`。
登录态只落本地文件，不写进用例、不灌进平台。

### 阶段 3 — 接入准备（无项目时）
按 `references/api-contract.md` 串现有 API：
`POST /projects/add` → `POST /project-envs/add` → `POST /project-env-vars/batch`（写 `URL`；`COOKIE` 等保密变量引导用户在平台手填）→ `GET /project-branches/default`（取 `branchId`）。全部用现有端点，不改平台。
已有 `PROJECT_ID` 则只取 `branchId`，不重建。

### 阶段 4 — AI 实地探索 + 生成用例池（LLM 生成槽位）
带着 `spec.md` 和登录态，用浏览器实地走查每个功能点：确认入口、真实可见文案、断言落点；修正「待实地确认」项，并把文档与实际的差异写入 `output/<run>/changes.md` 的「文档差异」节。

然后一次性生成**接入基线用例池**（不是三份独立用例），每条是一个 7 列 JSON 项（`code/name/format/tags/selfHealEnabled/promptContent/scriptContent`）：
- `format='prompt'`，自然语言全文放 `promptContent`，严格套用手册 10 条硬约束；
- `code` 由标题生成稳定大写编码（`^[A-Z][A-Z0-9_]{1,127}$`）；
- `tags` 打分层标签：`冒烟` / `核心` / `负向`。三批是同一池的筛选视图：**冒烟 ⊂ 核心 ⊂ 全量**，全量 = 核心 ∪ 负向。
- 负向用例单独生成但共享 code 前缀，断言写「系统正确拒绝/给出错误提示」这类可判定陈述。

生成后先跑 `node scripts/case-lint.mjs <pool.json>`（见 `references/case-rules.md`）做静态校验，不过的先自修。

### 阶段 5 — 三批串行自执行 + 改到全过（本地执行槽位）
按 **冒烟 → 核心 → 全量** 门禁执行，前一批全过才进下一批。每条用例：
1. 用 Midscene + Playwright 本地执行（复用登录态），判定 pass/fail。
2. **失败 → 归因**（这是核心）：默认系统正常，失败只可能是两类——
   - (a) **用例问题**：元素描述不够视觉化、步骤错、断言写法平台判不了、`${VAR}` 未配、入口路径错 → 按实地看到的行为改用例；
   - (b) **文档落后**：文档描述与系统实际不符 → 按系统实际行为改用例，并把差异记入 `changes.md`。
   **绝不因为失败就判定「系统有 bug」而挂起**（除非用户另行说明系统可能有问题）。
3. 改完重跑该条，直到通过。用同一把执行模型；失败截图/日志存 `output/<run>/runs/<code>/` 供追溯。
4. **熔断**：同一条用例连续 3 次修正仍不过 → 标 `needs_human`、写清卡点，**跳过它继续其他用例**，不阻塞整批。批次结束时若存在 `needs_human`，该批不算「全过」，暂停并向用户报告。

### 阶段 6 — 灌入 aitestui（不改平台）
全过（或用户确认接受 `needs_human`）后，按 `references/api-contract.md` 用 `POST /test-cases/import` 把通过用例批量灌入 `PROJECT_ID` + `branchId`。code 冲突语义是**覆盖**，反复导入会更新平台已有内容——首次接入前确认目标项目是空的或用户接受覆盖。导入后核对返回的 `created/updated/failed`。

### 阶段 7 — 变更清单收口
`output/<run>/changes.md` 分两节定稿：
- **文档差异**：文档说 X、系统实际 Y、用例已按 Y 写；
- **接口需求**：测试所需但系统/平台当前缺失的接口或能力。
只在确需改造 aitestui 平台时才在这里记「平台改造点」，**本 skill 一律不改平台代码**——改造点最后统一开发。

## 产物（output/<run>/）

| 文件 | 用途 |
|---|---|
| `spec.md` | 文档解析出的功能点/入口/文案 |
| `.auth/state.json` | 被测系统登录态（本地，勿提交） |
| `pool.json` / `pool.xlsx` | 接入基线用例池（JSON 供执行与导入，XLSX 供人审阅，7 列往返模板） |
| `runs/<code>/` | 每条用例的执行截图、日志、修正历史 |
| `changes.md` | 文档差异 + 接口/平台改造需求（最后统一开发） |
| `summary.md` | 三批通过统计、`needs_human` 清单、导入结果 |

## 硬边界

- **不改平台代码、不改平台接口**；一切写入走现有 API，改造需求只记录。
- **登录态不进用例、不进平台**；`COOKIE` 等保密变量引导用户在平台环境里手填。
- **执行模型与生成模型分离配置**，但都只认 OpenAI 兼容端点（`MIDSCENE_MODEL_*` 9 种 family 开箱兼容）。
- **失败不判系统 bug**（除非用户明确说系统可能有问题），按真实行为改用例到全过；3 次熔断转人工。
- 全程中文用例、断言结尾；不写死域名/凭据/易变数值。
