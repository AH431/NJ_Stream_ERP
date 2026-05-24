// ==============================================================================
// ForecastProvider — Phase 4 Sprint 4B PR-5 M5.1/M5.2
//
// 負責從後端 /api/v1/analytics/forecast 拉取需求預測資料。
//
// 設計原則：
//   - 複用 SyncProvider.authenticatedDio（含 token refresh interceptor）
//   - fetchReorderAlerts: 接收低庫存品項清單 → 並行查詢各品項 4 週預測 → 計算 Top 3 補貨警示
//   - fetchProductForecast: 查詢單一產品 12 週預測（供 ProductForecastScreen 使用）
//   - 15 分鐘記憶體快取，離線 / 未登入時靜默失敗
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../database/dao/inventory_items_dao.dart';

// ── 資料模型 ──────────────────────────────────────────────

class ForecastWeek {
  final String weekStart; // 'YYYY-MM-DD'
  final double qty;
  final double? lower;
  final double? upper;

  const ForecastWeek({
    required this.weekStart,
    required this.qty,
    this.lower,
    this.upper,
  });
}

class ProductForecast {
  final int productId;
  final String sku;
  final List<ForecastWeek> forecasts;

  const ProductForecast({
    required this.productId,
    required this.sku,
    required this.forecasts,
  });

  bool get isEmpty => forecasts.isEmpty;
}

class ReorderAlert {
  final int productId;
  final String sku;
  final String productName;
  final double forecastQty4w;  // 未來 4 週預測需求量合計
  final int currentStock;      // available = onHand - reserved
  final bool isRising;         // week4.qty > week1.qty

  const ReorderAlert({
    required this.productId,
    required this.sku,
    required this.productName,
    required this.forecastQty4w,
    required this.currentStock,
    required this.isRising,
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

// ── ForecastProvider ──────────────────────────────────────

class ForecastProvider extends ChangeNotifier {
  final Dio _dio;

  ForecastProvider({required Dio dio}) : _dio = dio;

  // ── 補貨警示快取 ─────────────────────────────────────────
  _CacheEntry<List<ReorderAlert>>? _alertsCache;
  bool _alertsLoading = false;

  bool get alertsLoading => _alertsLoading;
  List<ReorderAlert>? get reorderAlerts => _alertsCache?.data;

  // ── 單品預測快取（productId → CacheEntry）───────────────
  final Map<int, _CacheEntry<ProductForecast>> _forecastCache = {};

  ProductForecast? _currentForecast;
  bool _forecastLoading = false;
  String? _forecastError;

  bool get forecastLoading => _forecastLoading;
  String? get forecastError => _forecastError;
  ProductForecast? get currentForecast => _currentForecast;

  // ── 公開方法 ─────────────────────────────────────────────

  /// 計算補貨警示。傳入低庫存品項清單（來自 watchLowStockItems），
  /// 並行查詢各品項 4 週預測，篩選出「預測上升 或 預測量 > 現有庫存」的品項，
  /// 依緊急程度排序後取 Top 3。
  Future<void> fetchReorderAlerts(
    List<LowStockItem> lowStockItems, {
    bool force = false,
  }) async {
    if (_alertsLoading) return;
    if (!force && _alertsCache != null && !_alertsCache!.isStale) return;

    if (lowStockItems.isEmpty) {
      _alertsCache = _CacheEntry([], DateTime.now());
      notifyListeners();
      return;
    }

    _alertsLoading = true;
    notifyListeners();

    try {
      final futures = lowStockItems.map(
        (item) => _fetchProductForecastData(item.productId, 4),
      );
      final results = await Future.wait(futures, eagerError: false);

      final alerts = <ReorderAlert>[];
      for (var i = 0; i < lowStockItems.length; i++) {
        final item = results[i];
        if (item == null || item.isEmpty) continue;

        final lsItem    = lowStockItems[i];
        final available = lsItem.onHand - lsItem.reserved;
        final qty4w     = item.forecasts.fold(0.0, (sum, w) => sum + w.qty);
        final isRising  = item.forecasts.length >= 2 &&
            item.forecasts.last.qty > item.forecasts.first.qty;

        if (isRising || qty4w > available) {
          alerts.add(ReorderAlert(
            productId:    lsItem.productId,
            sku:          lsItem.sku,
            productName:  lsItem.productName,
            forecastQty4w: qty4w,
            currentStock: available,
            isRising:     isRising,
          ));
        }
      }

      alerts.sort((a, b) => _urgencyScore(b).compareTo(_urgencyScore(a)));
      _alertsCache = _CacheEntry(
        alerts.take(3).toList(),
        DateTime.now(),
      );
    } catch (_) {
      // 靜默失敗，保留舊快取
    } finally {
      _alertsLoading = false;
      notifyListeners();
    }
  }

  /// 查詢單一產品的 N 週預測，結果存入 _currentForecast。
  /// 供 ProductForecastScreen 使用。
  Future<void> fetchProductForecast(int productId, {int weeks = 12}) async {
    if (_forecastLoading) return;

    final cached = _forecastCache[productId];
    if (cached != null && !cached.isStale) {
      _currentForecast = cached.data;
      notifyListeners();
      return;
    }

    _forecastLoading = true;
    _forecastError   = null;
    _currentForecast = null;
    notifyListeners();

    try {
      _currentForecast = await _fetchProductForecastData(productId, weeks);
    } on DioException catch (e) {
      _forecastError = e.response?.statusCode == 401 ? 'auth_error' : 'network_error';
    } catch (_) {
      _forecastError = 'unknown_error';
    } finally {
      _forecastLoading = false;
      notifyListeners();
    }
  }

  // ── 內部 helper ────────────────────────────────────────────

  int _urgencyScore(ReorderAlert a) {
    var score = 0;
    if (a.isRising) score += 2;
    if (a.forecastQty4w > a.currentStock) score += 1;
    return score;
  }

  Future<ProductForecast?> _fetchProductForecastData(
    int productId,
    int weeks,
  ) async {
    // 若快取中已有此產品的 12 週預測，可截取前 N 週
    final cached = _forecastCache[productId];
    if (cached != null && !cached.isStale) return cached.data;

    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/analytics/forecast',
        queryParameters: {'productId': productId, 'weeks': weeks},
      );
      final data         = resp.data ?? <String, dynamic>{};
      final forecastList = (data['forecasts'] as List?) ?? [];

      final forecast = ProductForecast(
        productId: (data['productId'] as num).toInt(),
        sku:       data['sku'] as String? ?? '',
        forecasts: forecastList.map((f) {
          final m = f as Map<String, dynamic>;
          return ForecastWeek(
            weekStart: m['weekStart'] as String,
            qty:       (m['qty'] as num).toDouble(),
            lower:     m['lower'] != null ? (m['lower'] as num).toDouble() : null,
            upper:     m['upper'] != null ? (m['upper'] as num).toDouble() : null,
          );
        }).toList(),
      );

      _forecastCache[productId] = _CacheEntry(forecast, DateTime.now());
      return forecast;
    } on DioException catch (e) {
      // 401 會由 Dio interceptor 處理 refresh；403 = 無權限；靜默回 null
      if (e.response?.statusCode == 404) return null;
      rethrow;
    }
  }
}
