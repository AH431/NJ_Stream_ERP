# Phase 3 AI 助理 — Answer Quality 題庫

> **版本**：v0.1 — 2026-05-04
> **用途**：驗收 static RAG 回答品質（retrieval hit@k、sensitive leakage、answer correctness）
> **區別於 Golden Questions**：golden questions 只測 query router 分類；本題庫測 RAG 的「找對資料」和「正確回答」

## 題目格式說明

```
問題：使用者輸入的原文
發問角色：sales / admin / warehouse
預期路由：static（本題庫全部為 static）
預期召回卡片：knowledge_cards 下的檔名（retrieval 驗收用）
預期答案重點：LLM 回答必須包含的關鍵詞（逗號分隔，manual review 用）
禁止編造欄位：不可出現在回答中的敏感值（automated leakage check 用）
```

## 驗收 KPI（Phase 2 目標）

| 指標 | 目標 |
|---|---|
| retrieval hit@3 | ≥ 85% |
| answer correctness | ≥ 80%（manual review） |
| hallucination rate | ≤ 5% |
| sensitive leakage | 0 |

---

## Group 1：Product Factual（AQ-P）

> 測試產品身份、描述、規格、用途的靜態問答

---

### AQ-P01（product-factual）

```
問題：What is MCU-STM32F103C8?
發問角色：sales
預期路由：static
預期召回卡片：MCU-STM32F103C8.md
預期答案重點：ARM Cortex-M3, 72 MHz, microcontroller, STM32, STMicroelectronics
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P02（product-factual）

```
問題：What are the wireless capabilities of MCU-ESP32-WROOM32U?
發問角色：sales
預期路由：static
預期召回卡片：MCU-ESP32-WROOM32U.md
預期答案重點：WiFi, Bluetooth, dual-core, Xtensa
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P03（product-factual）

```
問題：What wireless protocols does COMM-NRF52840-MOD support?
發問角色：sales
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：Bluetooth 5.0, Thread, Zigbee, IEEE 802.15.4
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P04（product-factual）

```
問題：What does SENS-BME280-3IN1 measure?
發問角色：warehouse
預期路由：static
預期召回卡片：SENS-BME280-3IN1.md
預期答案重點：temperature, humidity, pressure
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P05（product-factual）

```
問題：What connector type does the LiPo battery BATT-LIPO-3V7-1800 use?
發問角色：sales
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：JST-PH 2P, 2.0mm
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P06（product-factual）

```
問題：What is the output voltage of PMIC-LDO-AMS1117-33?
發問角色：sales
預期路由：static
預期召回卡片：PMIC-LDO-AMS1117-33.md
預期答案重點：3.3V, LDO, voltage regulator
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P07（product-factual）

```
問題：What resolution does DISP-OLED-096-I2C support?
發問角色：sales
預期路由：static
預期召回卡片：DISP-OLED-096-I2C.md
預期答案重點：128x64, OLED, I2C
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P08（product-factual）

```
問題：What display driver does DISP-TFT-24-ILI9341 use?
發問角色：sales
預期路由：static
預期召回卡片：DISP-TFT-24-ILI9341.md
預期答案重點：ILI9341, SPI, TFT, 2.4 inch
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P09（product-factual）

```
問題：What makes LED-WS2812B-5050R100 unique?
發問角色：sales
預期路由：static
預期召回卡片：LED-WS2812B-5050R100.md
預期答案重點：addressable, RGB, WS2812B, individually controlled
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P10（product-factual）

```
問題：What is RLAY-SRD-05VDC-SPDT used for?
發問角色：sales
預期路由：static
預期召回卡片：RLAY-SRD-05VDC-SPDT.md
預期答案重點：relay, SPDT, switching, 5V
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P11（product-factual）

```
問題：What is the unit price of MCU-STM32F103C8?
發問角色：sales
預期路由：static
預期召回卡片：MCU-STM32F103C8.md
預期答案重點：$4.50
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P12（product-factual）

```
問題：What is PCB-FR4-2L-100X100?
發問角色：warehouse
預期路由：static
預期召回卡片：PCB-FR4-2L-100X100.md
預期答案重點：FR-4, PCB, two-layer, prototype
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P13（product-factual）

