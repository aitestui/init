---
name: aitestui
display_name: aitestui 接入基线用例自动生成
display_name_en: aitestui Onboarding Baseline Autocase
description: 为「接入 aitestui 的新系统」从系统手册等文档自动生成接入基线用例集，用平台自身能力完成「识别项目类型 → 建项目/环境 → 配登录态 → 生成用例 → 导入 → 平台执行 → 读日志 → 改用例重跑」全链路。网页项目自动判公网/内网，内网引导装本地 runner；Windows 桌面等非网页项目强制本地 runner。涉及上传附件的功能不猜测文件用途，先提示/教用户配置或与用户确认。用户提供平台身份令牌 + 一句话参数（文档/站点或应用/环境/数量/层级/被测系统账号密码）即可，AI 全部通过平台 API 驱动，不自己开浏览器。当用户想「根据文档自动写 aitestui 测试用例」「降低用例初始化工作量」「一句话初始化 N 条核心用例」「批量接入系统/铺冒烟用例」「接入内网系统」「接入 Windows 桌面应用」时使用。
description_zh: 给一份系统手册，自动识别项目类型（网页/Windows 桌面等）、建项目配变量、生成基线测试用例、导入 aitestui、平台执行并按真实日志改用例到全过，最后交付执行总结与截图，大幅降低新系统接入的用例初始化工作量。
description_en: From a system manual, detect project type (web / Windows desktop), set up project and variables, generate baseline test cases, import to aitestui, run them on the platform and fix cases against real logs until passing, then deliver a summary with screenshots.
examples_zh:
- "用户身份 h5qa_xxx 读取当前目录文档，初始化 10 条核心测试用例，环境 testrun222，站点 https://example.com，账号 mahy 密码 1234"
- "接入内网系统，读取手册生成基线用例并跑通，站点 http://10.0.0.10:8080"
- "接入 Windows 桌面应用，读取手册初始化 10 条核心用例，应用名「XX 客户端」"
examples_en:
- "My platform token h5qa_xxx, read docs in current directory, initialize 10 core test cases, env testrun222, site https://example.com"
- "Onboard an intranet system: read the manual, generate baseline cases and run them, site http://10.0.0.10:8080"
- "Onboard a Windows desktop app: read the manual, initialize 10 core cases, app name XX"
version: 1.3.0
author: aitestui
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

**例外只两处，都不是"自己干活"**：① **网络可达性探测（阶段 2a，仅网页项目）**——允许用 `curl` 从本地 + 经平台 `/proxy` 探同一站点，只判「内网 / 公网」决定 runner 走法；桌面应用项目（windows/computer/android）没有站点 URL、强制本地 runner，不探活。② **按需安装并启动测试机程序（阶段 2a 步骤 3）**——没有在线本地机时先询问用户，**仅用户同意**才在当前机器执行 `npx aitestuirunner join`（装完即启动），且只做接入准备、不代替执行用例。除这两处外，仍遵守上面的禁令；两处都不访问页面内容、不登录、不断言、不看业务数据。

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
| 「https://xxx/#/zh-CN/」 | `TARGET_URL` | 网页项目写入环境 `URL` 变量（平台只接受 origin，hash/路径自动忽略）；桌面应用项目不用 |
| 「Windows 桌面应用」「电脑桌面 Windows」「windows 项目」「XX 客户端」 | `TARGET_TYPE=windows` | 建项目传 `targetType:'windows'`；强制本地 runner、接入命令带 `--target-type windows`；被测应用名/路径写进用例入口，不写 URL |
| 「macOS 桌面应用」「Mac 客户端」 | `TARGET_TYPE=computer` | 同上，桌面端走本地 runner；命令带 `--target-type computer` |
| 「安卓 App / android 项目」 | `TARGET_TYPE=android` | 本地 runner；命令带 `--target-type android` |
| 「testrun222 环境」 | `ENV_NAME` | 按 name/key 复用已有环境，找不到才新建 |
| 「主干系统项目」 | `PROJECT_NAME` | 按 name 复用已有项目，找不到才新建 |
| 「初始化 10 条」 | `COUNT` | 用例数量上限 |
| 「核心测试用例」「冒烟」「全量含负向」 | `LEVEL` | 生成层级：冒烟 / 核心 / 全量 |
| 「账号 mahy，密码 1234」 | 被测系统 `USERNAME`/`PASSWORD` | 写成平台环境级 secret 变量 |
| 「用户身份 token：xxx」（被测站点登录态） | 被测系统 `COOKIE` | 写成平台环境级 secret 变量 |
| 「用 /path/合同模板.xlsx 测导入合同」（文件 + 对应功能同时给） | `ATTACH_FILE` + `ATTACH_FOR` | 唯一可自主完成附件用例的情形，见「附件变量类功能」门禁；只给文件没给用途、或只给功能没给文件，都不算 |

> **注意**：`DOC`（系统手册/文档目录）和 `ATTACH_FILE`（被测系统要上传的测试附件）是两回事，绝不能混用——手册是用来生成用例的依据，不是被测系统的输入文件。

