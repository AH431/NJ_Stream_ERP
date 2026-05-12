# NJ Stream ERP 客戶常見問題（FAQ）v1.0

> **適用範圍**：業務人員、倉管、管理者  
> **更新日期**：2026年5月12日  
> **涵蓋內容**：Phase 1（進銷存基礎） × Phase 2（智慧決策） × Phase 3（AI助理）

涵蓋內容分佈：
主題	題數	重點
核心價值 & 適用場景	4 題	誰該用、為什麼用、成本考量
進銷存功能	4 題	報價→訂單→出貨自動化、庫存管理、缺貨處理、數據安全
Phase 2 決策智慧	4 題	異常預警實例、儀表板設計、客戶評分、應收帳款
Phase 3 AI 助理	4 題	AI 聊天、準確性保證、數據隱私、ROI
實施與支援	4 題	遷移流程、費用結構、技術支援、數據出口
補充	—	投資回報估算、與傳統 ERP 對比、速查表

核心特色
✅ 客戶導向：每題都從「我們公司用了會怎樣」出發，不是技術廢話

✅ 實例豐富：具體場景（如「IC-8800 庫存查詢」）而非抽象概念

✅ 價值量化：有 ROI 估算（月省 $81K+、2-4 月回本）

✅ 疑慮消解：直接回應「AI 會搶工作嗎」「會不會被鎖進來」等常見恐懼

✅ 全階段涵蓋：Phase 1 基礎、Phase 2 智慧、Phase 3 AI 都有對應的用途說明

可用於：市場推廣資料、銷售團隊簽單、客戶現場演示、自助服務知識庫。

---

## 一、核心價值 & 適用場景（4題）

### Q1. NJ Stream ERP 適合我們公司嗎？
**A:** NJ Stream ERP 針對台灣5-50人的中小企業設計（貿易、批發、零售、輕製造），核心解決三大痛點：
- **進銷存一體化**：線上線下同步，庫存即時更新，無需Excel
- **手機隨處操作**：業務外出簽單、倉管手機掃碼入出庫，脫離電腦
- **數據驅動決策**：一眼掌握營收趨勢、客戶健康度、缺貨預警，不再被動應急

*典型客戶*：食品批發、電子配件、服飾代理、五金物流

---

### Q2. 「行動優先」是什麼意思？為什麼重要？
**A:** 行動優先 = 手機 App 與後端功能同步完整，不是「縮小版網頁」。
- **業務場景**：客戶現場展示產品、即時簽單、完成報價→訂單轉換，無需回辦公室
- **倉管場景**：掃商品條碼、確認庫存、執行入出庫，手機+掃槍完成全流程
- **優勢**：減少流程環節、加速業務週期、降低錯誤率（手寫單據→數位化）

---

### Q3. 離線工作真的有那麼重要嗎？
**A:** 對台灣企業至關重要。NJ Stream ERP 支援完整離線工作模式：
- **業務離線新增報價→同步回來自動轉訂單**，無需在線等候
- **倉管離線掃碼入庫→同步後庫存自動更新**，即使山區或偏遠倉庫無信號也可操作
- **自動衝突解決**：若同時修改同一筆資料，系統採「最後同步者贏」原則，並提示用戶有調整
- **場景**：偏遠物流點、通勤時間、臨時停機維護，業務仍可照常進行

---

### Q4. 使用 NJ Stream ERP 需要升級硬體或網路嗎？
**A:** **不需要**。
- **App 安裝檔 < 300MB**，老舊安卓機（4GB RAM）也能跑
- **後端極輕量**：基礎 2 vCPU + 4GB RAM 足夠 10-50 人公司
- **網路**：只需基本 4G，無需企業級 VPN（但建議有 HTTPS 加密連線）
- **成本低**：沒有昂貴伺服器或授權費用

---

## 二、進銷存核心功能（4題）

