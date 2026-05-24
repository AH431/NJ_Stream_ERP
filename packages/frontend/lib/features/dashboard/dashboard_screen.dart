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
import '../../providers/forecast_provider.dart';
import 'forecast_summary_card.dart';
import '../onboarding/onboarding_banner.dart';

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
        // ForecastProvider alerts 由 ForecastSummaryCard 內的 StreamSubscription 觸發
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
        final forecast  = context.read<ForecastProvider>();
        await sync.pullData();
        if (mounted) {
          await analytics.fetchAll(force: true);
          // 強制刷新補貨警示快取（新庫存資料拉下後重算）
          await forecast.fetchReorderAlerts([], force: true);
        }
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16), // ← 整個 Dashboard 頁面四周內距 16 dp
        children: [
          // ── Onboarding Banner（M7.2：入駐未完成時顯示）──────
          const OnboardingBanner(),

          // ── KPI 卡片列（現有）────────────────────────────────
          Row(
            children: [
              Expanded(child: _ConfirmedOrderCard(db: db)),
              const SizedBox(width: 12), // ← 兩張 KPI 卡之間的水平間隔 12 dp
              Expanded(child: _MonthlyQuotationCard(db: db)),
            ],
          ),
          const SizedBox(height: 20), // ← KPI 卡 → 圖表區的垂直間隔 20 dp

          // ── 圖表區（Phase 2 新增）────────────────────────────
          const _AnalyticsSection(),
          const SizedBox(height: 20), // ← 圖表區 → 低庫存列表的垂直間隔 20 dp

          // ── 補貨預測警示（Phase 4 PR-5 M5.1）────────────────
          ForecastSummaryCard(db: db),
          const SizedBox(height: 12),

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

    // 無資料（後端資料庫空的）：顯示提示文字
    if (analytics.revenueData != null && analytics.revenueData!.isEmpty &&
        analytics.statusData != null  && analytics.statusData!.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8), // ← 無資料提示文字的垂直內距 8 dp
        child: Text(
          s.isEnglish ? 'No analytics data yet.' : '尚無分析數據，請先新增訂單。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← 字型：bodySmall（通常 12 sp）
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 圖表 1：出貨＋營收 Combo Chart ──────────────────────────────────
        if (analytics.inventoryTrendData != null && analytics.inventoryTrendData!.isNotEmpty) ...[
          _ShipmentRevenueComboChart(
            shipmentData: analytics.inventoryTrendData!,
            revenueData: analytics.revenueData,
          ),
          const SizedBox(height: 16), // ← Combo Chart → 下一區塊的垂直間隔 16 dp
        ],

        // ── 圖表 2 + 3：訂單環形圖 & Top 5 產品 並排 Row ──────────────────
        if (analytics.statusData != null || analytics.topProductData != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 環形圖：flex=4（佔寬度 40%）
              if (analytics.statusData != null && analytics.statusData!.isNotEmpty)
                Expanded(
                  flex: 5, // ← 環形圖佔 4 份寬度
                  child: _OrderStatusDonut(data: analytics.statusData!),
                ),
              // 環形圖與長條圖之間的水平間隔
              if (analytics.statusData != null && analytics.topProductData != null)
                const SizedBox(width: 12), // ← 環形圖 → 長條圖的水平間隔 12 dp
              // 長條圖：flex=6（佔寬度 60%）
              if (analytics.topProductData != null && analytics.topProductData!.isNotEmpty)
                Expanded(
                  flex: 5, // ← Top 5 長條圖佔 6 份寬度
                  child: _TopProductsBar(data: analytics.topProductData!),
                ),
            ],
          ),

        // ── 圖表 4：損益摘要（Admin 專用）────────────────────────────────
        if (analytics.profitData != null && analytics.profitData!.isNotEmpty) ...[
          const SizedBox(height: 16), // ← 損益摘要與上方圖表的垂直間隔 16 dp
          _ProfitSummaryCard(data: analytics.profitData!),
        ],

        // ── 圖表 5：報價漏斗（admin + sales）────────────────────────────
        if (analytics.funnelData != null && analytics.funnelData!.totalQuotations > 0) ...[
          const SizedBox(height: 16), // ← 漏斗卡與上方圖表的垂直間隔 16 dp
          _FunnelCard(data: analytics.funnelData!),
        ],

        // ── 圖表 6：客戶熱力圖（admin + sales）──────────────────────────
        if (analytics.heatmapData != null && analytics.heatmapData!.isNotEmpty) ...[
          const SizedBox(height: 16), // ← 熱力圖與上方圖表的垂直間隔 16 dp
          _CustomerHeatmapCard(
            rows: analytics.heatmapData!,
            months: analytics.heatmapMonths ?? [],
          ),
        ],

        // ── 最後更新時間標籤 ─────────────────────────────────────────────
        if (analytics.lastFetchedAt != null) ...[
          const SizedBox(height: 6), // ← 更新時間標籤與上方圖表的垂直間隔 6 dp
          _LastUpdatedLabel(fetchedAt: analytics.lastFetchedAt!),
        ],
      ],
    );
  }
}