**用户原话示例及解析**：

> `/aitestui 用户身份：h5qa_xxx 读取当前目录下的文档 初始化 10 条核心测试用例 环境：testrun222 url: https://bims-testrun2-2-2.ccic.com/ccictyx/#/zh-CN/ 账号 mahy,密码 1234`

- 平台 PAT = h5qa_xxx（Bearer）；文档 = 当前目录；环境 = testrun222（按名复用）；
- 数量 = 10；层级 = 核心（**只生成核心层 10 条，跳过冒烟/负向门禁**）；
- 被测系统账号 mahy / 密码 1234 → 写入该环境的 `USERNAME`/`PASSWORD` secret 变量；
- URL → 写入 `URL` 变量（平台归一为 `https://bims-testrun2-2-2.ccic.com`）。

**缺省规则**：

- **项目类型**：用户没说 → `web`（网页，缺省走原来的内外网判定）；明确说了桌面/移动端 → 对应 `targetType`（windows/computer/android），跳过内外网判定、强制本地 runner。用户给的头像是被测系统登录态令牌时仍按 COOKIE 处理，与项目类型无关。
- **数量按积分动态定量**（规则见下节「数量决策」）：用户没给数量 → 先查积分余额算出本次生成条数 N；用户显式给了数量 → 以用户为准。**任何情况单次批量硬上限 100 条**。
- **层级**：没给层级 → 以核心层为主；给了层级（核心/冒烟/全量）→ 按指定层生成。数量 N 与层级共同决定生成范围。
- 三批门禁（冒烟 ⊂ 核心 ⊂ 全量）只决定**执行顺序与筛选视图**，不改变池的总量 N；给了数量/层级就只做指定范围，不自作主张跑三批。
- **单个执行任务 ≤ 50 条**：任一批次用例数 > 50 时，拆成多个子任务串行执行——长任务没有好处，失败归因也慢。
- 没有平台令牌 → 停下用大白话请用户提供（这是唯一必须问的平台项）；缺文档或站点地址 → 一轮问齐。
- 被测系统没给账号密码/COOKIE → 照常生成用例，但登录步骤用 `${USERNAME}`/`${PASSWORD}` 占位并提示用户到平台补填登录态变量，不自己登录。

### 数量决策（按积分余额动态定量）

生成用例前，先查当前 PAT 用户的积分余额：`GET /credits/me` → `data.balance`（数字）。**在本次生成开始时查一次即可，不要每条重查**（执行会持续扣费，中途重查会让 N 漂移）。

- **用户显式给了数量** → 直接用用户给的 N（仍受 100 硬顶；超过就提示分批，不一次塞）。
- **用户没给数量** → 按余额算：
  ```
  N = min(100, 10 + floor(balance / 500) * 10)
  ```
  即余额低于 500 时生成约 10 条（积分少，少生成，避免堆一批没调试成功的用例）；每多 500 积分多生成 10 条以提高效率；单次硬上限 100 条。对照表：

  | 余额 | 生成条数 | 余额 | 生成条数 |
  |---|---|---|---|
  | < 500 | 10 | 2500–2999 | 60 |
  | 500–999 | 20 | 3000–3499 | 70 |
  | 1000–1499 | 30 | 3500–3999 | 80 |
  | 1500–1999 | 40 | 4000–4499 | 90 |
  | 2000–2499 | 50 | ≥ 4500 | 100（封顶） |

- **积分查询失败**（`code≠200`、网络异常、`balance` 不是数字）→ 保守取 **10 条**，在 `summary.md` 注明「积分未取到，按 10 条保守生成」，**不阻塞主流程**。
- 若查得 `balance < 1`，用大白话提示用户积分不足、执行会失败（入队要求余额 ≥ 1），但仍按规则生成用例，是否充值由用户决定。
- 查询到的余额与算出的 N 写进 `summary.md` 的「数量决策」行（不回显 PAT）。

## 工作流（严格分阶段，阶段间是门禁）

### 阶段 1 — 文档解析
读 `DOC`，抽取四样东西写成 `output/<run>/spec.md`：① 功能点清单（每条可独立验证）；② 入口（web 项目写 `/path` 不写域名；桌面项目写应用名/可执行文件路径）；③ 关键可见文案（按钮/标题/提示原文）；④ **疑似需要附件的功能点**（上传图片/导入 Excel/上传合同等），单列一节，供上面的「附件变量类功能」门禁使用。文档里查不到的标「待实地确认」——**注意：这里不靠 skill 开浏览器确认，而是先按文档写用例，靠阶段 5 的平台执行结果来校正**。文档与平台跑出来的真实行为不符时以真实行为为准，差异记入 `changes.md`。

### 阶段 2a — 项目类型与网络可达性判定（决定 runner 走法）

> **执行顺序（别按标题编号硬套）**：本阶段的**判定**（项目类型、内外网两条 curl）不需要项目 id，可先做；但步骤 3 查在线机 / 取 runner-token / 切执行偏好都**依赖 `projectId`**。所以真实顺序是：**阶段 2 第 1 步（建/复用项目，拿到 `projectId`）→ 回到本阶段做判定与 runner 部署 → 再回到阶段 2 完成环境、变量、分支**。若还没建项目，先做阶段 2 第 1 步，不要把 `projectId` 留空去调接口。

