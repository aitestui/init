# ADR-0075：接入基线用例自动生成 skill（文档→实地探索→自执行→灌回平台）

- Status: **Accepted**（grill-with-docs 定案，2026-11-18；三轮 grill 收敛，前沿已空）
- Date: 2026-11-18
- Applies to: 全局（用户级）skill `~/.workbuddy/skills/aitestui/`（SKILL.md + references + scripts，本地名与对外发布名统一为 `aitestui`）；不改 `api-h5qa` / `fe_aitestui` / `runner` 任何代码。原为项目级 skill，2026-11-18 移至全局——本 skill 用于测试**其他**项目，绑在 h5qa 项目目录会限制其适用范围
- Related: ADR-0063（纯自然语言执行）、ADR-0070（导入导出端点回退恢复）、ADR-0033（7 列往返模板）、ADR-0039（会话凭据）、ADR-0052（约定变量）
- Terminology: `docs/glossary-onboarding-baseline.md`（本文不重复定义术语）

## Context

诉求原文（经三轮澄清后）：「用户使用 aitestui 时初始工作量太大，需要利用现有系统手册之类的文档和 AI 能力自动完成初始化测试用例；我现在缺的就是这个能力。如果这个能力需要改造 aitestui，先记录下来，最后统一添加。」

第一轮 grill 曾把目标误解为「通用测试执行/自愈工具」，被用户纠正：**目标不是找 bug 的工具，而是降低新系统接入 aitestui 的冷启动成本**——把系统手册喂给 AI，自动铺出一套能跑通的基线用例。第二轮问执行引擎/登录态/产物格式被用户指出「不是真正的问题」后，重新聚焦到这块能力缺口本身。

代码核对出的硬事实（决定边界）：

1. **平台「写用例」这一步最重**：用户须按手册 §6.2 的 10 条硬约束逐条手写自然语言 prompt，且常因「元素描述不够视觉化」首跑失败（`aitestui-user-manual.md:188-199,459`）。这正是冷启动痛点。
2. **平台没有任何「文档→用例」生成端点**：全量扫描 controller 无 generate/文档解析上传路由；手册 §6.3 让用户把提示词贴到外部 AI 再手工粘回（`test-cases.controller.ts` / `scenario-templates.controller.ts`）。故生成能力只能放平台外。
3. **灌回平台不需要改接口**：`POST /test-cases/import` 收纯 JSON 7 列用例、上限 500、按 code 覆盖（`test-cases.controller.ts:112-117`、`test-cases.service.ts:671-854`）。项目/环境/变量/分支也都有现成端点（变量可 batch）。
4. **导入导出端点现行有效**：ADR-0063 曾下线 `/test-cases/import*`，ADR-0070 已整体回退恢复；`CONTEXT.md`「现行条文速查」第 1/7 条关于导入导出下线的表述是过期文本，以 ADR-0070 与活代码为准。
5. **兼容主流模型已有底座**：`MIDSCENE_MODEL_*`（baseURL/apiKey/name/family）指向任意 OpenAI 兼容端点，Midscene 按 family 选 adapter，覆盖豆包/Qwen/DeepSeek/Gemini/GPT-5/Kimi/GLM/MiMo 等 9+ family；Anthropic/Claude 无执行期 adapter。

## 术语

见 `docs/glossary-onboarding-baseline.md`。核心是把过载的「初始化测试用例」精确为 **接入基线用例集**——为被测系统首次接入生成的第一批、覆盖主干、可直接执行的自然语言用例。

## Decision

**D1 能力放平台外，不改 aitestui 代码**：生成、编排、归因全部在独立 skill 内完成；写入只调现有 API。用户明确「需要改造的先记录，最后统一添加」——需要改造的点记入 `changes.md`，本期一律不动平台。（早期把「保密变量 API 写入」列为改造点，2026-11-19 经源码核实该能力**已存在**，已移出改造清单，见 D9。）