// ── 骨架佔位（載入中狀態）──────────────────────────────────────────────────

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160, // ← 骨架高度 160 dp；可調整以匹配實際圖表高度
      decoration: BoxDecoration(
        // surfaceContainerHighest + alpha 80（約 31% 不透明）→ 淡灰背景
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withAlpha(80),
        borderRadius: BorderRadius.circular(12), // ← 骨架圓角 12 dp
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)), // ← 細線進度圈，strokeWidth=2
    );
  }
}

// ── 損益摘要卡（Admin 專用）────────────────────────────────────────────────
//
// 佈局：Card > Padding(all:16) > Column
//   Row(icon + 標題)  → titleSmall 字型
//   Row(4 個 KPI 格)  → bodySmall 標籤 / bodyMedium+w600 數值

class _ProfitSummaryCard extends StatelessWidget {
  final List<ProfitPoint> data;
  const _ProfitSummaryCard({required this.data});

  // 將數值格式化為千分位字串（不含小數），負數前加 '-'
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
    // 只取最新一個月（data.last）的資料展示摘要
    final latest = data.last;
    final hasMargin = latest.grossMarginPct != null;
    final s = AppStrings.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16), // ← 損益卡四周內距 16 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題行 ───────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.trending_up, size: 18), // ← icon 尺寸 18 dp
                const SizedBox(width: 6),                // ← icon → 標題文字間距 6 dp
                Text(
                  s.dashProfitTitle(latest.month),
                  style: Theme.of(context).textTheme.titleSmall, // ← titleSmall（通常 14 sp, w500）
                ),
              ],
            ),
            const SizedBox(height: 12), // ← 標題 → KPI 格的垂直間隔 12 dp

            // ── KPI 格列（營收 / COGS / 毛利 / 毛利率）────────────────
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
                  // 毛利正 → green.shade700；負 → red
                  valueColor: latest.grossProfit >= 0 ? Colors.green.shade700 : Colors.red,
                )),
                if (hasMargin)
                  Expanded(child: _ProfitKpi(
                    label: s.dashProfitMargin,
                    value: '${latest.grossMarginPct!.toStringAsFixed(1)}%', // ← 毛利率保留 1 位小數
                    valueColor: latest.grossMarginPct! >= 0 ? Colors.green.shade700 : Colors.red,
                  )),
              ],
            ),
            // 未設定成本時顯示提示
            if (!hasMargin) ...[
              const SizedBox(height: 6),
              Text(
                '尚未設定商品成本，無法計算毛利率。',
                style: Theme.of(context).textTheme.bodySmall // ← bodySmall（通常 12 sp）
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// 損益摘要：單一 KPI 格（標籤 + 數值堆疊）
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
        Text(label, style: Theme.of(context).textTheme.bodySmall), // ← 標籤：bodySmall（12 sp）
        const SizedBox(height: 2), // ← 標籤 → 數值間距 2 dp
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith( // ← 數值：bodyMedium（14 sp）
            fontWeight: FontWeight.w600,                            //   加粗 w600
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

// ── 最後更新時間標籤 ────────────────────────────────────────────────────────

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
      style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← bodySmall（12 sp）
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}


// ── Combo Chart LEGEND 圖例（色塊 + 線段）──────────────────────────────────────────
//
// 水平排列：[色塊 10×10] [空 3] [barLabel] [空 8] [色線 16×2] [空 3] [lineLabel]

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
      fontSize: 9, // ← LEGEND 圖例文字大小 9 sp；可調整，推薦範圍 8–11
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 15, height: 10,                              // ← 柱狀色塊尺寸 10×10 dp
        decoration: BoxDecoration(color: barColor, borderRadius: BorderRadius.circular(2)),
      ),
      const SizedBox(width: 3),  // ← LEGEND 色塊 圖例 → bar 標籤間距 3 dp
      Text(barLabel, style: style),
      const SizedBox(width: 10),  // ← LEGEND bar 圖例 → line 圖例間距 8 dp
      Container(width: 16, height: 2, color: lineColor), // ← 折線色條尺寸 16×2 dp
      const SizedBox(width: 5),  // ← LEGEND 色條 → line 標籤間距 5 dp
      Text(lineLabel, style: style),
    ]);
  }
}

// ==============================================================================
// 圖表 2：訂單狀態環形圖（雙環）
// ==============================================================================
//
// 佈局：Card > Padding(all:12) > Column
//   標題文字（titleSmall w600）
//   SizedBox(height:144) Stack：
//     PieChart 外環（裝飾）：centerSpaceRadius=54, sectionRadius=15
//     SizedBox(110×110) PieChart 內環（主要）：centerSpaceRadius=30, sectionRadius=20
//     Column 中央文字（'Total'/'總計' 8sp + 數字 titleMedium bold）
//   Wrap 圖例（spacing=10, runSpacing=4, 圓點 9×9 + 文字 10sp）

class _OrderStatusDonut extends StatelessWidget {
  final List<OrderStatusCount> data;
  const _OrderStatusDonut({required this.data});

  // 主環色（較深）
  static const _colors = {
    'pending':   Color(0xFFE8A94D), // 橘黃
    'confirmed': Color(0xFF3A9DA8), // 青藍
    'shipped':   Color(0xFF87CEDC), // 淡藍
    'cancelled': Color(0xFFB0C4CE), // 灰藍
  };

