---
name: aitestui
description: 为「接入 aitestui 的新系统」从系统手册等文档自动生成接入基线用例集，用平台自身能力完成「建项目/环境 → 写登录态变量 → 生成用例 → 导入 → 平台执行 → 读日志 → 改用例重跑」全链路。用户提供平台身份令牌 + 一句话参数（文档/站点/环境/数量/层级/被测系统账号密码）即可，AI 全部通过平台 API 驱动，不自己开浏览器。当用户想「根据文档自动写 aitestui 测试用例」「降低用例初始化工作量」「一句话初始化 N 条核心用例」「批量接入系统/铺冒烟用例」时使用。
---

# aitestui 接入基线用例自动生成（Onboarding Baseline Autocase）

补上 aitestui 缺失的那块能力：**用户不必从零手写用例**。给一份被测系统的手册和平台身份，本 skill 用**平台自身的能力**完成「建工程 → 配登录态 → 生成用例 → 导入 → 执行 → 读日志 → 改用例到全过」。

## 一句话不变量（最重要，先读）

> **这个 skill 不自己干活，只指挥 aitestui 干活。** 所有事情——打开被测站点、登录、点按钮、判定结果、出报告——都是**平台 runner 执行用例**时做的。skill 只做三件事：**调平台 API**（建工程/写变量/导入用例/触发执行/读结果）、**生成与修改用例文本**、**按执行日志归因**。

具体说，**skill 绝不做**这些事（这些都是平台 runner 的职责，做错了方向）：

- ❌ 自己开浏览器去访问被测站点、实地走查页面、确认入口/文案；
- ❌ 自己登录被测系统、识别验证码、注入 Cookie、写"等待验证码输入"脚本；
- ❌ 自己在本地用 Midscene/Playwright 执行用例。

入口和文案对不对、**登录态是否有效**，一律由**平台执行用例的真实结果**来证明；失败就看平台日志，按日志改用例重跑。文档可能落后，以平台跑出来的真实行为为准。

## 用户沟通纪律

**用户是普通使用者**。AI 不主动索要技术词，用户主动给的东西照单全收、直接用，不反问"其实你不需要给这个"。确认时用大白话。用户给的**平台身份令牌、被测系统账号密码**只在调 API / 配变量时使用，绝不写进用例、产物或回复，绝不回显。

## 鉴权：用户给的平台身份令牌（PAT）

用户在调用里给的身份令牌（形如 `h5qa_...`）是 aitestui 的个人访问令牌，**直接用它调所有平台 API**：

```
Authorization: Bearer <用户给的身份令牌>
Content-Type: application/json
```

平台 guard 对 Bearer 通道放行 PAT（`machine` 类型令牌**只在 Cookie 通道被禁**，Bearer 完全可用，见源码 `access-token-auth.guard.ts`）。所以：

- **不需要浏览器登录平台，不要引导用户登录 aitestui**；
- 从这里开始所有 API 都用脚本发请求带这个头（不是浏览器同源 fetch）；
- 令牌只放在脚本请求头里，**不写进任何文件、不回显、日志脱敏**。

平台基址固定生产 `https://aitestui.com/api/v1`；仅用户明确说连本地才用 `http://127.0.0.1:7001/api/v1`。**不读 runner/.env 推断平台参数**（那是 runner 自己的机器凭据，打生产返回 `code:1101`）。不做探索式探测、不 curl 本地探活、不翻工作区找令牌。

## 调用方式：一句话带齐参数

用户不必填表，一句大白话把能给的都给了，AI 从中解析，缺关键项才一轮问齐：

