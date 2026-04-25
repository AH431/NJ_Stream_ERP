// ==============================================================================
// CustomerDetailScreen — Phase 2 C4
//
// 顯示：客戶基本資訊、RFM 評分卡（sales/admin）、近 5 筆訂單、
//       互動備忘（新增 / 軟刪除）、相關異常告警
// ==============================================================================

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/dao/interaction_dao.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../database/database.dart';
import '../../providers/anomaly_provider.dart';
import '../../providers/rfm_provider.dart';
import '../../providers/sync_provider.dart';
import 'customer_form_screen.dart';

class CustomerDetailScreen extends StatelessWidget {
  final Customer customer;
  const CustomerDetailScreen({super.key, required this.customer});

  // ── 日期 / 金額格式化（無 intl 依賴） ─────────────────────

  static String _fmtDate(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${_p2(d.month)}-${_p2(d.day)}';
  }

  static String _fmtDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.year}-${_p2(d.month)}-${_p2(d.day)} ${_p2(d.hour)}:${_p2(d.minute)}';
  }

  static String _p2(int n) => n.toString().padLeft(2, '0');

  static String _fmtNtd(double amount) {
    final i = amount.round();
    final s = i.abs().toString();
    final buf = StringBuffer(i < 0 ? '-' : '');
    for (int j = 0; j < s.length; j++) {
      if (j > 0 && (s.length - j) % 3 == 0) buf.write(',');
      buf.write(s[j]);
    }
    return 'NT\$ $buf';
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final sync    = context.watch<SyncProvider>();
    final role    = sync.role ?? '';
    final canEdit = role == 'sales' || role == 'admin';
    final canCrm  = canEdit;

    final rfmItem = canCrm
        ? context.watch<RfmProvider>().itemsById[customer.id]
        : null;

    final relatedAnomalies = context
        .watch<AnomalyProvider>()
        .items
        .where((a) =>
            a.entityType == 'customer' && a.entityId == customer.id)
        .toList();

    final db = context.read<AppDatabase>();
    final s  = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(customer.name),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: s.custTooltipEdit,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CustomerFormScreen(customer: customer),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.small(
              tooltip: s.isEnglish ? 'Add note' : '新增備忘',
              onPressed: () => _showAddNoteDialog(context),
              child: const Icon(Icons.add_comment_outlined),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          // ── 基本資訊 ───────────────────────────────────────
          _CustomerInfoCard(customer: customer, s: s),
          const Divider(height: 1),

          // ── RFM 評分卡（sales/admin only） ─────────────────
          if (canCrm) ...[
            _SectionHeader(s.isEnglish ? 'Customer Score' : '客戶評分'),
            rfmItem != null
                ? _RfmCard(item: rfmItem, s: s)
                : Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Text(
                      s.isEnglish
                          ? '— No score data (sync to refresh) —'
                          : '— 暫無評分資料（下拉同步以更新）—',
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
          ],

          // ── 近 5 筆訂單 ────────────────────────────────────
          _SectionHeader(s.isEnglish ? 'Recent Orders' : '近期訂單'),
          FutureBuilder<List<SalesOrder>>(
            future: db.getRecentOrdersForCustomer(customer.id),
            builder: (_, snap) {
              final orders = snap.data ?? [];
              if (orders.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Text(
                    s.isEnglish ? 'No orders yet.' : '尚無訂單記錄',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: orders
                    .map((o) => _OrderRow(order: o, s: s))
                    .toList(),
              );
            },
          ),

          // ── 互動備忘 ───────────────────────────────────────
          _SectionHeader(s.isEnglish ? 'Interaction Notes' : '互動備忘'),
          StreamBuilder<List<CustomerInteraction>>(
            stream: db.watchActiveInteractions(customer.id),
            builder: (_, snap) {
              final notes = snap.data ?? [];
              if (notes.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Text(
                    s.isEnglish
                        ? 'No notes yet. Tap + to add.'
                        : '尚無備忘。點擊 + 新增。',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                );
              }
              return Column(
                children: notes
                    .map((n) => _NoteRow(
                          note: n,
                          canEdit: canEdit,
                          onDelete: canEdit
                              ? () => _deleteNote(context, n)
                              : null,
                          s: s,
                        ))
                    .toList(),
              );
            },
          ),

          // ── 相關異常 ───────────────────────────────────────
          if (relatedAnomalies.isNotEmpty) ...[
            _SectionHeader(s.isEnglish ? 'Related Alerts' : '相關異常'),
            ...relatedAnomalies.map((a) => _AnomalyRow(anomaly: a, s: s)),
          ],
        ],
      ),
    );
  }

  // ── 新增備忘 dialog ──────────────────────────────────────

  Future<void> _showAddNoteDialog(BuildContext context) async {
    final controller = TextEditingController();
    final s = AppStrings.read(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isEnglish ? 'New Note' : '新增備忘'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: s.isEnglish ? 'Enter note...' : '輸入備忘內容…',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnSave),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;
    final note = controller.text.trim();
    if (note.isEmpty) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();
    final id   = SyncProvider.nextLocalId();

    await db.insertInteraction(CustomerInteractionsCompanion(
      id:         Value(id),
      customerId: Value(customer.id),
      note:       Value(note),
      createdBy:  Value(sync.userId),
      createdAt:  Value(now),
      updatedAt:  Value(now),
    ));
    await sync.enqueueCreate('customer_interaction', {
      'id':         id,
      'customerId': customer.id,
      'note':       note,
      'createdBy':  sync.userId,
      'createdAt':  now.toIso8601String(),
      'updatedAt':  now.toIso8601String(),
      'deletedAt':  null,
    });
  }

  // ── 軟刪除備忘 ───────────────────────────────────────────

  Future<void> _deleteNote(
      BuildContext context, CustomerInteraction note) async {
    final s = AppStrings.read(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.isEnglish ? 'Delete Note' : '刪除備忘'),
        content: Text(s.isEnglish
            ? 'Delete this note? This cannot be undone.'
            : '確定刪除此備忘？此操作無法復原。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnDelete),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();

    await db.softDeleteInteraction(note.id, now);
    await sync.enqueueDelete('customer_interaction', note.id, {
      'id':         note.id,
      'customerId': note.customerId,
      'note':       note.note,
      'createdBy':  note.createdBy,
      'createdAt':  note.createdAt.toIso8601String(),
      'updatedAt':  now.toIso8601String(),
      'deletedAt':  now.toIso8601String(),
    });
  }
}