  // 外裝飾環色（較淺，約比主環亮 30%）
  static const _lightColors = {
    'pending':   Color(0xFFF2CA80),
    'confirmed': Color(0xFF72C0CB),
    'shipped':   Color(0xFFB2E1ED),
    'cancelled': Color(0xFFCDD9E0),
  };

  @override
  Widget build(BuildContext context) {
    final s     = AppStrings.of(context);
    final total = data.fold(0, (sum, d) => sum + d.count);

    // 產生 PieChartSectionData 列表的共用函式
    // colorMap：選用主色或淺色；radius：扇形徑向厚度（dp）
    List<PieChartSectionData> buildSections(
            Map<String, Color> colorMap, double radius,
            {String titleMode = 'both'}) =>    // ← 命名參數：'none' | 'count' | 'percent'
        data
            .map((d) => PieChartSectionData(
                  value: d.count.toDouble(),
                  color: colorMap[d.status] ?? Colors.grey,
                  radius: radius,    // ← 扇形厚度（dp）：外環=15, 內環=20
                  showTitle: titleMode != 'none',
                  title: titleMode == 'count'
                      ? '${d.count}'
                      : titleMode == 'percent'
                          ? '${(d.count / total * 100).toStringAsFixed(0)}%'
                          : '',
                  titleStyle: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                  titlePositionPercentageOffset: 0.55,
                ))
            .toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(11), // ← 環形圖卡四周內距 11 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題 ───────────────────────────────────────────────────────
            Text(
              s.isEnglish ? 'Order Status' : '訂單狀態',
              style: Theme.of(context).textTheme.titleSmall?.copyWith( // ← titleSmall（14 sp）
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 9), // ← 標題 → 環形圖的垂直間隔 9 dp

            // ── 雙環圖區域（高度固定 144 dp）──────────────────────────────
            SizedBox(
              height: 144, // ← 環形圖區域總高度 144 dp；可調整
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // 外裝飾環：佔滿 144dp 高度，centerSpaceRadius=54 → 外環佔 15dp 徑向
                  PieChart(
                    PieChartData(
                      sectionsSpace: 2,          // ← 各扇形間隔縫 2 dp
                      centerSpaceRadius: 54,     // ← 外環空心半徑 54 dp（內圓半徑）
                      sections: buildSections(_lightColors, 15, titleMode: 'percent'), // ← 外環顯示百分比
                    ),
                  ),

                  // 內主環：限定在 110×110 dp 容器內，centerSpaceRadius=30 → 可見厚度約 25dp
                  SizedBox(
                    width:  110, // ← 內環容器寬度 110 dp
                    height: 110, // ← 內環容器高度 110 dp
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,         // ← 各扇形間隔縫 2 dp
                        centerSpaceRadius: 30,    // ← 內環空心半徑 30 dp
                        sections: buildSections(_colors, 20, titleMode: 'count'), // ← 內環顯示數字
                      ),
                    ),
                  ),

                  // 中央數字：'Total'/'總計'（8 sp, 半透明）+ 總數（titleMedium bold）
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        s.isEnglish ? 'Total' : '總計',
                        style: TextStyle(
                            fontSize: 9, // ← 中央小標題字型 9 sp；可調整 8–10
                            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5)),
                      ),
                      Text(
                        '$total',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith( // ← titleMedium（16 sp）
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 9), // ← 環形圖 → 圖例的垂直間隔 9 dp

            // ── 圖例（Wrap 自動換行）──────────────────────────────────────
            Wrap(
              spacing: 6,    // ← 圖例項目水平間距 6 dp
              runSpacing: 4,  // ← 圖例換行後的垂直間距 4 dp
              children: data.map((d) {
                final color = _colors[d.status] ?? Colors.grey;
                final label = _statusLabel(d.status, s);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8, height: 8, // ← 圖例圓點尺寸 8×8 dp
                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 4), // ← 圓點 → 文字間距 4 dp
                    Text(label, style: const TextStyle(fontSize: 10)), // ← 圖例文字 10 sp
                  ],
                );
              }).toList(),
            ),
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
//
// 佈局：Card > Padding(all:12) > Column
//   標題（titleSmall w600）
//   ...最多 5 個 Padding(bottom:8) > Column
//     Row(排名. | 產品名 | 數量)  → fontSize 10/11/11
//     LinearProgressIndicator(minHeight:6, 圓角 2)

