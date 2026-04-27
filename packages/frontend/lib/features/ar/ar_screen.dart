// ==============================================================================
// ArScreen — Phase 2 P2-ACC（Admin 專用）
//
// 顯示應收帳款總覽（aging buckets）及未收訂單明細列表。
// 允許 Admin 標記訂單為「已付款」或「呆帳沖銷」。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/ar_provider.dart';

String _fmtAmount(double v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  final len = s.length;
  for (var i = 0; i < len; i++) {
    if (i > 0 && (len - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

String _fmtDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.year}-${dt.month.toString().padLeft(2,'0')}-${dt.day.toString().padLeft(2,'0')}';
  } catch (_) {
    return '—';
  }
}

class ArScreen extends StatefulWidget {
  const ArScreen({super.key});

  @override
  State<ArScreen> createState() => _ArScreenState();
}

class _ArScreenState extends State<ArScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ArProvider>().fetchAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ar = context.watch<ArProvider>();
    final s = AppStrings.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.arTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: ar.isLoading ? null : () => ar.fetchAll(force: true),
          ),
        ],
      ),
      body: ar.isLoading && ar.summary == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => ar.fetchAll(force: true),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (ar.error == 'fetch_error')
                    _ErrorBanner(message: s.arFetchError),
                  if (ar.summary != null) ...[
                    _SummaryCard(summary: ar.summary!),
                    const SizedBox(height: 16),
                    _AgingCard(summary: ar.summary!),
                    const SizedBox(height: 16),
                  ],
                  _OrderListSection(orders: ar.orders),
                ],
              ),
            ),
    );
  }
}

// ── 總覽卡 ────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final ArSummary summary;
  const _SummaryCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = AppStrings.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.arSummaryTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _KpiTile(
                  label: s.arTotalUnpaid,
                  value: 'NT\$ ${_fmtAmount(summary.totalUnpaid)}',
                  valueColor: colorScheme.primary,
                )),
                Expanded(child: _KpiTile(
                  label: s.arTotalOverdue,
                  value: 'NT\$ ${_fmtAmount(summary.totalOverdue)}',
                  valueColor: summary.totalOverdue > 0 ? Colors.red : colorScheme.onSurface,
                )),
                Expanded(child: _KpiTile(
                  label: s.arTotalCurrent,
                  value: 'NT\$ ${_fmtAmount(summary.totalCurrent)}',
                  valueColor: colorScheme.secondary,
                )),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              s.arUnpaidOrderCount(summary.unpaidOrderCount),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _KpiTile extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _KpiTile({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: valueColor, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// ── Aging Buckets 卡 ──────────────────────────────────────

class _AgingCard extends StatelessWidget {
  final ArSummary summary;
  const _AgingCard({required this.summary});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final buckets = [
      (s.arBucket030,   summary.bucket030,   Colors.orange.shade300),
      (s.arBucket3160,  summary.bucket3160,  Colors.orange.shade600),
      (s.arBucket6190,  summary.bucket6190,  Colors.red.shade400),
      (s.arBucket90Plus, summary.bucket90Plus, Colors.red.shade800),
    ];
    final total = buckets.fold<double>(0, (acc, b) => acc + b.$2);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.arAgingTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (label, amount, color) in buckets) ...[
              _BucketRow(
                label: label,
                amount: amount,
                total: total,
                color: color,
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _BucketRow extends StatelessWidget {
  final String label;
  final double amount;
  final double total;
  final Color  color;
  const _BucketRow({
    required this.label,
    required this.amount,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? amount / total : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            Text(
              'NT\$ ${_fmtAmount(amount)}',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: pct,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

// ── 未收訂單列表 ──────────────────────────────────────────

class _OrderListSection extends StatelessWidget {
  final List<ArOrder> orders;
  const _OrderListSection({required this.orders});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    if (orders.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(s.arNoUnpaid, style: const TextStyle(color: Colors.grey)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(s.arUnpaidOrders, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final order in orders)
          _OrderTile(order: order),
      ],
    );
  }
}

// Replaced ListTile to avoid trailing-Column bottom overflow.
class _OrderTile extends StatelessWidget {
  final ArOrder order;
  const _OrderTile({required this.order});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final dueDateStr = _fmtDate(order.dueDate);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left: order info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.arOrderTitle(order.id, order.customerName),
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    s.arDueDate(dueDateStr),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (order.isOverdue) ...[
                    const SizedBox(height: 4),
                    Chip(
                      label: Text(s.arOverdueDays(order.daysOverdue)),
                      backgroundColor: Colors.red.shade50,
                      labelStyle: TextStyle(color: Colors.red.shade800, fontSize: 11),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
            ),
            // Right: amount + action menu — no trailing constraint
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NT\$ ${_fmtAmount(order.orderTotal)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                _MarkPaidButton(orderId: order.id),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkPaidButton extends StatelessWidget {
  final int orderId;
  const _MarkPaidButton({required this.orderId});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.read(context);
    return PopupMenuButton<String>(
      tooltip: s.arMarkStatus,
      icon: const Icon(Icons.more_horiz, size: 18),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'paid',
          child: Text(s.arMarkPaid,
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
        ),
        PopupMenuItem(
          value: 'written_off',
          child: Text(s.arWriteOff,
              style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600)),
        ),
      ],
      onSelected: (value) async {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(value == 'paid' ? s.arConfirmPaid : s.arConfirmWriteOff),
            content: Text(value == 'paid'
                ? s.arMarkPaidBody(orderId)
                : s.arWriteOffBody(orderId)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(s.btnCancel)),
              FilledButton(onPressed: () => Navigator.pop(ctx, true),  child: Text(s.btnSave)),
            ],
          ),
        );
        if (confirmed == true && context.mounted) {
          final ok = await context.read<ArProvider>().markPayment(orderId, value);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(ok ? s.arUpdateSuccess : s.arUpdateFailed)),
            );
          }
        }
      },
    );
  }
}

// ── 錯誤提示 ──────────────────────────────────────────────

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined, color: Colors.orange),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
        ],
      ),
    );
  }
}
