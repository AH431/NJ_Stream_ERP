// ==============================================================================
// AnalyticsProvider — Phase 2 P2-VIS Wave 1 + Wave 2
//
// 負責從後端 /api/v1/analytics/* 拉取聚合資料，並在記憶體中快取 15 分鐘。
//
// 設計原則：
//   - 純讀取，不觸碰同步協定，不寫 PendingOperations
//   - 複用 SyncProvider.authenticatedDio（已注入 token refresh interceptor）
//   - 離線 / 未登入時靜默失敗，圖表顯示上次快取或空狀態
//   - 快取失效後由 UI 的 RefreshIndicator 主動觸發重拉
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class RevenuePoint {
  final String month;   // 'YYYY-MM'
  final double revenue;
  const RevenuePoint({required this.month, required this.revenue});
}

class OrderStatusCount {
  final String status;
  final int count;
  const OrderStatusCount({required this.status, required this.count});
}

class TopProduct {
  final int    id;
  final String name;
  final String sku;
  final int    totalQty;
  final double totalRevenue;
  const TopProduct({
    required this.id,
    required this.name,
    required this.sku,
    required this.totalQty,
    required this.totalRevenue,
  });
}

class ProfitPoint {
  final String  month;
  final double  revenue;
  final double  cogs;
  final double? grossMarginPct;
  double get grossProfit => revenue - cogs;
  const ProfitPoint({
    required this.month,
    required this.revenue,
    required this.cogs,
    this.grossMarginPct,
  });
}

// ── Wave 2 模型 ───────────────────────────────────────────

class CustomerHeatmapRow {
  final int         customerId;
  final String      name;
  final List<int>   counts; // 與 monthLabels 對齊，各月訂單數
  const CustomerHeatmapRow({
    required this.customerId,
    required this.name,
    required this.counts,
  });
}

class FunnelData {
  final int    totalQuotations;
  final int    converted;
  final double conversionRate;
  final int    expiredCount;
  final int    pendingCount;
  final double? avgDaysToConvert;
  const FunnelData({
    required this.totalQuotations,
    required this.converted,
    required this.conversionRate,
    required this.expiredCount,
    required this.pendingCount,
    this.avgDaysToConvert,
  });
}

class InventoryTrendPoint {
  final String month;
  final int    totalOutbound;
  final int    activeProducts;
  const InventoryTrendPoint({
    required this.month,
    required this.totalOutbound,
    required this.activeProducts,
  });
}

// ── 快取容器 ──────────────────────────────────────────────

class _CacheEntry<T> {
  final T data;
  final DateTime fetchedAt;
  const _CacheEntry(this.data, this.fetchedAt);
  bool get isStale =>
      DateTime.now().difference(fetchedAt).inMinutes >= 15;
}

// ── AnalyticsProvider ──────────────────────────────────────

class AnalyticsProvider extends ChangeNotifier {
  final Dio _dio;

  AnalyticsProvider({required Dio dio}) : _dio = dio;

  // ── 快取 ────────────────────────────────────────────────
  _CacheEntry<List<RevenuePoint>>?      _revenueCache;
  _CacheEntry<List<OrderStatusCount>>?  _statusCache;
  _CacheEntry<List<TopProduct>>?        _topProductsCache;
  _CacheEntry<List<ProfitPoint>>?       _profitCache;
  // Wave 2
  _CacheEntry<(List<CustomerHeatmapRow>, List<String>)>? _heatmapCache;
  _CacheEntry<FunnelData>?              _funnelCache;
  _CacheEntry<List<InventoryTrendPoint>>? _inventoryTrendCache;

  // ── 載入狀態 ────────────────────────────────────────────
  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? get lastFetchedAt => _revenueCache?.fetchedAt;

  // ── 資料 Getters（快取未命中回傳 null，UI 顯示骨架）──────

  List<RevenuePoint>?    get revenueData    => _revenueCache?.data;
  List<OrderStatusCount>? get statusData   => _statusCache?.data;
  List<TopProduct>?      get topProductData => _topProductsCache?.data;
  List<ProfitPoint>?     get profitData     => _profitCache?.data;
  // Wave 2
  List<CustomerHeatmapRow>? get heatmapData    => _heatmapCache?.data.$1;
  List<String>?             get heatmapMonths  => _heatmapCache?.data.$2;
  FunnelData?               get funnelData     => _funnelCache?.data;
  List<InventoryTrendPoint>? get inventoryTrendData => _inventoryTrendCache?.data;

  // ── 公開方法 ─────────────────────────────────────────────

