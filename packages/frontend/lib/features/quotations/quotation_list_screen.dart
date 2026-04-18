// ==============================================================================
// QuotationListScreen — 報價單列表
//
// 功能：
//   - StreamBuilder 監聽 watchActiveQuotations()（deleted_at IS NULL）
//   - 每列顯示客戶名、合計金額、狀態標籤（Row Icon+Text）、離線 icon
//   - 軟刪除（sales / admin，converted 不可刪）
//   - 轉訂單（draft / sent，convertedToOrderId == null，已同步）
//
// UI 規範：
//   - 狀態標籤：Row(Icon + Text)，純文字+色彩，無外框無背景
//   - 操作按鈕：TextButton.icon（有文字標籤）
//   - 佈局：Card + Column（與 SalesOrderListScreen 一致）
// ==============================================================================

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/document_actions.dart';
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

  @override
  void initState() {
    super.initState();
    _loadCustomerMap();
  }

  Future<void> _loadCustomerMap() async {
    final db = context.read<AppDatabase>();
    final customers = await db.getActiveCustomers();
    if (!mounted) return;
    setState(() {
      _customerMap = {for (final c in customers) c.id: c.name};
    });
  }

  // ─── 狀態標籤 ───────────────────────────────────────────────────────────────

  Widget _buildStatusLabel(String status) {
    final (label, icon, color) = switch (status) {
      'sent'      => ('已發送', Icons.send_outlined,          Colors.blue),
      'converted' => ('已轉訂', Icons.check_circle_outline,   Colors.green),
      'expired'   => ('已過期', Icons.timer_off_outlined,     Colors.orange),
      _           => ('草稿',   Icons.edit_outlined,          Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ─── 軟刪除 ─────────────────────────────────────────────────────────────────

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

  // ─── 轉訂單 ─────────────────────────────────────────────────────────────────

  Future<void> _convertToOrder(
    BuildContext context,
    AppDatabase db,
    SyncProvider sync,
    Quotation quotation,
  ) async {
    await db.updateQuotationStatus(quotation.id, 'converted');

    final now = DateTime.now().toUtc();
    final localOrderId = SyncProvider.nextLocalId();

    await db.insertSalesOrder(SalesOrdersCompanion(
      id: Value(localOrderId),
      quotationId: Value(quotation.id),
      customerId: Value(quotation.customerId),
      createdBy: Value(sync.userId!),
      status: const Value('pending'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));

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

  // ─── 報價列表項目 ─────────────────────────────────────────────────────────────

  Widget _buildQuotationTile(BuildContext context, Quotation q, String? role) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    final customerName = _customerMap[q.customerId] ?? '客戶 #${q.customerId}';
    final isOffline = q.id < 0;

    final canDelete = (role == 'sales' || role == 'admin') &&
        q.status != 'converted';
    final canConvert = (role == 'sales' || role == 'admin') &&
        (q.status == 'draft' || q.status == 'sent') &&
        q.convertedToOrderId == null &&
        !isOffline;
    final pendingConvert = isOffline &&
        (role == 'sales' || role == 'admin') &&
        (q.status == 'draft' || q.status == 'sent') &&
        q.convertedToOrderId == null;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：客戶名 + 離線 icon
            Row(
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Icon(
                  isOffline ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                  size: 18,
                  color: isOffline ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：狀態標籤 + 合計金額
            Row(
              children: [
                _buildStatusLabel(q.status),
                const SizedBox(width: 12),
                Text(
                  '合計：${q.totalAmount}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(q.createdAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            // 操作按鈕（有權限才顯示）
            if (canConvert || pendingConvert || canDelete || (!isOffline && (role == 'sales' || role == 'admin'))) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (!isOffline && (role == 'sales' || role == 'admin')) ...[
                    TextButton.icon(
                      onPressed: () => downloadAndOpenPdf(
                        context,
                        apiPath: '/api/v1/quotations/${q.id}/pdf',
                        filename: 'quotation-${q.id}.pdf',
                      ),
                      icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                      label: const Text('PDF'),
                      style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                    ),
                    TextButton.icon(
                      onPressed: () => sendEmail(
                        context,
                        apiPath: '/api/v1/quotations/${q.id}/send-email',
                      ),
                      icon: const Icon(Icons.email_outlined, size: 16),
                      label: const Text('寄信'),
                      style: TextButton.styleFrom(foregroundColor: Colors.teal),
                    ),
                  ],
                  if (canConvert)
                    TextButton.icon(
                      onPressed: () => _convertToOrder(context, db, sync, q),
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('轉訂單'),
                      style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                    ),
                  if (pendingConvert)
                    TextButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('連線推送後轉訂單'),
                    ),
                  if (canDelete)
                    TextButton.icon(
                      onPressed: () => _confirmDelete(context, db, sync, q),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('刪除'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final role = sync.role;

    return StreamBuilder<List<Quotation>>(
      stream: db.watchActiveQuotations(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final quotations = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () => sync.pullData(),
          child: quotations.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Text(
                        '尚無報價單\n下拉以同步取得最新資料',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: quotations.length,
                  itemBuilder: (context, index) =>
                      _buildQuotationTile(context, quotations[index], role),
                ),
        );
      },
    );
  }
}
