# Sony XA1 實機部署步驟 — Issue #14 Phase 0 Option B

對應 `Issue14_task.md` Phase 0-4 Option B（實體 Android 裝置 USB 除錯）。

**執行順序**：H-1 → H-2 → H-3 → H-4 → H-5 → H-6 → H-7  
H-1、H-2 為一次性前置設定，完成後之後每次只需執行 H-3 以後的步驟。

---

## H-1：安裝完整 Android SDK（一次性，當前阻塞點）

> 目前 `C:\Users\archi\OneDrive\Documents\軟體_驅動程式\platform-tools` 只有 `adb.exe`，
> 缺少 `cmdline-tools`、`build-tools`、`platforms`，`flutter run` 無法編譯 APK。

### 1-1. 下載 Command-line tools

前往 Android 官網下載 **Command-line tools only**（Windows）：  
`commandlinetools-win-*_latest.zip`

解壓後，建立以下資料夾結構（**路徑不能含空格**）：

```
C:\Android\
  cmdline-tools\
    latest\          ← 將解壓出的 cmdline-tools 內容放在這裡
      bin\
      lib\
      ...
  platform-tools\    ← 可沿用現有的，或讓 sdkmanager 重新下載
```

### 1-2. 設定環境變數

以系統管理員身份開啟 PowerShell：

```powershell
[System.Environment]::SetEnvironmentVariable("ANDROID_HOME", "C:\Android", "Machine")
[System.Environment]::SetEnvironmentVariable("ANDROID_SDK_ROOT", "C:\Android", "Machine")

# 取得現有 Path 並附加
$oldPath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
$newPath = $oldPath + ";C:\Android\cmdline-tools\latest\bin;C:\Android\platform-tools"
[System.Environment]::SetEnvironmentVariable("Path", $newPath, "Machine")
```

**重開 PowerShell** 後確認生效：

```powershell
echo $env:ANDROID_HOME    # 應輸出 C:\Android
sdkmanager --version      # 應輸出版本號，不報錯
```

### 1-3. 安裝 SDK 元件

```powershell
sdkmanager "platform-tools" "platforms;android-33" "build-tools;33.0.2"
sdkmanager --licenses     # 全部輸入 y 接受
```

### 1-4. 驗收

```powershell
cd c:\Projects\NJ_Stream_ERP\packages\frontend
flutter doctor -v
```

**預期**：`[√] Android toolchain` — 不再出現 `cmdline-tools component is missing`。

---

## H-2：建立 Android Runner（一次性）

> `packages/frontend/android/` 目前不存在，必須先產生才能編譯 APK。

```powershell
cd c:\Projects\NJ_Stream_ERP\packages\frontend
flutter create --platforms=android .
```

完成後修改 `android/app/build.gradle`，確認：

```gradle
minSdkVersion 23
```

> **注意**：`flutter create` 預設產生 `minSdkVersion 21`，但本專案使用
> `flutter_secure_storage ^9.2.0`（EncryptedSharedPreferences），**硬性需要 API 23**。
> 若預設為 21，手動改為 23。

確認 `.gitignore` 已涵蓋（`flutter create` 通常自動加入）：

```
android/.gradle/
android/app/build/
```

---

## H-3：手機實體設定（Sony XA1）

每次測試前確認以下狀態：

1. 設定 → 關於手機 → 連續點擊「版本號碼」7 次 → 啟用開發者模式
2. 開發者選項 → 確認「USB 偵錯」已開啟
3. （選做）開啟「充電時保持螢幕喚醒」— 方便長時間觀察 Console 日誌

---

## H-4：USB 連線與授權

1. 用**具資料傳輸功能的 USB 線**接上電腦

   > Sony XA1 對線材品質敏感，若 `adb devices` 看不到裝置，優先換線。

2. 手機跳出「是否允許 USB 偵錯？」→ 勾選「**永遠允許此電腦**」→ 確定

3. 驗證連線：

   ```powershell
   adb devices
   ```

   | 輸出狀態 | 說明 |
   |----------|------|
   | `CB5A1TXXXX    device` | 正常，記下序號供 H-7 使用 |
   | `CB5A1TXXXX    unauthorized` | 手機上尚未確認授權，重新確認彈出視窗 |
   | 空列表 | USB 線問題或驅動問題，換線或重插 |

---

## H-5：確認手機與電腦在同一 Wi-Fi 網段

```powershell
ipconfig
```

找「無線區域網路 Wi-Fi」的 **IPv4 位址**（例如：`192.168.1.105`）。

> 手機必須連接到**與電腦相同的 Wi-Fi**，否則手機無法連到後端 `:3000`。

---

## H-6：啟動後端

```powershell
cd c:\Projects\NJ_Stream_ERP\packages\backend
npm run dev
```

確認輸出含：

```
Server listening at http://0.0.0.0:3000
```

若防火牆阻擋手機連入，允許通訊埠 `3000` 通過區域網路：

```powershell
# 以系統管理員身份執行
netsh advfirewall firewall add rule name="NJ ERP Dev" dir=in action=allow protocol=TCP localport=3000
```

---

## H-7：編譯並部署 App 至手機

```powershell
cd c:\Projects\NJ_Stream_ERP\packages\frontend

# 將 192.168.1.105 換成 H-5 查到的 IPv4
# 將 CB5A1TXXXX 換成 H-4 adb devices 查到的序號
flutter run `
  --dart-define=API_BASE_URL=http://192.168.1.105:3000 `
  -d CB5A1TXXXX
```

| 狀態 | 說明 |
|------|------|
| 第一次編譯 | 約 3–5 分鐘，系統產生 APK 並推送至手機 |
| 成功標誌 | 手機螢幕自動亮起，進入 App 登入畫面 |
| 紅字報錯 | 查看 Console，常見原因見下方排除表 |

---

## 常見問題排除

| 問題 | 解法 |
|------|------|
| `adb devices` 空列表 | 換 USB 線（需支援資料傳輸），重插後再確認授權彈窗 |
| `adb devices` 顯示 `unauthorized` | 手機解鎖，重新確認「允許 USB 偵錯」對話框 |
| App 顯示 Network Error | 確認手機與電腦同一 Wi-Fi；確認防火牆已開放 3000 port（見 H-6）|
| `flutter run` 報 `minSdkVersion` 錯誤 | 確認 `android/app/build.gradle` 中 `minSdkVersion 23` |
| `flutter run` 報 `No connected devices` | 確認 `-d` 後的序號正確，或重執行 `adb devices` 取得最新序號 |
| 安裝失敗（空間不足）| 手機保留 10.8 GB，空間足夠；執行 `adb uninstall com.example.frontend` 清除舊殘留 |
| `sdkmanager` 找不到指令 | 確認 H-1-2 環境變數已設定，且已重開 PowerShell |

---

## 執行順序小結

```
H-1 安裝 Android SDK（一次性）
  ↓
H-2 建立 android/ runner（一次性）
  ↓
H-3 確認手機開發者模式
  ↓
H-4 USB 連線 + adb devices 驗證
  ↓
H-5 取得電腦 Wi-Fi IPv4
  ↓
H-6 啟動後端（npm run dev）
  ↓
H-7 flutter run --dart-define=API_BASE_URL=http://<IP>:3000 -d <serial>
  ↓
進入 Issue14_task.md Phase 1（離線建單）
```