### Q5. 報價→訂單→出貨 這個流程會自動化嗎？
**A:** **半自動化**。流程如下：
1. **業務建報價**→ 客戶簽核
2. **報價轉訂單**→ 系統自動建訂單、記錄明細
3. **確認訂單**→ 系統自動 **預留庫存**（reserve）
4. **出貨作業**→ 倉管掃碼確認，系統同步扣減庫存
5. **完成**→ 訂單狀態自動轉「已出貨」，自動計算應收帳款

**無需手動**：不用重複輸入品項、不用再次簽核，系統記住整個歷史。

---

### Q6. 庫存管理會像傳統 ERP 那樣複雜嗎？
**A:** **完全相反**。NJ Stream ERP 庫存設計極簡：

| 狀態 | 說明 | 何時觸發 |
|------|------|---------|
| **現有庫存（On Hand）** | 倉庫實際有多少件 | 入庫時增加、出貨時減少 |
| **已預留（Reserved）** | 訂單已確認，正在等待出貨 | 確認訂單時增加 |
| **可用庫存** | On Hand - Reserved = 還能售出多少 | 即時計算 |

**沒有**：多層級倉庫、批號追蹤、複雜轉移單（MVP 限制，但業務流完整）

---

### Q7. 臨時缺貨時怎麼辦？會影響訂單嗎？
**A:** NJ Stream ERP 有三層防線：

1. **預警層**：低於 `最低庫存水位` → 儀表板顯示「紅色警示」，團隊立即看到
2. **確認層**：確認訂單時若庫存不足 → **系統警告「庫存不足，請補貨」**，可選擇：
   - A. 延後確認（等進貨後再確認）
   - B. 強制確認（客戶同意缺貨交期）
3. **自動異常**（Phase 2）：連續 7 天缺貨 → 自動產生「Critical Alert」，通知管理層

**不會自動取消**，讓公司有彈性應對。

---

### Q8. 如何確保業務簽的訂單金額不會被人偷改？
**A:** NJ Stream ERP 有完整稽核機制：

- **簽核流程**：報價 → 轉訂單 → 確認訂單，每一步都記錄「誰」「何時」修改了什麼
- **權限隔離**：
  - 業務只能「建報價 + 轉訂單」，不能改出貨價格
  - 倉管只能「確認出貨」，不能改訂單金額
  - 只有 Admin 可改既有訂單（且被記錄）
- **版本追蹤**：修改歷史永久保存，可查「2026/5/12 14:30 誰將單價改了多少」
- **Phase 3 審計日誌**：每個 AI 查詢、每次工具調用都有日誌

---

## 三、Phase 2：決策智慧（4題）

### Q9. 「智慧異常預警」具體預警什麼？有用嗎？
**A:** 不是虛幻功能，是真實業務場景的自動偵測：

| 預警類型 | 觸發條件 | 用途 |
|---------|---------|------|
| **缺貨警示** | 連續 7 天可用庫存 < 最低水位 | 立即補貨 |
| **客戶流失** | 活躍客戶（90天內有訂單）突然 60 天無動靜 | 業務主動聯繫 |
| **呆滯庫存** | 某產品有庫存但 90 天沒出過貨 | 清倉或停止進貨 |
| **大單異常** | 該客戶歷史訂單均價 $10K，突然 $100K 大單 | 確認不是誤單 |
| **訂單停滯** | 訂單 14 天還在「待確認」狀態 | 催促業務或客戶簽核 |
| **高價值客戶流失** | 貢獻度前 20% 的客戶 60 天無訂單 | 董事長等級重點救援 |

**效果**：小公司老闆不必每天盯 Excel，系統主動告訴你「誰要跟進」

---

### Q10. 儀表板能幫我做什麼？會像複雜的 BI 工具一樣難用嗎？
**A:** **完全不同**。NJ Stream ERP 儀表板是「老闆秘書」：

**打開 App 首頁，一眼看到：**
- 本月營收趨勢（折線圖）+ 年成長率
- 訂單狀況（環形圖）：待確認幾筆、待出貨幾筆、已完成幾筆
- 暢銷品排行（Top 5），直接點入可看詳細明細
- **紅色異常卡**：「2 個客戶 60 天沒下單」、「庫存 IC-8800 即將缺貨」，點入立即行動

