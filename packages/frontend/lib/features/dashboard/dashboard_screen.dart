// ==============================================================================
// DashboardScreen — Phase 2 P2-VIS Wave 1
//
// 在既有 KPI 卡片和低庫存列表之間，插入三個圖表區塊：
//   1. 月度營收折線圖（近 6 個月）
//   2. 訂單狀態環形圖
//   3. Top 5 產品銷售排行（水平長條圖）
//
// 現有功能完全不動（KPI 卡、低庫存列表、Pull-to-refresh sync）
// 圖表資料由 AnalyticsProvider 獨立管理，失敗時顯示骨架，不影響主流程。
// ==============================================================================

import 'package:decimal/decimal.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../providers/sync_provider.dart';
import '../../providers/analytics_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    // 進入頁面時若快取過期則自動拉取，不阻塞 UI
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AnalyticsProvider>().fetchAll();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    return RefreshIndicator(
      onRefresh: () async {
        final analytics = context.read<AnalyticsProvider>();
        await sync.pullData();
        if (mounted) await analytics.fetchAll(force: true);
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          // ── KPI 卡片列（現有）────────────────────────────────
          Row(
            children: [
              Expanded(child: _ConfirmedOrderCard(db: db)),
              const SizedBox(width: 12),
              Expanded(child: _MonthlyQuotationCard(db: db)),
            ],
          ),
          const SizedBox(height: 20),

          // ── 圖表區（Phase 2 新增）────────────────────────────
          const _AnalyticsSection(),
          const SizedBox(height: 20),

          // ── 低庫存列表（現有）────────────────────────────────
          _LowStockSection(db: db),
        ],
      ),
    );
  }
}

// ==============================================================================
// 圖表區總容器
// ==============================================================================

class _AnalyticsSection extends StatelessWidget {
  const _AnalyticsSection();

  @override
  Widget build(BuildContext context) {
    final analytics = context.watch<AnalyticsProvider>();
    final s         = AppStrings.of(context);

    // 載入中：顯示骨架（不阻擋其他 UI）
    if (analytics.isLoading && analytics.revenueData == null) {
      return const _ChartSkeleton();
    }

    // 未登入或網路錯誤：靜默（不顯示圖表區，等 sync 成功後 pull-to-refresh 再試）
    if (analytics.error == 'auth_error') return const SizedBox.shrink();

    // 無資料（後端資料庫空的）：顯示提示
    if (analytics.revenueData != null && analytics.revenueData!.isEmpty &&
        analytics.statusData != null  && analytics.statusData!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          s.isEnglish ? 'No analytics data yet.' : '尚無分析數據，請先新增訂單。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 出貨＋營收合併 Combo Chart
        if (analytics.inventoryTrendData != null && analytics.inventoryTrendData!.isNotEmpty) ...[
          _ShipmentRevenueComboChart(
            shipmentData: analytics.inventoryTrendData!,
            revenueData: analytics.revenueData,
          ),
          const SizedBox(height: 16),
        ],

        // 2. 訂單狀態環形圖 + Top 5 並排
        if (analytics.statusData != null || analytics.topProductData != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (analytics.statusData != null && analytics.statusData!.isNotEmpty)
                Expanded(
                  flex: 4,
                  child: _OrderStatusDonut(data: analytics.statusData!),
                ),
              if (analytics.statusData != null && analytics.topProductData != null)
                const SizedBox(width: 12),
              if (analytics.topProductData != null && analytics.topProductData!.isNotEmpty)
                Expanded(
                  flex: 6,
                  child: _TopProductsBar(data: analytics.topProductData!),
                ),
            ],
          ),

        // 3. 損益摘要（Admin 專用）
        if (analytics.profitData != null && analytics.profitData!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ProfitSummaryCard(data: analytics.profitData!),
        ],

        // 4. 報價漏斗（admin + sales）
        if (analytics.funnelData != null && analytics.funnelData!.totalQuotations > 0) ...[
          const SizedBox(height: 16),
          _FunnelCard(data: analytics.funnelData!),
        ],

        // 5. 客戶熱力圖（admin + sales）
        if (analytics.heatmapData != null && analytics.heatmapData!.isNotEmpty) ...[
          const SizedBox(height: 16),
          _CustomerHeatmapCard(
            rows: analytics.heatmapData!,
            months: analytics.heatmapMonths ?? [],
          ),
        ],

        // 最後更新時間
        if (analytics.lastFetchedAt != null) ...[
          const SizedBox(height: 6),
          _LastUpdatedLabel(fetchedAt: analytics.lastFetchedAt!),
        ],
      ],
    );
  }
}

// ── 骨架佔位 ──────────────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

// ── 損益摘要（Admin 專用）────────────────────────────────

