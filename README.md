# aitestui/init — 接入基线用例自动生成 skill

给 aitestui 补上缺失的那块能力：**用户不必从零手写测试用例**。给一份被测系统的手册和平台身份，本 skill 用**平台自身的能力**完成「判内外网 → 建项目/环境 → 写登录态 → 生成用例 → 导入 → 执行 → 读日志 → 改用例到全过」，显著降低新系统接入的冷启动工作量。

> **核心原则：skill 不自己干活，只指挥 aitestui 干活。** 打开被测站点、登录、点按钮、判定结果、出报告，全是平台 runner 执行用例时做的。skill 只做三件事：调平台 API、生成与修改用例文本、按执行日志归因。文档可能落后，以平台跑出来的真实行为为准。

- Skill 名：`aitestui`（安装后用 `/aitestui` 调用）
- 设计说明与术语见 [`docs/`](docs/)（决策记录与术语表）

## 安装

### 国内用户（推荐，不依赖 GitHub）

```bash
npx skills add https://aitestui.com/skills/aitestui.zip
```

这是最简便的方式：安装包放在 aitestui 官网静态目录下，全程不走 GitHub。`npx skills add <URL>` 支持直接下载 zip/tar.gz 并解压安装（已实测）。若 `npx` 拉包慢，先配 npm 镜像：`npm config set registry https://registry.npmmirror.com`。

### 海外 / 可直连 GitHub（skills.sh 市场）

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

### WorkBuddy 技能市场（客户端一键安装）

在 WorkBuddy 客户端左侧【专家·技能·连接器】→【技能】→ 技能市场，搜索 `aitestui`，点技能右上角加号即可安装，安装后对话中可直接用 `/aitestui` 调用。

### WorkBuddy 本地手动安装

`npx skills add` 不认识 WorkBuddy 这个目标（它写 `~/.agents/skills/`，而 WorkBuddy 只扫 `~/.workbuddy/skills/`）。也可以下载官网 zip 解压到 `~/.workbuddy/skills/aitestui/`，或直接对 WorkBuddy 说「安装 aitestui 技能」。技能列表在会话启动时固化，**装完需新开会话**才能用 `/aitestui`。

### 技能包发布到 WorkBuddy 市场（维护者）

WorkBuddy 市场的包结构与官网/skills.sh **相反**：解压第一层必须**直接是 `SKILL.md`**（不套 `aitestui/` 目录），且 `SKILL.md` frontmatter 需含 `display_name`/`display_name_en`/`description_zh`/`description_en`/`version`（三段式）/`author`/`examples_zh`/`examples_en`。生成市场包：

```bash
bash scripts/build-marketplace-zip.sh dist
# 产出 dist/aitestui-workbuddy-market.zip（解压根目录即 SKILL.md）
```

发布流程在 **WorkBuddy 开放平台**（`open.workbuddy.cn`，非 GitHub）：完成开发者认证 →【发布管理 → 技能 → 创建】上传该 zip → 选分类/类目、传 512×512 头像 → 提交审核（约 7 个工作日）→ 审核通过后**手动点「发布」**。更新版本须升 `version` 并重新上传审核。官网 zip（`build-web-zip.sh`）与市场 zip（`build-marketplace-zip.sh`）是两个不同渠道，别混用。

## 怎么用：一句话带齐参数

不必填表，一句大白话把能给的都给出来，AI 自己解析，缺关键项才一轮问齐：

```
/aitestui 用户身份：h5qa_xxx 读取当前目录下的文档 初始化 10 条核心测试用例
环境：testrun222 url: https://bims-testrun2-2-2.ccic.com/ccictyx/#/zh-CN/ 账号 mahy,密码 1234
```