**絕無**：複雜的篩選器、自己拖拉圖表、SQL 查詢
**設計原則**：老闆花 30 秒掃一眼，就知道今天要重點關注什麼

---

### Q11. 「客戶健康度評分」是怎樣算的？會亂嗎？
**A:** 使用經典的 **RFM 模型**（行銷科學驗證過 30 年）：

| 維度 | 說明 | 例子 |
|------|------|------|
| **R（最近度）** | 距最後訂單多少天（越少越好）| 客戶 A：5 天前下單 = 高分；客戶 B：120 天 = 低分 |
| **F（頻率）** | 90 天內下單幾次（越多越好）| 客戶 A：12 次 = 高分；客戶 C：1 次 = 低分 |
| **M（金額）** | 90 天內消費總額（越多越好）| 客戶 A：$500K = 高分；客戶 D：$5K = 低分 |

**結果分級：**
- 🌟 **VIP（12-15 分）**：金牌客戶，應定期維繫、贈送禮物
- 💚 **活躍（9-11 分）**：主要客戶，持續跟進
- 🟡 **觀察（6-8 分）**：中等客戶，主動關懷
- 🔴 **流失風險（3-5 分）**：緊急聯繫、可提供優惠拉回

**驗證方式**：業務進客戶詳情頁一眼看分級 + 互動記錄，完全符合人工判斷。

---

### Q12. 「應收帳款管理」對小公司有幫助嗎？
**A:** **非常有**。這是很多中小企業的隱形漏洞：

**常見問題**：
- 不知道誰還欠錢、欠了多久
- 應該 30 天內收款，結果變成 90 天才收
- 預算不知道什麼時候真正進來

**NJ Stream ERP 的解決方案**：
1. 出貨後自動計算 **到期日**（出貨日 + 客戶付款條件天數，如 30 天）
2. **應收帳款頁面**自動分類：
   - 0-30 天（正常）：綠色
   - 31-60 天（注意）：黃色
   - 61-90 天（警示）：橙色
   - 90+ 天（逾期）：紅色，顯示欠了多久
3. **自動預警**：逾期客戶系統自動產生 Alert，業務收到通知立即催款
4. **月度損益**：看本月真正進帳多少（而非以為的訂單金額），財務預測準確度大幅提升

**效果**：應收帳款週期縮短 10-20 天，現金流改善，老闆心不慌

---

## 四、Phase 3：AI 助理（4題）

### Q13. 為什麼需要「AI 助理」？不是有系統查詢功能嗎？
**A:** AI 助理的核心價值在於**語言自然化 + 智慧理解**：

**傳統方式**：
- 「查一下 IC-8800 的庫存」→ 進庫存頁面 → 搜尋產品 → 看數字 → 3 分鐘

**AI 助理方式**：
- 「IC-8800 現在庫存多少？」→ App 打開、在聊天框說話或打字 → 1 秒得到「現有 150 件、已預留 50 件、可用 100 件」+ 數據來源

**場景優勢**：
- **邊走邊問**：倉管邊掃貨邊問庫存
- **複雜查詢**：「過去 30 天出貨超過 1000 件的產品有哪些？」（Excel 要 5 分鐘，AI 說話 10 秒）
- **無需培訓**：不用學系統按鈕，就像問同事

---

### Q14. AI 助理會不會不夠聰明，給出錯誤答案？
**A:** NJ Stream ERP 的 AI 助理設計**優先正確性，其次聰明度**：

**三層防護**：
1. **靜態知識**（不會出錯）：
   - 公司簡介、產品規格、常見流程
   - 用 RAG 技術（檢索增強生成），確保答案來自「已驗證的公司知識庫」

2. **動態查詢**（即時準確）：
   - 「IC-8800 庫存」、「客戶 ABC 上月訂單」
   - 系統**直接查資料庫**，不靠 AI「猜」，確保準確率 100%

3. **敏感操作禁止**：
   - 修改訂單金額、刪除訂單等重大操作 → AI 拒絕，需人工操作
   - AI 問什麼都可以，但改什麼不行