  /// 若快取未過期則跳過，[force] 可強制重拉。
  Future<void> fetchAll({bool force = false}) async {
    if (_loading) return;
    final allFresh = !force &&
        _revenueCache        != null && !_revenueCache!.isStale &&
        _statusCache         != null && !_statusCache!.isStale  &&
        _topProductsCache    != null && !_topProductsCache!.isStale &&
        _profitCache         != null && !_profitCache!.isStale &&
        _heatmapCache        != null && !_heatmapCache!.isStale &&
        _funnelCache         != null && !_funnelCache!.isStale &&
        _inventoryTrendCache != null && !_inventoryTrendCache!.isStale;
    if (allFresh) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchRevenue(),
        _fetchOrderStatus(),
        _fetchTopProducts(),
        _fetchProfit(),
        _fetchHeatmap(),
        _fetchFunnel(),
        _fetchInventoryTrend(),
      ]);

      final now = DateTime.now();
      _revenueCache        = _CacheEntry(results[0] as List<RevenuePoint>,    now);
      _statusCache         = _CacheEntry(results[1] as List<OrderStatusCount>, now);
      _topProductsCache    = _CacheEntry(results[2] as List<TopProduct>,       now);
      _profitCache         = _CacheEntry(results[3] as List<ProfitPoint>,      now);
      _heatmapCache        = _CacheEntry(results[4] as (List<CustomerHeatmapRow>, List<String>), now);
      _funnelCache         = _CacheEntry(results[5] as FunnelData,             now);
      _inventoryTrendCache = _CacheEntry(results[6] as List<InventoryTrendPoint>, now);
    } on DioException catch (e) {
      _error = e.response?.statusCode == 401
          ? 'auth_error'
          : 'network_error';
    } catch (e) {
      _error = 'unknown_error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── 個別 fetch helpers ──────────────────────────────────

  Future<List<RevenuePoint>> _fetchRevenue() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/analytics/revenue',
      queryParameters: {'months': 6},
    );
    final rows = (resp.data?['data'] as List?) ?? [];
    return rows.map((r) => RevenuePoint(
      month:   r['month'] as String,
      revenue: double.tryParse(r['revenue'].toString()) ?? 0.0,
    )).toList();
  }

  Future<List<OrderStatusCount>> _fetchOrderStatus() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/analytics/orders/status-summary',
    );
    final rows = (resp.data?['data'] as List?) ?? [];
    return rows.map((r) => OrderStatusCount(
      status: r['status'] as String,
      count:  (r['count'] as num).toInt(),
    )).toList();
  }

  Future<List<TopProduct>> _fetchTopProducts() async {
    final resp = await _dio.get<Map<String, dynamic>>(
      '/api/v1/analytics/products/top-sales',
      queryParameters: {'days': 30, 'limit': 5},
    );
    final rows = (resp.data?['data'] as List?) ?? [];
    return rows.map((r) => TopProduct(
      id:           (r['id'] as num).toInt(),
      name:         r['name'] as String,
      sku:          r['sku'] as String,
      totalQty:     (r['total_qty'] as num).toInt(),
      totalRevenue: double.tryParse(r['total_revenue'].toString()) ?? 0.0,
    )).toList();
  }

  Future<List<ProfitPoint>> _fetchProfit() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/analytics/profit',
        queryParameters: {'months': 6},
      );
      final rows = (resp.data?['data'] as List?) ?? [];
      return rows.map((r) => ProfitPoint(
        month:          r['month'] as String,
        revenue:        double.tryParse(r['revenue'].toString()) ?? 0.0,
        cogs:           double.tryParse(r['cogs'].toString()) ?? 0.0,
        grossMarginPct: r['gross_margin_pct'] == null
            ? null
            : double.tryParse(r['gross_margin_pct'].toString()),
      )).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return [];
      rethrow;
    }
  }

  Future<(List<CustomerHeatmapRow>, List<String>)> _fetchHeatmap() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/analytics/customers/heatmap',
        queryParameters: {'months': 6, 'limit': 10},
      );
      final rows       = (resp.data?['data'] as List?) ?? [];
      final monthsList = ((resp.data?['monthLabels'] as List?) ?? []).cast<String>();
      final customers = rows.map((r) => CustomerHeatmapRow(
        customerId: (r['customerId'] as num).toInt(),
        name:       r['name'] as String,
        counts:     ((r['counts'] as List?) ?? []).map((c) => (c as num).toInt()).toList(),
      )).toList();
      return (customers, monthsList);
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return (<CustomerHeatmapRow>[], <String>[]);
      rethrow;
    }
  }

  Future<FunnelData> _fetchFunnel() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/analytics/funnel',
        queryParameters: {'days': 30},
      );
      final d = resp.data?['data'] as Map<String, dynamic>? ?? {};
      return FunnelData(
        totalQuotations:  (d['totalQuotations'] as num?)?.toInt() ?? 0,
        converted:        (d['converted'] as num?)?.toInt() ?? 0,
        conversionRate:   (d['conversionRate'] as num?)?.toDouble() ?? 0.0,
        expiredCount:     (d['expiredCount'] as num?)?.toInt() ?? 0,
        pendingCount:     (d['pendingCount'] as num?)?.toInt() ?? 0,
        avgDaysToConvert: d['avgDaysToConvert'] != null
            ? (d['avgDaysToConvert'] as num).toDouble()
            : null,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) {
        return const FunnelData(
          totalQuotations: 0, converted: 0,
          conversionRate: 0, expiredCount: 0, pendingCount: 0,
        );
      }
      rethrow;
    }
  }

  Future<List<InventoryTrendPoint>> _fetchInventoryTrend() async {
    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/analytics/inventory/trend',
      );
      final rows = (resp.data?['data'] as List?) ?? [];
      return rows.map((r) => InventoryTrendPoint(
        month:          r['month'] as String,
        totalOutbound:  (r['total_outbound'] as num).toInt(),
        activeProducts: (r['active_products'] as num).toInt(),
      )).toList();
    } on DioException catch (e) {
      if (e.response?.statusCode == 403) return [];
      rethrow;
    }
  }
}