// ── Section header ────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.2,
              ),
        ),
      );
}

// ── 基本資訊卡 ────────────────────────────────────────────

class _CustomerInfoCard extends StatelessWidget {
  final Customer  customer;
  final AppStrings s;
  const _CustomerInfoCard({required this.customer, required this.s});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    if (customer.contact != null) {
      rows.add(_InfoRow(Icons.person_outline, s.isEnglish ? 'Contact' : '聯絡人', customer.contact!));
    }
    if (customer.email != null) {
      rows.add(_InfoRow(Icons.email_outlined, 'Email', customer.email!));
    }
    if (customer.taxId != null) {
      rows.add(_InfoRow(Icons.badge_outlined, s.isEnglish ? 'Tax ID' : '統編', customer.taxId!));
    }
    if (customer.id < 0) {
      rows.add(const Row(children: [
        Icon(Icons.cloud_upload_outlined, size: 13, color: Colors.orange),
        SizedBox(width: 4),
        Text('等待同步', style: TextStyle(fontSize: 12, color: Colors.orange)),
      ]));
    }

    if (rows.isEmpty) return const SizedBox(height: 8);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String   label;
  final String   value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Icon(icon, size: 15, color: Colors.grey),
            const SizedBox(width: 8),
            Text('$label：',
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Expanded(
                child: Text(value, style: const TextStyle(fontSize: 13))),
          ],
        ),
      );
}

// ── RFM 評分卡 ────────────────────────────────────────────

class _RfmCard extends StatelessWidget {
  final RfmItem  item;
  final AppStrings s;
  const _RfmCard({required this.item, required this.s});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _TierBadge(tier: item.tier),
                const Spacer(),
                Text(
                  s.isEnglish
                      ? 'RFM score: ${item.rfmScore}'
                      : 'RFM 總分：${item.rfmScore}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _ScoreBox(
                    label: 'R',
                    score: item.rScore,
                    tooltip: s.isEnglish ? 'Recency' : '近期性'),
                const SizedBox(width: 8),
                _ScoreBox(
                    label: 'F',
                    score: item.fScore,
                    tooltip:
                        s.isEnglish ? 'Frequency (90d)' : '購買頻率（90天）'),
                const SizedBox(width: 8),
                _ScoreBox(
                    label: 'M',
                    score: item.mScore,
                    tooltip:
                        s.isEnglish ? 'Monetary (90d)' : '購買金額（90天）'),
              ],
            ),
            const Divider(height: 20),
            _MetricRow(
              s.isEnglish ? 'Days since last order' : '距上次下單',
              item.daysSinceLastOrder >= 9999
                  ? (s.isEnglish ? 'Never' : '尚未下單')
                  : '${item.daysSinceLastOrder} ${s.isEnglish ? 'days' : '天'}',
            ),
            _MetricRow(
              s.isEnglish ? 'Orders (90d)' : '近90天訂單數',
              '${item.orderCount90d}',
            ),
            _MetricRow(
              s.isEnglish ? 'Revenue (90d)' : '近90天營收',
              CustomerDetailScreen._fmtNtd(item.revenue90d),
            ),
            _MetricRow(
              s.isEnglish ? 'LTV' : '終生價值',
              CustomerDetailScreen._fmtNtd(item.ltv),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScoreBox extends StatelessWidget {
  final String label;
  final int    score;
  final String tooltip;
  const _ScoreBox(
      {required this.label, required this.score, required this.tooltip});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Tooltip(
          message: tooltip,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 2),
                Text('$score',
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ),
      );
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetricRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontSize: 13, color: Colors.grey)),
            Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500)),
          ],
        ),
      );
}

