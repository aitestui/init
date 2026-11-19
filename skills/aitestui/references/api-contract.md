# aitestui 现有 API 契约（只读参照，勿改平台）

基址：生产 `https://aitestui.com/api/v1`（**含 `/v1`，写死**）；仅用户明确要求本地开发平台时才用 `http://127.0.0.1:7001/api/v1`。**不从 runner/.env 推断**——其 `API_BASE_URL` 指向本地 7001、其 TOKEN 打生产返回 `code:1101`，两者都不可复用。以下端点均为**现行**：
导入导出端点现行有效；以本文件为准。

**鉴权（用用户给的平台身份令牌 PAT，Bearer 直调）**：用户在调用里给的 `h5qa_...` 令牌是 aitestui 个人访问令牌，所有 API 用脚本发请求带 Bearer 头即可，**不需要浏览器登录、不需要同源 fetch**：
```
Authorization: Bearer <用户给的身份令牌>
Content-Type: application/json
```
平台 guard（`access-token-auth.guard.ts`）对 Bearer 通道放行 PAT——`machine` 类型令牌**只在 Cookie 通道被禁**，Bearer 完全可用。令牌只放请求头，不写文件、不回显、日志脱敏。**绝不用 runner/.env 的机器 token**（打生产返回 `code:1101`）。

**统一响应包装**：所有端点返回 `{"code":200,"data":<实体>,"message":"success","deployVersion":"..."}`，成功码 `code=200`；真正的业务数据在 `data` 里。`code≠200` 为失败，读 `message`。分页 data 是 `{rows,total,...}`。

## 执行闭环（阶段 5-6：导入 → 触发 → 轮询 → 日志 → 改用例重跑）

### 1) 导入后反查 caseId
`POST /test-cases/import` 只回计数、**不回 caseId**。用 `GET /test-cases/index?projectId=<>&branchId=<>&code=<精确编码>` 从 `data.rows[]` 取 `id`，建 `code → caseId` 映射。也可用 `tags` 过滤做批次筛选。

### 2) 触发执行
- 批量：`POST /test-runs/batch-run`，body `{projectId, branchId, caseIds:number[], environmentId?, variables?, modelRef?, name?}` → `data:{id}`（runId）。`variables` 是本次变量覆盖；`modelRef` 形如 `platform:<id>`/`project:<id>`，留空走默认解析链。
- 单条：`POST /test-runs/run`，body `{projectId, branchId, testCaseId, environmentId?, variables?, modelRef?}` → `data:{id}`。
- 重跑失败：`POST /test-runs/rerun-failed` body `{id:<原runId>}` → 新 runId（用最新发布版本）。
- 权限码：`execution:run:batch-run` / `execution:run:run`；登录用户需具备对应角色的权限。

### 3) 轮询终态
`GET /test-runs/get?id=<runId>` → `data` 是 TestRunEntity：
- `status`：`queued|running|passed|failed|cancelled`（后三者为终态）；
- 用例计数：`total/passed/failed/cancelled/warnings`；`durationSeconds`、`tokenCount`、`startTime/endTime`；
- `attempts[]`：每条是一次用例尝试。关键字段：`id`（**= attemptId，本地日志目录名后缀**）、`caseId`、`caseName`、`runnerType`（`local`/`cloud`）、`runnerUuid`、`status`、`errorCode`、`errorMessage`、`failureResponsibility`、`failurePhase`、`failureScope`、`resultSummary`、`midsceneReportUri`——**用例级 pass/fail、失败原因、日志寻址的第一真相源**。（`executionToken` 不返回。）
- 轮询设总超时（建议 30 分钟），超时标 `needs_human`；实时进度可选订阅 `GET /test-runs/<id>/events`（SSE，`run-update` 事件带 run 摘要 + `logs[]`）。

### 4) 读日志与报告（失败归因必做，本地优先）

**先判归属**：从 `attempts[]` 按 `caseId` 取目标条目的 `id`/`runnerType`/`runnerUuid`。`runnerType==='local'` 且 `runnerUuid` 与本地 runner 一致 → 走 4A；否则（cloud 或本地无目录/超期）→ 走 4B。

#### 4A) 本地 runner 日志（默认，`RUNNER_MODE=local`）
本地每执行一次 attempt 落一个目录，**无环境变量可改根路径**——根目录恒为 runner 进程 cwd 下的 `.h5qa-runs`（runner 代码 `resolve(process.cwd(), '.h5qa-runs', '<runId>-<attemptId>')`）。故 skill 必须传入 `LOCAL_RUNNER_ROOT`（runner 的工作目录，本地开发如 `/Users/yfj/code/h5qa/runner`；Docker 内为 `/app`，宿主挂载见下）。