class _ProfitSummaryCard extends StatelessWidget {
  final List<ProfitPoint> data;
  const _ProfitSummaryCard({required this.data});

  String _fmt(double v) {
    final s = v.abs().toStringAsFixed(0);
    final buf = StringBuffer(v < 0 ? '-' : '');
    final len = s.length;
    for (var i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  @override
  Widget build(BuildContext context) {
    // 只取最新一個月的資料展示摘要
    final latest = data.last;
    final hasMargin = latest.grossMarginPct != null;
    final s = AppStrings.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up, size: 18),
                const SizedBox(width: 6),
                Text(
                  s.dashProfitTitle(latest.month),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _ProfitKpi(
                  label: s.dashProfitRevenue,
                  value: '\$ ${_fmt(latest.revenue)}',
                )),
                Expanded(child: _ProfitKpi(
                  label: s.dashProfitCogs,
                  value: '\$ ${_fmt(latest.cogs)}',
                )),
                Expanded(child: _ProfitKpi(
                  label: s.dashProfitGross,
                  value: '\$ ${_fmt(latest.grossProfit)}',
                  valueColor: latest.grossProfit >= 0 ? Colors.green.shade700 : Colors.red,
                )),
                if (hasMargin)
                  Expanded(child: _ProfitKpi(
                    label: s.dashProfitMargin,
                    value: '${latest.grossMarginPct!.toStringAsFixed(1)}%',
                    valueColor: latest.grossMarginPct! >= 0 ? Colors.green.shade700 : Colors.red,
                  )),
              ],
            ),
            if (!hasMargin) ...[
              const SizedBox(height: 6),
              Text(
                '尚未設定商品成本，無法計算毛利率。',
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProfitKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _ProfitKpi({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── 最後更新標籤 ──────────────────────────────────────────

class _LastUpdatedLabel extends StatelessWidget {
  final DateTime fetchedAt;
  const _LastUpdatedLabel({required this.fetchedAt});

  @override
  Widget build(BuildContext context) {
    final s   = AppStrings.of(context);
    final ago = DateTime.now().difference(fetchedAt).inMinutes;
    final label = s.isEnglish
        ? (ago < 1 ? 'Updated just now' : 'Updated ${ago}m ago')
        : (ago < 1 ? '剛剛更新' : '$ago 分鐘前更新');
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}


// ── Combo chart 圖例 ──────────────────────────────────────

class _ComboLegend extends StatelessWidget {
  final Color  barColor;
  final Color  lineColor;
  final String barLabel;
  final String lineLabel;
  const _ComboLegend({
    required this.barColor,
    required this.lineColor,
    required this.barLabel,
    required this.lineLabel,
  });

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 9,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 10, height: 10,
          decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2))),
      const SizedBox(width: 3),
      Text(barLabel, style: style),
      const SizedBox(width: 8),
      Container(width: 16, height: 2, color: lineColor),
      const SizedBox(width: 3),
      Text(lineLabel, style: style),
    ]);
  }
}

// ==============================================================================
// 圖表 2：訂單狀態環形圖
// ==============================================================================

class _OrderStatusDonut extends StatelessWidget {
  final List<OrderStatusCount> data;
  const _OrderStatusDonut({required this.data});

  static const _colors = {
    'pending':   Color(0xFF9E9E9E),
    'confirmed': Color(0xFF2196F3),
    'shipped':   Color(0xFF4CAF50),
    'cancelled': Color(0xFFF44336),
  };

