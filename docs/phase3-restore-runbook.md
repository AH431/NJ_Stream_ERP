# NJ Stream ERP — Restore Runbook

**適用版本**：Phase 3 PR-5 及之後  
**對應 PRD**：v5.0 §M0.3、§M7.2

---

## 1. 前置條件

| 項目 | 驗證方式 |
|------|----------|
| Docker Desktop 已啟動 | `docker ps` |
| PostgreSQL 容器正在運行 | `docker inspect --format '{{.State.Running}}' nj-erp-postgres` → `true` |
| Gpg4win (GnuPG ≥ 2.1) 已安裝，`gpg` 在 PATH | `gpg --version` |
| PowerShell 5.1+ | `$PSVersionTable.PSVersion` |
| 環境變數已設定（見下方） | — |

> **注意**：容器映像為 `postgres:16-alpine`，內建 `sh`、`psql`、`pg_restore`、`rm`，**不含 bash**。腳本已避免使用 `bash`。

### 必要環境變數

```powershell
# 首選：直接指定（docker-compose 本身也使用這些變數）
$env:POSTGRES_USER     = 'postgres'
$env:POSTGRES_DB       = 'nj_erp'
$env:POSTGRES_PASSWORD = '<strong-password>'   # 與 docker-compose 相同的密碼

# 備份專用
$env:BACKUP_PASSPHRASE = '<at-least-20-chars>' # 獨立於 DB 密碼，≥20 字元
$env:BACKUP_DIR        = 'C:\Backups\NJ_ERP'   # 備份輸出目錄

# 選填（預設 nj-erp-postgres）
$env:POSTGRES_CONTAINER = 'nj-erp-postgres'

# 替代：若未設定 POSTGRES_* 個別變數，腳本退而解析 DATABASE_URL
# $env:DATABASE_URL = 'postgresql://postgres:<password>@localhost:5432/nj_erp'
```

---

## 2. 備份流程

```powershell
# 步驟 1：設定環境變數（見上方）

# 步驟 2：執行備份
.\scripts\backup_pg.ps1

# 預期輸出：
# [backup] Container 'nj-erp-postgres' is running.
# [backup] DB=nj_erp  user=postgres  output=C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg
# [backup] pg_dump inside container → /tmp/20260430_120000.pgdump
# [backup] docker cp → C:\Users\...\AppData\Local\Temp\20260430_120000.pgdump
# [backup] GPG encrypt → 20260430_120000.pgdump.gpg
# [backup] SUCCESS: C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg (X.XX MB)
```

備份完成後記錄檔名，還原時需要完整路徑。

---

## 3. 標準還原（`pg_restore -c`，預設模式）

適用情境：容器仍有 `nj_erp` 資料庫，要用備份覆蓋現有資料。

```powershell
# 步驟 1：設定環境變數（BACKUP_DIR 非必要，只需 BACKUP_PASSPHRASE）

# 步驟 2：執行還原
.\scripts\restore_pg.ps1 -BackupFile 'C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg'

# 步驟 3：看到警告後輸入 YES（大寫）確認
# ============================================================
#  RESTORE WILL OVERWRITE DATABASE: 'nj_erp'
#  Container : nj-erp-postgres
#  Backup    : C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg
#  Mode      : pg_restore -c (clean in place)
# ============================================================
# Type YES to continue: YES
```

若出現 FK 約束錯誤，改用 §4 的完整重建模式。

---

## 4. 完整重建還原（`-DropAndRecreate`）

適用情境：Schema 差異導致 `-c` 模式失敗，或 M7.2 smoke test 需要從空白 DB 驗證。

```powershell
.\scripts\restore_pg.ps1 `
    -BackupFile 'C:\Backups\NJ_ERP\20260430_120000.pgdump.gpg' `
    -DropAndRecreate
# → 輸入 YES 確認
```

腳本內部流程：
1. 終止所有連至 `nj_erp` 的 session
2. `DROP DATABASE IF EXISTS nj_erp`
3. `CREATE DATABASE nj_erp OWNER postgres`
4. `pg_restore`（不帶 `-c`，因為是空白 DB）

---

## 5. M7.2 Smoke Test 驗收清單

### 本機 / Dev 路徑