| 用户这么说 | 解析成 |
|---|---|
| 「用户身份：h5qa_xxx」 | 平台个人令牌，Bearer 直调全部 API（唯一必须提供的平台项） |
| 「读取当前目录下的文档」「手册在 /path/a.pdf」 | 文档文件或目录（PDF/DOCX/MD/HTML 全读） |
| 「https://xxx/#/zh-CN/」 | 被测站点地址，写入环境 `URL` 变量（网页项目） |
| 「Windows 桌面应用」「XX 客户端」「macOS 桌面」「安卓 App」 | 项目类型（网页之外的目标端），一律本地 runner，入口写应用名/路径 |
| 「testrun222 环境」「主干系统项目」 | 按名字复用已有环境/项目，找不到才新建 |
| 「初始化 10 条」「核心测试用例」 | 本次生成数量与层级；「10 条核心」＝只做核心层 10 条 |
| 「账号 mahy，密码 1234」「用户身份 token：xxx」 | 被测系统登录态，写成平台环境级保密变量 |

没有给数量时按积分余额自动定量（见下）。账号密码、令牌这类凭据只在调 API / 配变量时使用，**不进用例、不进产物、不在回复里回显**。

## 它能做什么

1. **文档解析**：读系统手册，抽出功能点、入口、关键可见文案，以及**疑似需要上传附件的功能点**，落成规格说明。
2. **项目类型识别 + 内外网判定**：先认项目类型——网页还是桌面应用（Windows/macOS）/安卓 App。网页项目才做内外网判定：明显内网地址（localhost / 10. / 192.168. 等）直接短路；其余地址用本地 + 平台双探活判定。桌面应用项目没有站点地址、一律走本地 runner，跳过探活。内网项目/桌面项目先查有没有在线且目标端匹配的本地测试机；**没有则先用大白话询问用户是否要在本机安装并启动测试机程序**，同意才装，不想装就把命令交给用户自己决定装在哪台（桌面项目命令自动带 `--target-type`）。
3. **接入准备**：全 API 建/复用项目与环境（按项目类型设置目标端），网页写 `URL` 与保密登录变量，桌面项目入口写应用名/路径，取默认分支——不打开浏览器。
4. **生成用例池**：按文档生成接入基线用例集，每条 7 列 JSON，按 `冒烟 / 核心 / 负向` 打分层标签；数量按积分余额决定，单批硬顶 100 条、单个执行任务 ≤ 50 条。**涉及上传/导入附件的功能不猜测文件用途**（见下方「已知边界」）。
5. **导入平台**：`POST /test-cases/import` 批量写入，按 code 覆盖；查回用例 id 建立映射。
6. **平台执行闭环**：触发执行 → 轮询终态 → 读真实日志 → 归因于「用例问题」「文档落后」或「附件配置问题」→ 改用例重跑到过；同 code 3 次不过转人工。
7. **最终交付**：执行情况总结 + 每批一张被测页截图（来自平台执行产物）+ 结果链接（单用例给执行结果页、多用例给用例列表页）+ 下一步生成更多用例的引导。

## 已知边界：附件变量暂不自主完成

平台支持附件变量（图片 / Excel / Word / PDF 等文件），但**「哪个文件对应哪个功能」属于业务语义，文档往往不给**。所以 skill 默认**不自主完成这类用例**：不把手册当成测试附件、不按文件名猜用途、不伪造占位文件、不在多个候选里挑一个。

唯一例外是用户**同时**明确给出「文件」和「它对应哪个功能」且无歧义。否则 skill 会三选一：提示这批先跳过并列出未覆盖的功能、教用户到平台「项目 → 配置 → 环境与变量 → 新建变量 → 值来源选『附件变量』」上传文件、或与用户确认文件与功能的对应关系。用例里附件统一写 `${VAR}` 占位，配置由用户掌握。

## 数量决策（按积分余额）

生成前查一次 `GET /credits/me` 取余额，用户没显式给数量时：

```
N = min(100, 10 + floor(balance / 500) * 10)
```

| 余额 | 生成条数 | 余额 | 生成条数 |
|---|---|---|---|
| < 500 | 10 | 2500–2999 | 60 |
| 500–999 | 20 | 3000–3499 | 70 |
| 1000–1499 | 30 | 3500–3999 | 80 |
| 1500–1999 | 40 | 4000–4499 | 90 |
| 2000–2499 | 50 | ≥ 4500 | 100（封顶） |

