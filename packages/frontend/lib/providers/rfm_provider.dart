// ==============================================================================
// RfmProvider — Phase 2 P2-CRM C1/C2
//
// 從後端 GET /api/v1/customers/rfm 拉取 RFM 分數與分級。
// 快取：15 分鐘（純只讀，資料更新頻率低）
// 複用 SyncProvider.authenticatedDio
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class RfmItem {
  final int    customerId;
  final String tier;          // VIP / 活躍 / 觀察 / 流失風險
  final int    rfmScore;
  final int    rScore;
  final int    fScore;
  final int    mScore;
  final int    daysSinceLastOrder;
  final int    orderCount90d;
  final double revenue90d;
  final double ltv;

  const RfmItem({
    required this.customerId,
    required this.tier,
    required this.rfmScore,
    required this.rScore,
    required this.fScore,
    required this.mScore,
    required this.daysSinceLastOrder,
    required this.orderCount90d,
    required this.revenue90d,
    required this.ltv,
  });

  factory RfmItem.fromJson(Map<String, dynamic> j) => RfmItem(
    customerId:         (j['customerId']         as num).toInt(),
    tier:               j['tier']                as String,
    rfmScore:           (j['rfmScore']           as num).toInt(),
    rScore:             (j['rScore']             as num).toInt(),
    fScore:             (j['fScore']             as num).toInt(),
    mScore:             (j['mScore']             as num).toInt(),
    daysSinceLastOrder: (j['daysSinceLastOrder'] as num).toInt(),
    orderCount90d:      (j['orderCount90d']      as num).toInt(),
    revenue90d:         (j['revenue90d']         as num).toDouble(),
    ltv:                (j['ltv']                as num).toDouble(),
  );
}

// ── RfmProvider ───────────────────────────────────────────

class RfmProvider extends ChangeNotifier {
  final Dio _dio;

  RfmProvider({required Dio dio}) : _dio = dio;

  Map<int, RfmItem> _itemsById = {};
  Map<int, RfmItem> get itemsById => _itemsById;

  bool   _loading  = false;
  bool   get isLoading => _loading;

  String? _error;
  String? get error => _error;

  DateTime? _fetchedAt;

  bool get _isCacheValid =>
      _fetchedAt != null &&
      DateTime.now().difference(_fetchedAt!).inMinutes < 15;

  Future<void> fetchRfm({bool force = false}) async {
    if (!force && _isCacheValid) return;
    if (_loading) return;

    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final resp = await _dio.get<List<dynamic>>('/customers/rfm');
      final list = resp.data ?? [];
      _itemsById = {
        for (final e in list)
          (e as Map<String, dynamic>)['customerId'] as int:
            RfmItem.fromJson(e),
      };
      _fetchedAt = DateTime.now();
      _error = null;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        _error = 'auth_error';
      }
      // 其他錯誤靜默，保留上次快取
    } catch (_) {
      // 靜默失敗
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