```
[ ] 1. restore_pg.ps1 以 exit 0 結束（無 FAILED 訊息）
[ ] 2. cd packages\backend && npm run db:migrate
       → 應顯示 "No pending migrations"（schema 已由 pg_restore 還原，idempotent）
[ ] 3. POST http://localhost:3000/api/v1/auth/login
       body: {"username":"...","password":"..."}
       → HTTP 200，回傳 accessToken
[ ] 4. GET http://localhost:3000/api/v1/sync/pull
       header: Authorization: Bearer <accessToken>
       → HTTP 200，回傳含頂層欄位（customers、products、quotations 等）的物件
[ ] 5. 確認資料列數：
       docker exec nj-erp-postgres psql -U postgres -d nj_erp -c "SELECT COUNT(*) FROM customers;"
       → 應與備份前一致
```

### 生產環境路徑

```
[ ] 1. restore_pg.ps1 以 exit 0 結束（容器 nj-erp-postgres，憑證來自 .env.production）
[ ] 2. docker compose -f docker-compose.prod.yml --env-file .env.production run --rm migrate
       → "No pending migrations"（idempotent）
[ ] 3. POST <Cloudflare Tunnel URL>/api/v1/auth/login → HTTP 200，回傳 accessToken
[ ] 4. GET <Cloudflare Tunnel URL>/api/v1/sync/pull
       header: Authorization: Bearer <accessToken>
       → HTTP 200，回傳含 customers、products、quotations 等頂層集合的物件
[ ] 5. docker exec nj-erp-postgres psql -U postgres -d nj_erp -c "SELECT COUNT(*) FROM customers;"
       → 與備份前一致
```

---

## 6. 自動化 Restore Drill

`drill_restore.ps1` 腳本可在隔離容器中自動執行完整備份→還原→驗證流程，**不影響正在運行的 `nj-erp-postgres`**。

### 前置條件

- 設定好所有必要環境變數（見 §1）
- Docker Desktop 已啟動

### 執行

```powershell
# 完整 drill（備份 + 還原 + 驗證）
.\scripts\drill_restore.ps1

# 僅驗證（跳過備份，使用 BACKUP_DIR 中最新檔案）
.\scripts\drill_restore.ps1 -SkipBackup
```

### 預期輸出（PASS 範例）

```
[drill] Running backup...
[drill] Using backup: C:\Backups\NJ_ERP\20260501_020000.pgdump.gpg
[drill] Starting isolated drill container: nj-erp-postgres-drill
[drill] Waiting for pg_isready...
[drill] Drill container is ready.
[drill] Restoring backup into drill container...
[drill] Running SQL smoke checks...
[drill]   customers: 42 row(s)
[drill]   active users: 3
[drill]   users: 4 row(s)
[drill]   ...
[drill] Tearing down drill container...
[drill] Backup file : C:\Backups\NJ_ERP\20260501_020000.pgdump.gpg
[drill] Duration    : 38.2s
[drill] PASS
```

### Drill Log（定期演練記錄）

| 日期 | 備份檔 | 時長 | 結果 | 操作人 |
|------|--------|------|------|--------|
| — | — | — | — | — |

---

## 7. 疑難排解

### GPG 彈出 GUI 視窗（未進行非互動式加密）

**原因**：GnuPG 版本 < 2.1，不支援 `--pinentry-mode loopback`。

**解決**：確認 `gpg --version` 顯示 2.1 以上。Gpg4win 最新版預設安裝 GnuPG 2.4.x。

---

### `gpg: decryption failed: Bad session key`

**原因**：`BACKUP_PASSPHRASE` 不符。

**解決**：確認還原時使用與備份時相同的 `BACKUP_PASSPHRASE` 值。

---

### `Error: No such container: nj-erp-postgres`

**原因**：容器未啟動，或 `POSTGRES_CONTAINER` 設定錯誤。

**解決**：
```powershell
docker ps | Select-String 'postgres'   # 查看實際容器名稱
$env:POSTGRES_CONTAINER = '<actual-name>'
```

---

### `pg_restore: error: could not execute query: ERROR: insert or update on table...violates foreign key constraint`

**原因**：`pg_restore -c` 無法在有約束的 DB 內以正確順序刪除/重建物件。

**解決**：改用 `-DropAndRecreate`，從空白 DB 完整還原。

---

### 容器內 `/tmp` 空間不足

**原因**：Alpine 的 tmpfs 預設較小；大型 DB dump 可能填滿。

**解決**：確認 `docker system df`；必要時 `docker system prune` 清理舊映像/容器。若 DB 超過 500MB，考慮改為 `docker cp` 先將備份檔複製至容器 volume 路徑後再 pg_restore。