class _TopProductsBar extends StatelessWidget {
  final List<TopProduct> data;
  const _TopProductsBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
    final maxQty = data.map((p) => p.totalQty).fold(0, (a, b) => a > b ? a : b);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(11), // ← Top 5 卡四周內距 11 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題 ───────────────────────────────────────────────────────
            Text(
              s.isEnglish ? 'Top 5 Products (30d)' : 'Top 5 產品（近 30 天）',
              style: Theme.of(context).textTheme.titleSmall?.copyWith( // ← titleSmall（14 sp）
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8), // ← 標題 → 第一條的垂直間隔 8 dp

            // ── 逐項產品列 ─────────────────────────────────────────────────
            ...data.asMap().entries.map((entry) {
              final idx  = entry.key;
              final prod = entry.value;
              final frac = maxQty == 0 ? 0.0 : prod.totalQty / maxQty; // 0.0~1.0

              return Padding(
                padding: const EdgeInsets.only(bottom: 8), // ← 每條之間的垂直間隔 8 dp
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 排名 + 產品名 + 數量
                    Row(
                      children: [
                        Text('${idx + 1}.',
                            style: TextStyle(
                              fontSize: 10, // ← 排名序號字型 10 sp
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            )),
                        const SizedBox(width: 4), // ← 序號 → 產品名間距 4 dp
                        Expanded(
                          child: Text(prod.name,
                              style: const TextStyle(fontSize: 11), // ← 產品名字型 11 sp
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text('${prod.totalQty}',
                            style: const TextStyle(
                                fontSize: 11,           // ← 數量字型 11 sp
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 3), // ← 文字 → 進度條間距 3 dp

                    // 進度條（以最大值 maxQty 為 100%）
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2), // ← 進度條圓角 2 dp
                      child: LinearProgressIndicator(
                        value: frac,        // ← 比例值 0.0~1.0
                        minHeight: 6,       // ← 進度條高度 6 dp；可調整 4–10
                        backgroundColor:
                            Theme.of(context).colorScheme.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          // primary 色 + alpha 200（約 78% 不透明）
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
//
// 佈局：Card > Padding(all:16) > Column
//   Row(icon 18 + 標題 titleSmall w600)
//   Row(4 個 Expanded _FunnelKpi)   → bodySmall 標籤 / bodyMedium+w600 數值
//   LinearProgressIndicator(minHeight:8, 圓角 3)
//   Row(過期數 10sp red + 待轉換 10sp onSurfaceVariant)

class _FunnelCard extends StatelessWidget {
  final FunnelData data;
  const _FunnelCard({required this.data});

  @override
  Widget build(BuildContext context) {
    final d = data;
    final s = AppStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16), // ← 漏斗卡四周內距 16 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題 ───────────────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.filter_alt_outlined, size: 18), // ← icon 18 dp
              const SizedBox(width: 6),                        // ← icon → 標題間距 6 dp
              Text(s.dashQuotFunnelTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith( // ← titleSmall（14 sp）
                      fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 12), // ← 標題 → KPI 格間距 12 dp

            // ── 四個 KPI 格（報價數 / 已轉換 / 轉換率 / 平均天數）──────────
            Row(children: [
              Expanded(child: _FunnelKpi(label: s.dashQuotCreated,   value: '${d.totalQuotations}')),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotConverted,
                value: '${d.converted}',
                valueColor: Colors.green.shade700,
              )),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotRate,
                value: '${d.conversionRate.toStringAsFixed(1)}%', // ← 轉換率 1 位小數
                // 50% 以上 → green；以下 → orange
                valueColor: d.conversionRate >= 50 ? Colors.green.shade700 : Colors.orange,
              )),
              Expanded(child: _FunnelKpi(
                label: s.dashQuotAvgDays,
                value: d.avgDaysToConvert != null
                    ? s.dashQuotDays(d.avgDaysToConvert!.toStringAsFixed(1)) // ← 平均天數 1 位小數
                    : '—',
              )),
            ]),
            const SizedBox(height: 8), // ← KPI 格 → 進度條間距 8 dp

            // ── 進度條（轉換率視覺化）──────────────────────────────────────
            ClipRRect(
              borderRadius: BorderRadius.circular(3), // ← 進度條圓角 3 dp
              child: LinearProgressIndicator(
                value: d.totalQuotations > 0 ? d.converted / d.totalQuotations : 0,
                minHeight: 8,        // ← 進度條高度 8 dp；比 Top 5 的 6dp 略高
                backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.green.shade600),
              ),
            ),
            const SizedBox(height: 4), // ← 進度條 → 底部標籤間距 4 dp

            // ── 底部輔助資訊（過期數 + 待轉換數）──────────────────────────
            Row(children: [
              Text('${s.dashQuotExpired} ${d.expiredCount}',
                  style: TextStyle(fontSize: 10, color: Colors.red.shade400)), // ← 10 sp, 紅色
              const SizedBox(width: 10), // ← 間距 10 dp
              Text('${s.dashQuotPending} ${d.pendingCount}',
                  style: TextStyle(fontSize: 10,                               // ← 10 sp
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ]),
          ],
        ),
      ),
    );
  }
}

// 漏斗：單一 KPI 格（與 _ProfitKpi 結構相同）
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
        Text(label, style: Theme.of(context).textTheme.bodySmall), // ← 標籤 bodySmall（12 sp）
        const SizedBox(height: 2),                                  // ← 標籤 → 數值間距 2 dp
        Text(value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith( // ← 數值 bodyMedium（14 sp）
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
//
// 整體佈局：Card > Padding(left:12, top:14, right:16, bottom:10) > Column
//   Row(icon 18 + 標題 titleSmall w600 + _ComboLegend)
//   SizedBox(height:150) Stack：
//     Layer 1：BarChart（出貨量，左 Y 軸）
//     Layer 2：IgnorePointer > LineChart（營收，右 Y 軸，正規化到左 Y 軸範圍）
//
// 軸保留空間（reserved size）：
//   _leftRes  = 40 dp → 左 Y 軸數字欄位寬度
//   _rightRes = 25 dp → 右 Y 軸數字欄位寬度，影響靠右位置的圖例對齊
//   _botRes   = 20 dp → 底部月份標籤高度
//
// Y 軸刻度：
//   左軸（出貨量）：maxY = max(totalOutbound) × 1.25，最小值 10
//   右軸（營收）：右軸標籤 = 正規化值 / maxY × maxRev，再用 _fmtK 轉 K/M

class _ShipmentRevenueComboChart extends StatelessWidget {
  final List<InventoryTrendPoint> shipmentData;
  final List<RevenuePoint>?       revenueData;

  const _ShipmentRevenueComboChart({
    required this.shipmentData,
    this.revenueData,
  });

  // ── 軸保留空間（px/dp）── 調整這三個值可改變軸標籤欄位寬度/高度
  static const double _leftRes  = 40; // ← 左 Y 軸（出貨量數字）欄位寬 40 dp
  static const double _rightRes = 25; // ← 右 Y 軸（營收數字）欄位寬 25 dp
  static const double _botRes   = 20; // ← 底部月份標籤欄位高 20 dp

  @override
  Widget build(BuildContext context) {
    final s            = AppStrings.of(context);
    final outlineColor = Theme.of(context).colorScheme.outlineVariant;

    // 以月份字串為 key 建立快查表
    final revMap = <String, double>{};
    for (final p in revenueData ?? []) {
      revMap[p.month] = p.revenue;
    }
    final hasRevenue = revMap.isNotEmpty;

    // 左 Y 軸最大值：最大出貨量 × 1.25，不足 10 則補 10
    final maxOut = shipmentData
        .map((p) => p.totalOutbound.toDouble())
        .fold(0.0, (a, b) => a > b ? a : b);
    final maxY = maxOut * 1.25 < 1 ? 10.0 : maxOut * 1.25;

    // 右 Y 軸最大值（僅用於正規化計算，不直接顯示）
    final maxRev = hasRevenue
        ? revenueData!.map((p) => p.revenue).fold(0.0, (a, b) => a > b ? a : b)
        : 0.0;

    // ── Layer 1：柱狀圖資料 ───────────────────────────────────────────────
    final barGroups = shipmentData.asMap().entries.map((e) => BarChartGroupData(
      x: e.key,
      barRods: [
        BarChartRodData(
          toY: e.value.totalOutbound.toDouble(), // ← 柱高 = 出貨量（左 Y 軸）
          color: Colors.orange,                  // ← 柱狀顏色：橘色
          width: 15,                             // ← 柱寬 15 dp；⟨F⟩ 調寬：改 16–20
          borderRadius: const BorderRadius.vertical(top: Radius.circular(3)), // ← 柱頂圓角 3 dp
        ),
      ],
    )).toList();

    // ── Layer 2：折線圖資料（正規化至左 Y 軸範圍，以便疊層顯示）──────────
    // 公式：lineY = (revenue / maxRev) × maxY
    final lineSpots = hasRevenue
        ? shipmentData.asMap().entries.map((e) {
            final rev = revMap[e.value.month] ?? 0.0;
            return FlSpot(e.key.toDouble(), maxRev > 0 ? rev / maxRev * maxY : 0.0);
          }).toList()
        : <FlSpot>[];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
        // ← 卡內距：左 16 / 上 14 / 右 8 / 下 10 dp
        // 右側留 8（比左側少 8）是為了讓右 Y 軸數字不貼邊?
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題列（icon + 文字 + 圖例）──────────────────────────────
            Row(children: [
              const Icon(Icons.inventory_2_outlined, size: 18), // ← icon 18 dp
              const SizedBox(width: 6),                          // ← icon → 標題間距 6 dp
              Expanded(
                child: Text(
                  s.isEnglish
                      ? 'Monthly Shipment & Revenue Trends'
                      : '月度出貨與營收',
                  style: Theme.of(context).textTheme.titleSmall  // ← titleSmall（14 sp）
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              // ⟨I⟩ 若需讓 Legend 水平對齊右 Y 軸（_rightRes = 25 dp），改為：
              // SizedBox(
              //   width: _rightRes,
              //   child: _ComboLegend(
              //     barColor: Colors.orange,
              //     lineColor: Colors.teal,
              //     barLabel: s.isEnglish ? 'Outbound' : '出貨量',
              //     lineLabel: s.isEnglish ? 'Revenue' : '營收',
              //   ),
              // ),
              _ComboLegend(
                barColor: Colors.orange,
                lineColor: Colors.teal,
                barLabel: s.isEnglish ? 'Outbound' : '出貨量',
                lineLabel: s.isEnglish ? 'Revenue' : '營收',
              ),
            ]),
            const SizedBox(height: 12), // ← 標題 → 圖表區間距 12 dp

            // ── 圖表區（固定高度 145 dp）──────────────────────────────────
            SizedBox(
              height: 145, // ← 圖表區高度 145 dp；可調整（推薦 120–200）
              child: Stack(children: [

                // ── Layer 1：BarChart（柱狀，出貨量）──────────────────────
                BarChart(BarChartData(
                  maxY: maxY, // ← 左 Y 軸上限（自動計算）
                  barGroups: barGroups,
                  groupsSpace: 28, // ← 柱組水平間距 28 dp；⟨G⟩ 縮小：改 20–25

                  // 格線設定
                  gridData: FlGridData(
                    drawVerticalLine: false,     // ← 不畫垂直格線
                    getDrawingHorizontalLine: (_) =>
                        FlLine(color: outlineColor, strokeWidth: 0.5), // ← 水平格線粗細 0.5 dp
                  ),
                  borderData: FlBorderData(show: false), // ← 不顯示外框

                  // 軸標題設定
                  titlesData: FlTitlesData(
                    // 左 Y 軸：出貨量數字
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _leftRes, // ← 左軸欄位寬 40 dp
                        getTitlesWidget: (val, _) => Text(
                          val.toInt().toString(),
                          style: const TextStyle(fontSize: 9), // ← 左軸數字 9 sp
                        ),
                      ),
                    ),
                    // 右 Y 軸（BarChart 層不顯示，但需保留空間以對齊 LineChart）
                    rightTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: hasRevenue ? _rightRes : 4, // ← 有營收時 44 dp，否則 4 dp
                        getTitlesWidget: (_, __) => const SizedBox.shrink(), // 隱藏
                      ),
                    ),
                    // 底部 X 軸：月份標籤
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: _botRes, // ← 底部月份欄位高 20 dp
                        getTitlesWidget: (val, _) {
                          final idx = val.toInt();
                          if (idx < 0 || idx >= shipmentData.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4), // ← 月份標籤上方間距 4 dp
                            child: Text(
                              s.monthLabel(shipmentData[idx].month),
                              style: const TextStyle(fontSize: 9), // ← 月份標籤字型 9 sp
                            ),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false), // 不顯示頂部軸
                    ),
                  ),

                  // Tooltip（長按/點擊柱狀時顯示）
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => Colors.black87, // ← Tooltip 背景色
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
                          const TextStyle(fontSize: 10, color: Colors.white), // ← Tooltip 文字 10 sp
                        );
                      },
                    ),
                  ),
                )),

                // ── Layer 2：LineChart 疊加（營收，右 Y 軸）──────────────
                // IgnorePointer：讓觸控事件穿透到下層 BarChart
                // minX=-0.5 / maxX=n-0.5：使折線點對齊柱狀中心
                if (hasRevenue)
                  IgnorePointer(
                    child: LineChart(LineChartData(
                      minX: -0.75,                                   // ← X 軸起點偏移 -0.5（對齊第一根柱中心）
                      maxX: shipmentData.length.toDouble() - 0.25,   // ← X 軸終點偏移 -0.5（對齊最後一根柱中心）
                      minY: 0,
                      maxY: maxY, // ← 與 BarChart 共用同一 Y 軸上限，確保視覺對齊

                      gridData: const FlGridData(show: false), // ← LineChart 不畫格線（避免重疊）
                      borderData: FlBorderData(show: false),

                      titlesData: FlTitlesData(
                        // 左軸：保留空間但不顯示（已由 BarChart 顯示）
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _leftRes, // ← 左軸欄位寬 40 dp（與 BarChart 對齊）
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                        // 右 Y 軸：顯示還原後的實際營收（K/M 格式，青色）
                        rightTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _rightRes,     // ← 右軸欄位寬 44 dp
                            interval: maxY / 4,          // ← 右軸顯示 4 個刻度（0 / 25% / 50% / 75% / 100%）
                            getTitlesWidget: (val, _) {
                              // 正規化反算：顯示值 = val / maxY × maxRev
                              final actual = maxRev > 0 ? val / maxY * maxRev : 0.0;
                              // ⟨J⟩ 右軸 label 往右偏移：在 Text 外包 Padding(left: X)
                              //   X 加大 → label 更靠右邊框；reservedSize(_rightRes) 若不夠寬需同步調大
                              return Padding(
                                padding: const EdgeInsets.only(left: 6),
                                child: Text(_fmtK(actual),
                                  style: const TextStyle(fontSize: 9, color: Colors.teal)),
                                );
                              // return Text(
                              //   _fmtK(actual),
                              //   style: const TextStyle(
                              //    fontSize: 9, color: Colors.teal), // ← 右軸數字 9 sp，青色
                              // );
                            },
                          ),
                        ),
                        // 底部：保留空間但不顯示（已由 BarChart 顯示月份標籤）
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: _botRes, // ← 底部欄位高 20 dp（與 BarChart 對齊）
                            getTitlesWidget: (_, __) => const SizedBox.shrink(),
                          ),
                        ),
                        topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false),
                        ),
                      ),

                      // ⟨H⟩ 折線數值標籤：取消下方註解後每個資料點將顯示還原後的營收數值
                      // showingTooltipIndicators: lineSpots.asMap().entries.map((e) =>
                      //   ShowingTooltipIndicators([LineBarSpot(lineSpots[e.key], 0, lineSpots[e.key])])
                      // ).toList(),
                      lineBarsData: [
                        LineChartBarData(
                          spots: lineSpots,
                          isCurved: true,          // ← 折線平滑曲線（true）；改 false 為折線
                          color: Colors.teal,      // ← 折線顏色：青色
                          barWidth: 2.5,           // ← 折線粗細 2.5 dp；可調整 1–4
                          dotData: FlDotData(
                            getDotPainter: (_, __, ___, ____) =>
                                FlDotCirclePainter(
                                    radius: 3,         // ← 資料點圓點半徑 3 dp；可調整 2–5
                                    color: Colors.teal,
                                    strokeWidth: 0),   // ← 圓點邊框 0（無邊框）
                          ),
                          belowBarData: BarAreaData(show: false), // ← 不填充折線下方區域
                        ),
                      ],
                      lineTouchData: const LineTouchData(
                        enabled: false, // ← 折線層不處理觸控
                        // ⟨H-tip⟩ Tooltip 樣式（需搭配 ⟨H⟩ showingTooltipIndicators 一起啟用；同時移除上方 const）
                        // touchTooltipData: LineTouchTooltipData(
                        //   getTooltipColor: (_) => Colors.teal.withOpacity(0.8),
                        //   getTooltipItems: (spots) => spots.map((s) {
                        //     final actual = maxRev > 0 ? s.y / maxY * maxRev : 0.0;
                        //     return LineTooltipItem(_fmtK(actual),
                        //         const TextStyle(fontSize: 8, color: Colors.white));
                        //   }).toList(),
                        // ),
                      ),
                    )),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  // 將數值格式化：≥1M → "1.1M"，≥1K → "123K"，其他 → 整數
  String _fmtK(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(1)}M';
    if (val >= 1000)    return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }
}