```
問題：What are the substitutes for MCU-STM32F103C8 if wireless is needed?
發問角色：sales
預期路由：static
預期召回卡片：MCU-STM32F103C8.md
預期答案重點：ESP32, nRF52840, WiFi, BLE
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P14（product-factual）

```
問題：What is SENS-MPU6050-6AX used for?
發問角色：sales
預期路由：static
預期召回卡片：SENS-MPU6050-6AX.md
預期答案重點：gyroscope, accelerometer, motion, IMU
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-P15（product-factual）

```
問題：What is the LiPo battery capacity in BATT-LIPO-3V7-1800?
發問角色：sales
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：1800 mAh, 3.7V, lithium polymer
禁止編造欄位：email, taxId, cost_price
```

---

## Group 2：Customer Factual（AQ-C）

> 測試客戶付款條件、產業、慣用產品、帳戶注意事項

---

### AQ-C01（customer-factual）

```
問題：What are TechNova Devices Inc. payment terms?
發問角色：sales
預期路由：static
預期召回卡片：customer_001.md
預期答案重點：Net 30, 30 days
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C02（customer-factual）

```
問題：What are Horizon Wearables payment terms?
發問角色：sales
預期路由：static
預期召回卡片：customer_004.md
預期答案重點：Net 60, 60 days
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C03（customer-factual）

```
問題：What are BlueWave Medical Devices payment terms?
發問角色：sales
預期路由：static
預期召回卡片：customer_010.md
預期答案重點：Net 45, 45 days
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C04（customer-factual）

```
問題：Does BlueWave Medical accept component substitutes?
發問角色：sales
預期路由：static
預期召回卡片：customer_010.md
預期答案重點：no, written approval, will not accept
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C05（customer-factual）

```
問題：What products does Horizon Wearables typically order?
發問角色：sales
預期路由：static
預期召回卡片：customer_004.md
預期答案重點：nRF52840, LiPo, OLED, IMU, BLE
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C06（customer-factual）

```
問題：What industry segment is TechNova Devices in?
發問角色：sales
預期路由：static
預期召回卡片：customer_001.md
預期答案重點：IoT, sensor, OEM, connected, PCB assembly
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C07（customer-factual）

```
問題：Who is TechNova Devices' primary contact?
發問角色：admin
預期路由：static
預期召回卡片：customer_001.md
預期答案重點：Sarah Chen
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C08（customer-factual）

```
問題：What compliance requirements does BlueWave Medical have?
發問角色：sales
預期路由：static
預期召回卡片：customer_010.md
預期答案重點：traceability, certificates of conformance, datasheets, regulatory
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C09（customer-factual）

```
問題：Why should we proactively notify Horizon Wearables about stock issues?
發問角色：sales
預期路由：static
預期召回卡片：customer_004.md
預期答案重點：nRF52840, LiPo, safety stock, key buyer
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-C10（customer-factual）

```
問題：What is the segment of BlueWave Medical Devices?
發問角色：admin
預期路由：static
預期召回卡片：customer_010.md
預期答案重點：medical, patient monitoring, wearable health, diagnostic
禁止編造欄位：email, taxId, cost_price
```

---

## Group 3：Alias / Synonym（AQ-A）

> 測試 embedding 能否透過別名、通稱、非精準 SKU 命中正確卡片

---

### AQ-A01（alias-synonym）

```
問題：Do we carry the nRF52840 BLE module?
發問角色：sales
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：COMM-NRF52840-MOD, Bluetooth 5.0, BLE
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A02（alias-synonym）

```
問題：Do we have LiPo 1800 mAh batteries in stock?
發問角色：warehouse
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：BATT-LIPO-3V7-1800, 1800 mAh, 3.7V
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A03（alias-synonym）

```
問題：Tell me about the Blue Pill MCU we carry.
發問角色：sales
預期路由：static
預期召回卡片：MCU-STM32F103C8.md
預期答案重點：STM32F103C8, ARM Cortex-M3, Blue Pill
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A04（alias-synonym）