**審計**：Phase 3 有完整日誌，看得到誰在什麼時候問了什麼、AI 回答了什麼

---

### Q15. 會不會 AI 偷看我的商業機密（客戶名單、售價）？
**A:** **不會**。有四層安全機制：

1. **角色隔離**：
   - 倉管 AI 只能看庫存相關資料
   - 業務 AI 只能看自己簽的報價單
   - Admin AI 才能看全公司數據
   （就像傳統 ERP 的權限，AI 問不到無權限的資料）

2. **內部網路**：
   - AI 服務 100% 在公司內網運行，不上雲
   - 你的資料不會外傳到任何第三方 AI（如 OpenAI、Google）
   - 即使停電，在地備份仍在

3. **通訊加密**：
   - App ↔ 伺服器全程 HTTPS 加密
   - 即使被攔截也是亂碼

4. **稽核日誌**：
   - 每次查詢都有日誌：誰、何時、問什麼、系統回答了什麼
   - Admin 可隨時查閱，發現異常行為立即警報

---

### Q16. 「手機 AI 助理」跟「後台數據查詢」的差別是什麼？值得額外付費嗎？
**A:** Phase 3 是 ERP 進階版，不是額外購買，包含在完整方案裡：

| 對比項目 | Phase 1-2 傳統查詢 | Phase 3 AI 助理 |
|---------|-----------------|-----------------|
| **查一項資料** | 進頁面 → 搜尋 → 看結果 | 語音/文字問 → 秒回 |
| **複雜查詢** | 進報表頁 → 手動篩選條件 | 「過去 30 天出貨 Top 5 產品」→ 直接回答 |
| **跨表查詢** | 在多個頁面切換 | 「客戶 ABC 的所有未出貨訂單」一句話 |
| **邊走邊查** | 需要停下來看手機 | 抓住倉管邊掃貨邊問 |
| **決策支持** | 看完數字自己判斷 | AI 連同數據來源、異常提示一起回答 |
| **使用門檻** | 需要培訓按鈕位置 | 像問同事一樣自然 |

**ROI**：以 20 人團隊計，平均每人每天省 30 分鐘查詢時間 = 月省 120 小時工資，遠超實施成本

---

## 五、實施與支援（4題）

### Q17. 從傳統 ERP（或 Excel）遷移到 NJ Stream 會很複雜嗎？要停業嗎？
**A:** **平滑遷移**，不需停業：

**標準流程（2-4 週）**：

1. **第 1 週：資料匯入**
   - 你提供現有客戶、產品、庫存清單（Excel 或 CSV）
   - 我們協助匯入系統、驗證數據（「客戶數 X、產品數 Y、庫存金額 Z 是否正確」）

2. **第 2 週：平行運行**
   - 業務同時用舊系統 + NJ Stream
   - 我們操作演示、回答問題、調整參數（如稅率、付款條件）

3. **第 3 週：全面切換**
   - 所有交易進 NJ Stream，舊系統歸檔
   - 我們駐廠支援 3-5 天（同步問題、流程微調）

4. **第 4 週：驗收 + 調優**
   - 跑一個完整週期（報價→訂單→出貨→應收），核對數字
   - 微調異常規則、報表格式、權限設定

**無需停業**，業務可照常進行

---

### Q18. 後續維護和更新怎麼計費？會有額外成本嗎？
**A:** **全包制**，無隱藏費用。費用結構透明：

| 項目 | 包含內容 | 計費方式 |
|------|---------|---------|
| **系統軟體** | 所有 Phase 1-3 功能、無限用戶 | 年費或月費（業務容量範圍內） |
| **雲端/伺服器** | 包含基礎架設（2 vCPU + 4GB RAM） | 評估硬體費用 |
| **更新維護** | Phase 3 AI、異常規則優化、新功能迭代 | 已含，無額外費用 |
| **備份復原** | 每日自動備份、加密儲存、災難復原演練 | 已含 |
| **技術支援** | Email / 電話 / 視訊支援、駐廠協助 | 分層：基本包含，特殊項目另計 |

