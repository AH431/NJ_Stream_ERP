// ==============================================================================
// AnalyticsProvider — Phase 2 P2-VIS Wave 1
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
  _CacheEntry<List<RevenuePoint>>?    _revenueCache;
  _CacheEntry<List<OrderStatusCount>>? _statusCache;
  _CacheEntry<List<TopProduct>>?      _topProductsCache;

  // ── 載入狀態 ────────────────────────────────────────────
  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? get lastFetchedAt => _revenueCache?.fetchedAt;

  // ── 資料 Getters（快取未命中回傳 null，UI 顯示骨架）──────

  List<RevenuePoint>?    get revenueData    => _revenueCache?.data;
  List<OrderStatusCount>? get statusData    => _statusCache?.data;
  List<TopProduct>?      get topProductData => _topProductsCache?.data;

  // ── 公開方法 ─────────────────────────────────────────────

  /// 若快取未過期則跳過，[force] 可強制重拉。
  Future<void> fetchAll({bool force = false}) async {
    if (_loading) return;
    if (!force &&
        _revenueCache  != null && !_revenueCache!.isStale &&
        _statusCache   != null && !_statusCache!.isStale  &&
        _topProductsCache != null && !_topProductsCache!.isStale) {
      return;
    }

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _fetchRevenue(),
        _fetchOrderStatus(),
        _fetchTopProducts(),
      ]);

      final now = DateTime.now();
      _revenueCache      = _CacheEntry(results[0] as List<RevenuePoint>,    now);
      _statusCache       = _CacheEntry(results[1] as List<OrderStatusCount>, now);
      _topProductsCache  = _CacheEntry(results[2] as List<TopProduct>,       now);
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
}