**先看项目类型 `TARGET_TYPE`（阶段 2 建项目时就要传 `targetType`）**——这一步决定后面要不要探活：

| 项目类型 `targetType` | 被测对象 | 执行落点 | 是否做内外网探活 | 接入命令 |
|---|---|---|---|---|
| `web`（缺省） | 网页站点 | 公网→云 runner / 内网→本地 runner | **要**（下方三步） | `npx aitestuirunner join --url https://aitestui.com/api --token <token>`（不带 `--target-type`，默认 web） |
| `windows` / `computer` / `android` | 桌面原生 App / 安卓 App | **一律本地 runner**（服务端强制 local，传 cloud 无效） | **不要**——没有站点 URL，探活无意义 | `npx aitestuirunner join --url https://aitestui.com/api --token <token> --target-type windows`（按项目类型换成 computer/android） |

**非 web 项目**：跳过下方全部探活步骤，直接进「步骤 3 本地 runner 处理」，但要额外确认在线本地机的**目标端能力匹配**——Windows 项目必须有一台声明 `windows` 能力的 runner（派单按 `capabilities.targetType` **严格相等**，Mac runner 领不到 Windows 单；没有匹配机则 attempt 一直 `queued` 到超时报「缺 windows 能力执行端」）。`runners/index` 列表**不返回 targetType**（该字段只在心跳里），所以**无法从 API 确认目标端是否匹配**——只能靠接入命令带了正确的 `--target-type`，再以阶段 5 执行时 `attempts[]` 的状态/日志为准（一直 queued + 「等待目标端匹配」就是没装对能力的机）。

**web 项目才做下面的内外网判定**：云 runner 在公网，**访问不到内网/私网地址**（如 `192.168.*`、`10.*`、企业内网域名、仅 VPN 可达的域名）。若被测站点是内网项目却用云 runner，所有用例会在导航阶段超时失败。所以建工程后、执行前必须先判一次，据此决定用本地 runner 还是云 runner。分三步：**① 明显内网地址直接短路 → ② 其余地址才探活 → ③ 内网处理先查在线本地机**。

**步骤 1 — 明显内网地址直接短路（跳过探活）**

取 `TARGET_URL` 的 host（去掉 scheme、端口、路径、hash），命中以下任一即**直接判为内网项目，不再做步骤 2 的两条 curl**：

- `localhost`、`127.0.0.0/8`（`127.*`）
- `10.0.0.0/8`（`10.*`）
- `172.16.0.0/12`（`172.16.*`–`172.31.*`）
- `192.168.0.0/16`（`192.168.*`）
- `169.254.0.0/16`（link-local）、IPv6 `::1` / `fc00::/7` / `fe80::/10`
- 辅助后缀：`*.local` / `*.internal` / `*.lan` / `*.home.arpa`

命中 → 直接进「步骤 3 内网项目处理」。理由：这些地址公网**必然**不可达，探活纯属浪费；而本地 curl 通不通还受用户当前是否连了 VPN 影响，**探活反而会误判**。命中后要检查在线本地测试机（步骤 3 第 1 条）。

**步骤 2 — 非明显内网地址才做两条 curl 探活（从 skill 所在机器发起，带 PAT）**

1. **本地视角**——探测 skill 所在机器能否访问被测站点：
   ```bash
   curl -sS -o /dev/null -w '%{http_code}' --max-time 8 '<TARGET_URL 的 origin>'
   ```
   （`TARGET_URL` 取用户给的站点地址，去掉 `#/...` hash 与路径，只用 `scheme://host[:port]`。）
2. **云端视角**——借平台的 `/proxy` 让**平台机器**去访问同一地址：
   ```bash
   curl -sS --max-time 10 \
     -H 'Cookie: h5qa_sid=<用户给的平台 PAT 明文>' \
     'https://aitestui.com/proxy?url=<TARGET_URL origin 的 URL 编码>'
   ```
   `/proxy?url=` 必须带 cookie `h5qa_sid`（值就是 PAT 原文，源码里 `h5qa_sid` 值即令牌明文），否则 nginx 返回 403 `Missing cookie h5qa_sid`；`url` 参数必须做 URL 编码（含 `:`、`/` 全编码）。平台 nginx 会用固定 UA `Nginx-Checker/1.0`、5 秒超时去请求目标；它**清空上游 Cookie**、不回写 Set-Cookie，只用于探活，不会登录被测系统。完整契约见 `references/api-contract.md`。

**判定矩阵**（以两条 curl 的 HTTP 码 / 连通性为准，不是看业务内容）：