// ── 訂單列 ────────────────────────────────────────────────

class _OrderRow extends StatelessWidget {
  final SalesOrder order;
  final AppStrings s;
  const _OrderRow({required this.order, required this.s});

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    final label = s.isEnglish
        ? switch (status) {
            'pending'   => 'Pending',
            'confirmed' => 'Confirmed',
            'shipped'   => 'Shipped',
            'cancelled' => 'Cancelled',
            _           => status,
          }
        : switch (status) {
            'pending'   => '待處理',
            'confirmed' => '已確認',
            'shipped'   => '已出貨',
            'cancelled' => '已取消',
            _           => status,
          };
    final color = switch (status) {
      'confirmed' => Colors.blue,
      'shipped'   => Colors.green,
      'cancelled' => Colors.grey,
      _           => Colors.orange,
    };
    final dateStr = CustomerDetailScreen._fmtDate(order.createdAt);

    return ListTile(
      dense: true,
      leading: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(top: 4),
        decoration: BoxDecoration(
            color: color, shape: BoxShape.circle),
      ),
      title: Text(
        s.isEnglish ? 'Order #${order.id}' : '訂單 #${order.id}',
        style: const TextStyle(fontSize: 13),
      ),
      subtitle: Text(dateStr, style: const TextStyle(fontSize: 12)),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color:        color.withAlpha(30),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                color:    color,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ── 備忘列 ────────────────────────────────────────────────

class _NoteRow extends StatelessWidget {
  final CustomerInteraction note;
  final bool                canEdit;
  final VoidCallback?       onDelete;
  final AppStrings          s;
  const _NoteRow({
    required this.note,
    required this.canEdit,
    required this.onDelete,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final dtStr = CustomerDetailScreen._fmtDateTime(note.createdAt);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline, size: 15, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(note.note, style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(dtStr,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey)),
                    if (note.id < 0) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.cloud_upload_outlined,
                          size: 12, color: Colors.orange),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (canEdit && onDelete != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Colors.red.shade300,
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              onPressed: onDelete,
              tooltip: s.btnDelete,
            ),
        ],
      ),
    );
  }
}

// ── 異常告警列 ────────────────────────────────────────────

class _AnomalyRow extends StatelessWidget {
  final AnomalyItem anomaly;
  final AppStrings  s;
  const _AnomalyRow({required this.anomaly, required this.s});

  static const _alertLabels = <String, String>{
    'LOW_STOCK':             '低庫存',
    'LARGE_SINGLE_ORDER':   '大額訂單',
    'DUPLICATE_ORDER':      '重複訂單',
    'ORDER_QUANTITY_SPIKE': '數量異常',
    'CUSTOMER_INACTIVE':    '客戶沉默',
  };

  static const _severityColors = <String, Color>{
    'critical': Colors.red,
    'high':     Colors.orange,
    'medium':   Colors.amber,
  };

  @override
  Widget build(BuildContext context) {
    final color = _severityColors[anomaly.severity] ?? Colors.blueGrey;
    final label = s.isEnglish
        ? anomaly.alertType
        : (_alertLabels[anomaly.alertType] ?? anomaly.alertType);
    return ListTile(
      dense: true,
      leading: Icon(Icons.warning_amber_rounded, color: color, size: 20),
      title: Text(label, style: const TextStyle(fontSize: 13)),
      subtitle: Text(anomaly.message,
          style: const TextStyle(fontSize: 11),
          maxLines: 2,
          overflow: TextOverflow.ellipsis),
    );
  }
}

// ── RFM 分級標籤（與 CustomerListScreen 一致） ────────────

class _TierBadge extends StatelessWidget {
  final String tier;
  const _TierBadge({required this.tier});

  static const _colors = <String, Color>{
    'VIP':     Color(0xFF7B1FA2),
    '活躍':    Color(0xFF2E7D32),
    '觀察':    Color(0xFFE65100),
    '流失風險': Color(0xFFC62828),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[tier] ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color:        color.withAlpha(22),
        border:       Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tier,
        style: TextStyle(
            fontSize: 11, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
