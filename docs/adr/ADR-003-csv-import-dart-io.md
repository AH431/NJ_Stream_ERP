# ADR-003：CSV Import 使用 dart:io 資料夾掃描，取代 FilePicker

**日期**：2026-04-20（重構）  
**狀態**：已採用  
**決策者**：Sprint 5

---

## 背景

### 時間線

| 日期 | 事件 |
|------|------|
| 4/16 | Issue #16 初版：使用 `file_picker` 套件，使用者點選 CSV 上傳 |
| 4/17 | 實機測試（Sony XA1 Android 8）：點選後 `file_picker` 回傳 `null`，上傳永遠不觸發 |
| 4/18 | 引入 `open_filex`，為此在 `AndroidManifest.xml` 新增 `FileProvider` |
| 4/20 | 診斷確認：`file_paths.xml` 未涵蓋 `/sdcard/Download/`，FileProvider 拋出 `IllegalArgumentException`，`file_picker` 靜默捕捉後回傳 `null` |

### 根本原因

Android 8.0 上的 `file_picker` 在處理外部儲存路徑時，需要 `FileProvider` 建立可分享 URI。
`file_paths.xml` 原本只涵蓋 `cache-path`，未涵蓋 `external-path`（`/sdcard/`），
導致 `FileProvider.getUriForFile()` 拋出 `IllegalArgumentException`，
`file_picker` 靜默捕捉後回傳 `null`。

---

## 決策

**放棄 FilePicker，改用 `dart:io` 直接讀取本機路徑（資料夾掃描流程）。**

### 新流程

```
使用 adb push 將 CSV 推送到 App 的 external storage 目錄
  ↓
App 啟動時自動呼叫 getExternalStorageDirectory()
  ↓
掃描 csv/ 資料夾，列出符合類型關鍵字的 .csv 檔
  ↓
使用者點選 → Radio 選中 + 前 8 行預覽
  ↓
點「確認匯入」→ File.readAsBytes() → uploadImportCsv()
```

### 關鍵技術決策

- 使用 `getExternalStorageDirectory()`（path_provider，已有相依）取得 App 自身 external storage
- **無需 `READ_EXTERNAL_STORAGE` 權限**（App 只讀取自己的目錄）
- `dart:io` 的 `File.readAsBytes()` 完全繞過 FileProvider URI 機制
- `FileSystemException` 完整包在 try-catch，OS error message 顯示於 UI

---

## 理由

| 替代方案 | 排除原因 |
|---------|---------|
| 修復 `file_paths.xml`（加入 `external-path`） | 已嘗試，但 Sony XA1 Android 8 上 `file_picker` 的 Activity recreation 問題仍存在，不夠穩定 |
| 使用 `flutter_file_dialog` | 另一個 FilePicker 替代品，同樣依賴 Android Intent，相同的設備相容性風險 |
| Content Provider / SAF | Android Storage Access Framework，複雜度高，且 MVP 場景（內部操作人員）不需要如此通用的存取機制 |

ERP 的 CSV Import 屬於**管理員操作**，使用 adb push 前置步驟是可接受的工作流程（不是一般使用者功能）。

---

## 後果

**正面**
- 完全繞過 FileProvider / Android Intent，無設備相容性問題
- 使用者可預覽檔案內容再確認，比 FilePicker 直接選取更安全
- 資料夾掃描自動過濾類型，減少選錯檔案的機率
- 無需額外 Android 權限

**負面**
- 需要額外的 `adb push` 前置步驟（非一般使用者友善）
- 只能讀取 App 自身 external storage 目錄（不能任意選系統其他位置的檔案）
- 資料夾名稱為 `csv`，adb push 目標路徑固定

---

## 正式環境考量

若未來需要讓非技術人員使用 CSV Import：
1. 在 App 內建立 FTP / WebDAV 接收伺服器（最簡單）
2. 改用 Content URI 並完整處理 Android 版本差異
3. 提供 Web 後台上傳 CSV（繞過 App 完全處理）

---

## 相關文件

- `LOG/daily/2026-04-20.md`（根因診斷過程）
- `CHANGELOG.md` Sprint 5 — CSV Import 修復
- `packages/frontend/android/app/src/main/res/xml/file_paths.xml`