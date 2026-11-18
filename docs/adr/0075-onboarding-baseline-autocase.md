# ADR-0075：接入基线用例自动生成 skill（文档→实地探索→自执行→灌回平台）

- Status: **Accepted**（grill-with-docs 定案，2026-11-18；三轮 grill 收敛，前沿已空）
- Date: 2026-11-18
- Applies to: 项目级 skill `.workbuddy/skills/aitestui-onboarding-autocase/`（SKILL.md + references + scripts）；不改 `api-h5qa` / `fe_aitestui` / `runner` 任何代码
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

**D1 能力放平台外，不改 aitestui 代码**：生成、探索、执行环节全部在独立 skill 内完成；写入只调现有 API。用户明确「需要改造的先记录，最后统一添加」——本 ADR 把一个独立的平台改造清单（聚合初始化端点、文档上传 UI、保密变量 API 写入）记入 `changes.md` 作为未来统一开发的输入，本期一律不动平台。

**D2 全程包办（用户 Q1=C）**：skill 不只产出用例文件，而是「文档 → 登录 → 实地探索 → 生成 → 本地自执行 → 改到全过 → 灌回平台」全链路闭环。否决「只产出 XLSX 让用户自己导入」的理由：那仍需用户手工跑通与修用例，没解决冷启动工作量。

**D3 两处人工辅助登录（用户 Q3=a+b）**：一次性采集两类登录态——(a) 登录被测系统导出 Playwright `storageState`，供 AI 实地探索与本地执行复用；(b) 登录 aitestui 取 API token 供灌库。登录态只落本地文件，不进用例、不进平台；失效时暂停提示重登，不自动重登。

**D4 失败语义：默认系统正常、文档可能落后（用户 Q3 第一轮裁决）**：这是本 skill 与「找 bug 的测试工具」的分水岭。失败只归因于 (a) 用例问题（描述不视觉化/步骤错/断言写法不对/变量未配）或 (b) 文档落后（文档与系统实际不符），两种情况都**按系统实际行为改用例**，差异记入 `changes.md`。**绝不因失败就判系统 bug 而挂起**（除非用户明确说系统可能有问题）。理由：被接入的是已知正常的系统，用例是待校准的产物；「改到全过」本身就是目标，不是掩盖缺陷。

**D5 三批是同一用例集的筛选视图，非三份独立用例（用户 Q4 推荐）**：生成单一用例池，每条打 `冒烟`/`核心`/`负向` 标签；冒烟 ⊂ 核心 ⊂ 全量，全量 = 核心 ∪ 负向。串行门禁：冒烟全过才进核心、核心全过才进全量。负向用例断言写「系统正确拒绝/提示」。

**D6 双模型槽位（用户 Q5）**：生成槽位（文档→用例、失败→改用例）用 LLM；执行槽位用 `MIDSCENE_MODEL_*`，天然兼容 9+ family。两者都只认 OpenAI 兼容端点，不新造 provider 适配层。

**D7 3 次熔断转人工（skill 自加保险，非用户裁决）**：同一用例连续 3 次修正仍不过 → 标 `needs_human`、写清卡点、跳过继续其他用例；批次含 `needs_human` 即不算全过，暂停报告用户。避免 D4 的「改到全过」在极端情况下无限循环。

**D8 灌库覆盖语义须显式确认**：`/test-cases/import` 按 code 覆盖（局部覆盖、空列不碰、format 不可变），反复导入会更新平台内容。首次接入前向用户确认目标项目为空或接受覆盖。

## Consequences

- **收益**：新系统接入从「逐条手写 + 反复调试」降为「给文档 + 两次登录 + 人工确认」，直接命中平台最大的冷启动痛点。
- **平台零改造**：全部走现有 API，本期不产生平台代码变更、不影响积分/权限/执行链。
- **风险：用例可能被改得「迎合系统」**：D4 刻意接受此取舍——因为系统正常、文档可能落后，用例本就该对齐系统真实行为。代价是若接入的其实是带缺陷的系统，本 skill 不会发现（这是明确的范围外，不是疏漏）。
- **风险：登录态采集中断**：验证码/扫码需人工，登录态失效须重登；这是 D3 刻意保留的人工环节，不自动化。
- **风险：覆盖已有用例**：D8 要求在灌库前确认；code 归一规则由 skill 生成合规码降低失败率。
- **未来**：`changes.md` 中的平台改造点（聚合初始化端点 / 文档上传 UI / 保密变量 API）留待统一开发，届时另起 ADR。

## 实施记录

- 2026-11-18：产出项目级 skill `.workbuddy/skills/aitestui-onboarding-autocase/`（SKILL.md、references/api-contract.md、references/case-rules.md、scripts/case-lint.mjs）；本 ADR 与新术语表同批落地。skill 尚未在真实系统上跑通过，首次使用按 SKILL.md 的阶段门禁执行并回填验收结果。