  @override
  Widget build(BuildContext context) {
    final s     = AppStrings.of(context);
    final total = data.fold(0, (sum, d) => sum + d.count);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.isEnglish ? 'Order Status' : '訂單狀態',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 120,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,
                      centerSpaceRadius: 30,
                      sections: data.map((d) {
                        final color = _colors[d.status] ?? Colors.grey;
                        return PieChartSectionData(
                          value: d.count.toDouble(),
                          color: color,
                          radius: 28,
                          showTitle: false,
                        );
                      }).toList(),
                    ),
                  ),
                  Text(
                    '$total',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            // 圖例
            ...data.map((d) {
              final color = _colors[d.status] ?? Colors.grey;
              final label = _statusLabel(d.status, s);
              return Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  children: [
                    Container(width: 8, height: 8,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Expanded(child: Text(label, style: const TextStyle(fontSize: 10),
                        overflow: TextOverflow.ellipsis)),
                    Text('${d.count}', style: const TextStyle(fontSize: 10)),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  String _statusLabel(String status, AppStrings s) {
    if (s.isEnglish) return status;
    const map = {
      'pending':   '待確認',
      'confirmed': '已確認',
      'shipped':   '已出貨',
      'cancelled': '已取消',
    };
    return map[status] ?? status;
  }
}

// ==============================================================================
// 圖表 3：Top 5 產品水平長條圖
// ==============================================================================

class _TopProductsBar extends StatelessWidget {
  final List<TopProduct> data;
  const _TopProductsBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
    final maxQty = data.map((p) => p.totalQty).fold(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.isEnglish ? 'Top 5 Products (30d)' : 'Top 5 產品（近 30 天）',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            ...data.asMap().entries.map((entry) {
              final idx  = entry.key;
              final prod = entry.value;
              final frac = maxQty == 0 ? 0.0 : prod.totalQty / maxQty;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('${idx + 1}.',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(prod.name,
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('${prod.totalQty}',
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value: frac,
                        minHeight: 6,
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Theme.of(context).colorScheme.primary.withAlpha(200),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ==============================================================================
// 圖表 4：報價轉換漏斗
// ==============================================================================

class _FunnelCard extends StatelessWidget {
  final FunnelData data;
  const _FunnelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final s = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.filter_alt_outlined, size: 18),
              const SizedBox(width: 6),
              Text(s.dashQuotFunnelTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _FunnelKpi(label: s.dashQuotCreated, value: '${d.totalQuotations}')),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotConverted,
                value: '${d.converted}',
                valueColor: Colors.green.shade700,
              )),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotRate,
                value: '${d.conversionRate.toStringAsFixed(1)}%',
                valueColor: d.conversionRate >= 50 ? Colors.green.shade700 : Colors.orange,
              )),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotAvgDays,
                value: d.avgDaysToConvert != null
                    ? s.dashQuotDays(d.avgDaysToConvert!.toStringAsFixed(1))
                    : '—',
              )),
            ]),
            const SizedBox(height: 8),
            // 進度條
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: d.totalQuotations > 0 ? d.converted / d.totalQuotations : 0,
                minHeight: 8,
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
              ),
            ),
            const SizedBox(height: 4),
            Row(children: [
              Text('${s.dashQuotExpired} ${d.expiredCount}',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade400)),
              const SizedBox(width: 10),
              Text('${s.dashQuotPending} ${d.pendingCount}',
                  style: TextStyle(fontSize: 10,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _FunnelKpi extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _FunnelKpi({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 2),
        Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor,
            )),
      ],
    );
  }
}

// ==============================================================================
// Combo Chart：月度出貨量（Column / 左 Y 軸）＋ 月度營收（Line / 右 Y 軸）
// ==============================================================================

class _ShipmentRevenueComboChart extends StatelessWidget {
  final List<InventoryTrendPoint> shipmentData;
  final List<RevenuePoint>?       revenueData;

  const _ShipmentRevenueComboChart({
    required this.shipmentData,
    this.revenueData,
  });

  static const double _leftRes  = 40;
  static const double _rightRes = 44;
  static const double _botRes   = 20;