```
<LOCAL_RUNNER_ROOT>/.h5qa-runs/<runId>-<attemptId>/
  log/<topic>.log        # Midscene 写入，colon→横杠命名
  report/<runId>-<attemptId>-YYYY-MM-DD_HH-mm-ss-<8hex>.html
  execution.webm         # 录像（失败回落 page@*.webm）
```
- **寻址**：精确用 `attempts[].id` 拼 `<root>/.h5qa-runs/<runId>-<attemptId>`；拿不到才兜底 glob `<runId>-*`。**重跑会产生新 runId**，绝复用旧 runId 找日志。
- **读哪些**：`log/` 下优先 `ai-call.log`（LLM 请求/响应，信息最全）、`planning.log`（模型决策）、`task-runner.log`、`agent.log`；`report/` 取 mtime 最新的 `*.html`（每步截图+dump，可视化最全）。日志行格式 `[时间戳] <message>`。
- **脱敏**：本地 `log/*.log` 是**未脱敏原文**（脱敏只在上传构件时对内存文本做，不回写本地）。展示/外发前按 `redactRunnerSecrets` 口径处理：sk- key、Bearer token、cookie/sessionid/token/csrf、OSSAccessKeyId/Signature 等。
- **时机与边界**：终态瞬间 topic 文件可能有毫秒级异步 flush 尾窗 → 读到空/半截就短暂等待重试一次；目录只保留 **3 天**（`RUN_DIR_RETENTION_DAYS`），超期转 4B。全程进程日志另在 `~/.h5qa-runner/logs/runner-YYYY-MM-DD.log`（7 天，未脱敏），可补充。
- 宿主侧若 runner 跑在 Docker：容器 `/app/.h5qa-runs` 通常挂载到宿主 `<instance>/runs`，`LOCAL_RUNNER_ROOT` 传容器工作目录还是宿主挂载路径取决于 skill 进程能否直连该目录。可参考 `runner/scripts/collect-runner-logs.py`（`--runs-root` 归档 `<runId>-<attemptId>` 的 log/report）。

#### 4B) 云 runner 日志（`RUNNER_MODE=cloud`，或本地不可用时兜底）
`GET /test-runs/<runId>/artifacts` → `data:[{attemptId,type,objectKey,mimeType,byteSize}]`（仅 `status=uploaded`）。`type` 枚举：
- `runner-log`：**失败全程日志**（脱敏后的 Midscene topic log + tee 窗口切片，**2MB 尾截**，仅 failed 上传）——云的失败归因主渠道；
- `midscene-report`：可视化 HTML 报告；`screenshot`：最终截图；`caselog-video`：录像；`pixel-diff`：视觉差异。
- `objectKey` 是对象键、**不是 URL**。拼公开域名：`https://static.appkc.com/<objectKey去掉前导/与旧域名>`（生产缺省；若平台配了 `VITE_OSS_PUBLIC_BASE` 以它为准）。`curl` 拉文本读尾部。
- 云 runner 是另一容器/进程，**本地 `.h5qa-runs` 不会有它的日志**，必须走本路径。

**兜底**：本地目录读不到且云 `artifacts` 无 `runner-log`，且 `errorMessage` 也空 → **不得猜着改用例**，标 `needs_human`。

### 5) runner 调度与 runnerPreference（决定谁执行，进而决定日志在哪）
- 项目级真源是 `project.runner_preference`（`local`/`cloud`）；新建 web 项目默认 `cloud`，computer/android 默认 `local`。
- 触发执行时的 `runnerPreference` 入参覆盖项目偏好，但受**死锁矩阵**：cloud 项目传 `local`、local 项目传 `cloud` 都返回 422。所以 skill 一般**不传**，让项目偏好生效；只有用户明确要求且项目偏好一致时才传。
- local 任务只被 `authentication.type==='local'` 且项目匹配的在线 runner 认领；无人认领则队列超时（云兜底翻转已删除）。**本地模式要先确认有 local runner 在线**。
- 云执行时日志只在云端 OSS，本地 `.h5qa-runs` 无目录——这正是 `RUNNER_MODE` 要与 `attempt.runnerType` 对齐校验的原因。

### 6) 执行模型（平台侧，全自动）
runner 从平台拿模型配置。**触发执行时不传 `modelRef`，走平台默认解析链**——不需要向用户要模型配置，也不需要 skill 查/配模型。文档→用例、失败→改用例由执行本 skill 的 AI 自己完成（它本身就是 LLM），无外部生成模型参数。family 兼容性与平台默认配置由平台负责。

### 7) 成本
每次入队判积分余额 ≥ 1，结算按实际消耗扣（无冻结、可扣负）。余额不足 attempt 落 `errorCode=user_credits_insufficient`。三批 + 反复重跑持续扣费——熔断（同 code 3 次）是成本护栏。

## 接入准备（先按名复用，找不到再新建）

用户一句话里可能给了项目名/环境名（如「主干系统项目」「testrun222 环境」）。**先查后用，不要每次新建**：

