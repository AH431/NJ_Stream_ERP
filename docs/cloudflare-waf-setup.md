# Cloudflare WAF 設定文件

**文件版本**：v1.0  
**建立日期**：2026-04-25  
**適用系統**：NJ Stream ERP（Phase 2 上線版）  
**前置條件**：已擁有自訂網域並已移入 Cloudflare DNS 管理

---

## 一、架構概覽

```
手機 App（Flutter）
      │
      ▼ HTTPS
Cloudflare Edge（WAF / Rate Limit / Bot Fight）
      │
      ▼ Cloudflare Tunnel（加密通道，不需開放 80/443）
宿主機 Docker
  └── backend:3000（Fastify + JWT）
  └── postgres（僅內部網路，不對外）
```

**重要**：使用 Cloudflare Tunnel 時，宿主機不需要開放任何 inbound port。  
WAF 規則在 Cloudflare Edge 執行，流量只有通過規則才會轉入 Tunnel。

---

## 二、DNS 設定

### 2.1 Proxy 模式（必須啟用）

| Type | Name | Content | Proxy |
|------|------|---------|-------|
| CNAME | `api` | `<tunnel-id>.cfargotunnel.com` | ✅ Proxied（橘雲）|

> ⚠️ 若設為 DNS only（灰雲），流量繞過 Cloudflare，WAF 規則無效。

### 2.2 Tunnel 設定（cloudflared）

`~/.cloudflared/config.yml`：

```yaml
tunnel: <tunnel-id>
credentials-file: /etc/cloudflared/<tunnel-id>.json

ingress:
  - hostname: api.your-domain.com
    service: http://localhost:3000
    originRequest:
      noTLSVerify: false
  - service: http_status:404
```

---

## 三、SSL/TLS 設定

位置：Cloudflare Dashboard → SSL/TLS

| 設定項 | 建議值 | 說明 |
|--------|--------|------|
| 加密模式 | **Full (strict)** | Tunnel 端點已有 Cloudflare 憑證，選 Full strict 最安全 |
| Always Use HTTPS | ✅ 開啟 | HTTP 自動 301 → HTTPS |
| Min TLS Version | **TLS 1.2** | 手機端 Android 7+ 支援，拒絕舊版 |
| TLS 1.3 | ✅ 開啟 | 現代加密，零 RTT 加速 |
| HSTS | 啟用，max-age=31536000 | 防止降級攻擊（首次設定後無法快速取消，確認後再啟用） |

---

## 四、Security Level

位置：Security → Settings

| 設定項 | 建議值 | 說明 |
|--------|--------|------|
| Security Level | **High** | 可疑 IP 顯示 challenge，已知惡意 IP 直接封鎖 |
| Bot Fight Mode | ✅ 開啟 | 封鎖已知爬蟲 bot，不計費 |
| Browser Integrity Check | ✅ 開啟 | 驗證 HTTP 標頭完整性 |

---

## 五、WAF 自訂規則（Custom Rules）

位置：Security → WAF → Custom Rules

規則優先序：數字越小越先執行。建議以下順序：

---

### Rule 1：封鎖非 API 路徑（Priority 1）

ERP Backend 只提供 `/api/v1/*` 與 `/health`，其他路徑一律封鎖。

```
Expression:
  not (
    starts_with(http.request.uri.path, "/api/v1/") or
    http.request.uri.path eq "/health"
  )

Action: Block
```

---

### Rule 2：Admin 端點 IP 白名單（Priority 2）

`/api/v1/ar/*`（應收帳款）與 `/api/v1/analytics/*`（損益）為 Admin 專用，  
只允許辦公室固定 IP 或已知 VPN 出口 IP 存取。

```
Expression:
  (
    starts_with(http.request.uri.path, "/api/v1/ar") or
    starts_with(http.request.uri.path, "/api/v1/analytics")
  )
  and not ip.src in {203.0.113.10 198.51.100.0/24}
  # ↑ 替換為實際辦公室 IP / VPN 出口 IP

Action: Block
```

> **填寫方式**：`{1.2.3.4 5.6.7.8/30}` 空白分隔，支援 CIDR。

---

### Rule 3：Auth 端點防暴力破解（Priority 3）

`/api/v1/auth/login` 超量即封鎖（Rate Limiting 補充規則）。

```
Expression:
  http.request.uri.path eq "/api/v1/auth/login"
  and http.request.method eq "POST"

Action: Managed Challenge（或 Block，視需求）
```

---

### Rule 4：封鎖可疑 User-Agent（Priority 4）

封鎖常見掃描工具。

```
Expression:
  http.user_agent contains "sqlmap" or
  http.user_agent contains "nikto" or
  http.user_agent contains "nmap" or
  http.user_agent contains "masscan" or
  http.user_agent contains "zgrab" or
  http.user_agent wildcard "*python-requests*" or
  http.user_agent eq ""

Action: Block
```

> 注意：Flutter 的 `http` 套件預設 User-Agent 為 `Dart/x.x (dart:io)`，不受影響。  
> 若未來改為自訂 UA，需在此規則新增豁免。