| 本地视角 | 云端 `/proxy` 视角 | 结论 | 动作 |
|---|---|---|---|
| 通（2xx/3xx/4xx/5xx 任一 HTTP 响应） | 通（拿到目标返回的 HTTP 响应，含 401/403 登录墙） | **公网项目** | 用默认**云 runner**，无需装本地 runner |
| 通 | 不通（403 / 502 / 504 / 连接失败 / 超时无响应） | **内网项目** | 走「步骤 3 内网项目处理」 |
| 不通 | — | 站点不可达（地址写错 / 本机无网络 / 需 VPN） | **停下**，用大白话请用户确认站点地址与当前网络 |

判定要点：
- 「通」= 拿到了 HTTP 状态码即可（哪怕是 401/403 登录墙或 500，说明网络层能到达）；「不通」= 连接被拒、DNS 失败、超时、000 空响应，或 `/proxy` 自身返回 403/502/504。
- 两条探测**都不带被测系统账号密码、不尝试登录**；登录态仍由阶段 2 的 secret 变量负责。
- PAT 只放进本地 curl 的 cookie 头与脚本内存，不写文件、不回显、不进产物。

**步骤 3 — 内网/本地项目处理：先查在线本地机，没有就询问用户是否要装+启动**

1. **先查有没有现成的在线本地测试机**：`GET /runners/index?projectId=<>&pageSize=100`，看是否有 `online=1` 的本地 runner（心跳驱动；桌面项目还要确认目标端能力匹配，见上）。**有就直接复用**——把项目 runnerPreference 切到 local（下方第 4 条），进入阶段 2/3，不用麻烦用户装任何东西，也跳过下面的询问与安装。
2. **没有在线本地机 → 先用大白话询问用户**（一轮 Yes/No，不堆技术词、不反复追问）：「这个站点/应用只有本机这类电脑能连上，现在还没有测试机在线。要不要我**在这台电脑上安装并启动**一个测试机程序？装一次就好，之后会自动在线。」用 `AskUserQuestion` 之类的一轮确认即可。
   - **用户同意** → 走第 3 条，skill 在当前机器安装并启动（不要再把命令丢给用户自己折腾）。
   - **用户想装到别的机器 / 暂时不想装** → 走第 3 条末尾「自行安装」，给出命令让用户自己决定装在哪台。
3. **安装并启动测试机程序**（仅用户同意时。这是「skill 不自己干活」铁律的第二个例外，**只做接入准备，绝不用它代替执行用例**——用例仍由平台 runner 经 API 执行）：
   - 用 `GET /projects/<projectId>/runner-token` 取该项目的 runner 接入 token（平台现有能力，不用用户去页面找）。
   - **先确认当前机器是合适的那台**：web 私网地址（localhost/127./10./172.16-31./192.168./169.254. 等）要求当前机器能打开该站点；企业内网域名若当前机器也打不开，先问清楚再装；桌面项目要求当前机器就是能启动被测应用的那台（windows→Windows、computer→Mac、android→连着设备的机器）。
   - 执行安装+启动命令（web 项目不带目标端；**桌面/移动项目必须带对应值**，否则 runner 按 web 上报、永远领不到任务）：
     ```bash
     # web 项目（内网站点）
     npx aitestuirunner join --url https://aitestui.com/api --token <runner-token>
     # windows 桌面项目（按项目类型换成 computer/android）
     npx aitestuirunner join --url https://aitestui.com/api --token <runner-token> --target-type windows
     ```
     `--url` 必须是**去掉 `/v1` 的 API 基址**（runner 侧 path 自带 `/v1`，传 `/api/v1` 会拼成 `/api/v1/v1/...`）。`join` 一条龙完成写配置、下载浏览器（桌面端跳过）、自检、**常驻启动**——装完即在线，不用再单独 `start`。用后台方式启动，别阻塞会话。
   - runner token 只在命令里用，不回显、不写进用例/产物。
   - **自行安装**（用户想装到别的机器或暂时不想让我装）：把上面的 join 命令原样给用户，说明装在哪台由他决定（必须能访问内网/被测应用），skill 不替他执行。
4. **切本地执行偏好**（第 1 条复用了也仍要确认）：`PATCH /projects/<projectId>/execution-settings`，body `{"runnerPreference":"local"}`（见 api-contract）。这样触发执行时才会派给本地 runner；**不切的话本地 runner 报 `project_preference_cloud` 告警、领不到任务**。
5. **确认在线**：再次 `GET /runners/index?projectId=<>&pageSize=100` 确认有 `online=1` 的本地 runner（新装的通常几十秒内上线）；确认后再进入阶段 3。
6. 用户暂时不装、也没有在线机 → 记录到 `summary.md` 的阻塞项，用大白话说明「没有本地助手，这批用例跑不了」，暂停后续执行阶段，等用户装好再继续。

公网 web 项目则跳过本步骤 3，直接进入阶段 2；桌面应用项目本就是本地 runner，走完步骤 3（含目标端匹配确认）再进阶段 2。

### 阶段 2 — 接入准备：建工程 + 配变量（全 API，无需浏览器）

按 `references/api-contract.md` 串现有端点（全部带 PAT 的 Bearer 头）：