**沒有**：按使用量計費、按 API 次數計費、功能升級費

**隱藏議題**：若你要客製（如特殊報表、複雜工作流），再評估客製費用

---

### Q19. 如果遇到問題，如何得到技術支援？支援時間是多少？
**A:** **多層支援**，確保不卡關：

| 級別 | 管道 | 回應時間 | 場景 |
|------|------|---------|------|
| **L1 FAQ** | App 內「幫助」頁面、線上知識庫 | 秒級 | 「怎麼新增客戶」、「怎麼轉訂單」 |
| **L2 線上** | Email / Slack / LINE，技術人員 | 4 小時內 | 「為什麼這個訂單改不了」、「報表數字不對」 |
| **L3 即時** | 電話 / 視訊通話，工程師螢幕共享 | 當天 | 「系統卡住了」、「資料丟了」 |
| **L4 駐廠** | 派技術人員到現場（另計費） | 2 天內安排 | 「遷移出問題」、「大規模資料異常」 |

**時區**：台灣標準時間 09:00-18:00，特急問題可聯繫 on-call 工程師

**SLA**：99.5% 月度可用率；故障 1 小時內恢復承諾

---

### Q20. 萬一我們決定不用了，資料可以帶走嗎？會被鎖進來嗎？
**A:** **絕對自由**。完全開放數據出口：

- **匯出格式**：Excel / CSV / JSON，所有資料一應俱全
- **歷史記錄**：包含所有版本、修改日誌、審計軌跡
- **API 接口**：提供 REST API 讓你用程式自動匯出（如要串接新系統）
- **離線備份**：你可隨時要求全資料庫備份（加密）

**停用流程**：
1. 通知我們終止日期
2. 我們協助你完整匯出 + 備份驗證
3. 系統下線後 90 天刪除備份（合規）

**承諾**：不會綁定、不會刪資料當要挾

---

## 六、價格與投資回報（補充）

### 典型投資回報估算（以 20 人公司為例）

| 項目 | 月度節省 |
|------|---------|
| 減少 Excel 手動作業（庫存、報表） | 40 人時 × $400/hr = $16K |
| 減少訂單流程錯誤（返工、補貨） | 預估每月 5 筆錯誤 × $2K = $10K |
| 加速應收帳款（現金流改善） | 應收週期縮短 10 天，現金釋放 $50K+ |
| 防止呆滯庫存、及時補貨 | 減少報廢 + 加快周轉率 = 月省 $5K |
| **小計** | **月省 $81K+** |

**NJ Stream ERP 年費**：約 $60-100K（20 人規模）  
**ROI**：約 2-4 個月內回本；後續純獲利

---

## 附錄：常見誤會解答

### 「AI 會不會搶走員工的工作？」
**A:** 不會。AI 助理的設計是「協助員工工作更快」，而非「取代」：
- 倉管用 AI 查庫存，不是倉管被裁，而是倉管有更多時間專注複雜操作
- 業務用 AI 分析客戶，是業務更會做業績，不是業務失業
- 老闆用儀表板預警異常，可以及時決策，不是決策被自動化

### 「要不要買同等級的傳統 ERP（如用友、金蝶）？」
**A:** 對比見下表：

| 對比項 | NJ Stream | 傳統 ERP |
|------|---------|---------|
| **成本** | $60-100K/年 | $300K+/年（許可證 + 實施） |
| **上線時間** | 2-4 週 | 3-6 個月 |
| **手機支援** | 完整（行動優先） | 老舊或需另購 |
| **AI 功能** | 內建 Phase 3 | 不支援或需三方整合 |
| **離線能力** | 強（完整同步） | 弱（多需在線） |
| **老舊系統遷移** | 平滑（我們協助） | 複雜、風險高 |
| **適合公司規模** | 5-50 人（中小企業 goldzone） | 100+ 人（大企業必需） |

---

## 常見提問的簡短回答速查表