**D2 全程包办（用户 Q1=C）**：skill 不只产出用例文件，而是「文档 → 登录 → 实地探索 → 生成 → 本地自执行 → 改到全过 → 灌回平台」全链路闭环。否决「只产出 XLSX 让用户自己导入」的理由：那仍需用户手工跑通与修用例，没解决冷启动工作量。

**D3 两处人工辅助登录（用户 Q3=a+b）**：一次性采集两类登录态——(a) 登录被测系统导出 Playwright `storageState`，供 AI 实地探索与本地执行复用；(b) 登录 aitestui 取 API token 供灌库。登录态只落本地文件，不进用例、不进平台；失效时暂停提示重登，不自动重登。

**D4 失败语义：默认系统正常、文档可能落后（用户 Q3 第一轮裁决）**：这是本 skill 与「找 bug 的测试工具」的分水岭。失败只归因于 (a) 用例问题（描述不视觉化/步骤错/断言写法不对/变量未配）或 (b) 文档落后（文档与系统实际不符），两种情况都**按系统实际行为改用例**，差异记入 `changes.md`。**绝不因失败就判系统 bug 而挂起**（除非用户明确说系统可能有问题）。理由：被接入的是已知正常的系统，用例是待校准的产物；「改到全过」本身就是目标，不是掩盖缺陷。

**D5 三批是同一用例集的筛选视图，非三份独立用例（用户 Q4 推荐）**：生成单一用例池，每条打 `冒烟`/`核心`/`负向` 标签；冒烟 ⊂ 核心 ⊂ 全量，全量 = 核心 ∪ 负向。串行门禁：冒烟全过才进核心、核心全过才进全量。负向用例断言写「系统正确拒绝/提示」。

**D6 双模型槽位（用户 Q5）**：生成槽位（文档→用例、失败→改用例）用 LLM；执行槽位用 `MIDSCENE_MODEL_*`，天然兼容 9+ family。两者都只认 OpenAI 兼容端点，不新造 provider 适配层。

**D7 3 次熔断转人工（skill 自加保险，非用户裁决）**：同一用例连续 3 次修正仍不过 → 标 `needs_human`、写清卡点、跳过继续其他用例；批次含 `needs_human` 即不算全过，暂停报告用户。避免 D4 的「改到全过」在极端情况下无限循环。

**D8 灌库覆盖语义须显式确认**：`/test-cases/import` 按 code 覆盖（局部覆盖、空列不碰、format 不可变），反复导入会更新平台内容。首次接入前向用户确认目标项目为空或接受覆盖。

**D9 skill 只指挥平台、不自己干活（2026-11-19 用户真实试跑纠正，推翻 D3 与 D6）**：打开被测站点、登录、识别验证码、点按钮、判定、出报告**全是平台 runner 执行用例时做的**，skill 只调平台 API + 生成/改用例 + 按日志归因。据此：①平台身份用用户给的 PAT 走 Bearer 直调（源码证实 `machine` 令牌只在 Cookie 通道被禁），不引导浏览器登录平台——推翻 D2/D3 里"浏览器登录取 token"的做法；②被测系统登录态通过 `PUT /project-env-vars/edit`（`type:'secret'`，源码证实支持加密落库）写入平台 secret 变量，不自己开浏览器登录、不识别验证码、不导出 `storageState`——推翻 D3；③生成由 skill 自身 LLM 完成、执行用平台默认模型，不配外部模型槽位——推翻 D6；④入口/文案/登录态的有效性一律由**平台执行结果 + 日志**证明，文档落后按日志改用例。用户给的账密/令牌只进平台 secret 变量，不进 skill 产物、不回显。

