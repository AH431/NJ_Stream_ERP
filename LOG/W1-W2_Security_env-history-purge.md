# W1–W2 / Security — packages/backend/.env 歷史清除記錄

**事件類型**：資安事件處置 — 敏感憑證歷史清除  
**發現日期**：2026-04-10  
**處置完成**：2026-04-10  
**狀態**：✅ 完全清除 — 歷史已重寫，憑證已輪換

---

## 1. 事件摘要

`packages/backend/.env` 在 commit `ea355f5` 中被意外納入 Git 追蹤，
導致以下敏感資訊暴露於 GitHub 公開歷史：

| 敏感資料 | 內容 | 風險等級 |
|---------|------|---------|
| `DATABASE_URL` | `postgresql://postgres:postgres123@localhost:5432/nj_erp` | 🔴 High |
| `JWT_SECRET` | `nj-stream-erp-dev-secret-change-in-production` | 🔴 High |

---

## 2. 根本原因

`.gitignore` 中雖有 `.env` 規則，但 `.env` 在規則生效前已被 `git add` 暫存，
導致後續 commit 將其納入追蹤。`git rm --cached` 僅移除追蹤，**無法清除既有歷史**。

---

## 3. 前置準備

### 3.1 安裝 git-filter-repo

```bash
pip install --upgrade git-filter-repo

# 驗證安裝
git filter-repo --version
# 輸出：a40bce548d2c ✅
```

### 3.2 .gitignore 強化（事先執行）

將 `.env` 規則從單行改為 glob 覆蓋所有子目錄：

```gitignore
**/.env
**/.env.local
!**/.env.example
docker-compose.yml
docker-compose.*.yml
*.pem
*.key
*.p12
*.pfx
```

---

## 4. 完整執行流程

### Step A：建立 Mirror 備份

```bash
mkdir -p ~/git-backups
cd ~/git-backups

git clone --mirror https://github.com/AH431/NJ_Stream_ERP.git nj-stream-erp-backup.git

# 額外壓縮備份
tar -czf nj-stream-erp-backup-$(date +%Y%m%d).tar.gz nj-stream-erp-backup.git
```

**執行結果**：
```
Cloning into bare repository 'nj-stream-erp-backup.git'...
✅ 備份檔案：nj-stream-erp-backup-20260410.tar.gz（157K）
```

---

### Step B：執行 git filter-repo 清除歷史

```bash
cd ~/git-backups/nj-stream-erp-backup.git

git filter-repo \
  --path packages/backend/.env \
  --invert-paths \
  --force
```

**執行結果**：
```
Parsed 17 commits
New history written in 0.23 seconds; now repacking/cleaning...
Repacking your repo and cleaning out old unneeded objects
Completely finished after 0.52 seconds. ✅
```

> **注意**：filter-repo 會自動移除 `origin` remote，需於 Step D 重新加回。

---

### Step C：驗證清除結果

```bash
# 驗證 .env 已從所有歷史消失
git log --all --oneline -- packages/backend/.env
# 輸出：（空） ✅

# 確認最新 10 筆 commit 完整
git log --oneline -10
```

**執行結果**：
```
128a8b5 security: 移除 .env 追蹤並強化 .gitignore
c973fdd docs(LOG): 更新 Issue #2 驗收清單
a1d2be6 fix(W1-W2): 修正 drizzle-kit ESM/CJS 相容性問題
450d512 feat(W1-W2/Issue#2): Agent A-1 Fastify + Drizzle Schema 全 8 表
ea1e986 security: 移除敏感設定檔並加入 .gitignore
c383fea feat(W1-W2): Contract-First SSOT — Sync & Auth API 規格產出
...
✅ commit 歷史完整，.env 不再出現
```

---

### Step D：Force Push 至 GitHub

```bash
# 重新加回 remote（filter-repo 會自動移除）
git remote add origin https://github.com/AH431/NJ_Stream_ERP.git

git push origin --force --all
git push origin --force --tags
```

**執行結果**：
```
To https://github.com/AH431/NJ_Stream_ERP.git
 + 9c8b658...128a8b5 main -> main (forced update) ✅
Everything up-to-date ✅
```

---

### Step E：同步本地 repo

```bash
cd /c/Projects/NJ_Stream_ERP

git fetch origin
git reset --hard origin/main
```

**執行結果**：
```
From https://github.com/AH431/NJ_Stream_ERP
 + 9c8b658...128a8b5 main -> origin/main (forced update)
HEAD is now at 128a8b5 security: 移除 .env 追蹤並強化 .gitignore ✅
```

---

## 5. 憑證輪換

清除歷史後立即輪換所有曝光憑證：

| 項目 | 舊值（已作廢） | 新值（已更新） |
|------|--------------|--------------|
| PostgreSQL 密碼 | `postgres123` | `[REDACTED]`（24-char URL-safe random，存於 .env） |
| JWT Secret | `nj-stream-erp-dev-secret-change-in-production` | `e433f872...c1c9`（96-char hex，secrets.token_hex(48)） |

更新位置（均在 `.gitignore` 保護下）：
- `packages/backend/.env` ✅
- `docker-compose.yml` ✅

---

## 6. 最終驗證

```bash
# GitHub 上已無 .env 歷史
git log --all --oneline -- packages/backend/.env
# （空） ✅

# git status 乾淨
git status
# nothing to commit, working tree clean ✅
```

---

## 7. 後續預防措施

| 措施 | 狀態 |
|------|------|
| `.gitignore` 改用 `**/.env` glob（覆蓋所有子目錄） | ✅ |
| 新增 `.env.local`、`.env.*.local` 變體規則 | ✅ |
| 新增 `docker-compose.*.yml` 規則 | ✅ |
| 新增 `*.pem`、`*.key`、`*.p12`、`*.pfx` 憑證規則 | ✅ |
| 所有 `.env` 替換為 `.env.example` 範本 | ✅ |
| PostgreSQL 密碼輪換 | ✅ |
| JWT Secret 輪換（96-char hex） | ✅ |

### Docker volume 重建指令（若容器已運行）

```bash
# ⚠️ 清除舊 volume（開發初期無正式資料可直接執行）
docker compose down -v
docker compose up -d
```

---

## 8. 備份位置

| 備份類型 | 路徑 |
|---------|------|
| Mirror bare repo | `~/git-backups/nj-stream-erp-backup.git` |
| 壓縮備份 | `~/git-backups/nj-stream-erp-backup-20260410.tar.gz`（157K） |