1. **项目**（工作流第一步，先做这步拿 `projectId` 供阶段 2a 用）：给项目名 → `GET /projects/index` 按 name 匹配复用；没有 → `POST /projects/add`。给了 id 直接用。**建项目时按 `TARGET_TYPE` 传 `targetType`**（不传默认 web）：windows/computer/android 等桌面/移动端项目必须显式传对应值；服务端对非 web 端会**强制 `runnerPreference='local'`**（传 cloud 也无效），无需 skill 再去切偏好。复用已有项目时若其 `targetType` 与本次不符，可用 `PUT /projects/edit`（body 带 `id`+`targetType`）改；服务端会把非 web 端的偏好强制收敛到 local。改目标端属于修改用户现有项目配置，**操作前先问用户确认**，不要悄悄改。
2. **环境**：给环境名（testrun222）→ `GET /project-envs/index?projectId=` 按 name/key 匹配复用；没有 → `POST /project-envs/add`。
3. **变量**：
   - `URL`：仅 **web 项目**写——新建环境预填的空行用 `POST /project-env-vars/batch` 写入（batch 只碰非保密变量）。**桌面应用项目没有站点，不写 `URL` 变量**，被测应用名/路径写在用例入口步骤里。
   - `USERNAME` / `PASSWORD` / `COOKIE` 是环境级 **secret 变量**：先 `GET /project-env-vars/index?projectId=&envId=&name=USERNAME` 拿到预填空行的 `id`，再用 `PUT /project-env-vars/edit`（带 `id`、`projectId`、`type:'secret'`、`value`）逐条写入。**secret 值禁止放进 batch**（会被整批 400 拒绝）。
4. **分支**：`GET /project-branches/default?projectId=` 取 `branchId`。

**复用已有项目/环境时不清空已有配置**；变量写入是覆盖式更新，只动本次用户明确给的那几行。设完即可，不用去浏览器核对。

### 附件变量类功能 — 暂不自主完成（阶段 1/3 门禁）

平台支持**附件变量**（图片/Excel/PDF/Word 等文件，白名单格式、单文件 ≤ 2MB），用例里用 `${VAR}` 引用，执行时 runner 会预下载附件并把 `${VAR}` 插值成本地文件绝对路径。但**「哪个文件该用在哪个功能上」是业务语义**：文档常常只写「支持上传附件」却不给文件，此时 skill 无从判断，猜错就会生成一批跑不通的用例、白烧积分。所以这类功能**默认不自主完成**。

**唯一例外——必须三条同时满足才算「能非常确定文件和对应的功能」**：

1. 用户**明确给出**具体文件路径，或明确说「用当前目录下的 XX.xlsx」；
2. 用户**明确说明**该文件对应哪个功能/哪条用例；或文档逐字写明「把 XX 模板上传到 YY 功能」，且该文件确实存在、名字与文档一致；
3. 只有**一个**候选文件，不存在「好几个文件看起来都能用」的歧义。

任一条不满足 → 走下面的「三选一」，不自主完成。

**禁止的猜测行为**（明确列出，别自我说服）：

- ❌ 把用户给的**系统手册/文档目录里的 PDF、DOCX、图片**当成被测系统要上传的测试附件；
- ❌ 按文件名、扩展名、所在目录推断「这个文件大概是给 XX 功能用的」；
- ❌ 自己生成/伪造占位文件（空白图片、假 xlsx）去凑上传步骤；
- ❌ 在多个候选文件里「挑一个看起来最合适的」；
- ❌ 只因文档写了「支持上传附件」就默认生成上传用例。

**不确定时三选一**（用大白话，一轮问齐，不反复追问、不堆技术词）：

1. **给用户提示**：列出「这些功能需要附件，本批未生成用例」，说明不影响其余用例照常跑；写进 `summary.md` 和阶段 7 收尾。
2. **教会用户如何做**：告诉用户在平台「项目 → 配置 → 环境/变量 → 新建变量 → 值来源选『附件变量』→ 上传文件」，用例里写 `${变量名}`；说明支持图片（PNG/JPG/WebP/GIF）和文档（Excel/Word/PDF/CSV/TXT/JSON）、单文件不超过 2MB。配好后让用户说一声，skill 用该变量名补生成对应用例。
3. **跟用户确认文件和功能的对应关系**：把「疑似需要附件的功能点」和「当前可见的候选文件」列出来，问清「哪个文件用于哪个功能」，确认后再继续。

**生成用例时的写法**：附件一律 `${VAR}` 占位（变量名由用户确认或按功能命名，如 `${ATTACH_CONTRACT}`），写 `上传 ${ATTACH_CONTRACT}`，**不写死文件名、绝对路径、URL**。附件变量原则上**由用户在平台配置**，skill 不主动替用户认定文件用途。仅当上述三条判据全满足且用户已授权时，才可用 multipart 端点创建附件变量（契约见 `references/api-contract.md`），并在回复里说明「用了哪个文件、配到了哪个变量」。

**执行阶段**：若日志或 `attempts[].errorCode` 出现 `variable_file_missing` / `missing_variable` 且指向附件变量，这是**附件没配好或文件已失效**（配置问题，执行前判失败、不扣积分），不是用例文本问题——提示用户到平台补传或替换附件，**不要改用例瞎重试**。

