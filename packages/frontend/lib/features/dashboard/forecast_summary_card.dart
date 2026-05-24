// ==============================================================================
// ForecastSummaryCard — Phase 4 PR-5 M5.1
//
// Dashboard 補貨預測警示卡片。
// 監聽本地低庫存品項 Stream，觸發 ForecastProvider 計算 Top 3 補貨警示。
//
// 顯示邏輯：
//   - 低庫存 + 預測上升 → 紅色警示列
//   - 點擊警示列 → 跳轉 ProductForecastScreen
//   - 無警示 / 尚無預測 → empty state 提示
// ==============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../providers/forecast_provider.dart';
import '../products/product_forecast_screen.dart';

class ForecastSummaryCard extends StatefulWidget {
  final AppDatabase db;
  const ForecastSummaryCard({super.key, required this.db});

  @override
  State<ForecastSummaryCard> createState() => _ForecastSummaryCardState();
}

class _ForecastSummaryCardState extends State<ForecastSummaryCard> {
  StreamSubscription<List<LowStockItem>>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.db.watchLowStockItems().listen((items) {
      if (!mounted) return;
      context.read<ForecastProvider>().fetchReorderAlerts(items);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final forecast = context.watch<ForecastProvider>();
    final s        = AppStrings.of(context);
    final scheme   = Theme.of(context).colorScheme;
    final text     = Theme.of(context).textTheme;

    final alerts = forecast.reorderAlerts;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ────────────────────────────────────────
            Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  size: 18,
                  color: scheme.error,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.forecastAlertTitle,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (forecast.alertsLoading)
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Body ──────────────────────────────────────────
            if (alerts == null && !forecast.alertsLoading)
              // 尚無預測資料
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  s.forecastNoData,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (alerts != null && alerts.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  s.forecastNoAlert,
                  style: text.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else if (alerts != null)
              ...alerts.map((alert) => _AlertTile(alert: alert)),
          ],
        ),
      ),
    );
  }
}

// ── 單筆補貨警示列 ─────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final ReorderAlert alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    final text   = Theme.of(context).textTheme;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProductForecastScreen(
            initialProductId: alert.productId,
            initialSku:       alert.sku,
          ),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            // 警告圖示
            Icon(
              Icons.warning_amber_rounded,
              size: 18,
              color: scheme.error,
            ),
            const SizedBox(width: 8),

            // 產品資訊
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    alert.sku,
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  Text(
                    alert.productName,
                    style: text.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // 預測量 vs 庫存
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (alert.isRising)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      s.forecastRisingBadge,
                      style: text.labelSmall?.copyWith(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  s.forecastQty4wVsStock(
                    alert.forecastQty4w.round(),
                    alert.currentStock,
                  ),
                  style: text.bodySmall?.copyWith(
                    color: scheme.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),

            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
