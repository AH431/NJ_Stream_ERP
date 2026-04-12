// ==============================================================================
// 全域常數（App 生命週期不變的設定值）
// ==============================================================================
//
// 使用方式：
//   開發環境（預設）：直接 flutter run
//   正式環境：flutter run --dart-define=API_BASE_URL=https://api.nj-stream.com
//
// 為什麼用 --dart-define 而不是 .env 檔：
//   - Flutter 無法在 Dart 層直接讀取 .env（需要額外 plugin）
//   - --dart-define 在編譯時注入，不需要額外依賴，也不會洩漏到版控
//   - 後端使用 .env，前端使用 --dart-define，兩者職責清楚分離

/// 後端 API 基礎 URL
/// 透過 --dart-define=API_BASE_URL=https://... 在建置時覆寫
/// 未設定時預設指向本機開發後端
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

/// HTTP 連線逾時（從發出請求到伺服器回應第一個 byte）
/// 15 秒：考量台灣中小企業的網路環境，偶發性延遲允許稍長等待
const Duration kConnectTimeout = Duration(seconds: 15);

/// HTTP 接收逾時（從第一個 byte 到接收完整 response body）
/// sync/push 最多 50 筆 operation，response 不大，15 秒足夠
const Duration kReceiveTimeout = Duration(seconds: 15);