---

### Rule 5：封鎖高風險國家/地區（選用，Priority 5）

若業務只在台灣，可封鎖其他地區降低雜訊。

```
Expression:
  not ip.geoip.country in {"TW" "HK" "JP"}
  # ↑ 依實際業務範圍調整

Action: Managed Challenge（建議先用 Challenge 而非 Block，觀察 2 週後決定）
```

---

## 六、Rate Limiting 規則

位置：Security → WAF → Rate Limiting Rules

> Rate Limiting 為計費功能（Free plan 只有基本限制），建議至少設 Auth 端點。

### RL-1：登入端點（每 IP 每 10 分鐘 10 次）

| 欄位 | 值 |
|------|----|
| Expression | `http.request.uri.path eq "/api/v1/auth/login"` |
| Requests | **10** |
| Period | **10 minutes** |
| Action | **Block**（持續 10 分鐘） |

### RL-2：全域 API 速率（每 IP 每分鐘 300 次）

| 欄位 | 值 |
|------|----|
| Expression | `starts_with(http.request.uri.path, "/api/v1/")` |
| Requests | **300** |
| Period | **1 minute** |
| Action | **Managed Challenge** |

> 300 req/min 對正常 ERP 使用綽綽有餘；超出者視為爬取或異常工具。

---

## 七、Managed Ruleset（OWASP + Cloudflare）

位置：Security → WAF → Managed Rules

| Ruleset | 建議設定 |
|---------|---------|
| Cloudflare Managed Rules | ✅ 啟用，Action = Block |
| Cloudflare OWASP Core Ruleset | ✅ 啟用，Sensitivity = **Medium**，Action = Block |

> OWASP High sensitivity 可能誤擋合法 JSON payload（如含特殊字元的備忘錄），  
> 建議先從 Medium 開始，觀察 Security Events 後再調整。

---

## 八、Page Rules / Transform Rules（可選）

### 強制 HTTPS Header（後端無法設定時的補充）

位置：Rules → Transform Rules → Response Header Modification

| Header | Operation | Value |
|--------|-----------|-------|
| `Strict-Transport-Security` | Set | `max-age=31536000; includeSubDomains` |
| `X-Content-Type-Options` | Set | `nosniff` |
| `X-Frame-Options` | Set | `DENY` |
| `Referrer-Policy` | Set | `strict-origin-when-cross-origin` |

---

## 九、監控與告警

### 9.1 Security Events

位置：Security → Events

- 每週查看一次 Block / Challenge 趨勢
- 若看到大量 Rule 5（地理封鎖）誤擋台灣 IP，代表 IP 歸屬有誤，可個別加白

### 9.2 Notifications

位置：Notifications → Add

建議設定：

| 事件 | 觸發條件 | 通知方式 |
|------|---------|---------|
| Security Attack Alert | 超過 1000 次/小時封鎖 | Email |
| Origin Error Rate Alert | 5xx 錯誤率 > 10% | Email |

---

## 十、設定 Checklist（上線前確認）

```
DNS
[ ] api.your-domain.com CNAME → Tunnel，Proxy = 橘雲（Proxied）
[ ] 無任何 A/CNAME 記錄指向宿主機真實 IP

SSL/TLS
[ ] 模式 = Full (strict)
[ ] Always Use HTTPS = ON
[ ] Min TLS = 1.2

Security
[ ] Security Level = High
[ ] Bot Fight Mode = ON

WAF Custom Rules（依序）
[ ] Rule 1：非 API 路徑封鎖
[ ] Rule 2：Admin IP 白名單（已填入正確辦公室/VPN IP）
[ ] Rule 3：Auth 端點 Challenge
[ ] Rule 4：可疑 UA 封鎖
[ ] Rule 5：地理限制（可選，先用 Challenge）

Rate Limiting
[ ] RL-1：登入 10 次/10 分鐘 Block
[ ] RL-2：全域 300 次/分鐘 Challenge

Managed Rules
[ ] Cloudflare Managed Rules = Block
[ ] OWASP Core Ruleset = Medium / Block

測試
[ ] 手機 App 正常登入與操作（所有功能）
[ ] Postman 測試 /api/v1/auth/login POST 正常
[ ] 瀏覽器存取 / 或 /other 被封鎖
[ ] sqlmap user-agent 被封鎖（curl -A "sqlmap" https://api.your-domain.com/api/v1/health）
[ ] Security Events 頁面有封鎖記錄，無誤擋
```

---

## 十一、後續維護

| 時機 | 動作 |
|------|------|
| 辦公室 IP 變更 | 更新 Rule 2 白名單 |
| 新增 API 路徑 | 確認 Rule 1 豁免覆蓋 |
| Flutter App 改自訂 UA | 更新 Rule 4 豁免清單 |
| 發現新型攻擊 pattern | 新增 Custom Rule，Priority 設在 Rule 4 之前 |
| 每季 | 檢視 OWASP Ruleset 版本，確認無新的誤擋 case |