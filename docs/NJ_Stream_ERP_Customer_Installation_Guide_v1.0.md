# NJ Stream ERP — 客戶安裝說明
**版本**：v1.0 ｜ **更新日期**：2026-05-25  
**適用對象**：導入工程師、IT 管理員  
**預估安裝時間**：半天（4~6 小時，含等待時間）

---

## 目錄

1. [系統架構概覽](#1-系統架構概覽)
2. [安裝前檢查清單](#2-安裝前檢查清單)
3. [伺服器硬體規格](#3-伺服器硬體規格)
4. [手機端硬體需求](#4-手機端硬體需求)
5. [伺服器安裝步驟](#5-伺服器安裝步驟)
6. [網域與對外連線設定](#6-網域與對外連線設定)
7. [初次啟動與資料庫初始化](#7-初次啟動與資料庫初始化)
8. [建立第一個公司帳號（Tenant Provisioning）](#8-建立第一個公司帳號)
9. [手機 APK 安裝與登入](#9-手機-apk-安裝與登入)
10. [系統健康確認](#10-系統健康確認)
11. [客戶資料匯入（CSV）](#11-客戶資料匯入-csv)
12. [常見問題排查](#12-常見問題排查)
13. [安裝完成後交接清單](#13-安裝完成後交接清單)

---

## 1. 系統架構概覽

```
客戶手機（Android App）
        ↕ HTTPS（全程加密）
Cloudflare CDN / WAF（免費 DDoS 防護 + 速率限制）
        ↕
Cloudflare Tunnel（無需開放防火牆 Port，零暴露）
        ↕
  伺服器（本地迷你主機 或 雲端 VM）
  ┌─────────────────────────────────┐
  │  backend（Node.js, port 3000）  │
  │  ai_service（Python / RAG）     │  ← 僅內網，不對外
  │  ollama（本地 LLM 推理引擎）    │  ← 僅內網，不對外
  │  postgres（資料庫）             │  ← 僅內網，不對外
  └─────────────────────────────────┘
```

**設計重點**：
- 只有 `backend:3000` 透過 Cloudflare Tunnel 對外，其餘服務均在 Docker 內網
- AI 模型與所有資料 100% 在客戶自己的伺服器上，不外傳任何資料至第三方雲端

---

## 2. 安裝前檢查清單

在開始安裝之前，請確認以下項目均已準備完成：

| # | 項目 | 負責人 | 完成 |
|---|------|--------|------|
| 1 | 伺服器（雲端 VM 或本地迷你主機）已可 SSH 登入 | IT | `[ ]` |
| 2 | 伺服器作業系統為 Ubuntu 22.04 LTS 64-bit | IT | `[ ]` |
| 3 | 網域已購買並移轉至 Cloudflare DNS 管理（例：`njstream.tw`）| 專案負責人 | `[ ]` |
| 4 | Cloudflare 帳號已建立，網域已顯示 Active 狀態 | IT | `[ ]` |
| 5 | 至少一支 Android 8.0+ 測試手機在現場 | 客戶 | `[ ]` |
| 6 | 客戶提供公司名稱、公司 Email、管理員帳號密碼（自訂）| 客戶 | `[ ]` |
| 7 | 客戶如有現有資料，已整理成 CSV（產品 / 客戶 / 庫存）| 客戶 | `[ ]` |
| 8 | Firebase 專案已建立，`google-services.json` 已備妥（FCM 推播用，可後補）| IT | `[ ]` |

---

## 3. 伺服器硬體規格

### 選項 A：雲端 VM（推薦，最快上手）

| 規格 | 最低需求 | 建議規格 |
|------|---------|---------|
| vCPU | 4 核 | 4 核 |
| RAM | 8 GB | 16 GB |
| 硬碟 | 60 GB SSD | 100 GB SSD |
| 網路 | 穩定公網 IPv4 | 不限流量方案 |
| 作業系統 | Ubuntu 22.04 LTS | Ubuntu 22.04 LTS |
| 每月費用（參考）| NT$700~1,200 | NT$1,500~2,500 |

**推薦供應商**（按台灣延遲排序）：
- Hinet 企業雲（最低延遲，繁體中文客服）
- DigitalOcean 新加坡節點（CP 值高，4 vCPU 8GB 約 $24 USD/月）
- Vultr 東京節點（彈性計費）

> RAM 最低需求計算：backend 0.5 GB + ai_service 2 GB + postgres 1 GB + Ollama (llama3.2:3b) 4 GB = **最低 8 GB**

### 選項 B：本地迷你主機（資料不出廠區）

| 項目 | 規格 | 參考費用（一次性）|
|------|------|-----------------|
| 機型 | Intel NUC 13 Pro 或同級 Mini PC | NT$12,000~18,000 |
| CPU | Intel i5 4 核 / 8 執行緒（含） | 已含 |
| RAM | 16 GB DDR4 | 已含（或擴充，約 NT$1,500）|
| 硬碟 | 256 GB NVMe SSD | 已含（或擴充，約 NT$1,200）|
| 電源 | 需 24 小時開機 | 約 NT$200~400/月（電費）|
| UPS | 建議加購（停電保護）| 約 NT$2,000~5,000 |
| 網路 | 接辦公室有線網路（不需固定 IP）| 已有 |

> 本地主機透過 Cloudflare Tunnel 對外，**不需要固定 IP**，也不需要開放任何防火牆 Port。

---

## 4. 手機端硬體需求

| 項目 | 規格 |
|------|------|
| 作業系統 | Android 8.0（Oreo）以上 |
| RAM | 4 GB 以上 |
| 儲存空間 | 預留 500 MB |
| 網路 | 4G / WiFi（支援離線工作，恢復連線後自動同步）|
| 相機 | 非必要（目前版本無條碼掃描，未來版本規劃加入）|

> iOS（iPhone / iPad）目前**不支援**，為 Android 專屬 APK。

---

## 5. 伺服器安裝步驟

### 5-1. 登入伺服器並更新系統

```bash
# SSH 登入後執行
sudo apt update && sudo apt upgrade -y
sudo reboot  # 更新後重啟（約 1 分鐘）
```

### 5-2. 安裝 Docker 與 Docker Compose

```bash
# 安裝 Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker  # 讓群組生效，不需登出

# 確認安裝成功
docker --version          # 應顯示 Docker version 24.x 以上
docker compose version    # 應顯示 Docker Compose version v2.x 以上
```

### 5-3. 安裝 Ollama（本地 AI 推理引擎）

```bash
# 安裝 Ollama
curl -fsSL https://ollama.com/install.sh | sh

# 下載 AI 語言模型（約 2 GB，視網速需 5~20 分鐘）
ollama pull llama3.2:3b

# 下載 Embedding 模型（向量搜尋用，約 670 MB）
ollama pull mxbai-embed-large

# 確認模型下載成功
ollama list
# 應看到：
# llama3.2:3b      ...
# mxbai-embed-large ...
```

### 5-4. 安裝 Cloudflare Tunnel 工具

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
cloudflared --version  # 確認安裝成功
```

### 5-5. 下載 NJ Stream ERP 程式碼

```bash
cd /opt
sudo git clone <提供的程式碼儲存庫 URL> nj-stream-erp
sudo chown -R $USER:$USER /opt/nj-stream-erp
cd /opt/nj-stream-erp
```

### 5-6. 設定環境變數

```bash
cp .env.production.example .env.production
nano .env.production  # 或使用 vim
```

**必填項目說明**（逐行填入）：

```env
# ── 資料庫 ─────────────────────────────────────────
POSTGRES_PASSWORD=請輸入自訂強密碼（英文大小寫+數字+符號，16字元以上）
DATABASE_URL=postgresql://postgres:上面的密碼@postgres:5432/nj_erp
DB_READONLY_URL=postgresql://postgres:上面的密碼@postgres:5432/nj_erp

# ── 驗證金鑰 ────────────────────────────────────────
# 產生隨機字串：openssl rand -hex 32
JWT_SECRET=（執行 openssl rand -hex 32 取得）
AI_SERVICE_INTERNAL_TOKEN=（執行 openssl rand -hex 32 取得）

# ── 公司資訊 ────────────────────────────────────────
COMPANY_NAME=貴公司名稱
COMPANY_ADDRESS=公司地址
COMPANY_PHONE=公司電話
COMPANY_EMAIL=公司Email
COMPANY_TAX_ID=統一編號

# ── AI 設定（通常不需修改）────────────────────────
OLLAMA_BASE_URL=http://host.docker.internal:11434
OLLAMA_MODEL=llama3.2:3b
EMBEDDING_MODEL=mxbai-embed-large
AI_FAKE_LLM=false

# ── FCM 推播（可後補，先留空）────────────────────
FIREBASE_SERVICE_ACCOUNT=
```

> **產生隨機金鑰**：`openssl rand -hex 32`，每次執行產生不同字串，JWT_SECRET 與 AI_SERVICE_INTERNAL_TOKEN 各需一組不同的字串。

---

## 6. 網域與對外連線設定

### 6-1. Cloudflare Tunnel 建立（約 10 分鐘）

```bash
# 登入 Cloudflare 帳號（會開啟瀏覽器授權）
cloudflared tunnel login

# 建立 Tunnel（名稱自訂，如 nj-erp）
cloudflared tunnel create nj-erp

# 將 Tunnel 綁定到子網域（將 njstream.tw 換成實際網域）
cloudflared tunnel route dns nj-erp api.njstream.tw

# 確認設定（顯示 Tunnel ID 即成功）
cloudflared tunnel list
```

### 6-2. 設定 Cloudflare Tunnel 設定檔

```bash
mkdir -p ~/.cloudflared
cat > ~/.cloudflared/config.yml << 'EOF'
tunnel: nj-erp
credentials-file: /root/.cloudflared/<Tunnel-ID>.json

ingress:
  - hostname: api.njstream.tw
    service: http://localhost:3000
  - service: http_status:404
EOF
```

> 將 `<Tunnel-ID>` 替換為 Step 6-1 建立時顯示的 ID（格式：`xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`）。

### 6-3. 設為系統服務（開機自動啟動）

```bash
# 安裝為 systemd 服務
sudo cloudflared service install
sudo systemctl start cloudflared
sudo systemctl enable cloudflared

# 確認服務狀態
sudo systemctl status cloudflared
# 應看到 Active: active (running)
```

---

## 7. 初次啟動與資料庫初始化

### 7-1. 啟動所有服務

```bash
cd /opt/nj-stream-erp

docker compose -f docker-compose.prod.yml --env-file .env.production up -d

# 觀察啟動過程（等待所有服務 healthy，約 2~3 分鐘）
docker compose -f docker-compose.prod.yml logs -f
```

啟動成功時，`docker ps` 應顯示三個服務均為 `healthy`：
```
nj-erp-backend      ... healthy
nj-erp-ai-service   ... healthy
nj-erp-postgres     ... healthy
```

### 7-2. 執行資料庫 Migration（首次必做）

```bash
docker compose -f docker-compose.prod.yml --env-file .env.production \
  run --rm migrate
```

成功訊息：`All migrations applied successfully`（或類似文字，無 error 即可）。

### 7-3. 確認服務健康

```bash
# 本機確認
curl http://localhost:3000/health
# 期望回應：{"status":"ok"}

# 從外部網路確認（需等 Cloudflare DNS 生效，約 2~5 分鐘）
curl https://api.njstream.tw/health
# 期望回應：{"status":"ok"}
```

---

## 8. 建立第一個公司帳號

執行以下指令，建立客戶公司的管理員帳號（**只需執行一次**）：

```bash
curl -X POST https://api.njstream.tw/api/v1/tenant/provision \
  -H "Content-Type: application/json" \
  -d '{
    "tenantName": "客戶公司名稱",
    "slug": "company-slug",
    "adminEmail": "admin@company.com",
    "adminPassword": "初始密碼（請通知客戶後立即更改）"
  }'
```

**參數說明**：

| 欄位 | 說明 | 範例 |
|------|------|------|
| `tenantName` | 公司顯示名稱 | `達豐電子有限公司` |
| `slug` | 公司唯一識別碼（英文小寫+連字號）| `ta-feng-electronics` |
| `adminEmail` | 管理員 Email | `admin@tafeng.com.tw` |
| `adminPassword` | 初始密碼（8 字元以上）| 請給予強密碼 |

**成功回應**：
```json
{
  "tenantId": 2,
  "adminUserId": 1,
  "message": "Tenant provisioned successfully"
}
```

> 建立完成後，請立即通知客戶管理員登入後在「設定」中更改密碼。

---

## 9. 手機 APK 安裝與登入

### 9-1. 取得 Production APK

在工程師端電腦執行（已設定好 Flutter 開發環境）：

```bash
cd packages/frontend

# 確認 app_config.dart 中 prodUrl 為正式網域
# 檔案位置：lib/config/app_config.dart
# 應為：static const String prodUrl = 'https://api.njstream.tw';

# 建置 Release APK
flutter build apk --release

# APK 輸出路徑：
# build/app/outputs/flutter-apk/app-release.apk
```

### 9-2. 傳送 APK 給使用者

推薦方式（安全性由高到低）：
1. **公司內網共享資料夾**：上傳至 NAS / Google Drive（公司帳號），員工下載
2. **LINE 傳送**：直接傳送 APK 檔案，操作最簡便
3. **Email 附件**：部分郵件服務會攔截 APK，備用方式

### 9-3. 手機安裝步驟（告知每位使用者）

1. 接收 APK 安裝檔，點擊開啟
2. 若彈出「封鎖安裝」提示 → 點選「設定」→ 開啟「允許此來源的應用程式」→ 返回重試
3. 點擊「安裝」，等待約 30 秒完成
4. 開啟 App，輸入管理員提供的帳號密碼
5. 首次登入後，Dashboard 頂部會出現設定引導 Banner，完成 3 個步驟（約 3 分鐘）

---

## 10. 系統健康確認

安裝完成後，請依序執行以下驗收確認：

```bash
# ── 後端 API ──────────────────────────────────────────
curl https://api.njstream.tw/health
# 期望：{"status":"ok"}

# ── AI 服務 ────────────────────────────────────────────
# （透過後端代理確認，AI 服務不直接對外）
curl -X POST https://api.njstream.tw/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@company.com","password":"初始密碼"}'
# 期望：回傳 accessToken + refreshToken

# ── Cloudflare Tunnel ──────────────────────────────────
sudo systemctl status cloudflared
# 期望：Active: active (running)
```

**手機端驗收（5 分鐘）**：

| 步驟 | 操作 | 期望結果 |
|------|------|---------|
| 1 | 手機登入 | 進入 Dashboard，顯示公司名稱 |
| 2 | 點選「庫存」 | 顯示庫存列表（初始為空）|
| 3 | 開啟 AI 聊天 | 輸入「你好」，有文字回應 |
| 4 | 開啟「設定」→「語言」| 可切換中文 / English |
| 5 | 關掉網路後操作（離線測試）| App 不閃退，可繼續瀏覽 |

---

## 11. 客戶資料匯入（CSV）

### 支援的匯入類型

| 類型 | CSV 欄位順序 | 範例 |
|------|------------|------|
| **產品** | `name, sku, unitPrice, minStock, description` | `螺絲 M3, SCR-M3-100, 5.0, 1000, 不鏽鋼螺絲` |
| **客戶** | `name, contactName, email, phone, address, taxId, paymentTerms` | `台灣科技, 陳大明, chen@example.com, 02-1234-5678, 台北市..., 12345678, 30` |
| **庫存** | `sku, quantity, location` | `SCR-M3-100, 5000, A-01` |

### 匯入步驟

1. App 主選單右上角 `⋮` → **開發者設定** → 開啟「匯入功能」
2. 返回主選單，點選「匯入」
3. 選擇類型（產品 / 客戶 / 庫存）
4. 選取對應 CSV 檔案
5. 確認預覽欄位無誤後，點擊「確認匯入」
6. 系統顯示匯入結果（成功 N 筆 / 失敗 N 筆）

> **注意**：CSV 第一行為標題列，不會被匯入。中文欄位請確認 CSV 存成 **UTF-8 without BOM** 格式。

---

## 12. 常見問題排查

### Q1. 手機登入失敗（網路錯誤 / 無法連線）

**原因**：APK 內建的 API URL 與實際網域不符。

```bash
# 確認後端網址
curl https://api.njstream.tw/health
# 若無回應，確認 Cloudflare Tunnel 是否正常運行：
sudo systemctl status cloudflared
sudo systemctl restart cloudflared
```

若 Tunnel URL 仍為臨時 `*.trycloudflare.com`，需重新打包 APK 並更新 `prodUrl`。

---

### Q2. AI 聊天無回應或回應極慢

**可能原因**：Ollama 模型首次載入需要 30~60 秒。

```bash
# 確認 Ollama 服務狀態
systemctl status ollama

# 手動測試 Ollama
curl http://localhost:11434/api/generate \
  -d '{"model":"llama3.2:3b","prompt":"Hello","stream":false}'
# 有 JSON 回應即正常
```

---

### Q3. 服務啟動後 ai_service 持續 unhealthy

```bash
# 查看 ai_service 容器日誌
docker logs nj-erp-ai-service --tail 50

# 常見原因：Ollama 尚未就緒
# 解法：等待 1~2 分鐘後重試，或手動重啟 ai_service
docker restart nj-erp-ai-service
```

---

### Q4. 資料庫 Migration 失敗

```bash
# 查看錯誤訊息
docker compose -f docker-compose.prod.yml logs migrate

# 常見原因：DATABASE_URL 格式錯誤
# 正確格式：postgresql://postgres:密碼@postgres:5432/nj_erp
# 注意：密碼中若含特殊符號需做 URL encode（如 @ → %40）
```

---

### Q5. CSV 匯入失敗（亂碼 / 格式錯誤）

1. 開啟 Excel → 另存新檔 → 選「CSV UTF-8（以逗號分隔）」
2. 確認欄位數量與說明一致（不可多欄或少欄）
3. 確認數字欄位（unitPrice、quantity）不含貨幣符號或千分位逗號

---

## 13. 安裝完成後交接清單

請在交接給客戶前確認以下所有項目：

### 工程師確認

- [ ] `curl https://api.njstream.tw/health` 回應 `{"status":"ok"}`
- [ ] Cloudflare Tunnel 設為系統服務（開機自動啟動）
- [ ] Docker 容器設為 `restart: unless-stopped`（非預期關機後自動重啟）
- [ ] 資料庫每日自動備份已設定（`crontab -e` 加入備份指令）
- [ ] 管理員帳號已建立，初始密碼已通知客戶
- [ ] 客戶資料已匯入並確認筆數正確
- [ ] 至少一支手機完成登入測試

### 客戶管理員確認

- [ ] 可登入 App，看到自己公司名稱
- [ ] 已完成 Dashboard Onboarding 引導（3 步驟）
- [ ] 已修改初始密碼
- [ ] 了解如何新增員工帳號（設定 → 使用者管理）
- [ ] 了解基本功能操作（庫存查詢 / 報價建立 / AI 聊天）
- [ ] 了解問題回報管道（Email / LINE）

### 交接文件

請於交接時提供客戶以下資訊（列印或書面）：

| 項目 | 內容 |
|------|------|
| API 網址 | `https://api.njstream.tw` |
| 管理員帳號 | `admin@company.com` |
| 技術支援 Email | （填入支援信箱）|
| 緊急聯繫電話 | （填入工程師電話）|
| 伺服器 IP / SSH 資訊 | （僅限 IT 管理員，勿公開）|

---

**文件維護**：NJ Stream ERP 產品團隊  
**下版預計**：v1.1（加入 iOS TestFlight 安裝步驟、多租戶追加說明）
