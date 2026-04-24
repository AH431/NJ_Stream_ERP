// ==============================================================================
// AnomalyProvider — Phase 2 P2-ALT
//
// 從後端 GET /api/v1/anomalies 拉取未解決異常清單。
// PATCH /api/v1/anomalies/:id/resolve 標記已解決。
//
// 快取策略：5 分鐘記憶體快取（異常比分析資料更新鮮，快取更短）
// 複用 SyncProvider.authenticatedDio（已含 token refresh interceptor）
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class AnomalyItem {
  final int    id;
  final String alertType;
  final String severity;    // critical / high / medium
  final String entityType;
  final int    entityId;
  final String message;
  final Map<String, dynamic>? detail;
  final bool   isResolved;
  final DateTime createdAt;

  const AnomalyItem({
    required this.id,
    required this.alertType,
    required this.severity,
    required this.entityType,
    required this.entityId,
    required this.message,
    this.detail,
    required this.isResolved,
    required this.createdAt,
  });

  factory AnomalyItem.fromJson(Map<String, dynamic> json) => AnomalyItem(
    id:         (json['id'] as num).toInt(),
    alertType:  json['alert_type'] as String,
    severity:   json['severity']   as String,
    entityType: json['entity_type'] as String,
    entityId:   (json['entity_id'] as num).toInt(),
    message:    json['message'] as String,
    detail:     json['detail'] as Map<String, dynamic>?,
    isResolved: json['is_resolved'] as bool,
    createdAt:  DateTime.parse(json['created_at'] as String),
  );
}

// ── AnomalyProvider ───────────────────────────────────────

class AnomalyProvider extends ChangeNotifier {
  final Dio _dio;

  AnomalyProvider({required Dio dio}) : _dio = dio;

  List<AnomalyItem> _items = [];
  List<AnomalyItem> get items => _items;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? _fetchedAt;

  bool get _isCacheValid =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!).inMinutes < 5;

  /// 未解決的 critical + high 數量（AppBar badge 用）
  int get urgentCount => _items
      .where((a) => a.severity == 'critical' || a.severity == 'high')
      .length;

  // ── 拉取清單 ─────────────────────────────────────────────

  Future<void> fetchAnomalies({bool force = false}) async {
    if (_loading) return;
    if (!force && _isCacheValid) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final resp = await _dio.get<Map<String, dynamic>>(
        '/api/v1/anomalies',
      );
      final rows = (resp.data?['data'] as List?) ?? [];
      _items = rows
          .map((r) => AnomalyItem.fromJson(r as Map<String, dynamic>))
          .toList();
      _fetchedAt = DateTime.now();
    } on DioException catch (e) {
      _error = e.response?.statusCode == 401 ? 'auth_error' : 'network_error';
    } catch (_) {
      _error = 'unknown_error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  // ── 標記已解決 ────────────────────────────────────────────

  Future<bool> resolve(int anomalyId) async {
    try {
      await _dio.patch('/api/v1/anomalies/$anomalyId/resolve');
      // 樂觀更新：從本地清單移除，不等下次 fetch
      _items = _items.where((a) => a.id != anomalyId).toList();
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