**D10 内网项目先探活、内网则引导装本地 runner（2026-11-20）**：接入前用两条 curl 判定被测站点是公网还是内网——①本地直连站点 origin；②经平台 nginx `GET /proxy?url=<encoded>`（必带 cookie `h5qa_sid`，值＝PAT 明文；nginx 5s 超时、清空上游 Cookie、固定 UA，仅探活不登录）。本地通+云端通＝公网，走默认云 runner；本地通+云端不通（403/502/504/超时）＝内网，**切项目 `runnerPreference='local'`（`PATCH /execution-settings`）并引导用户在其内网机器执行 `npx aitestuirunner join --url https://aitestui.com/api --token <runner-token>`**（token 来自 `GET /projects/:id/runner-token`），轮询 `/runners/index` 确认在线再执行；本地不通＝地址/网络问题停下问用户。这两条 curl 是 D9 禁令的唯一例外——只取 HTTP 连通性、不登录不断言不看内容。理由：云 runner 在公网，内网项目若走云会在导航阶段全数超时失败；且本地 runner 若项目偏好仍是 cloud 会领不到任务（`project_preference_cloud`）。是否装、装哪台机器由用户决定，skill 不替用户执行 join。

**D11 按积分余额动态定量，控制生成规模与任务粒度（2026-11-20）**：用户没给数量时不再固定「三批全量」，而是生成前 `GET /credits/me` 查一次 `data.balance`，按 `N = min(100, 10 + floor(balance/500)*10)` 算生成条数——余额<500 生成约 10 条（避免堆一批没调试成功的用例），每多 500 积分多 10 条（积分多则提效），单次硬顶 100。用户显式给数量则以其为准（仍受 100 硬顶）。**单执行任务 ≤ 50 条**，超出拆多个 batch-run 串行（长任务失败归因慢、收益低）。查询失败兜底 10 条、记 summary、不阻塞；`balance<1` 提示积分不足但照常生成。理由：积分即执行成本，生成规模必须与可承受的调试/重跑成本匹配——低余额时海量未调试用例纯属浪费，高余额时适度放量提效；任务过长无收益。推翻原「没给数量=三批全量」的缺省（D5 的三批仍作为执行筛选视图保留，但不再决定生成总量）。

**D12 最终交付：总结 + 每批一张产物截图 + 分流链接 + 下一步引导（2026-11-21）**：全部批次跑完后给用户大白话收尾，四块缺一不可——①执行情况总结（用例数/批次/通过失败转人工/积分消耗/needs_human 卡点）；②**三批各一张被测页截图**——从每批 runId 的 `GET /test-runs/<runId>/artifacts` 筛 `type='screenshot'`，用 `objectKey` 拼 `https://static.appkc.com/<objectKey>`（Midscene 执行时平台自动截的被测页面图，**全程 API 拉取，不自己开浏览器/截图**，守 D9）；按实际执行批次取，跑了三批才三张、只跑一批就一张，优先取通过用例的截图，某批无截图则跳过并说明、不编造；③结果链接按用例数分流——**仅 1 条用例→ `https://aitestui.com/projects/<projectId>/history/<runId>`（执行结果页），多条→ `/projects/<projectId>/cases`（用例列表页）**，均为数字 id，引导用户打开确认；④下一步引导（继续补负向/再初始化下一批，沿用现有项目环境），有文档差异则提示修订。截图/链接只来自平台真实返回，拿不到如实说、不编造。理由：接入的最后一公里是让用户直观看到并核实结果，被测页截图比文字更有说服力；单/多用例的结果落点不同，给对链接省去用户自己找。截图来源用户在 2026-11-21 明确选「取执行产物截图」（而非 AI 开浏览器截平台页 / 只给链接），「三个」明确为「三批各一张」。

## Consequences

- **收益**：新系统接入从「逐条手写 + 反复调试」降为「给文档 + 两次登录 + 人工确认」，直接命中平台最大的冷启动痛点。
- **平台零改造**：全部走现有 API，本期不产生平台代码变更、不影响积分/权限/执行链。
- **风险：用例可能被改得「迎合系统」**：D4 刻意接受此取舍——因为系统正常、文档可能落后，用例本就该对齐系统真实行为。代价是若接入的其实是带缺陷的系统，本 skill 不会发现（这是明确的范围外，不是疏漏）。
- **风险：登录态采集中断**：验证码/扫码需人工，登录态失效须重登；这是 D3 刻意保留的人工环节，不自动化。
- **风险：覆盖已有用例**：D8 要求在灌库前确认；code 归一规则由 skill 生成合规码降低失败率。
- **未来**：`changes.md` 中的平台改造点（聚合初始化端点 / 文档上传 UI / 保密变量 API）留待统一开发，届时另起 ADR。

