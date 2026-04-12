/// 以 --dart-define=API_BASE_URL=https://... 覆寫
/// 未提供時預設指向本機後端（開發用）
const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000',
);

const Duration kConnectTimeout = Duration(seconds: 15);
const Duration kReceiveTimeout = Duration(seconds: 15);
