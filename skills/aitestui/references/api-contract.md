# aitestui 现有 API 契约（只读参照，勿改平台）

基址：`AITESTUI_BASE`（生产 `https://aitestui.com/api`）。所有请求带 token。以下端点均为**现行**：
导入导出曾被 ADR-0063 下线，已由 ADR-0070 整体回退恢复；以本文件为准。

## 接入准备（无项目时按顺序串）

| 步骤 | 端点 | 要点 |
|---|---|---|
| 建项目 | `POST /projects/add` | 必填仅 `name`；`targetUrl`/`targetType`/`runnerPreference` 可空（默认 web/cloud） |
| 建环境 | `POST /project-envs/add` | 必填 `projectId`/`key`/`name`；域名不是环境字段，写进 `URL` 变量 |
| 写变量 | `POST /project-env-vars/batch` | 整批原子 upsert，行只带 `name`+`value`，定位键 `(scope,envId,name)`，上限 500；**不碰保密变量**（COOKIE 引导用户在平台手填） |
| 取分支 | `GET /project-branches/default` | 项目无分支时自动补「主分支」，返回 `branchId` |

保密变量（`USERNAME`/`PASSWORD`/`COOKIE`）只能走平台前端单条弹窗录入，API 不支持——这是刻意设计，不要试图绕过。

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

## 模型（执行槽位，OpenAI 兼容）

`MIDSCENE_MODEL_BASE_URL` / `MIDSCENE_MODEL_API_KEY` / `MIDSCENE_MODEL_NAME` / `MIDSCENE_MODEL_FAMILY`。
family 覆盖 `qwen2.5-vl / qwen3-vl / qwen3 / doubao-vision / doubao-seed / gemini / gpt-5 / deepseek / kimi / kimi3 / glm-v / auto-glm / vlm-ui-tars / xiaomi-mimo`。按 family 选 adapter，不按模型名猜。可指向 AIProxy 加密网关（provider-agnostic）。

## 不做的改造（若要，记入 changes.md 最后统一开发）

- 「一个端点完成全部初始化」的聚合接口 —— 目前只能串多个现有端点。
- 平台内的「上传文档→生成用例」UI 入口 —— 目前生成只能在平台外（本 skill）。
- 保密变量经 API 写入 —— 目前只能前端手填。