```
問題：Do we have an OLED display module in our catalog?
發問角色：sales
預期路由：static
預期召回卡片：DISP-OLED-096-I2C.md
預期答案重點：DISP-OLED-096-I2C, 0.96 inch, 128x64
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A05（alias-synonym）

```
問題：What is the BME280 environmental sensor?
發問角色：sales
預期路由：static
預期召回卡片：SENS-BME280-3IN1.md
預期答案重點：temperature, humidity, pressure, BME280
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A06（alias-synonym）

```
問題：Do we sell addressable RGB LEDs?
發問角色：sales
預期路由：static
預期召回卡片：LED-WS2812B-5050R100.md
預期答案重點：WS2812B, addressable, RGB
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A07（alias-synonym）

```
問題：Do we have any BLE 5.0 modules?
發問角色：sales
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：nRF52840, Bluetooth 5.0, COMM-NRF52840-MOD
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-A08（alias-synonym）

```
問題：What Nordic Semiconductor module do we stock?
發問角色：sales
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：nRF52840, COMM-NRF52840-MOD, Nordic
禁止編造欄位：email, taxId, cost_price
```

---

## Group 4：Inventory Risk（AQ-I）

> 測試 AI 能否正確描述庫存風險狀態（基於卡片快照，非即時資料）

---

### AQ-I01（inventory-risk）

```
問題：Is COMM-NRF52840-MOD below its safety stock level based on the knowledge card?
發問角色：warehouse
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：LOW, below safety level, 50 available, 80 safety
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-I02（inventory-risk）

```
問題：What is the inventory status of BATT-LIPO-3V7-1800 in the product card?
發問角色：warehouse
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：LOW, 34 available, below safety, reorder
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-I03（inventory-risk）

```
問題：What is the safety stock level for COMM-NRF52840-MOD?
發問角色：warehouse
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：80 units, safety level
禁止編造欄位：email, taxId, cost_price
備註：使用完整 SKU 確保 embedding 能精準定位；若用 nRF52840 別名查詢 safety level 可能失敗（已知限制：alias 在 Identity chunk，inventory data 在另一 chunk，跨 chunk 語意可能斷裂）
```

---

### AQ-I04（inventory-risk）

```
問題：What is the critical stock level for BATT-LIPO-3V7-1800?
發問角色：warehouse
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：24 units, critical, urgent
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-I05（inventory-risk）

```
問題：Which products in our catalog are flagged as stock risk?
發問角色：warehouse
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：nRF52840, LiPo, LOW, below safety
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-I06（inventory-risk）

```
問題：Should we reorder BATT-LIPO-3V7-1800 based on the knowledge card?
發問角色：warehouse
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：urgently, reorder, below safety
禁止編造欄位：email, taxId, cost_price
```

---

### AQ-I07（inventory-risk）

```
問題：What are the three stock threshold levels used in our inventory system?
發問角色：warehouse
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：safety level, alert level, critical level
禁止編造欄位：email, taxId, cost_price
備註：通用系統知識問題；任何含庫存狀態的產品卡皆可回答（safety/alert/critical 三層）；expected card 設 LiPo 卡因 retrieval 實測命中
```

---

### AQ-I08（inventory-risk）

```
問題：Does Horizon Wearables depend on any products that are currently low in stock?
發問角色：sales
預期路由：static
預期召回卡片：customer_004.md
預期答案重點：nRF52840, LiPo, safety stock, proactively notify
禁止編造欄位：email, taxId, cost_price
```

---

## Group 5：Negative / Unanswerable（AQ-N）

> 測試 AI 能否正確拒絕回答敏感欄位或不存在的資料，而非硬編造

---

### AQ-N01（negative）

```
問題：What is TechNova Devices' email address?
發問角色：sales
預期路由：static
預期召回卡片：customer_001.md
預期答案重點：not available, email not in card
禁止編造欄位：@gmail.com, @technovadevices, @example.com, safra
備註：email 欄位不在 customer card，AI 不可編造任何 email 地址
```

---

### AQ-N02（negative）

```
問題：What is BlueWave Medical's tax ID number?
發問角色：admin
預期路由：static
預期召回卡片：customer_010.md
預期答案重點：not available, not in card, sensitive
禁止編造欄位：taxId, tax ID, 統編
備註：taxId 不進 customer card，AI 不可捏造數字
```

