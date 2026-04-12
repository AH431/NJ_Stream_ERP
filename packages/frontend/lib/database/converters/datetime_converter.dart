import 'package:drift/drift.dart';

/// Drift TypeConverter：在 SQLite TEXT 欄位與 Dart DateTime 之間轉換
///
/// 為什麼不用 Drift 內建的 DateTimeColumn（INTEGER unix timestamp）：
///   後端所有時間欄位均以 ISO-8601 UTC 字串傳輸（e.g. "2026-04-12T08:30:00.000Z"）
///   若本地存 INTEGER 而後端傳字串，Sync 時需額外轉換，容易產生時區誤差。
///   直接存字串，DB 內容與 API payload 格式一致，除錯更直觀。
///
/// 時區規則：
///   - fromSql：DateTime.parse 會保留原始時區資訊（Z = UTC）
///   - toSql：強制轉換為 UTC 再序列化，防止本地時區混入
///
/// 使用範例（schema.dart）：
///   DateTimeColumn get updatedAt => dateTime().map(const Iso8601DateTimeConverter())();
class Iso8601DateTimeConverter extends TypeConverter<DateTime, String> {
  const Iso8601DateTimeConverter();

  /// DB 字串 → Dart DateTime
  /// e.g. "2026-04-12T08:30:00.000Z" → DateTime(2026, 4, 12, 8, 30, 0, 0, isUtc: true)
  @override
  DateTime fromSql(String fromDb) {
    return DateTime.parse(fromDb);
  }

  /// Dart DateTime → DB 字串（強制 UTC）
  /// e.g. DateTime.now() → "2026-04-12T08:30:00.000Z"
  @override
  String toSql(DateTime value) {
    return value.toUtc().toIso8601String();
  }
}
