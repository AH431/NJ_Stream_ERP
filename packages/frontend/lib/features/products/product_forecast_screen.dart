// ==============================================================================
// ProductForecastScreen — Phase 4 PR-5 M5.2
//
// 產品需求預測詳細頁，顯示：
//   - ProductSelector：DropdownButton 載入該 tenant 產品清單
//   - ForecastChart：fl_chart LineChart，12 週折線 + 信賴區間陰影
//   - ForecastTable：週次 / 預測量 / 建議採購量
//   - ExportButton：匯出 CSV 至暫存目錄並開啟
//
// 路由傳入：initialProductId / initialSku（可選，來自 ForecastSummaryCard 點擊）
// ==============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../providers/forecast_provider.dart';

class ProductForecastScreen extends StatefulWidget {
  final int?    initialProductId;
  final String? initialSku;

  const ProductForecastScreen({
    super.key,
    this.initialProductId,
    this.initialSku,
  });

  @override
  State<ProductForecastScreen> createState() => _ProductForecastScreenState();
}

class _ProductForecastScreenState extends State<ProductForecastScreen> {
  List<Product> _products = [];
  int?          _selectedProductId;
  int           _currentStock = 0;    // available = onHand - reserved

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final db = context.read<AppDatabase>();
    final list = await db.getActiveProducts();
    if (!mounted) return;
    setState(() {
      _products = list;
      if (widget.initialProductId != null) {
        _selectedProductId = widget.initialProductId;
      } else if (list.isNotEmpty) {
        _selectedProductId = list.first.id;
      }
    });
    if (_selectedProductId != null) {
      _onProductChanged(_selectedProductId!);
    }
  }

  Future<void> _onProductChanged(int productId) async {
    setState(() => _selectedProductId = productId);

    // 查詢現有庫存（用已有的 getInventoryItemByProductId）
    final db  = context.read<AppDatabase>();
    final inv = await db.getInventoryItemByProductId(productId);
    if (!mounted) return;
    setState(() {
      _currentStock = inv == null
          ? 0
          : inv.quantityOnHand - inv.quantityReserved;
    });

    // 拉取預測
    if (mounted) {
      context.read<ForecastProvider>().fetchProductForecast(productId);
    }
  }

  Future<void> _exportCsv(ProductForecast forecast) async {
    final s = AppStrings.read(context);
    try {
      final lines = <String>[
        'week_start,forecast_qty,lower_bound,upper_bound,suggested_order',
        ...forecast.forecasts.map((w) {
          final suggested = math.max(0, (w.qty - _currentStock).round());
          return '${w.weekStart},'
              '${w.qty.toStringAsFixed(1)},'
              '${w.lower?.toStringAsFixed(1) ?? ''},'
              '${w.upper?.toStringAsFixed(1) ?? ''},'
              '$suggested';
        }),
      ];
      final csv  = lines.join('\n');
      final dir  = await getTemporaryDirectory();
      final ts   = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/forecast_${forecast.sku}_$ts.csv');
      await file.writeAsString(csv);
      await OpenFilex.open(file.path);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.forecastExportFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final forecast = context.watch<ForecastProvider>();
    final s        = AppStrings.of(context);
    final scheme   = Theme.of(context).colorScheme;
    final text     = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.forecastScreenTitle),
        actions: [
          if (forecast.currentForecast != null &&
              !forecast.currentForecast!.isEmpty)
            IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: s.forecastExportCsv,
              onPressed: () => _exportCsv(forecast.currentForecast!),
            ),
        ],
      ),
      body: _products.isEmpty
          ? Center(
              child: Text(
                s.forecastNoProducts,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Product Selector ─────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: _selectedProductId,
                        items: _products.map((p) {
                          return DropdownMenuItem(
                            value: p.id,
                            child: Text(
                              '${p.sku} — ${p.name}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        onChanged: (id) {
                          if (id != null) _onProductChanged(id);
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Current Stock Badge ───────────────────────
                Row(
                  children: [
                    Icon(
                      Icons.inventory_2_outlined,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      s.forecastCurrentStock(_currentStock),
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // ── Chart ─────────────────────────────────────
                if (forecast.forecastLoading)
                  const _ChartSkeleton()
                else if (forecast.forecastError == 'auth_error')
                  const SizedBox.shrink()
                else if (forecast.currentForecast == null ||
                    forecast.currentForecast!.isEmpty)
                  _EmptyState(message: s.forecastEmptyState)
                else
                  _ForecastChart(
                    forecast: forecast.currentForecast!,
                    cardColor: scheme.surface,
                    primaryColor: scheme.primary,
                  ),

                const SizedBox(height: 16),

                // ── Table ─────────────────────────────────────
                if (forecast.currentForecast != null &&
                    !forecast.currentForecast!.isEmpty)
                  _ForecastTable(
                    forecast: forecast.currentForecast!,
                    currentStock: _currentStock,
                  ),
              ],
            ),
    );
  }
}

// ── 圖表 ──────────────────────────────────────────────────

class _ForecastChart extends StatelessWidget {
  final ProductForecast forecast;
  final Color cardColor;
  final Color primaryColor;

  const _ForecastChart({
    required this.forecast,
    required this.cardColor,
    required this.primaryColor,
  });

  @override
  Widget build(BuildContext context) {
    final text   = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final weeks  = forecast.forecasts;

    // fl_chart x-axis = 週序（0-based），y-axis = qty
    FlSpot toSpot(int i, double qty) => FlSpot(i.toDouble(), qty);

    final mainSpots  = [for (var i = 0; i < weeks.length; i++) toSpot(i, weeks[i].qty)];
    final upperSpots = [
      for (var i = 0; i < weeks.length; i++)
        toSpot(i, weeks[i].upper ?? weeks[i].qty),
    ];
    final lowerSpots = [
      for (var i = 0; i < weeks.length; i++)
        toSpot(i, weeks[i].lower ?? weeks[i].qty),
    ];

    final maxY = upperSpots.fold(0.0, (m, s) => math.max(m, s.y)) * 1.15;
    final minY = math.max(
      0.0,
      lowerSpots.fold(double.infinity, (m, s) => math.min(m, s.y)) * 0.85,
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 16, 12),
        child: SizedBox(
          height: 200,
          child: LineChart(
            LineChartData(
              minY: minY,
              maxY: maxY == 0 ? 10 : maxY,
              lineBarsData: [
                // 1. Upper bound — 信賴區間頂部填色（由 upper 往下）
                LineChartBarData(
                  spots: upperSpots,
                  isCurved: true,
                  color: Colors.transparent,
                  barWidth: 0,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: primaryColor.withAlpha(30),
                  ),
                ),
                // 2. Lower bound — 遮蔽 lower 以下，形成區間帶
                LineChartBarData(
                  spots: lowerSpots,
                  isCurved: true,
                  color: Colors.transparent,
                  barWidth: 0,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: cardColor,
                  ),
                ),
                // 3. Main forecast line
                LineChartBarData(
                  spots: mainSpots,
                  isCurved: true,
                  color: primaryColor,
                  barWidth: 2.5,
                  dotData: const FlDotData(show: false),
                  shadow: Shadow(
                    color: primaryColor.withAlpha(40),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ),
              ],
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, _) => Text(
                      v.toInt().toString(),
                      style: text.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: weeks.length <= 6 ? 1 : 2,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= weeks.length) {
                        return const SizedBox.shrink();
                      }
                      // 顯示 "W1", "W3", ...
                      return Text(
                        'W${idx + 1}',
                        style: text.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      );
                    },
                  ),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              gridData: FlGridData(
                show: true,
                horizontalInterval: maxY > 0 ? maxY / 5 : 2,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: scheme.outlineVariant.withAlpha(80),
                  strokeWidth: 1,
                ),
                drawVerticalLine: false,
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipItems: (spots) => spots.map((s) {
                    if (s.barIndex != 2) return null; // 只顯示主線 tooltip
                    final idx = s.spotIndex;
                    final w   = weeks[idx];
                    return LineTooltipItem(
                      'W${idx + 1}  ${w.qty.toStringAsFixed(1)}',
                      const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── 預測表格 ──────────────────────────────────────────────

class _ForecastTable extends StatelessWidget {
  final ProductForecast forecast;
  final int currentStock;

  const _ForecastTable({required this.forecast, required this.currentStock});

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              s.forecastTableTitle,
              style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // 表頭
            Row(
              children: [
                _HeaderCell(s.forecastColWeek,     flex: 3),
                _HeaderCell(s.forecastColQty,      flex: 3),
                _HeaderCell(s.forecastColSuggest,  flex: 4),
              ],
            ),
            const Divider(height: 8),

            // 表格行
            ...forecast.forecasts.asMap().entries.map((entry) {
              final idx      = entry.key;
              final w        = entry.value;
              final suggest  = math.max(0, (w.qty - currentStock).round());
              final isHigh   = suggest > 0;

              return Container(
                color: idx.isOdd
                    ? scheme.surfaceContainerHighest.withAlpha(60)
                    : null,
                child: Row(
                  children: [
                    _DataCell('W${idx + 1}  ${w.weekStart}',   flex: 3),
                    _DataCell(w.qty.toStringAsFixed(1),          flex: 3),
                    _DataCell(
                      suggest.toString(),
                      flex: 4,
                      color: isHigh ? scheme.error : null,
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

class _HeaderCell extends StatelessWidget {
  final String label;
  final int    flex;
  const _HeaderCell(this.label, {required this.flex});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  final String  label;
  final int     flex;
  final Color?  color;
  const _DataCell(this.label, {required this.flex, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

// ── 骨架 / Empty State ────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SizedBox(
        height: 200,
        child: Center(
          child: CircularProgressIndicator(
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  const _EmptyState({required this.message});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