积分少时少生成，避免堆一批没调试成功的用例；积分多时多生成提效。用户显式给的数量优先（仍受 100 硬顶）；查询失败保守取 10 条、不阻塞主流程。

## 前置条件

- Node.js ≥ 18；能访问你的 aitestui 实例（默认生产 `https://aitestui.com`）。
- 一个 aitestui 个人身份令牌（`h5qa_...`），由用户在调用时提供。
- 被测系统的手册与可访问地址；账号密码/登录令牌由用户提供，写进平台保密变量。
- 内网站点需要一台能访问该站点的电脑安装本地 runner；Windows/macOS 桌面应用或安卓 App 需要在对应机器装带正确目标端的本地 runner（skill 会先询问是否在本机安装并启动，也可把现成命令交给用户自己决定装在哪台机器）。
- 涉及上传/导入附件的测试，需要用户明确提供文件并说明它对应哪个功能，或在平台自行配置附件变量；skill 不会猜测文件用途。
- 执行用的模型与 runner 全部由平台内部处理，用户不需要配置模型。

## 安全与权限

- **不改平台代码/接口**：所有写入只调 aitestui 现有 API；平台改造需求只记录到 `changes.md`，留待统一开发。
- **凭据只走平台保密变量**：账号密码/令牌通过单条变量 API 加密写入平台，不进用例、不进产物、不回显；本地产物不保存明文凭据。
- **灌库按 code 覆盖**：首次接入前确认目标项目为空或接受覆盖（详见 [api-contract.md](skills/aitestui/references/api-contract.md)）。
- **两处例外，都不是「自己干活」**：① 只允许 curl 取连通性判断内外网，不登录、不断言、不看页面内容；② 无在线本地机且用户同意时，在本机安装并启动测试机程序（只做接入准备，不代替执行用例）。
- **附件不猜测**：不替用户认定「哪个文件属于哪个功能」，附件变量默认由用户配置。
- 脚本 `skills/aitestui/scripts/case-lint.mjs` 只读本地 JSON、无网络与写操作。

## zip 包从哪来 / 怎么更新

zip 由发布仓库 `skills/aitestui/` 打包而成，放在前端静态目录 `fe_aitestui/public/skills/aitestui.zip`，随前端构建发布到 `https://aitestui.com/skills/aitestui.zip`。**更新 skill 后必须同时推 GitHub 仓库并重新生成官网 zip**，否则官网安装到的是旧版。生成 zip：

```bash
bash scripts/build-web-zip.sh /Users/yfj/code/h5qa/fe_aitestui/public/skills
```

脚本会把 `skills/aitestui/` 打成顶层 `aitestui/` 目录的 zip（CLI 要求的结构），并排除 `.auth`/`output` 等本地运行产物。

本仓库还带一个 post-commit hook：只要提交里改了 `skills/aitestui/`，就会用 **HEAD 中已提交的内容**自动重建上面的 zip（不会混入未保存的本地改动）。克隆后装一次即可：

```bash
bash scripts/install-git-hook.sh
```

装好后正常 `git commit` 即可，zip 会随之更新；之后记得在前端仓库提交 `public/skills/aitestui.zip`。

## 目录结构

```
skills/aitestui/
├── SKILL.md                    # skill 主文件（触发、工作流、硬边界）
├── references/
│   ├── case-rules.md           # 平台现行真相 + 10 条用例硬约束
│   └── api-contract.md         # 现有 API 端点与字段契约
└── scripts/
    └── case-lint.mjs           # 用例池静态校验器
docs/                           # 设计记录与术语（背景参考资料）
```

## 验证

```bash
node skills/aitestui/scripts/case-lint.mjs <pool.json>
```

合法用例池退出码 0；不合规项逐条列出并退出码 1。

## License

MIT — 见 [LICENSE](LICENSE)。