// ==============================================================================
// 圖表 6：客戶下單熱力圖
// ==============================================================================
//
// 佈局：Card > Padding(all:12) > Column
//   Row(icon 18 + 標題 titleSmall w600)
//   LayoutBuilder → 計算格子寬度
//     標題行：Row(nameW=80 + n×SizedBox(cellW))   → 9 sp bold
//     資料行：Row(nameW=80 + n×Container(cellW×22, 圓角 3))
//       格子內文字：9 sp w600
//
// 格子寬度計算：cellW = (可用寬度 - 80) / 月份數
// 色階：count=0 → surfaceContainerHighest；1 → blue.100；2~3 → blue.300；4+ → blue.600

class _CustomerHeatmapCard extends StatelessWidget {
  final List<CustomerHeatmapRow> rows;
  final List<String>             months;
  const _CustomerHeatmapCard({required this.rows, required this.months});

  // 根據訂單數量決定格子顏色（4 個色階）
  Color _cellColor(BuildContext context, int count) {
    if (count == 0) return Theme.of(context).colorScheme.surfaceContainerHighest; // ← 0：灰底
    if (count == 1) return Colors.blue.shade100;  // ← 1：淡藍
    if (count <= 3) return Colors.blue.shade300;  // ← 2~3：中藍
    return Colors.blue.shade600;                  // ← 4+：深藍
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final shortMonths = months.map((m) => s.monthLabel(m)).toList();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12), // ← 熱力圖卡四周內距 12 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 標題 ───────────────────────────────────────────────────────
            Row(children: [
              const Icon(Icons.grid_on_outlined, size: 18), // ← icon 18 dp
              const SizedBox(width: 6),                      // ← icon → 標題間距 6 dp
              Flexible(
                child: Text(s.dashHeatmapTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith( // ← titleSmall（14 sp）
                        fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 10), // ← 標題 → 熱力格的垂直間隔 10 dp

            // ── 熱力格（LayoutBuilder 讓格子填滿卡片寬度）──────────────────
            LayoutBuilder(builder: (context, constraints) {
              const nameW = 80.0; // ← 客戶名稱欄固定寬度 80 dp；可調整 60–100
              final n = months.isEmpty ? 1 : months.length;
              // 格子寬度 = (卡片可用寬度 - 名稱欄) / 月份數，取整數避免浮點誤差
              final cellW = ((constraints.maxWidth - nameW) / n).floorToDouble();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 月份標題行
                  Row(children: [
                    const SizedBox(width: nameW), // ← 左邊名稱欄佔位
                    ...shortMonths.map((m) => SizedBox(
                      width: cellW, // ← 每個月份標題欄位寬 = cellW dp
                      child: Text(m,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w500)), // ← 月份標籤 9 sp bold
                    )),
                  ]),
                  const SizedBox(height: 4), // ← 月份標題 → 第一個客戶行間距 4 dp

                  // 客戶資料行
                  ...rows.map((row) => Padding(
                    padding: const EdgeInsets.only(bottom: 3), // ← 每行之間的垂直間距 3 dp
                    child: Row(children: [
                      // 客戶名稱
                      SizedBox(
                        width: nameW, // ← 名稱欄寬 80 dp
                        child: Text(row.name,
                            style: const TextStyle(fontSize: 10), // ← 客戶名字型 10 sp
                            overflow: TextOverflow.ellipsis),
                      ),
                      // 各月訂單數格子
                      ...row.counts.map((count) => Container(
                        width: cellW,  // ← 格子寬度（動態計算）
                        height: 22,    // ← 格子高度 22 dp；可調整 18–28
                        padding: const EdgeInsets.symmetric(horizontal: 1), // ← 格子內左右邊距 1 dp
                        decoration: BoxDecoration(
                          color: _cellColor(context, count), // ← 色階決定背景色
                          borderRadius: BorderRadius.circular(3), // ← 格子圓角 3 dp
                        ),
                        alignment: Alignment.center,
                        child: count > 0
                            ? Text('$count',
                                style: TextStyle(
                                  fontSize: 9,                                          // ← 格子內數字 9 sp
                                  color: count >= 4 ? Colors.white : Colors.blue.shade800,
                                  // ← 深藍格（4+）→ 白字；其他 → 深藍字
                                  fontWeight: FontWeight.w600,
                                ))
                            : null, // ← 0 訂單時不顯示文字
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

// KPI 摘要卡（現有 Widget）
//
// 佈局：Card > Padding(horizontal:16, vertical:14) > Column
//   Row(icon 18 + label bodySmall onSurfaceVariant)
//   Row(value headlineSmall bold + unit bodySmall onSurfaceVariant)

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
        // ← KPI 卡內距：水平 16 dp, 垂直 14 dp
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 18, color: iconColor), // ← icon 18 dp
                const SizedBox(width: 6),               // ← icon → 標籤間距 6 dp
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← bodySmall（12 sp）
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8), // ← 標籤 → 數值間距 8 dp
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith( // ← headlineSmall（24 sp）
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(width: 4), // ← 數值 → 單位間距 4 dp
                Padding(
                  padding: const EdgeInsets.only(bottom: 2), // ← 單位文字底部偏移 2 dp（對齊基線）
                  child: Text(
                    unit,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← 單位 bodySmall（12 sp）
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

// 低庫存警告區（現有 Widget）
//
// 佈局：Column
//   Row(icon 18 警告色 + 標題 titleSmall w600 + 數量 bodySmall orange)
//   SizedBox(height:8)
//   若無低庫存 → Padding(vertical:12) Text bodySmall
//   若有低庫存 → ...items.map(_LowStockTile)

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
                  size: 18, // ← 警告 icon 18 dp
                  color: items.isEmpty ? Colors.grey : Colors.orange,
                ),
                const SizedBox(width: 6), // ← icon → 標題間距 6 dp
                Text(
                  s.dashLowStockAlert,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith( // ← titleSmall（14 sp）
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(width: 8), // ← 標題 → 數量標籤間距 8 dp
                if (items.isNotEmpty)
                  Text(
                    countLabel,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← 數量標籤 bodySmall（12 sp）
                          color: Colors.orange,
                        ),
                  ),
              ],
            ),
            const SizedBox(height: 8), // ← 標題 → 列表間距 8 dp
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12), // ← 無低庫存提示垂直內距 12 dp
                child: Text(
                  s.dashNoLowStock,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← bodySmall（12 sp）
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

// 低庫存：單一品項 Tile
//
// 佈局：Card(margin bottom:8) > Padding(horizontal:14, vertical:10)
//   Row：
//     左：Expanded Column(產品名 14 sp w600 + SKU bodySmall)
//     右：Column(右對齊)
//       Row(icon 13 + 庫存數 12 sp orange w600)
//       Text(在庫/已預留  bodySmall)
//       Text(安全庫存/短缺  bodySmall)

class _LowStockTile extends StatelessWidget {
  final LowStockItem item;
  const _LowStockTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final shortage = item.minStockLevel - item.available;

    return Card(
      margin: const EdgeInsets.only(bottom: 8), // ← 每個 Tile 底部間距 8 dp
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        // ← Tile 內距：水平 14 dp, 垂直 10 dp
        child: Row(
          children: [
            // 左側：產品名 + SKU
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.productName,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14), // ← 產品名 14 sp w600
                  ),
                  const SizedBox(height: 2), // ← 產品名 → SKU 間距 2 dp
                  Text(
                    item.sku,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← SKU bodySmall（12 sp）
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            // 右側：庫存數值（橘色）+ 在庫/預留 + 安全庫存
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 13, color: Colors.orange), // ← icon 13 dp
                    const SizedBox(width: 4), // ← icon → 文字間距 4 dp
                    Text(
                      s.dashAvailable(item.available),
                      style: const TextStyle(fontSize: 12, color: Colors.orange, fontWeight: FontWeight.w600),
                      // ← 可用庫存：12 sp, 橘色, w600
                    ),
                  ],
                ),
                const SizedBox(height: 2), // ← 庫存行 → 在庫/預留行間距 2 dp
                Text(
                  s.dashOnHandReserved(item.onHand, item.reserved),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← bodySmall（12 sp）
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2), // ← 在庫/預留行 → 安全庫存行間距 2 dp
                Text(
                  s.dashSafetyShortage(item.minStockLevel, shortage),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith( // ← bodySmall（12 sp）
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