| 用户可能这么说 | 解析成 | 用途 |
|---|---|---|
| 「用户身份：h5qa_xxx」 | 平台 PAT | Bearer 调所有 API（必需） |
| 「读取当前目录下的文档」「手册在 /path/a.pdf」 | `DOC` | 文档文件或目录（目录下 PDF/DOCX/MD/HTML 全读） |
| 「https://xxx/#/zh-CN/」 | `TARGET_URL` | 写入环境 `URL` 变量（平台只接受 origin，hash/路径自动忽略） |
| 「testrun222 环境」 | `ENV_NAME` | 按 name/key 复用已有环境，找不到才新建 |
| 「主干系统项目」 | `PROJECT_NAME` | 按 name 复用已有项目，找不到才新建 |
| 「初始化 10 条」 | `COUNT` | 用例数量上限 |
| 「核心测试用例」「冒烟」「全量含负向」 | `LEVEL` | 生成层级：冒烟 / 核心 / 全量 |
| 「账号 mahy，密码 1234」 | 被测系统 `USERNAME`/`PASSWORD` | 写成平台环境级 secret 变量 |
| 「用户身份 token：xxx」（被测站点登录态） | 被测系统 `COOKIE` | 写成平台环境级 secret 变量 |

**用户原话示例及解析**：

> `/aitestui 用户身份：h5qa_xxx 读取当前目录下的文档 初始化 10 条核心测试用例 环境：testrun222 url: https://bims-testrun2-2-2.ccic.com/ccictyx/#/zh-CN/ 账号 mahy,密码 1234`

- 平台 PAT = h5qa_xxx（Bearer）；文档 = 当前目录；环境 = testrun222（按名复用）；
- 数量 = 10；层级 = 核心（**只生成核心层 10 条，跳过冒烟/负向门禁**）；
- 被测系统账号 mahy / 密码 1234 → 写入该环境的 `USERNAME`/`PASSWORD` secret 变量；
- URL → 写入 `URL` 变量（平台归一为 `https://bims-testrun2-2-2.ccic.com`）。

**缺省规则**：

- 没给数量也没给层级 → 默认**三批全量**（冒烟 ⊂ 核心 ⊂ 全量，串行门禁）。
- 给了层级没给数量 → 生成该层全部；给了数量没给层级 → 默认核心层取前 N 条。
- 数量/层级只决定生成与执行范围，不自作主张跑三批。
- 没有平台令牌 → 停下用大白话请用户提供（这是唯一必须问的平台项）；缺文档或站点地址 → 一轮问齐。
- 被测系统没给账号密码/COOKIE → 照常生成用例，但登录步骤用 `${USERNAME}`/`${PASSWORD}` 占位并提示用户到平台补填登录态变量，不自己登录。

## 工作流（严格分阶段，阶段间是门禁）

### 阶段 1 — 文档解析
读 `DOC`，抽取三样东西写成 `output/<run>/spec.md`：① 功能点清单（每条可独立验证）；② 入口路径（`/path`，不写域名）；③ 关键可见文案（按钮/标题/提示原文）。文档里查不到的标「待实地确认」——**注意：这里不靠 skill 开浏览器确认，而是先按文档写用例，靠阶段 5 的平台执行结果来校正**。文档与平台跑出来的真实行为不符时以真实行为为准，差异记入 `changes.md`。

### 阶段 2 — 接入准备：建工程 + 配变量（全 API，无需浏览器）

按 `references/api-contract.md` 串现有端点（全部带 PAT 的 Bearer 头）：

1. **项目**：给项目名 → `GET /projects/index` 按 name 匹配复用；没有 → `POST /projects/add`。给了 id 直接用。
2. **环境**：给环境名（testrun222）→ `GET /project-envs/index?projectId=` 按 name/key 匹配复用；没有 → `POST /project-envs/add`。
3. **变量**：
   - `URL`：新建环境预填的空行用 `POST /project-env-vars/batch` 写入（batch 只碰非保密变量）；
   - `USERNAME` / `PASSWORD` / `COOKIE` 是环境级 **secret 变量**：先 `GET /project-env-vars/index?projectId=&envId=&name=USERNAME` 拿到预填空行的 `id`，再用 `PUT /project-env-vars/edit`（带 `id`、`projectId`、`type:'secret'`、`value`）逐条写入。**secret 值禁止放进 batch**（会被整批 400 拒绝）。
4. **分支**：`GET /project-branches/default?projectId=` 取 `branchId`。

**复用已有项目/环境时不清空已有配置**；变量写入是覆盖式更新，只动本次用户明确给的那几行。设完即可，不用去浏览器核对。

### 阶段 3 — 生成用例（AI 自己写，无需外部模型）

