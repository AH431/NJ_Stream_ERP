# NJ Stream ERP — 網路邊界與路由允許矩陣

> 建立：2026-05-24 | 對應 Phase 4 Checklist M2.4

---

## 服務拓樸

```
Internet
  │
  ▼
Cloudflare CDN / WAF
  │
  ▼
Cloudflare Tunnel (cloudflared)
  │  固定 hostname: api.njstream.tw（M2.1 待設定）
  │  目前：localhost Tunnel 臨時 URL
  ▼
backend:3000  [127.0.0.1 binding, Docker host]
  │
  ├── /api/v1/**  ← 所有 JWT 保護的業務路由
  │
  └── nj-erp-net (Docker internal network)
        │
        ├── ai_service:8000   [NO public port]
        │     /chat           ← X-Internal-Token required
        │     /forecast/**    ← X-Internal-Token + scope required
        │     /health
        │
        └── postgres:5432     [NO public port]
```

---

## 端口暴露矩陣

| 服務 | 容器埠 | 主機映射 | 對外可達 |
|------|--------|----------|----------|
| backend | 3000 | `127.0.0.1:3000` | 透過 Cloudflare Tunnel ✅ |
| ai_service | 8000 | **無映射** | ❌ 僅 Docker 內網 |
| postgres | 5432 | **無映射** | ❌ 僅 Docker 內網 |

> 設定來源：`docker-compose.prod.yml`
> - backend `BACKEND_BIND_ADDRESS` 預設 `127.0.0.1`（可覆寫）
> - ai_service / postgres 無 `ports:` 區塊

---

## Internal-Only 路由清單

以下路由**不應**經由 public edge（`api.njstream.tw`）被存取：

| 服務 | 路徑 | 保護機制 |
|------|------|----------|
| ai_service | `POST /forecast/generate` | X-Internal-Token + scope `forecast.generate` |
| ai_service | `GET /forecast` | X-Internal-Token + scope `analytics.read` |
| ai_service | `POST /chat` | X-Internal-Token |
| ai_service | `GET /health` | 無 auth（但無 public port，僅 Docker 內網） |
| backend | `GET /api/v1/analytics/sales-history` | X-Internal-Token（ai_service → backend 內部呼叫） |

> ai_service 路由因 **無主機映射**，外部完全無法直接存取，無需額外 WAF 規則。

---

## 對外路由（Cloudflare Tunnel 暴露）

| 路徑前綴 | Auth | 說明 |
|---------|------|------|
| `GET /health` | 無 | Docker healthcheck + 外部監控 |
| `POST /api/v1/auth/login` | 無 | 登入 |
| `POST /api/v1/auth/refresh` | 無 | 刷新 token |
| `POST /api/v1/auth/logout` | JWT（可過期） | 登出 |
| `POST /api/v1/tenant/provision` | 無（公開 SaaS 入駐） | 建立新租戶 |
| `GET/PATCH /api/v1/tenant` | JWT | 租戶資料 |
| `/api/v1/customers/**` | JWT | 客戶 CRUD |
| `/api/v1/products/**` | JWT | 產品 CRUD |
| `/api/v1/inventory/**` | JWT | 庫存查詢 |
| `/api/v1/sales_orders/**` | JWT | 銷售訂單 |
| `/api/v1/quotations/**` | JWT | 報價單 |
| `/api/v1/analytics/**` (JWT 端點) | JWT + role | 分析查詢（forecast 代理） |
| `POST /api/v1/ai/chat` | JWT | AI 聊天（代理 ai_service） |
| `/api/v1/users/**` | JWT + admin | 使用者管理 |

---

## 待辦（需 M2.1 網域就緒後）

- [ ] `curl https://api.njstream.tw/forecast/generate` → 應回 404（路由不存在於 backend）
- [ ] `curl https://api.njstream.tw:8000/forecast/generate` → 連線拒絕（ai_service 無 public port）
- [ ] Cloudflare WAF rate limit 規則確認 `/api/v1/tenant/provision` 有保護（公開端點，易被濫用）
