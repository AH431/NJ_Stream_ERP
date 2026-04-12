// ==============================================================================
// QuotationDao — AppDatabase extension
//
// 設計說明：同 CustomerDao，使用 extension 而非 @DriftAccessor。
//
// items 欄位儲存設計：
//   Quotations.items 為 TEXT 欄（不使用 Drift 關聯表），
//   儲存序列化後的 JSON 字串，格式由 QuotationItemModel 控制。
//   優點：報價草稿階段結構鬆散，JSON 降低表關聯複雜度。
//   轉訂單後由前端解析 JSON → 寫入 SalesOrders + OrderItems。
//
// 稅額邏輯（強制規範）：
//   taxAmount = subtotalSum × 0.05（含稅）或 0.00（未稅）
//   totalAmount = subtotalSum + taxAmount
//   所有金額以 Decimal 計算，最終以 "xxx.xx" 字串存 DB。
// ==============================================================================

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

import '../database.dart';

// ==============================================================================
// QuotationItemModel — items JSON 欄位的序列化 helper（不進 Drift schema）
// ==============================================================================

class QuotationItemModel {
  final int productId;
  final int quantity;
  final String unitPrice; // "100.00"
  final String subtotal;  // "200.00"

  const QuotationItemModel({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.subtotal,
  });

  factory QuotationItemModel.fromJson(Map<String, dynamic> json) =>
      QuotationItemModel(
        productId: json['productId'] as int,
        quantity:  json['quantity']  as int,
        unitPrice: json['unitPrice'] as String,
        subtotal:  json['subtotal']  as String,
      );

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'quantity':  quantity,
        'unitPrice': unitPrice,
        'subtotal':  subtotal,
      };

  /// DB TEXT 欄 → Dart List
  static List<QuotationItemModel> fromJsonString(String jsonStr) {
    if (jsonStr.isEmpty || jsonStr == '[]') return [];
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list
        .map((e) => QuotationItemModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Dart List → DB TEXT 欄
  static String toJsonString(List<QuotationItemModel> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  /// 動態計算小計（Decimal 精算）
  Decimal get subtotalDecimal =>
      (Decimal.tryParse(unitPrice) ?? Decimal.zero) *
      Decimal.parse(quantity.toString());
}

// ==============================================================================
// QuotationDao
// ==============================================================================

extension QuotationDao on AppDatabase {
  // --------------------------------------------------------------------------
  // Read
  // --------------------------------------------------------------------------

  /// 監聽未軟刪除的報價清單，依 updatedAt 降序排列。
  Stream<List<Quotation>> watchActiveQuotations() {
    return (select(quotations)
          ..where((t) => t.deletedAt.isNull())
          ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)]))
        .watch();
  }

  // --------------------------------------------------------------------------
  // Write
  // --------------------------------------------------------------------------

  /// 插入新報價（離線新增時 id 為負數臨時 id，同步後由 pull 覆蓋）
  Future<void> insertQuotation(QuotationsCompanion companion) async {
    await into(quotations).insert(companion);
  }

  /// 軟刪除：寫入 deleted_at + 更新 updatedAt
  Future<void> softDeleteQuotation(int id, DateTime deletedAt) async {
    await (update(quotations)..where((t) => t.id.equals(id))).write(
      QuotationsCompanion(
        deletedAt: Value<DateTime?>(deletedAt),
        updatedAt: Value(deletedAt),
      ),
    );
  }

  /// 樂觀更新報價狀態（轉訂單時使用）
  /// 注意：convertedToOrderId 在此不更新，Pull 後由 upsertQuotationFromServer 補齊
  Future<void> updateQuotationStatus(int id, String status) async {
    await (update(quotations)..where((t) => t.id.equals(id))).write(
      QuotationsCompanion(
        status:    Value(status),
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }

  /// 從伺服器 upsert（pull / Force Overwrite 機制使用）
  /// LWW：若本地 updatedAt 較新或相同，不覆蓋
  Future<void> upsertQuotationFromServer(QuotationsCompanion companion) async {
    return transaction(() async {
      final serverId        = companion.id.value;
      final serverUpdatedAt = companion.updatedAt.value;

      final existing = await (select(quotations)
            ..where((t) => t.id.equals(serverId)))
          .getSingleOrNull();

      if (existing != null) {
        if (existing.updatedAt.isAfter(serverUpdatedAt) ||
            existing.updatedAt.isAtSameMomentAs(serverUpdatedAt)) {
          return;
        }
      }

      await into(quotations).insertOnConflictUpdate(companion);
    });
  }

  /// 清除無對應 PendingOperation 的本地臨時報價（id < 0）
  Future<void> clearOrphanedOfflineQuotations(
      List<String> pendingRelatedIds) async {
    await (delete(quotations)
          ..where((t) => t.id.isBiggerOrEqualValue(0).not())
          ..where((t) => t.id.cast<String>().isIn(
                pendingRelatedIds.map((s) => s.split(':').last),
              ).not()))
        .go();
  }
}