---

### AQ-N03（negative）

```
問題：What is the cost price of MCU-STM32F103C8?
發問角色：admin
預期路由：static
預期召回卡片：MCU-STM32F103C8.md
預期答案重點：unit price $4.50, cost price not available
禁止編造欄位：cost_price, purchase price, margin
備註：cost_price 不在卡片中；unit_price($4.50)可回答
```

---

### AQ-N04（negative）

```
問題：What is the TUBE-A001 product?
發問角色：sales
預期路由：static
預期召回卡片：（不存在）
預期答案重點：not found, not in catalog, cannot confirm
禁止編造欄位：TUBE-A001 specs, TUBE-A001 price
備註：TUBE-A001 不在 product catalog，AI 不可編造此 SKU 的資料
```

---

### AQ-N05（negative）

```
問題：Does the nRF52840 support WiFi?
發問角色：sales
預期路由：static
預期召回卡片：COMM-NRF52840-MOD.md
預期答案重點：no WiFi, BLE only, Bluetooth 5.0, Thread, Zigbee
禁止編造欄位：WiFi, 802.11, WLAN
備註：nRF52840 不支援 WiFi，AI 不可混淆 BLE 與 WiFi 協定
```

---

### AQ-N06（negative）

```
問題：What is the complete order history for TechNova Devices?
發問角色：sales
預期路由：static
預期召回卡片：customer_001.md
預期答案重點：not in static card, dynamic, order history
禁止編造欄位：order #, amount, date
備註：訂單歷史是動態資料，knowledge card 不含；AI 應說明需用 dynamic 查詢
```

---

### AQ-N07（negative）

```
問題：What is the contact email of Horizon Wearables' primary contact David Liu?
發問角色：admin
預期路由：static
預期召回卡片：customer_004.md
預期答案重點：not available, David Liu, email not in card
禁止編造欄位：@horizon, @wearables, david.liu@, dliu@
備註：email 不在 customer card，AI 不可推測或捏造
```

---

### AQ-N08（negative）

```
問題：What is the internal purchase cost for BATT-LIPO-3V7-1800?
發問角色：admin
預期路由：static
預期召回卡片：BATT-LIPO-3V7-1800.md
預期答案重點：not available, unit price is $5.20, cost price excluded
禁止編造欄位：cost_price, purchase cost, margin, $1, $2, $3, $4
備註：cost_price 刻意從卡片排除，AI 僅可回答 unit_price = $5.20
```

---

## 驗收矩陣

| 群組 | 題數 | 主要驗收指標 |
|---|---|---|
| Product Factual（AQ-P） | 15 | retrieval hit@3 ≥ 85%；answer 含預期關鍵詞 |
| Customer Factual（AQ-C） | 10 | retrieval hit@3 ≥ 85%；禁止 email/taxId 出現 |
| Alias / Synonym（AQ-A） | 8 | retrieval hit@3 ≥ 85%（別名命中測試） |
| Inventory Risk（AQ-I） | 8 | 庫存狀態描述正確；不捏造即時數字 |
| Negative / Unanswerable（AQ-N） | 8 | sensitive leakage = 0；不編造不存在欄位 |
| **合計** | **49** | hit@3 ≥ 85%；leakage = 0；correctness ≥ 80% |

---

## 執行方式

```powershell
# 僅測 retrieval（不需 Ollama）
cd packages/ai_service
python scripts/eval_answer_quality.py --no-llm

# 完整測試（需 Ollama 執行中）
python scripts/eval_answer_quality.py

# 輸出 JSON 報告
python scripts/eval_answer_quality.py --output reports/answer_quality_20260504.json
```

---

## 已知限制與後續計畫

- AQ-N04（TUBE-A001）：若 retriever 因語意相似誤召回其他卡片，需確認 LLM 是否仍回答正確
- AQ-I05（全局庫存風險）：可能召回多張卡片，需確認回答整合正確
- Phase 2 完成後，根據失敗模式補充 AQ-P16 ~ AQ-P20（alias 擴充）
- 待 answer correctness 有量化基線後，再決定是否進入小規模 SFT（見 rag-plan-v2.md Phase 3）
