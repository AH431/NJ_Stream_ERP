// ==============================================================================
// QuotationListScreen — 報價單列表
//
// 功能：
//   - StreamBuilder 監聽 watchActiveQuotations()（deleted_at IS NULL）
//   - 每列顯示客戶名、合計金額、狀態標籤（Row Icon+Text）、離線 icon
//   - 軟刪除：長按進入選取模式 → 頂部工具列批次刪除（sales / admin，converted 不可選）
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

import '../../core/app_strings.dart';
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
  Map<int, String> _customerMap = {};

  // 選取模式
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<Quotation> _quotations = [];  // 供批次刪除使用

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

  // ─── 選取模式 ────────────────────────────────────────────────────────────────

  void _enterSelectionMode(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleItem(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _batchDelete(BuildContext context) async {
    final s     = context.read<AppStrings>();
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ds = ctx.read<AppStrings>();
        return AlertDialog(
          title: Text(ds.isEnglish ? 'Confirm Delete' : '確認刪除'),
          content: Text(ds.isEnglish
              ? 'Delete $count quotations? This cannot be undone.'
              : '確定要刪除 $count 張報價單？此操作無法復原。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.btnCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ds.btnDelete, style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();

    for (final id in _selectedIds) {
      final q = _quotations.where((q) => q.id == id).firstOrNull;
      if (q == null) continue;

      await db.softDeleteQuotation(id, now);
      await sync.enqueueDelete('quotation', id, {
        'id': q.id,
        'customerId': q.customerId,
        'createdBy': q.createdBy,
        'items': q.items,
        'totalAmount': q.totalAmount,
        'taxAmount': q.taxAmount,
        'status': q.status,
        'convertedToOrderId': q.convertedToOrderId,
        'createdAt': q.createdAt.toUtc().toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'deletedAt': now.toIso8601String(),
      });
    }

    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? '$count quotations deleted (pending sync).'
            : '已刪除 $count 張報價單，待同步後從伺服器移除')),
      );
    }
  }

  Widget _buildSelectionBar(BuildContext context, String? role) {
    final s         = AppStrings.of(context);
    final canDelete = role == 'sales' || role == 'admin';
    return ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: s.isEnglish ? 'Exit selection' : '離開選取',
            onPressed: _exitSelectionMode,
          ),
          Expanded(
            child: Text(
              s.isEnglish ? '${_selectedIds.length} selected' : '已選取 ${_selectedIds.length} 項',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (canDelete)
            TextButton.icon(
              onPressed: _selectedIds.isEmpty ? null : () => _batchDelete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(s.btnDelete),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── 狀態標籤 ───────────────────────────────────────────────────────────────

  Widget _buildStatusLabel(String status, AppStrings s) {
    final (label, icon, color) = switch (status) {
      'sent'      => (s.quotStatusSent,      Icons.send_outlined,          Colors.blue),
      'converted' => (s.quotStatusConverted, Icons.check_circle_outline,   Colors.green),
      'expired'   => (s.quotStatusExpired,   Icons.timer_off_outlined,     Colors.orange),
      _           => (s.quotStatusDraft,     Icons.edit_outlined,          Colors.grey),
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
      final s = context.read<AppStrings>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? 'Convert to order queued for sync.'
            : '轉訂單已排入待同步佇列')),
      );
    }
  }

  // ─── 報價列表項目 ─────────────────────────────────────────────────────────────

  Widget _buildQuotationTile(BuildContext context, Quotation q, String? role) {
    final s    = AppStrings.of(context);
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    final customerName = _customerMap[q.customerId] ??
        (s.isEnglish ? 'Customer #${q.customerId}' : '客戶 #${q.customerId}');
    final isOffline = q.id < 0;

    final canConvert = (role == 'sales' || role == 'admin') &&
        (q.status == 'draft' || q.status == 'sent') &&
        q.convertedToOrderId == null &&
        !isOffline;
    final pendingConvert = isOffline &&
        (role == 'sales' || role == 'admin') &&
        (q.status == 'draft' || q.status == 'sent') &&
        q.convertedToOrderId == null;

    // 已轉訂的報價不可選取刪除
    final isSelectable = q.status != 'converted' &&
        (role == 'sales' || role == 'admin');

    final isSelected = _selectedIds.contains(q.id);

    return GestureDetector(
      onLongPress: (!_selectionMode && isSelectable)
          ? () => _enterSelectionMode(q.id)
          : null,
      onTap: (_selectionMode && isSelectable) ? () => _toggleItem(q.id) : null,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：(checkbox) + 客戶名 + 離線 icon
              Row(
                children: [
                  if (_selectionMode && isSelectable)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleItem(q.id),
                      visualDensity: VisualDensity.compact,
                    ),
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
              // 第二行：狀態標籤 + 合計金額 + 日期
              Row(
                children: [
                  _buildStatusLabel(q.status, s),
                  const SizedBox(width: 12),
                  Text(
                    s.isEnglish ? 'Total: ${q.totalAmount}' : '合計：${q.totalAmount}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _formatDate(q.createdAt),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              // 操作按鈕（選取模式下隱藏）
              if (!_selectionMode &&
                  (canConvert || pendingConvert ||
                      (!isOffline && (role == 'sales' || role == 'admin')))) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    if (!isOffline && (role == 'sales' || role == 'admin')) ...[
                      TextButton.icon(
                        onPressed: () => downloadAndOpenPdf(
                          context,
                          apiPath: '/api/v1/quotations/${q.id}/pdf',
                          filename: 'quotation-${q.id}.pdf',
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: Text(s.btnPdf),
                        style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                      ),
                      TextButton.icon(
                        onPressed: () => sendEmail(
                          context,
                          apiPath: '/api/v1/quotations/${q.id}/send-email',
                        ),
                        icon: const Icon(Icons.email_outlined, size: 16),
                        label: Text(s.btnSendEmail),
                        style: TextButton.styleFrom(foregroundColor: Colors.teal),
                      ),
                    ],
                    if (canConvert)
                      TextButton.icon(
                        onPressed: () => _convertToOrder(context, db, sync, q),
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: Text(s.btnConvert),
                        style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                      ),
                    if (pendingConvert)
                      TextButton.icon(
                        onPressed: null,
                        icon: const Icon(Icons.swap_horiz, size: 16),
                        label: Text(s.btnConvertOnline),
                      ),
                  ],
                ),
              ],
            ],
          ),
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
    final s    = AppStrings.of(context);
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
        // 更新快取供批次刪除使用
        _quotations = quotations;

        return Column(
          children: [
            if (_selectionMode) _buildSelectionBar(context, role),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => sync.pullData(),
                child: quotations.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              s.quotEmptyHint,
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
              ),
            ),
          ],
        );
      },
    );
  }
}