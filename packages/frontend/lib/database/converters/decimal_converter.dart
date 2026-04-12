import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

class DecimalConverter extends TypeConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) {
    return Decimal.parse(fromDb);
  }

  @override
  String toSql(Decimal value) {
    // 確保永遠輸出兩位小數，符合後端 pattern: '^\d+\.\d{2}$'
    return value.toStringAsFixed(2);
  }
}