| 問題 | 答案 |
|------|------|
| 多少人可以用？ | 無限，月費按使用者數量級 |
| 支不支援多幣別（RMB / USD）? | 支援（Phase 2+），含匯率更新 |
| 可以用手寫簽名簽核嗎？ | 支援（含影像辨識，Phase 2+） |
| 廠房停電了會怎樣？ | 有離線模式，恢復後同步；重要日誌加密備份 |
| 資料量很大（100 萬筆訂單）會卡嗎？ | 可承載，需評估硬體升級成本 |
| 可以客製工作流（如多級核准）? | 可以，另外估價（客製工程） |

---

**文件維護**：NJ_Stream_ERP 產品團隊  
**版本**：v1.0（2026.05.12）  
**下版預計**：v1.1（加入實戶案例、使用故事）

---

# NJ Stream ERP Customer FAQ (English) v1.0

> **Scope**: Sales team, warehouse staff, management  
> **Updated**: May 12, 2026  
> **Coverage**: Phase 1 (Core Inventory) × Phase 2 (Smart Analytics) × Phase 3 (AI Assistant)

---

## I. Core Value & Use Cases (4 Questions)

### Q1. Is NJ Stream ERP suitable for our company?
**A:** Designed for Taiwan's 5-50 person SMEs (trading, wholesale, retail, light manufacturing), solving three core pain points:
- **Unified inventory management**: Online/offline sync, real-time stock, no more Excel
- **Mobile operations**: Sales sign on-site, warehouse scanners, office-independent workflow
- **Data-driven decisions**: Revenue trends, customer health, stockout alerts at a glance

*Typical customers*: Food wholesalers, electronics distributors, apparel traders, hardware logistics

---

### Q2. What does "mobile-first" mean? Why matters?
**A:** Mobile-first = full feature parity, not a "shrunk website."
- **Sales**: Demo products, sign quotes on-site, auto-convert to orders—no office needed
- **Warehouse**: Scan codes, confirm inventory, execute in/out—complete with phone + scanner
- **Benefits**: Fewer steps, faster cycles, lower error rates (handwritten → digital)

---

### Q3. Is offline capability essential?
**A:** Critical for Taiwan. Full offline support:
- **Sales offline**: Create quotes → sync auto-converts to orders; no online waiting
- **Warehouse offline**: Scan inventory → sync updates stock; works without signal
- **Auto conflict resolution**: "Last-sync-wins" rule; users notified of changes
- **Scenarios**: Remote logistics, commute, maintenance windows—business uninterrupted

---

### Q4. Hardware/network upgrades needed?
**A:** **No.**
- **App < 300MB**, runs on old Android (4GB RAM)
- **Backend lightweight**: 2 vCPU + 4GB RAM for 10-50 people
- **Network**: Basic 4G, no VPN needed (HTTPS recommended)
- **Cost**: No expensive servers or licenses

---

## II. Inventory Core (4 Questions)

### Q5. Does quote→order→shipment automate?
**A:** **Semi-automated:**
1. Sales creates quote → Customer approves
2. Convert quote → Auto-creates order, records details
3. Confirm order → Auto-**reserves inventory**
4. Shipment → Warehouse scans, stock deducts
5. Complete → Auto-transitions to "shipped", AR auto-calculated

**No manual**: No re-entry, no re-approval, system remembers everything.

---

### Q6. Is inventory as complex as traditional ERP?
**A:** **Opposite.** Minimal design:

| State | Description | Trigger |
|------|-------------|---------|
| **On Hand** | Physical warehouse quantity | +In stock, -Shipment |
| **Reserved** | Confirmed orders pending | +Order confirm |
| **Available** | On Hand - Reserved | Real-time calc |

**No**: Multi-level warehouses, lot tracking, complex transfers (MVP limits, business flow complete)

---

### Q7. Out of stock scenario?
**A:** Three safeguards:
1. **Alert**: Below min level → Red dashboard warning
2. **Confirm**: Insufficient stock → "Replenish?" option, can delay or force confirm
3. **Auto-anomaly**: 7+ days out → Critical alert to management

**No auto-cancel**, company keeps flexibility.

---