按 `spec.md` 生成**接入基线用例池**，每条是 7 列 JSON（`code/name/format/tags/selfHealEnabled/promptContent/scriptContent`）：

- `format='prompt'`，自然语言全文放 `promptContent`，严格套用 `references/case-rules.md` 的 10 条硬约束；
- `code` 由标题生成稳定大写编码（`^[A-Z][A-Z0-9_]{1,127}$`）；
- `tags` 是**字符串数组**，如 `["冒烟","核心"]`，打 `冒烟`/`核心`/`负向` 分层标签（三批是同一池的筛选视图：冒烟 ⊂ 核心 ⊂ 全量）。**不要写成 `"冒烟,核心"` 逗号字符串**——那是 XLSX 模板单元格的格式，平台前端会自动切分，而本 skill 直接 POST 的 JSON 不会，传字符串会被导入接口拒绝；
- **登录处理**：阶段 2 已配好登录态变量时，按手册规则"配了 COOKIE 免登录就不写登录步骤"；只有账号密码时，需要登录的用例写 `输入 ${USERNAME}` / `输入 ${PASSWORD}` 占位步骤；
- **入口只写 `/path`**，不写域名（域名在 `URL` 变量里）；负向用例断言写「系统正确拒绝/提示」。

**按调用参数收敛范围**：给了数量/层级就按指定生成（「10 条核心」= 只生成核心层 10 条）；没指定才生成完整三批池。生成后跑 `node scripts/case-lint.mjs <pool.json>` 静态校验，不过的先自修。

### 阶段 4 — 导入平台（先导入才能执行）

用 `POST /test-cases/import` 把当前批次用例批量导入项目 + `branchId`（纯 JSON、驼峰列，字段类型表见 api-contract）。
- 发请求前逐项对表：`projectId`/`branchId` 是查回来的**数字 id**（不是名字/字符串），`items[].tags` 是**字符串数组**，`selfHealEnabled` 是数字 `0|1`。类型错了整批会被 422 拒掉，别原样重试。
- code 冲突语义是**覆盖**（空列不碰、format 不可变）；复用已有项目时首次接入前确认目标为空或用户接受覆盖。核对返回 `created/updated/unchanged/failed`。
- 导入失败（422 或 `failed[]` 非空）时，按 `message` / 行内原因定位到具体字段改 `pool.json` 再重导；**看不出原因就停下报告用户，不要盲目重跑**。
- 导入只回计数、**不回 caseId**。用 `GET /test-cases/index?projectId=&branchId=&code=<精确编码>` 逐条查回 `id`，建 `code → caseId` 映射存 `output/<run>/case-ids.json`。

### 阶段 5 — 平台执行 + 读日志 + 改用例到全过（核心闭环）

按调用参数决定的范围执行：默认 **冒烟 → 核心 → 全量** 串行门禁；用户指定则**只跑指定范围**（「10 条核心」只跑这 10 条）。每批子流程：

1. **触发执行**：`POST /test-runs/batch-run`，body `{"projectId","branchId","caseIds":[...],"environmentId":?,"name":"<批次名>"}` → `{id}`（runId）。单条调试用 `POST /test-runs/run`（`testCaseId`）。**不传 `runnerPreference`**，让项目偏好生效（强传冲突偏好会被 422 拒绝）。local 模式须有在线且匹配的 runner，否则队列超时。
2. **轮询终态**：`GET /test-runs/get?id=<runId>` 看 `data.status`（终态 `passed|failed|cancelled`）。退避轮询 + 总超时（30 分钟），超时标 `needs_human`。`data.attempts[]` 每条有 `id`（= attemptId）、`caseId`、`runnerType`、`runnerUuid`、`status`、`errorCode`、`errorMessage`、`failurePhase`、`resultSummary`——**用例级 pass/fail、失败原因、日志寻址的第一真相源**。
3. **读日志与报告**（失败归因必做，细节见 api-contract）：
   - **local（默认）**：从 `attempts[]` 按 `caseId` 取 attemptId，核对 `runnerType/runnerUuid`；直读 `<LOCAL_RUNNER_ROOT>/.h5qa-runs/<runId>-<attemptId>/` 下的 `log/*.log`（优先 `ai-call.log`、`planning.log`）和 `report/` 最新 `*.html`。重跑产生新 runId，绝不复用。日志 3 天保留、未脱敏，外发前脱敏。
   - **cloud**：`GET /test-runs/<runId>/artifacts` 取 `objectKey`，拼 `https://static.appkc.com/<key>` 拉；`runner-log` 是脱敏失败全程日志，`midscene-report` 是 HTML 报告。
   - 归档到 `output/<run>/runs/<runId>-<attemptId>/`。
