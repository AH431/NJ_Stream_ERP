import 'package:drift/drift.dart';

class Iso8601DateTimeConverter extends TypeConverter<DateTime, String> {
  const Iso8601DateTimeConverter();

  @override
  DateTime fromSql(String fromDb) {
    return DateTime.parse(fromDb);
  }

  @override
  String toSql(DateTime value) {
    // 確保輸出 UTC ISO-8601，符合後端 updated_at 格式
    return value.toUtc().toIso8601String();
  }
}