| 目标 | 端点 | 要点 |
|---|---|---|
| 找项目 | `GET /projects/index` | 返回 `data.rows[]`，按 `name` 匹配；命中取 `id` 复用。用户直接给 id 则跳过 |
| 建项目 | `POST /projects/add` | 没命中时；必填仅 `name`；`targetUrl`/`targetType`/`runnerPreference` 可空（默认 web/cloud） |
| 找环境 | `GET /project-envs/index?projectId=<>` | 返回 `data.rows[]`（`{id,key,name,...}`），按 `name` 或 `key` 匹配，命中取 `id` 复用 |
| 建环境 | `POST /project-envs/add` | 没命中时；必填 `projectId`/`key`/`name`；域名不是环境字段，写进 `URL` 变量 |
| 写普通变量（如 URL） | `POST /project-env-vars/batch` | 整批原子 upsert，行只带 `name`+`value`，定位键 `(scope,envId,name)`，上限 500；**不碰保密变量**（碰了整批 400） |
| 写保密变量 | `PUT /project-env-vars/edit`（或 `POST /project-env-vars/add`） | **支持 secret！** DTO 带 `type:'secret'`+`value`，service 加密落库。见下方详解 |
| 查变量行 id | `GET /project-env-vars/index?projectId=&envId=&name=` | `data.rows[]` 里每条有 `id`；secret 值只掩码回显（前二+星+后二），但**拿 id 就够**用来 edit |
| 查变量 | `GET /project-env-vars/resolve?...` | 解析项目级→环境级，`secret` 类型**不回读值**（只回 null），别指望从这里拿凭据 |
| 取分支 | `GET /project-branches/default?projectId=<>` | 项目无分支时自动补「主分支」，返回 `branchId` |

**保密变量（USERNAME/PASSWORD/COOKIE）写入方法**（已核实源码 `project-env-vars.service.ts`，勿再当成"API 不支持"）：

1. 新建项目/环境时平台会预填这四行约定变量（`URL/USERNAME/PASSWORD/COOKIE`）的**空行**。先用 `GET /project-env-vars/index?projectId=&envId=&name=USERNAME` 找到该行的 `id`（name 是模糊匹配，取精确等于的那条）。
2. 用 `PUT /project-env-vars/edit`，body：`{"id":<行id>,"projectId":<项目id>,"type":"secret","value":"<明文值>"}`。service 会把 value 加密落库；repeat edit 传新 value 即覆盖。
3. 三个变量分别写：`USERNAME`=账号、`PASSWORD`=密码、`COOKIE`=站点登录态（用户给令牌时）。**secret 值绝不放进 batch**（DTO 无 type 字段，会被判脏行整批拒绝）。
4. 值与令牌只在请求体里出现，不写日志、不写产物、不回显。

**绝不需要**：开浏览器登录平台、识别验证码、在平台前端代填。这些都基于过时的"保密变量 API 写不了"的错误结论——那是错的。复用已有项目/环境时**不清空已有配置**，变量写入只覆盖本次用户明确给的那几行；导入用例是覆盖语义（见下）。

## 灌入用例（阶段 6）

`POST /test-cases/import`，**纯 JSON**，单批上限 500：

```json
{
  "projectId": 12,
  "branchId": 34,
  "items": [
    {
      "code": "SMOKE_CART_CHECKOUT",
      "name": "购物车结算下单",
      "format": "prompt",
      "tags": "冒烟,核心",
      "selfHealEnabled": 1,
      "promptContent": "购物车结算下单\n1. 打开 /cart\n...\n断言：页面出现「下单成功」文案",
      "scriptContent": ""
    }
  ]
}
```

- 列为**驼峰**（`selfHealEnabled`/`promptContent`/`scriptContent`），不是下划线。
- 自然语言全文放 `promptContent`；非 prompt 格式仅作存档、runner 不读。
- `code`：trim → 非 `[A-Z0-9_]` 转 `_` → 大写，须匹配 `^[A-Z][A-Z0-9_]{1,127}$`；不合规进 `failed[]`。建议 skill 直接生成合规码。
- **冲突语义 = 覆盖**：命中即局部覆盖（空列不碰、format 不可变），未命中新建。反复导入会更新平台已有内容——首次接入确认目标项目是空的或用户接受覆盖。新建行 `selfHealEnabled` 默认 0，要勾选需显式传 `1`。
- 返回 `created/updated/unchanged/failed/warnings`，导入后逐一核对。
- 另一通道 `POST /test-cases/import-zip`（一案一文件）本 skill 不用。

## 用例生成（无需外部模型配置）

「文档→用例」「失败→改用例」由执行本 skill 的 AI 自己完成（它本身就是 LLM），**不读取、不要求任何外部模型配置**。不向用户索取模型名、接口地址或密钥。

## 不做的改造（若要，记入 changes.md 最后统一开发）

- 「一个端点完成全部初始化」的聚合接口 —— 目前只能串多个现有端点。
- 平台内的「上传文档→生成用例」UI 入口 —— 目前生成只能在平台外（本 skill）。
- 保密变量经 API 写入 —— 目前只能前端手填。