  @override
  Widget build(BuildContext context) {
    final s            = AppStrings.of(context);
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;

    final revMap = <String, double>{};
    for (final p in revenueData ?? []) {
      revMap[p.month] = p.revenue;
    }
    final hasRevenue = revMap.isNotEmpty;

    final maxOut = shipmentData
        .map((p) => p.totalOutbound.toDouble())
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxOut * 1.25 < 1 ? 10.0 : maxOut * 1.25;

    final maxRev = hasRevenue
        ? revenueData!.map((p) => p.revenue).fold(0.0, (a, b) => a > b ? a : b)
        : 0.0;

    final barGroups = shipmentData.asMap().entries.map((e) => BarChartGroupData(
      x: e.key,
      barRods: [
        BarChartRodData(
          toY: e.value.totalOutbound.toDouble(),
          color: Colors.orange,
          width: 14,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
        ),
      ],
    )).toList();

    // normalize revenue → [0, maxY] for overlay
    final lineSpots = hasRevenue
        ? shipmentData.asMap().entries.map((e) {
            final rev = revMap[e.value.month] ?? 0.0;
            return FlSpot(e.key.toDouble(), maxRev > 0 ? rev / maxRev * maxY : 0.0);
          }).toList()
        : <FlSpot>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.inventory_2_outlined, size: 18),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  s.isEnglish
                      ? 'Monthly Shipment & Revenue (6M)'
                      : '月度出貨與營收（近 6 個月）',
                  style: Theme.of(context).textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              _ComboLegend(
                barColor: Colors.orange,
                lineColor: Colors.teal,
                barLabel: s.isEnglish ? 'Outbound' : '出貨量',
                lineLabel: s.isEnglish ? 'Revenue' : '營收',
              ),
            ]),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              child: Stack(children: [
                // ── Layer 1: Column bars (totalOutbound, left Y) ──────
                BarChart(BarChartData(
                  maxY: maxY,
                  barGroups: barGroups,
                  gridData: FlGridData(
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: outlineColor, strokeWidth: 0.5),
                  ),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _leftRes,
                        getTitlesWidget: (val, _) => Text(
                          val.toInt().toString(),
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: hasRevenue ? _rightRes : 4,
                        getTitlesWidget: (_, __) => const SizedBox.shrink(),
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _botRes,
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= shipmentData.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              s.monthLabel(shipmentData[idx].month),
                              style: const TextStyle(fontSize: 9),
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final idx = group.x;
                        if (idx < 0 || idx >= shipmentData.length) return null;
                        final pt  = shipmentData[idx];
                        final rev = revMap[pt.month];
                        final revStr = rev != null
                            ? '\n${s.isEnglish ? "Revenue" : "營收"}: ${_fmtK(rev)}'
                            : '';
                        return BarTooltipItem(
                          '${pt.month}\n${s.isEnglish ? "Outbound" : "出貨量"}: ${pt.totalOutbound}$revStr',
                          const TextStyle(fontSize: 10, color: Colors.white),
                        );
                      },
                    ),
                  ),
                )),

                // ── Layer 2: Line overlay (revenue, right Y) ──────────
                // minX/maxX match BarChart's bar span so dots align with bars
                if (hasRevenue)
                  IgnorePointer(
                    child: LineChart(LineChartData(
                      minX: -0.5,
                      maxX: shipmentData.length.toDouble() - 0.5,
                      minY: 0,
                      maxY: maxY,
                      gridData: const FlGridData(show: false),
                      borderData: FlBorderData(show: false),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _leftRes,
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _rightRes,
                            interval: maxY / 4,
                            getTitlesWidget: (val, _) {
                              final actual =
                                  maxRev > 0 ? val / maxY * maxRev : 0.0;
                              return Text(
                                _fmtK(actual),
                                style: const TextStyle(
                                    fontSize: 9, color: Colors.teal),
                              );
                            },
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _botRes,
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),
                      lineBarsData: [
                        LineChartBarData(
                          spots: lineSpots,
                          isCurved: true,
                          color: Colors.teal,
                          barWidth: 2.5,
                          dotData: FlDotData(
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                                    radius: 3,
                                    color: Colors.teal,
                                    strokeWidth: 0),
                          ),
                          belowBarData: BarAreaData(show: false),
                        ),
                      ],
                      lineTouchData: const LineTouchData(enabled: false),
                    )),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _fmtK(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000)    return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }
}

// ==============================================================================
// 圖表 6：客戶下單熱力圖
// ==============================================================================

class _CustomerHeatmapCard extends StatelessWidget {
  final List<CustomerHeatmapRow> rows;
  final List<String>             months;
  const _CustomerHeatmapCard({required this.rows, required this.months});

  Color _cellColor(BuildContext context, int count) {
    if (count == 0) return Theme.of(context).colorScheme.surfaceContainerHighest;
    if (count == 1) return Colors.blue.shade100;
    if (count <= 3) return Colors.blue.shade300;
    return Colors.blue.shade600;
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final shortMonths = months.map((m) => s.monthLabel(m)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.grid_on_outlined, size: 18),
              const SizedBox(width: 6),
              Flexible(
                child: Text(s.dashHeatmapTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10),
            // 月份標題列 — LayoutBuilder 讓格子填滿卡片寬度
            LayoutBuilder(builder: (context, constraints) {
              const nameW = 80.0;
              final n = months.isEmpty ? 1 : months.length;
              final cellW = ((constraints.maxWidth - nameW) / n).floorToDouble();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題行
                  Row(children: [
                    const SizedBox(width: nameW),
                    ...shortMonths.map((m) => SizedBox(
                      width: cellW,
                      child: Text(m,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500)),
                    )),
                  ]),
                  const SizedBox(height: 4),
                  // 資料行
                  ...rows.map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Row(children: [
                      SizedBox(
                        width: nameW,
                        child: Text(row.name,
                            style: const TextStyle(fontSize: 10),
                            overflow: TextOverflow.ellipsis),
                      ),
                      ...row.counts.map((count) => Container(
                        width: cellW,
                        height: 22,
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: _cellColor(context, count),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        alignment: Alignment.center,
                        child: count > 0
                            ? Text('$count',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: count >= 4 ? Colors.white : Colors.blue.shade800,
                                  fontWeight: FontWeight.w600,
                                ))
                            : null,
                      )),
                    ]),
                  )),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}


// ==============================================================================
// 以下：現有 Widgets 完全不動
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
    final buffer = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return buffer.toString();
  }
}

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