## 实施记录

- 2026-11-18：产出 skill（SKILL.md、references/api-contract.md、references/case-rules.md、scripts/case-lint.mjs）；本 ADR 与新术语表同批落地。skill 尚未在真实系统上跑通过，首次使用按 SKILL.md 的阶段门禁执行并回填验收结果。
- 2026-11-18（同日修订）：skill 从项目级 `.workbuddy/skills/` **移至全局用户级 `~/.workbuddy/skills/aitestui/`**——用途是用 h5qa 平台接入/测试其他项目，留在 h5qa 项目目录会限制适用范围。同时对 SKILL.md 做了两处实质修订：①「运行前必读」改为自包含（去掉对本私仓 `grillme/docs`、`aitestui-user-manual.md` 的路径引用），使脱离 h5qa 仓库也能执行；②交互极简化（见下条实施记录）。本地名与对外发布名统一为 `aitestui`（GitHub 仓库 + 官网 zip），旧名 `aitestui-onboarding-autocase` 已停用。
- 2026-11-18（16:38 修订）：统一三处副本——发布仓 `~/code/init/skills/aitestui/`、WorkBuddy 全局 `~/.workbuddy/skills/aitestui/`、`npx skills` 安装目录 `~/.agents/skills/aitestui/` 全部同步为发布仓最新版。此前 `~/.agents` 那份停留在最早版本（仍索要 TOKEN 与模型配置），是用户看到说明前后矛盾的根源；WorkBuddy 会话在启动时固化技能列表，改名后须新开会话才能用 `/aitestui`。
- 2026-11-18（16:38 补充）：查明 `npx skills add` 对 WorkBuddy **不生效**——该 CLI 的受支持 agent 列表里根本没有 WorkBuddy（只有名字相近的 CodeBuddy，落在 `~/.codebuddy/skills/`），全局安装实际写入 `~/.agents/skills/`，而 WorkBuddy 只扫描 `~/.workbuddy/skills/`。故 push 到 GitHub 也无法让 `npx skills add` 对 WorkBuddy 用户生效；国内分发应走官网 zip → 手动放到 `~/.workbuddy/skills/aitestui/`（或在 WorkBuddy 内让 AI 直接写入该目录）。
- 2026-11-19：按用户期望的调用方式改造 skill——支持**一句话带齐参数**（文档/站点/环境名/项目名/数量/层级/登录凭据），AI 自行解析，不逐项追问。按 name/key 复用已有项目与环境；数量/层级收敛生成与执行范围（「10 条核心」只做核心层 10 条，跳过三批门禁），缺省才三批全量。
- 2026-11-19（**方向性纠正，推翻上一条的凭据双轨**）：用户真实试跑时指出 skill 跑去「开浏览器看登录方式 → 识别图形验证码 → 写等待验证码脚本」，完全跑偏。**立 D9（见下）**：skill 不自己干活，只指挥 aitestui 干活——打开页面/登录/断言/出报告全是平台 runner 执行用例时做的。据此重写 SKILL.md：①鉴权改为**用户给的平台 PAT（h5qa_…）Bearer 直调全部 API**，不引导浏览器登录平台（源码 `access-token-auth.guard.ts` 证实 machine 令牌只在 Cookie 通道被禁，Bearer 可用）；②被测系统登录态通过 **`PUT /project-env-vars/edit`（type=secret）写入平台 secret 变量**——**推翻"保密变量 API 写不了"的旧结论**：源码 `project-env-vars.service.ts` 的 add/edit 明确支持 secret 加密落库，只有 batch 拒绝；故删掉"浏览器自动登录/识别验证码/实地走查/前端代填"整套错误路径；③入口/文案对不对、登录态是否有效一律由**平台执行结果 + 日志**来证明，文档落后按日志改用例。三处副本 + 官网 zip 已同步，FFFD=0。
- 2026-11-20：发布仓从 `~/code/init` 迁至 **`~/code/h5qa/skills`**（权威源＝`skills/skills/aitestui/`），ADR/术语表同步进其 `docs/`。**立 D10**：加阶段 2a 内外网判定——本地 curl + 平台 `/proxy?url=`（带 `h5qa_sid`=PAT）双探活，内网则切 `runnerPreference=local` 并用 `GET /projects/:id/runner-token` + `npx aitestuirunner join --url https://aitestui.com/api --token <token>` 引导用户装本地 runner，轮询 `/runners/index` 确认在线。源码核实：`h5qa_sid` 值即令牌明文（`auth-cookie.util.ts`）、`--url` 必须去掉 `/v1`（前端 `client.ts`/`ProjectConfigView.tsx`）、三个端点均现行。SKILL.md 新增阶段 2a + 硬边界例外，api-contract.md 新增「网络可达性判定与 runner 部署」章节。三处副本 + 官网 zip 已同步，FFFD=0。
- 2026-11-20（同日）：**立 D11**：按积分余额动态定量。源码核实 `GET /credits/me`（`credits.controller.ts`）返回 `data.balance`。生成前查一次，`N = min(100, 10 + floor(balance/500)*10)`，用户显式数量优先（仍受 100 硬顶）；单执行任务 ≤ 50 条、超出拆多批串行；查询失败兜底 10 条记 summary 不阻塞；`balance<1` 提示不足。SKILL.md 新增「数量决策」节 + 改缺省规则/阶段 3/阶段 5/硬边界，api-contract.md 成本节补端点与公式。三处副本 + 官网 zip 已同步，FFFD=0。
- 2026-11-21（发布）：**正式发布到技能市场**——skills.sh 已收录 `aitestui/init`（页面 `https://skills.sh/aitestui/init`，安装命令 `npx skills add aitestui/init`）；官网 zip `https://aitestui.com/skills/aitestui.zip` HTTP 200 且含全部现行能力（阶段 2a / 数量决策 / 阶段 7 / 私网短路）。发布前重写市场门面 `README.md`：旧版仍描述「开浏览器登录 + 导出 storageState + 模型配置」等被 D9 推翻的流程，改为现行「纯 API 驱动 / 内网判定与本地 runner / 积分定量 / 最终交付 / 用户沟通纪律」，并明示 WorkBuddy 安装路径差异（npx skills 不认识 workbuddy 目标）。`git push origin main`（GitHub skills.sh 源）与 `git push ali main`（Codeup 国内镜像）均成功。
- 2026-11-21（D10 细化）：内网判定加「明显私网地址短路」——host 命中 localhost/127./10./172.16-31./192.168./169.254./::1/fc00::/fe80:: 或 *.local/*.internal/*.lan 后缀即直接判内网，**跳过两条 curl 探活**（公网必然不可达，探活浪费且受用户 VPN 状态干扰会误判）。判为内网后先 `GET /runners/index` 查有无 online=1 本地机，有就复用、没有才切 local + 引导装 runner。SKILL.md 阶段 2a 重组为三步（短路→探活→内网处理）+ 硬边界，api-contract.md 同步。三处副本 + 官网 zip 已同步，FFFD=0。
- 2026-11-21：**立 D12**：最终交付四块（总结 + 每批一张被测页截图 + 单/多用例分流链接 + 下一步引导）。用户两问澄清：截图来源选「取执行产物 screenshot」（非 AI 开浏览器截平台页、非只给链接），「三个」＝三批各一张。源码核实：`GET /test-runs/<id>/artifacts` 返回 `[{attemptId,type,objectKey,...}]`（`test-runs.service.ts`），`type='screenshot'` 拼 `https://static.appkc.com/<objectKey>`；路由 `/projects/:id/history/:runId`（运行报告）与 `/projects/:id/cases`（用例列表）前端真实存在（`nav.ts`/`Workbench.tsx`）。SKILL.md 新增阶段 7 + summary 行 + 硬边界。三处副本 + 官网 zip 已同步，FFFD=0。