### Q8. Prevent order amount tampering?
**A:** Complete audit:
- **Sign-offs logged**: Quote → Order → Confirmation, each step tracked
- **Role isolation**: Sales creates, warehouse ships, only Admin modifies (logged)
- **Version history**: Permanent change log with timestamps
- **Phase 3 audit**: All AI queries logged

---

## III. Phase 2: Smart Analytics (4 Questions)

### Q9. What does "smart anomaly alert" detect?
**A:** Real business auto-detection:

| Alert | Trigger | Action |
|-------|---------|--------|
| **Stockout** | 7+ days below min | Replenish |
| **Churn** | Active customer → 60 days silent | Outreach |
| **Dead stock** | Stock but 90 days no shipment | Clear or stop |
| **Large order** | 10x customer average | Verify accuracy |
| **Stalled order** | 14+ days pending confirm | Escalate |
| **VIP churn** | Top 20% silent 60 days | Executive action |

**Impact**: No manual Excel checking; system flags what needs attention.

---

### Q10. Dashboard complexity?
**A:** Simple, not like BI tools:

**At a glance:**
- Monthly revenue trend + YoY growth
- Order status donut: pending / shipping / completed
- Top 5 products (clickable)
- Red alert cards: "2 customers inactive," "IC-8800 critical"

**No**: Filters, drag-drop, SQL  
**30-second scan**, know daily priorities

---

### Q11. Customer health score formula?
**A:** Proven **RFM model** (30-year marketing science):

| Dimension | Meaning | Example |
|----------|---------|---------|
| **R(ecency)** | Days since last order | 5 days = high; 120 = low |
| **F(requency)** | 90-day orders | 12x = high; 1x = low |
| **M(onetary)** | 90-day spend | $500K = high; $5K = low |

**Tiers:**
- 🌟 VIP (12-15): Golden, maintain + gifts
- 💚 Active (9-11): Key, continuous follow
- 🟡 Watch (6-8): Medium, proactive care
- 🔴 Churn (3-5): Urgent, consider offers

---

### Q12. AR management valuable for SMEs?
**A:** **Absolutely.** Hidden leak for most:

**Problems**: Don't know who owes, collection drags to 90 days, budget timing unclear

**NJ Stream solution:**
1. Auto-calculates due date (ship + payment terms)
2. **AR aging auto-classified**: 0-30 (green) / 31-60 (yellow) / 61-90 (orange) / 90+ (red)
3. **Auto-escalation**: Overdue triggers alert for collection
4. **P&L accuracy**: See actual cash-in, not assumed order amount

**Impact**: AR cycle -10-20 days, cash flow improves, stress drops

---

## IV. Phase 3: AI Assistant (4 Questions)

### Q13. Why AI assistant vs. query functions?
**A:** **Natural language + smart understanding:**

**Traditional**: "Check IC-8800" → Stock page → Search → 3 minutes  
**AI**: "IC-8800 inventory?" → Chat → 1 second: "150 on-hand, 50 reserved, 100 available" + source

**Scenes:**
- Walk-and-ask while scanning
- "Products shipped >1000 units past 30 days?" → 10 seconds voice vs. 5 min Excel
- No training needed

---

### Q14. Wrong answers? Trustworthy?
**A:** **Accuracy-first design:**

**Three-layer safety:**
1. **Static** (no error): Company info, product specs from verified knowledge base (RAG)
2. **Dynamic** (100% accurate): "IC-8800 stock" → Direct DB query, no guessing
3. **Sensitive blocked**: Modify amounts, delete → AI refuses, manual only

**Audit**: Phase 3 logs every query—who, when, what asked, what answered

---

### Q15. Leak business secrets (customers, pricing)?
**A:** **No.** Four protections:
1. **Role isolation**: Warehouse sees stock only, Sales sees own quotes, Admin sees all
2. **On-premises**: AI runs locally, no cloud, no third-party AI (OpenAI, etc.)
3. **Encrypted**: App ↔ Server HTTPS, interception = gibberish
4. **Audit logs**: Every query logged; Admin audits anytime

---

### Q16. Mobile AI vs. traditional query—worth extra cost?
**A:** Phase 3 included, not add-on:

