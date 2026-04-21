// ==============================================================================
// DashboardScreen — 簡易儀表板（Issue #15）
//
// PRD §4.3 規格（已凍結）：
//   1. 待出貨訂單數（status = confirmed）
//   2. 低庫存產品列表（available <= minStockLevel，minStockLevel > 0）
//   3. 本月報價總額（含稅）
//
// 設計原則：
//   - 全部資料來自本地 Drift 查詢（StreamBuilder），離線可用
//   - Pull-to-refresh 觸發 sync.pullData() 更新本地快照
//   - 狀態標籤：Row(Icon + Text)，無外框無背景（UI 規範）
// ==============================================================================

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../providers/sync_provider.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    return RefreshIndicator(
      onRefresh: () => sync.pullData(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ── 上方：兩個摘要 Card 並排 ─────────────────────────────────────
          Row(
            children: [
              Expanded(child: _ConfirmedOrderCard(db: db)),
              const SizedBox(width: 12),
              Expanded(child: _MonthlyQuotationCard(db: db)),
            ],
          ),
          const SizedBox(height: 20),
          // ── 低庫存列表 ────────────────────────────────────────────────────
          _LowStockSection(db: db),
        ],
      ),
    );
  }
}

// ==============================================================================
// 待出貨訂單數 Card
// ==============================================================================

class _ConfirmedOrderCard extends StatelessWidget {
  final AppDatabase db;
  const _ConfirmedOrderCard({required this.db});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return StreamBuilder<int>(
      stream: db.watchConfirmedOrderCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return _SummaryCard(
          icon: Icons.local_shipping_outlined,
          iconColor: count > 0 ? Colors.orange : Colors.green,
          label: s.dashPendingShipments,
          value: '$count',
          unit: s.dashPendingUnit,
        );
      },
    );
  }
}

// ==============================================================================
// 本月報價總額 Card
// ==============================================================================

class _MonthlyQuotationCard extends StatelessWidget {
  final AppDatabase db;
  const _MonthlyQuotationCard({required this.db});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final now = DateTime.now();
    final monthLabel = s.isEnglish ? s.dashMonthlyQuotations : '${now.month} ${s.dashMonthlyQuotations}';

    return StreamBuilder<Decimal>(
      stream: db.watchCurrentMonthQuotationTotal(),
      builder: (context, snapshot) {
        final total = snapshot.data ?? Decimal.zero;
        // 格式化：整數部分加千分位
        final formatted = _formatDecimal(total);
        return _SummaryCard(
          icon: Icons.receipt_long_outlined,
          iconColor: Colors.blue,
          label: monthLabel,
          value: formatted,
          unit: s.dashCurrencyUnit,
        );
      },
    );
  }

  String _formatDecimal(Decimal d) {
    final intPart = d.truncate().toBigInt().toString();
    // 千分位
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return buffer.toString();
  }
}

// ==============================================================================
// 共用摘要 Card Widget
// ==============================================================================

class _SummaryCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String unit;

  const _SummaryCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.unit,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// 低庫存列表區塊
// ==============================================================================

class _LowStockSection extends StatelessWidget {
  final AppDatabase db;
  const _LowStockSection({required this.db});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return StreamBuilder<List<LowStockItem>>(
      stream: db.watchLowStockItems(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? [];
        final countLabel = s.isEnglish ? '${items.length} items' : '${items.length} 項';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 標題列
            Row(
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  size: 18,
                  color: items.isEmpty ? Colors.grey : Colors.orange,
                ),
                const SizedBox(width: 6),
                Text(
                  s.dashLowStockAlert,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8),
                if (items.isNotEmpty)
                  Text(
                    countLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.orange,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // 無低庫存
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  s.dashNoLowStock,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              )
            else
              ...items.map((item) => _LowStockTile(item: item)),
          ],
        );
      },
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final LowStockItem item;
  const _LowStockTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final shortage = item.minStockLevel - item.available;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            // 產品資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.sku,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            // 庫存數字
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.orange),
                    const SizedBox(width: 4),
                    Text(
                      s.dashAvailable(item.available),
                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  s.dashOnHandReserved(item.onHand, item.reserved),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  s.dashSafetyShortage(item.minStockLevel, shortage),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
