# Backlog — NJ Stream ERP
# 最後更新：2026-05-03（RAG v2 Day 2 完成）

> 只列未完成事項。已完成的 Sprint 記錄見 `CHANGELOG.md`。

---

## 進行中 — RAG v2 Rich Card Pipeline（Phase 2）

> Phase 1 已完成（2026-05-03）：20 product cards + 12 customer cards + Chroma index 重建。

### Day 3（下次工作日）

- [ ] 補充 answer-quality 題庫 v0.1（`docs/artifacts/phase3-ai-answer-quality-questions.md`）
  - 分組：product factual / customer factual / alias / inventory risk / negative
  - 每題記錄：問題、角色、預期路由、預期召回卡片、預期答案重點、禁止編造欄位
- [ ] 手機端靜態問答驗收（5 題 static / 5 題 dynamic / 3 題 blocked）
- [ ] 驗證 SourceCard 行為：static 無 tool_call source、dynamic 顯示 tool source
- [ ] 記錄失敗模式：查不到 / alias 未命中 / 回答太空泛 / 編造欄位

**Phase 2 驗收門檻**
- routing baseline 維持全綠（36/36）
- answer-quality 第一版量化結果
- 手機端 5S + 5D + 3B 全部完成

---

## 本 Sprint（2026-04-21 起）

### Retro Action Items
- [ ] 手機實機驗證英文模式 — 8 輪測試（見 `LOG/guides/phone-test-guide.md` 第八輪）
- [ ] 確認 import screen 英文模式下格式說明與按鈕文字正確

### 功能
- [ ] 雙裝置 race condition 實測（Phase 6）— 需兩台 Android 同時操作

---

## 下個 Sprint（待排）

### 部署準備
- [ ] `npm run db:migrate` 執行（0004–0006）— 需 Docker + DB 連線
- [ ] Cloudflare WAF 實際啟用 — 需購買網域（`verify_waf.ps1` 待網域後執行）

### 功能擴充
- [ ] FCM 推播 E2E 驗證（AnomalyScanner → FCM → 手機通知）— 需實機 + Firebase Console 完整設定

### Firebase 設定（有外部依賴）
- [ ] Firebase Console 建立 Android App（package: `com.example.nj_stream_erp`）
- [ ] 下載 `google-services.json` 放至 `packages/frontend/android/app/`
- [ ] 產生 Service Account JSON 並寫入 `.env.production`

### RAG Phase 3（條件式，Phase 2 完成後評估）
- [ ] 小規模 SFT 驗證（200–300 筆）— 前提：Phase 2 有穩定失敗案例
- [ ] 決定是否進入 LoRA 擴充 — 前提：SFT 有明顯提升

---

## 已完成（本 Sprint 內，參考用）

| 日期 | 項目 |
|------|------|
| 2026-05-03 | RAG v2 Day 2：card_generator.py rich card 升級、product/customer catalog YAML、Chroma index 重建（mxbai-embed-large）、chunk min-length filter、vectorstore full rebuild fix、RAG prompt v2（修正 false negative + hallucination）、test_card_generator.py 改寫 25/25、CLI 靜態問答驗收 5/5 retrieval |
| 2026-05-03 | Dashboard Combo Chart（月度營收 + 出貨趨勢 Column+Line dual-axis）|
| 2026-05-03 | DevSettings Force Full Sync 按鈕（DB 重建後一鍵重置手機快取）|
| 2026-05-03 | seed-production-en.ts（20 產品、12 客戶、45 訂單正式英文資料集）|
| 2026-05-03 | verify_app_security.ps1（本機/Quick Tunnel 可跑的安全邊界驗收腳本）|
| 2026-05-03 | AI 聊天手機端對端實測（dynamic tool call + SourceCard + blocked 路由）|
| 2026-04-29 | PR-1 ~ PR-10 全部完成，Phase 3 核心功能可演示 |