### 阶段 3 — 生成用例（AI 自己写，无需外部模型）

按 `spec.md` 生成**接入基线用例池**，每条是 7 列 JSON（`code/name/format/tags/selfHealEnabled/promptContent/scriptContent`）：

- `format='prompt'`，自然语言全文放 `promptContent`，严格套用 `references/case-rules.md` 的 10 条硬约束；
- `code` 由标题生成稳定大写编码（`^[A-Z][A-Z0-9_]{1,127}$`）；
- `tags` 是**字符串数组**，如 `["冒烟","核心"]`，打 `冒烟`/`核心`/`负向` 分层标签（三批是同一池的筛选视图：冒烟 ⊂ 核心 ⊂ 全量）。**不要写成 `"冒烟,核心"` 逗号字符串**——那是 XLSX 模板单元格的格式，平台前端会自动切分，而本 skill 直接 POST 的 JSON 不会，传字符串会被导入接口拒绝；
- **入口写法按项目类型分**：
  - **web 项目**：入口只写 `/path`，不写域名（域名在 `URL` 变量里）；
  - **桌面应用项目（windows/computer/android）**：没有 URL，入口写**被测应用的可启动标识**——应用名或可执行文件路径（如 `打开「XX 客户端」` 或 `打开 C:\Program Files\XX\XX.exe`），由 runner 的桌面会话负责启动；不写 `http(s)://`、不写 `/path`。应用标识从手册或用户给的「应用名」参数取。
- **登录处理**：阶段 2 已配好登录态变量时，按手册规则"配了 COOKIE 免登录就不写登录步骤"；只有账号密码时，需要登录的用例写 `输入 ${USERNAME}` / `输入 ${PASSWORD}` 占位步骤；
- **负向用例断言写「系统正确拒绝/提示」**。
- **涉及上传/导入文件的功能**：先过上面的「附件变量类功能」门禁——未确认的文件↔功能关系一律不生成，确认过的用 `${VAR}` 占位写 `上传 ${VAR}`。

**按数量决策 + 调用参数收敛范围**：层级按用户指定（没指定以核心为主）；**生成总数 N** = 用户显式数量优先，否则用「数量决策」按积分余额算出的 N（10~100 硬顶）。「10 条核心」= 只生成核心层 10 条。生成后跑 `node scripts/case-lint.mjs <pool.json>` 静态校验，不过的先自修。

### 阶段 4 — 导入平台（先导入才能执行）

用 `POST /test-cases/import` 把当前批次用例批量导入项目 + `branchId`（纯 JSON、驼峰列，字段类型表见 api-contract）。
- 发请求前逐项对表：`projectId`/`branchId` 是查回来的**数字 id**（不是名字/字符串），`items[].tags` 是**字符串数组**，`selfHealEnabled` 是数字 `0|1`。类型错了整批会被 422 拒掉，别原样重试。
- code 冲突语义是**覆盖**（空列不碰、format 不可变）；复用已有项目时首次接入前确认目标为空或用户接受覆盖。核对返回 `created/updated/unchanged/failed`。
- 导入失败（422 或 `failed[]` 非空）时，按 `message` / 行内原因定位到具体字段改 `pool.json` 再重导；**看不出原因就停下报告用户，不要盲目重跑**。
- 导入只回计数、**不回 caseId**。用 `GET /test-cases/index?projectId=&branchId=&code=<精确编码>` 逐条查回 `id`，建 `code → caseId` 映射存 `output/<run>/case-ids.json`。

### 阶段 5 — 平台执行 + 读日志 + 改用例到全过（核心闭环）

按数量决策 + 调用参数决定的范围执行：默认 **冒烟 → 核心 → 全量** 串行门禁；用户指定则**只跑指定范围**（「10 条核心」只跑这 10 条）。**单批执行任务 ≤ 50 条**：某层用例数 > 50 时，拆成多个子任务（每批 ≤ 50）串行触发 `batch-run`，一批全过再下一批——长任务失败归因慢、收益低。每批子流程：

1. **触发执行**：`POST /test-runs/batch-run`，body `{"projectId","branchId","caseIds":[...],"environmentId":?,"name":"<批次名>"}` → `{id}`（runId）。单条调试用 `POST /test-runs/run`（`testCaseId`）。**不传 `runnerPreference`**，让项目偏好生效（强传冲突偏好会被 422 拒绝）。local 模式须有在线且**目标端能力匹配**的 runner，否则队列超时。桌面项目若一批长时间 `queued`，先看 `attempts[].errorMessage` 是否有「等待目标端匹配 / 缺 windows 能力执行端」——是则本地 runner 没带对 `--target-type`，引导用户重装，别改用例。
2. **轮询终态**：`GET /test-runs/get?id=<runId>` 看 `data.status`（终态 `passed|failed|cancelled`）。退避轮询 + 总超时（30 分钟），超时标 `needs_human`。`data.attempts[]` 每条有 `id`（= attemptId）、`caseId`、`runnerType`、`runnerUuid`、`status`、`errorCode`、`errorMessage`、`failurePhase`、`resultSummary`——**用例级 pass/fail、失败原因、日志寻址的第一真相源**。
3. **读日志与报告**（失败归因必做，细节见 api-contract）：
   - **local（默认）**：从 `attempts[]` 按 `caseId` 取 attemptId，核对 `runnerType/runnerUuid`；直读 `<LOCAL_RUNNER_ROOT>/.h5qa-runs/<runId>-<attemptId>/` 下的 `log/*.log`（优先 `ai-call.log`、`planning.log`）和 `report/` 最新 `*.html`。重跑产生新 runId，绝不复用。日志 3 天保留、未脱敏，外发前脱敏。
   - **cloud**：`GET /test-runs/<runId>/artifacts` 取 `objectKey`，拼 `https://static.appkc.com/<key>` 拉；`runner-log` 是脱敏失败全程日志，`midscene-report` 是 HTML 报告。
   - 归档到 `output/<run>/runs/<runId>-<attemptId>/`。
