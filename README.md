# aitestui/init — 接入基线用例自动生成 skill

给 aitestui 补上缺失的那块能力：**用户不必从零手写测试用例**。给一份被测系统的手册，让 AI 完成「登录 → 实地探索 → 生成三批用例 → 本地自执行 → 按系统真实行为改用例到全过 → 灌回 aitestui」的全链路，显著降低新系统接入的冷启动工作量。

- Skill 名：`aitestui`（安装后用 `/aitestui` 调用）
- 决策依据：[ADR-0075](docs/adr/0075-onboarding-baseline-autocase.md) · 术语：[Glossary](docs/glossary-onboarding-baseline.md)

## 安装

### 国内用户（推荐，不依赖 GitHub）

```bash
npx skills add https://aitestui.com/skills/aitestui.zip
```

这是最简便的方式：安装包放在 aitestui 官网静态目录下，全程不走 GitHub。`npx skills add <URL>` 支持直接下载 zip/tar.gz 并解压安装（已实测）。若 `npx` 拉包慢，先配 npm 镜像：`npm config set registry https://registry.npmmirror.com`。

### 海外 / 可直连 GitHub

```bash
npx skills add aitestui/init
```

> `npx skills add` 的 GitHub source 必须是 `owner/repo`，裸名 `aitestui` 不作为独立 package 解析。安装到全局加 `-g`，指定 agent 加 `-a <agent>`。

国内若坚持用 GitHub 仓库源，可配 git 镜像改写（CLI 的 git 子进程会继承）：
```bash
git config --global url."https://gitclone.com/".insteadOf "https://github.com/"
npx skills add aitestui/init
git config --global --unset url."https://gitclone.com/".insteadOf
```
镜像站会变动，公益镜像**勿带任何 token/cookie**；已有代理（VPN/Clash 或 `HTTPS_PROXY`）则无需改写。

安装后在 agent 里用 `/aitestui` 调用，或说「根据这份文档帮我生成 aitestui 初始化测试用例」。

### zip 包从哪来 / 怎么更新

zip 由发布仓库 `skills/aitestui/` 打包而成，放在本项目前端静态目录 `fe_aitestui/public/skills/aitestui.zip`，随前端构建发布到 `https://aitestui.com/skills/aitestui.zip`。**更新 skill 后必须同时推 GitHub 仓库并重新生成官网 zip**，否则官网安装到的是旧版。生成 zip：

```bash
bash scripts/build-web-zip.sh /Users/yfj/code/h5qa/fe_aitestui/public/skills
```

脚本会把 `skills/aitestui/` 打成顶层 `aitestui/` 目录的 zip（CLI 要求的结构），并排除 `.auth`/`output` 等本地运行产物。

## 它能做什么

1. **文档解析**：读系统手册（PDF/DOCX/MD/HTML），抽取功能点、入口路径、关键可见文案。
2. **人工辅助登录**：开浏览器让你登录被测系统（导出 storageState）+ 登录 aitestui（取 API token）。登录态只落本地。
3. **实地探索**：带登录态在真实页面走查，修正文档缺漏与落后之处。
4. **生成用例池**：一次性生成接入基线用例集，按 `冒烟 / 核心 / 负向` 打标签（冒烟 ⊂ 核心 ⊂ 全量）。
5. **三批串行自执行**：冒烟 → 核心 → 全量；失败按真实行为改用例重跑到通过，3 次不过转人工。
6. **灌回平台**：用现有 `POST /test-cases/import` 批量写入，不新增平台接口。
7. **变更清单**：文档差异与「需改造平台、最后统一开发」的点记入 `changes.md`。

## 前置条件

- Node.js ≥ 18；可联网访问 npm（`npx skills`）与你的 aitestui 实例。
- 一个可登录的 aitestui 账号与项目（token 由你在运行时提供）。
- 一个可访问的被测站点；内网站点需自备能访问内网的本地 runner。
- 执行模型走 OpenAI 兼容端点（`MIDSCENE_MODEL_*`，支持豆包 / Qwen / DeepSeek / Gemini / GPT-5 / Kimi / GLM / MiMo 等 family）；生成模型另配。

## 参数

| 参数 | 必填 | 说明 |
|---|---|---|
| `DOC` | 是 | 被测系统手册/需求文档路径，可多份 |
| `TARGET_URL` | 是 | 被测站点地址（写入环境 `URL` 变量） |
| `PROJECT_ID` | 否 | 已有 aitestui 项目 id；不填则新建 |
| `AITESTUI_BASE` | 是 | 平台接口基址，如 `https://aitestui.com/api` |
| `AITESTUI_TOKEN` | 是 | 登录后取得的 API token |
| `MIDSCENE_MODEL_*` | 是 | 执行模型 baseURL/apiKey/name/family |

## 安全与权限

- **不改平台代码/接口**：所有写入只调 aitestui 现有 API；平台改造需求只记录。
- **登录态不进用例、不进平台**：storageState 与 token 只存本地 `output/<run>/.auth/`，请勿提交；失效时暂停提示重登，不自动重登。
- **保密变量**（`COOKIE`/`USERNAME`/`PASSWORD`）API 不写入，引导用户在平台环境里手填。
- **灌库按 code 覆盖**：首次接入前确认目标项目为空或接受覆盖（详见 [api-contract.md](skills/aitestui/references/api-contract.md)）。
- 脚本 `skills/aitestui/scripts/case-lint.mjs` 只读本地 JSON、无网络与写操作。

## 目录结构

```
skills/aitestui/
├── SKILL.md                    # skill 主文件（触发、工作流、硬边界）
├── references/
│   ├── case-rules.md           # 平台现行真相 + 10 条用例硬约束
│   └── api-contract.md         # 现有 API 端点与字段契约
└── scripts/
    └── case-lint.mjs           # 用例池静态校验器
docs/                           # ADR 与术语（背景参考资料）
```

## 验证

```bash
node skills/aitestui/scripts/case-lint.mjs <pool.json>
```

合法用例池退出码 0；不合规项逐条列出并退出码 1。

## License

MIT — 见 [LICENSE](LICENSE)。
