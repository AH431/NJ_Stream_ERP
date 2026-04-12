import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

/// Drift TypeConverter：在 SQLite TEXT 欄位與 Dart Decimal 型別之間轉換
///
/// 為什麼不用 REAL（浮點數）：
///   浮點數在金額運算中會產生誤差（e.g. 0.1 + 0.2 ≠ 0.3）
///   後端以字串格式儲存金額（"158000.00"），前端同樣用字串存 SQLite，
///   確保前後端金額表示完全一致。
///
/// 使用範例（schema.dart）：
///   TextColumn get unitPrice => text().map(const DecimalConverter())();
///
/// 注意：const 建構子讓 Drift codegen 可以把 converter 視為編譯期常數，
/// 不需在每次存取時重新建立物件。
class DecimalConverter extends TypeConverter<Decimal, String> {
  const DecimalConverter();

  /// DB 字串 → Dart Decimal
  /// e.g. "158000.00" → Decimal.parse("158000.00")
  @override
  Decimal fromSql(String fromDb) {
    return Decimal.parse(fromDb);
  }

  /// Dart Decimal → DB 字串
  /// 強制輸出兩位小數，確保符合後端 pattern: ^\d+\.\d{2}$
  /// e.g. Decimal.parse("158000") → "158000.00"
  @override
  String toSql(Decimal value) {
    return value.toStringAsFixed(2);
  }
}