4. **失败 → 归因**（默认系统正常，文档可能落后，只两类）：
   - (a) **用例问题**：元素描述不视觉化、断言平台判不了、`missing_variable`、`entry_url_unresolvable`、步骤错、登录态失效（`errorCode` 指向变量/登录） → 结合 `errorMessage` 和真实日志改 `promptContent` 或补配变量；
   - (b) **文档落后**：日志显示系统实际行为与文档不符（真实文案/入口不同） → 按真实行为改用例，差异记入 `changes.md`「文档差异」节。
   **绝不因失败就判「系统有 bug」而挂起**（除非用户另行说明）。日志读不到且 `errorMessage` 也空 → 不得猜着改，标 `needs_human`。
5. **改完重跑**：改后重新 `POST /test-cases/import`（按 code 覆盖），再 `POST /test-runs/batch-run` 只跑这些 caseIds。循环到通过。
6. **熔断**：同一 code 连续 3 次修正仍不过 → 标 `needs_human`、写清卡点（runId + errorMessage + 日志路径/URL），跳过继续其他用例；批次有 `needs_human` 就不算全过，暂停报告用户。

### 阶段 6 — 变更清单收口
`changes.md` 分两节：① **文档差异**（文档说 X、系统实际 Y、用例已按 Y 写）；② **接口需求**（测试所需但平台当前缺失的能力）。**本 skill 一律不改平台代码**，改造点最后统一开发。

## 产物（output/<run>/）

| 文件 | 用途 |
|---|---|
| `spec.md` | 文档解析出的功能点/入口/文案 |
| `pool.json` / `pool.xlsx` | 用例池（JSON 供导入，XLSX 供人审阅，7 列往返模板） |
| `case-ids.json` | 用例 code → 平台 caseId 映射 |
| `runs/<runId>-<attemptId>/` | 每次尝试的 attempt 摘要、日志/报告（本地路径或云 URL）、修正历史 |
| `changes.md` | 文档差异 + 接口/平台改造需求 |
| `summary.md` | 通过统计、`needs_human` 清单、导入结果、总积分消耗 |

登录态（账号密码/令牌/Cookie）**只在平台变量里加密存储**，skill 侧产物不保存明文凭据。

## 硬边界

- **只用 aitestui 能力，skill 不自己开浏览器访问/登录被测站点、不识别验证码、不本地执行用例**；打开页面、登录、断言、出报告全是平台 runner 的事。
- **平台身份用用户给的 PAT，Bearer 直调 API**；不引导浏览器登录平台、不读 runner/.env、不做探索式探测。
- **登录态走平台 secret 变量 API**（单条 add/edit 支持 secret，batch 不支持）；凭据不进用例、不进产物、不回显、不外发。
- **不改平台代码、不改平台接口**；改造需求只记录到 `changes.md`。
- **日志默认直读本地 runner 文件系统（local），云执行走平台 OSS 构件（cloud）**；按 `attempt.runnerType/runnerUuid` 校验对齐。`RUNNER_MODE` 只选日志来源、不改执行落点。
- **失败必读真实日志再归因**；本地日志未脱敏，外发前脱敏；读不到不得猜着改，标 `needs_human`。
- **失败不判系统 bug**（除非用户明确说），按真实行为改用例到全过；同 code 3 次熔断转人工。
- **范围按用户指定**：给了数量/层级只做指定范围，缺省才三批全量。
- **积分成本**：执行会扣积分，开跑前确认余额；反复重跑持续扣费，熔断避免无底洞。
- 全程中文用例、断言结尾；不写死域名/凭据/易变数值。