| | Phase 1-2 Query | Phase 3 AI |
|---|---|---|
| Single data | Page → Search → View | Voice/text → instant |
| Complex | Report page → manual filters | "Top 5 past 30 days" → instant |
| Cross-table | Page switching | "ABC pending orders" → one sentence |
| Walk-and-check | Stop to view | Ask while scanning |
| Decision | View numbers, self-judge | AI returns data + sources + alerts |
| Learning | Train on buttons | Natural like coworker |

**ROI**: 20 people, 30 min/day saved = 120 hrs/month = far exceeds cost

---

## V. Implementation & Support (4 Questions)

### Q17. Migration complexity? Shutdown needed?
**A:** **Smooth, no downtime (2-4 weeks):**

1. **Week 1**: You provide data (Excel/CSV) → We import + verify
2. **Week 2**: Old + new systems parallel → Demo + adjust settings
3. **Week 3**: Full cutover → On-site support 3-5 days
4. **Week 4**: Validate full cycle → Fine-tune alerts

---

### Q18. Maintenance billing? Hidden costs?
**A:** **All-inclusive, transparent:**

| Item | Includes | Cost |
|------|----------|------|
| **Software** | Phase 1-3, unlimited users | Annual/monthly |
| **Server** | 2 vCPU + 4GB base | Hardware assessed |
| **Updates** | AI, alerts, features | Included |
| **Backup** | Daily encrypted | Included |
| **Support** | Email/phone/video | Tiered |

**No**: Usage, API call, feature upgrade fees

---

### Q19. Tech support on issues?
**A:** **Layered:**

| Level | Channel | Response | Scenario |
|-------|---------|----------|----------|
| L1 | FAQ, help | Instant | "How to add customer" |
| L2 | Email/Slack/LINE | 4 hrs | "Why order locked" |
| L3 | Phone/video | Same day | "System frozen" |
| L4 | On-site (fee) | 2 days | "Data corruption" |

**Hours**: Taiwan 9am-6pm, after-hours on-call  
**SLA**: 99.5% monthly; 1-hour recovery

---

### Q20. Export data if we leave?
**A:** **Completely free:**
- **Formats**: Excel / CSV / JSON, everything
- **History**: All versions + audit trail
- **API**: REST for automation
- **Offline backup**: Anytime

**Exit**: Notify → We export → Verify → Delete after 90 days  
**Promise**: No lock-in, no hostage

---

## VI. ROI Summary

### 20-person company savings

| Item | Monthly |
|------|---------|
| Reduce Excel work | 40 hrs × $400 = $16K |
| Fewer order errors | 5 errors × $2K = $10K |
| Faster AR (cash freed) | -10 days = $50K+ |
| Prevent dead stock | Fewer write-offs = $5K |
| **Total** | **$81K+** |

**Annual cost**: $60-100K  
**Payback**: 2-4 months, pure profit after

---

## Common Misconceptions

### "AI replaces workers?"
No. Design is "help faster," not "replace." Staff focus on complex work, not layoffs.

### "Traditional ERP (SAP, Oracle) vs. NJ Stream?"

| | NJ Stream | Traditional |
|---|-----------|-----------|
| Cost | $60-100K/yr | $300K+ |
| Launch | 2-4 weeks | 3-6 months |
| Mobile | Full | Legacy |
| AI | Built-in | Unsupported |
| Offline | Strong | Weak |
| Migration | Smooth | Complex |
| Best for | 5-50 people | 100+ people |

---

## Quick Q&A

| Q | A |
|---|---|
| Users? | Unlimited, scales by count |
| Multi-currency? | Yes (Phase 2+), auto rates |
| Handwritten signatures? | Yes (image recognition, Phase 2+) |
| Power outage? | Offline works, syncs after; backups encrypted |
| Large data (1M orders)? | Supported, hardware evaluated |
| Custom workflows? | Yes, separate estimate |

---

**Maintained by**: NJ_Stream_ERP Product Team  
**Version**: v1.0 (2026.05.12)  
**Next**: v1.1 (customer case studies + stories)
