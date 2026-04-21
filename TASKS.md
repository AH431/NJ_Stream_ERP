# Backlog — NJ Stream ERP
# 最後更新：2026-04-21

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
- [ ] Release APK 正式簽章（`--obfuscate --split-debug-info`）
- [ ] Cloudflare WAF 設定（需購買網域）
- [ ] 後端 Docker Compose 生產環境配置

### 功能擴充
- [ ] stockAlertAt push 通知（需後端 WebSocket / FCM push service）
- [ ] CSV Import 正式環境命名調整（資料夾名稱從 `test_csv` 改為正式名稱）

### 技術債
- [ ] Drizzle 改用 `generate + migrate` 流程，migration files 納入 git 追蹤
- [ ] `README.md` 前端結構圖保持與 `lib/` 同步（每 Sprint 確認一次）