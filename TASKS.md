# Backlog — NJ Stream ERP
# 最後更新：2026-04-26（Session 4 PRD 盤點後）

> 只列未完成事項。已完成的 Sprint 記錄見 `CHANGELOG.md`。

---

## 本 Sprint（2026-04-21 起）

### Retro Action Items（優先執行）
- [ ] 手機實機驗證英文模式 — 8 輪測試（見 `LOG/guides/phone-test-guide.md` 第八輪）
- [ ] 確認 import screen 英文模式下格式說明與按鈕文字正確

### 功能
- [ ] 雙裝置 race condition 實測（Phase 6）— 需兩台 Android 同時操作

---

## 下個 Sprint（待排）

### 部署準備
- [x] Release APK 正式簽章（`--obfuscate --split-debug-info`）— 完成於 2026-04-26 Session 3，APK 54.1MB build 成功
- [x] 後端 Docker Compose 生產環境配置 — 完成於 2026-04-25，Dockerfile + docker-compose.prod.yml 建立
- [x] Cloudflare WAF 設定文件 — 完成於 2026-04-25，`docs/cloudflare-waf-setup.md` 建立（上線仍需購買網域）
- [ ] `npm run db:migrate` 執行（0004–0006）— 需 Docker + DB 連線
- [ ] Cloudflare WAF 實際啟用 — 需購買網域

### 功能擴充
- [ ] FCM 推播 E2E 驗證（AnomalyScanner → FCM → 手機通知）— 需實機 + Firebase Console 完整設定

### Firebase 設定（有外部依賴）
- [ ] Firebase Console 建立 Android App（package: `com.example.nj_stream_erp`）
- [ ] 下載 `google-services.json` 放至 `packages/frontend/android/app/`
- [ ] 產生 Service Account JSON 並寫入 `.env.production`

### 技術債
- [x] Drizzle 改用 `generate + migrate` 流程（已完成：無 db:push，0000–0006 migration 完整；drizzle/ 待下次 commit 納入 git）
- [x] `README.md` 前端結構圖保持與 `lib/` 同步（已修正：移除不存在的 language_provider.dart）