4. **失败 → 归因**（默认系统正常，文档可能落后，三类）：
   - (a) **用例问题**：元素描述不视觉化、断言平台判不了、`missing_variable`（附件变量名除外）、`entry_url_unresolvable`、步骤错、登录态失效（`errorCode` 指向变量/登录） → 结合 `errorMessage` 和真实日志改 `promptContent` 或补配变量；
   - (b) **文档落后**：日志显示系统实际行为与文档不符（真实文案/入口不同） → 按真实行为改用例，差异记入 `changes.md`「文档差异」节。
   - (c) **附件配置问题**：`variable_file_missing`，或 `missing_variable` 指向附件变量名 → **不是用例文本问题**，提示用户到平台补传/替换附件变量（见「附件变量类功能」门禁），**不要改用例瞎重试**。
   **绝不因失败就判「系统有 bug」而挂起**（除非用户另行说明）。日志读不到且 `errorMessage` 也空 → 不得猜着改，标 `needs_human`。
5. **改完重跑**：改后重新 `POST /test-cases/import`（按 code 覆盖），再 `POST /test-runs/batch-run` 只跑这些 caseIds。循环到通过。
6. **熔断**：同一 code 连续 3 次修正仍不过 → 标 `needs_human`、写清卡点（runId + errorMessage + 日志路径/URL），跳过继续其他用例；批次有 `needs_human` 就不算全过，暂停报告用户。

### 阶段 6 — 变更清单收口
`changes.md` 分两节：① **文档差异**（文档说 X、系统实际 Y、用例已按 Y 写）；② **接口需求**（测试所需但平台当前缺失的能力）。**本 skill 一律不改平台代码**，改造点最后统一开发。

### 阶段 7 — 最终交付给用户（总结 + 截图 + 链接 + 下一步引导）

全部批次结束后，用**大白话**给用户一份收尾消息，包含下面四块，缺一不可：

**① 执行情况总结**：本次接入了多少条用例、分哪几批、通过/失败/转人工各多少、总消耗积分（读 `summary.md` 与各 run 的 `total/passed/failed`）。有 `needs_human` 的如实点出卡点，不掩盖；有「因附件未确认而跳过的功能点」一并列出，说明这批用例没覆盖它们。

**② 运行结果截图（三批各一张，来自平台执行产物，不自己截图）**：从**每批**对应的 runId 取 `GET /test-runs/<runId>/artifacts`，筛 `type='screenshot'` 的构件，用其 `objectKey` 拼 `https://static.appkc.com/<objectKey>` 得到被测页面截图 URL。这是 Midscene 执行用例时平台自动截的**被测页面**图，全程 API 拉取，**不自己开浏览器、不自己截图**。要点：
- 按**实际执行的批次**取：跑了三批就三张（冒烟/核心/全量各一张），只跑一批（如「10 条核心」）就一张，不硬凑三张。
- 每批取哪张：优先取该批**通过用例**的 screenshot（截图更有代表性）；按 `attemptId` 关联 `attempts[]` 挑。若该批无任何 screenshot 构件（如执行失败未落图），就跳过这张并在总结里说明，不要编造 URL。
- 在回复里以图片形式呈现（能内联就内联，不能就给出图片 URL）。
- 只做展示，不用截图做断言——判定仍以 `attempts[]` 状态为准。

**③ 结果链接（按用例数二选一，引导用户打开确认）**：
- **只有 1 条用例** → 给该次执行的结果页：`https://aitestui.com/projects/<projectId>/history/<runId>`（projectId 用项目数字 id、runId 用该批 run 的 id）。
- **多条用例** → 给用例列表页：`https://aitestui.com/projects/<projectId>/cases`。
- 用大白话引导："点开确认一下用例和执行结果，看看有没有要调整的。"
- `<projectId>`/`<runId>` 都是**数字 id**（阶段 2/5 查回来的），不是名字、不是 hash 路由里的占位。

