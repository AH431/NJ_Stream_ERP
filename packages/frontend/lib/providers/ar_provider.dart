// ==============================================================================
// ArProvider — Phase 2 P2-ACC
//
// 從後端拉取 AR 摘要與未收訂單列表。
// 快取：5 分鐘（Admin 使用，更新頻率中等）
// 複用 SyncProvider.authenticatedDio
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class ArSummary {
  final double totalUnpaid;
  final double totalOverdue;
  final double totalCurrent;
  final double bucket030;
  final double bucket3160;
  final double bucket6190;
  final double bucket90Plus;
  final int    unpaidOrderCount;

  const ArSummary({
    required this.totalUnpaid,
    required this.totalOverdue,
    required this.totalCurrent,
    required this.bucket030,
    required this.bucket3160,
    required this.bucket6190,
    required this.bucket90Plus,
    required this.unpaidOrderCount,
  });

  factory ArSummary.fromJson(Map<String, dynamic> j) => ArSummary(
    totalUnpaid:      _toDouble(j['total_unpaid']),
    totalOverdue:     _toDouble(j['total_overdue']),
    totalCurrent:     _toDouble(j['total_current']),
    bucket030:        _toDouble(j['bucket_0_30']),
    bucket3160:       _toDouble(j['bucket_31_60']),
    bucket6190:       _toDouble(j['bucket_61_90']),
    bucket90Plus:     _toDouble(j['bucket_90_plus']),
    unpaidOrderCount: (j['unpaid_order_count'] as num? ?? 0).toInt(),
  );

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : double.tryParse(v.toString()) ?? 0.0;
}

class ArOrder {
  final int    id;
  final String customerName;
  final String? shippedAt;
  final String? dueDate;
  final int    daysOverdue;
  final double orderTotal;

  const ArOrder({
    required this.id,
    required this.customerName,
    this.shippedAt,
    this.dueDate,
    required this.daysOverdue,
    required this.orderTotal,
  });

  factory ArOrder.fromJson(Map<String, dynamic> j) => ArOrder(
    id:           (j['id'] as num).toInt(),
    customerName: j['customer_name'] as String? ?? '',
    shippedAt:    j['shipped_at'] as String?,
    dueDate:      j['due_date'] as String?,
    daysOverdue:  (j['days_overdue'] as num? ?? 0).toInt(),
    orderTotal:   double.tryParse(j['order_total']?.toString() ?? '0') ?? 0.0,
  );

  bool get isOverdue => daysOverdue > 0;
}

// ── ArProvider ────────────────────────────────────────────

class ArProvider extends ChangeNotifier {
  final Dio _dio;

  ArProvider({required Dio dio}) : _dio = dio;

  ArSummary?    _summary;
  ArSummary?    get summary => _summary;

  List<ArOrder> _orders = [];
  List<ArOrder> get orders => _orders;

  bool    _loading = false;
  bool    get isLoading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? _fetchedAt;

  bool get _isCacheValid =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!).inMinutes < 5;

  Future<void> fetchAll({bool force = false}) async {
    if (!force && _isCacheValid) return;
    if (_loading) return;

    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        _dio.get<Map<String, dynamic>>('/api/v1/ar/summary'),
        _dio.get<Map<String, dynamic>>('/api/v1/ar/orders'),
      ]);

      final summaryJson = (results[0].data?['data'] as Map<String, dynamic>?) ?? {};
      _summary = ArSummary.fromJson(summaryJson);

      final ordersJson = (results[1].data?['data'] as List<dynamic>?) ?? [];
      _orders = ordersJson
          .map((e) => ArOrder.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.customerName.compareTo(b.customerName));

      _fetchedAt = DateTime.now();
      _error     = null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _error = 'auth_error';
      } else {
        _error = 'fetch_error';
      }
    } catch (_) {
      _error = 'fetch_error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<bool> markPayment(int orderId, String paymentStatus) async {
    try {
      await _dio.put<dynamic>(
        '/api/v1/ar/orders/$orderId/payment',
        data: {'paymentStatus': paymentStatus},
      );
      // 強制重新拉取
      await fetchAll(force: true);
      return true;
    } catch (_) {
      return false;
    }
  }
}
