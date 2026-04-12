// ==============================================================================
// QuotationListScreen — 報價單列表（Issue #8 Phase 4）
//
// 功能：
//   - StreamBuilder 監聽 watchActiveQuotations()（deleted_at IS NULL）
//   - 每列顯示客戶名（從 customerMap 查詢）、totalAmount、狀態 Chip、離線 icon
//   - 軟刪除（sales / admin，converted 不可刪）
//   - 轉訂單（draft / sent，convertedToOrderId == null）
// ==============================================================================

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../providers/sync_provider.dart';

class QuotationListScreen extends StatefulWidget {
  const QuotationListScreen({super.key});

  @override
  State<QuotationListScreen> createState() => _QuotationListScreenState();
}

class _QuotationListScreenState extends State<QuotationListScreen> {
  /// 快取 customerId → customerName，一次查詢後存放，避免 N+1
  Map<int, String> _customerMap = {};
  bool _customerMapLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCustomerMap();
  }

  Future<void> _loadCustomerMap() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final customers = await db.getActiveCustomers();
    if (!mounted) return;
    setState(() {
      _customerMap = {for (final c in customers) c.id: c.name};
      _customerMapLoaded = true;
    });
  }

  // --------------------------------------------------------------------------
  // 狀態 Chip 顏色
  // --------------------------------------------------------------------------

  Color _chipColor(String status) {
    return switch (status) {
      'draft'     => Colors.grey,
      'sent'      => Colors.blue,
      'converted' => Colors.green,
      'expired'   => Colors.orange,
      _           => Colors.grey,
    };
  }

  String _chipLabel(String status) {
    return switch (status) {
      'draft'     => '草稿',
      'sent'      => '已發送',
      'converted' => '已轉訂',
      'expired'   => '已過期',
      _           => status,
    };
  }

  // --------------------------------------------------------------------------
  // 軟刪除確認
  // --------------------------------------------------------------------------

  Future<void> _confirmDelete(
    BuildContext context,
    AppDatabase db,
    SyncProvider sync,
    Quotation quotation,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認刪除'),
        content: const Text('刪除後無法復原，確定要刪除此報價單嗎？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final now = DateTime.now().toUtc();
    await db.softDeleteQuotation(quotation.id, now);

    final payload = {
      'id': quotation.id,
      'customerId': quotation.customerId,
      'createdBy': quotation.createdBy,
      'items': quotation.items,
      'totalAmount': quotation.totalAmount,
      'taxAmount': quotation.taxAmount,
      'status': quotation.status,
      'convertedToOrderId': quotation.convertedToOrderId,
      'createdAt': quotation.createdAt.toUtc().toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': now.toIso8601String(),
    };
    await sync.enqueueDelete('quotation', quotation.id, payload);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('報價單已刪除，待下次同步')),
      );
    }
  }

  // --------------------------------------------------------------------------
  // 轉訂單
  // --------------------------------------------------------------------------

  Future<void> _convertToOrder(
    BuildContext context,
    AppDatabase db,
    SyncProvider sync,
    Quotation quotation,
  ) async {
    // 樂觀更新本地狀態
    await db.updateQuotationStatus(quotation.id, 'converted');

    final now = DateTime.now().toUtc();
    final localOrderId = SyncProvider.nextLocalId();

    // 插入本地臨時銷售訂單（id < 0）
    await db.insertSalesOrder(SalesOrdersCompanion(
      id: Value(localOrderId),
      quotationId: Value(quotation.id),
      customerId: Value(quotation.customerId),
      createdBy: Value(sync.userId!),
      status: const Value('pending'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));

    // 排入同步佇列
    final payload = {
      'id': localOrderId,
      'quotationId': quotation.id,
      'customerId': quotation.customerId,
      'createdBy': sync.userId,
      'status': 'pending',
      'confirmedAt': null,
      'shippedAt': null,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': null,
    };
    await sync.enqueueCreate('sales_order', payload);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('轉訂單已排入待同步佇列')),
      );
    }
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final db   = Provider.of<AppDatabase>(context, listen: false);
    final sync = Provider.of<SyncProvider>(context, listen: false);
    final role = sync.role;

    if (!_customerMapLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return StreamBuilder<List<Quotation>>(
      stream: db.watchActiveQuotations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final quotations = snapshot.data ?? [];
        if (quotations.isEmpty) {
          return const Center(child: Text('尚無報價單'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(8),
          itemCount: quotations.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final q = quotations[index];
            final customerName = _customerMap[q.customerId] ?? '(客戶 ${q.customerId})';
            final canDelete = (role == 'sales' || role == 'admin') &&
                q.status != 'converted';
            final canConvert = (role == 'sales' || role == 'admin') &&
                (q.status == 'draft' || q.status == 'sent') &&
                q.convertedToOrderId == null &&
                q.id > 0; // 尚未同步的本地臨時單不可轉單

            return ListTile(
              title: Text(customerName),
              subtitle: Text('合計：${q.totalAmount}'),
              leading: q.id < 0
                  ? const Icon(Icons.cloud_upload_outlined, color: Colors.orange)
                  : const Icon(Icons.cloud_done_outlined, color: Colors.green),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 狀態 Chip
                  Chip(
                    label: Text(
                      _chipLabel(q.status),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                    backgroundColor: _chipColor(q.status),
                    padding: EdgeInsets.zero,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  // 轉訂單
                  if (canConvert)
                    IconButton(
                      icon: const Icon(Icons.swap_horiz),
                      tooltip: '轉訂單',
                      onPressed: () => _convertToOrder(context, db, sync, q),
                    ),
                  // 軟刪除
                  if (canDelete)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '刪除',
                      onPressed: () => _confirmDelete(context, db, sync, q),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