**④ 下一步引导（生成更多用例）**：主动给用户一条继续的路，例如："这批跑通后，可以再让我『基于同一份文档补充负向用例』或『再初始化下一批核心用例』，我会沿用现有项目和环境接着生成。" 有 `changes.md` 文档差异时，顺带提示哪些文档已过时、是否要按真实行为修订。**若有待补附件的功能点，这里补一句大白话指引**：告诉用户配好附件后说一声，就能把这批没覆盖的上传/导入类用例补上。

**硬约束**：链接和截图 URL 只来自平台真实返回（artifacts 的 objectKey、查回来的数字 id），**不拼凑、不猜测**；拿不到就如实说明，不编造地址给用户点。

## 产物（output/<run>/）

| 文件 | 用途 |
|---|---|
| `spec.md` | 文档解析出的功能点/入口/文案 |
| `pool.json` / `pool.xlsx` | 用例池（JSON 供导入，XLSX 供人审阅，7 列往返模板） |
| `case-ids.json` | 用例 code → 平台 caseId 映射 |
| `runs/<runId>-<attemptId>/` | 每次尝试的 attempt 摘要、日志/报告（本地路径或云 URL）、修正历史 |
| `changes.md` | 文档差异 + 接口/平台改造需求 |
| `summary.md` | 通过统计、`needs_human` 清单、导入结果、总积分消耗、数量决策、**待补附件的功能点清单**、各批截图 URL 与结果链接（最终交付的留痕） |

登录态（账号密码/令牌/Cookie）**只在平台变量里加密存储**，skill 侧产物不保存明文凭据。

## 硬边界

- **只用 aitestui 能力，skill 不自己开浏览器访问/登录被测站点、不识别验证码、不本地执行用例**；打开页面/启动应用、登录、断言、出报告全是平台 runner 的事。
- **项目类型先判对**：缺省 web；桌面/移动项目（windows/computer/android）建项目时显式传 `targetType`，服务端强制 local。桌面项目不做网络探活、不写 URL 变量，入口写应用名/路径而非 `/path`。接入命令必须带**与项目类型一致的 `--target-type`**——不带 runner 会按 web 上报、领不到桌面任务；派单严格相等匹配，Mac runner 领不到 Windows 单。
- **仅两处例外，都不算「自己干活」**：① **网络探活（只对 web 项目）**——web 明显私网地址（localhost/127./10./172.16-31./192.168./169.254./::1 等）直接判内网、跳过探活；其余 web 地址才允许两条 curl（本地直连 + 平台 `/proxy`）判定，只取 HTTP 连通性，不登录、不断言、不看页面内容；桌面/移动项目跳过整段探活。② **按需装本地测试机**——判为内网/本地项目且无在线机时，**先用大白话询问用户是否要在本机安装并启动测试机程序**；同意才在当前机器执行 `npx aitestuirunner join`（先确认这台机器能访问内网/启动被测应用、后台启动、token 不回显、只做接入准备不代替执行用例），不同意就把命令给用户自己决定装在哪台。有在线机就复用、不折腾用户；不猜测网络。
- **平台身份用用户给的 PAT，Bearer 直调 API**；不引导浏览器登录平台、不读 runner/.env、不做探索式探测。
- **登录态走平台 secret 变量 API**（单条 add/edit 支持 secret，batch 不支持）；凭据不进用例、不进产物、不回显、不外发。
- **不改平台代码、不改平台接口**；改造需求只记录到 `changes.md`。
- **日志默认直读本地 runner 文件系统（local），云执行走平台 OSS 构件（cloud）**；按 `attempt.runnerType/runnerUuid` 校验对齐。`RUNNER_MODE` 只选日志来源、不改执行落点。
- **附件变量类功能暂不自主完成**：文档只说「支持上传附件/导入文件」而不给具体文件时，不猜文件与功能的对应关系——不拿手册当附件、不按文件名猜用途、不造假文件、不自己挑候选。除非用户明确给了文件 + 明确说明对应功能 + 无歧义，否则三选一：提示跳过、教用户到平台配置、或跟用户确认对应关系。用例里附件只写 `${VAR}` 占位；`variable_file_missing` 属配置问题，不改用例瞎重试。
- **失败必读真实日志再归因**；本地日志未脱敏，外发前脱敏；读不到不得猜着改，标 `needs_human`。
- **失败不判系统 bug**（除非用户明确说），按真实行为改用例到全过；同 code 3 次熔断转人工。
- **范围按用户指定**：给了数量/层级只做指定范围，缺省才三批全量。
- **积分成本与定量**：生成前 `GET /credits/me` 查一次余额定 N（用户显式数量优先，否则 `min(100, 10+floor(balance/500)*10)`，失败兜底 10 条）；单次批量硬顶 100、单执行任务 ≤ 50 条。反复重跑持续扣费，熔断避免无底洞。
- **最终交付**：总结 + 每批一张被测页截图（artifacts 的 screenshot 拼 `https://static.appkc.com/<objectKey>`，全部 API 拉取，不自己截图）+ 结果链接（单用例→`history/<runId>`，多用例→`cases`，数字 id）+ 下一步生成更多用例的引导；截图/链接只来自平台真实返回，拿不到如实说、不编造。
- 全程中文用例、断言结尾；不写死域名/凭据/易变数值。
