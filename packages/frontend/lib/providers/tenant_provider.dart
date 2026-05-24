import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class TenantInfo {
  final int     id;
  final String  name;
  final String  slug;
  final String  plan;
  final String? contactEmail;
  final String  timezone;
  final bool    isActive;
  final DateTime? onboardedAt;

  const TenantInfo({
    required this.id,
    required this.name,
    required this.slug,
    required this.plan,
    this.contactEmail,
    required this.timezone,
    required this.isActive,
    this.onboardedAt,
  });

  bool get isOnboarded => onboardedAt != null;

  factory TenantInfo.fromJson(Map<String, dynamic> j) => TenantInfo(
    id:           (j['id'] as num).toInt(),
    name:         j['name'] as String,
    slug:         j['slug'] as String,
    plan:         j['plan'] as String? ?? 'basic',
    contactEmail: j['contactEmail'] as String?,
    timezone:     j['timezone'] as String? ?? 'UTC',
    isActive:     j['isActive'] as bool? ?? true,
    onboardedAt:  j['onboardedAt'] == null
        ? null
        : DateTime.tryParse(j['onboardedAt'] as String),
  );
}

// ── TenantProvider ────────────────────────────────────────

class TenantProvider extends ChangeNotifier {
  final Dio _dio;

  TenantProvider({required Dio dio}) : _dio = dio;

  TenantInfo? _tenant;
  TenantInfo? get tenant => _tenant;
  bool get isOnboarded => _tenant?.isOnboarded ?? true;

  bool _loading = false;
  bool get isLoading => _loading;

  String? _error;
  String? get error => _error;

  /// 取得目前登入者所屬租戶資訊（已快取則直接回傳，[force] 強制重拉）
  Future<void> fetchTenant({bool force = false}) async {
    if (_loading) return;
    if (!force && _tenant != null) return;

    _loading = true;
    _error   = null;
    notifyListeners();

    try {
      final resp = await _dio.get<Map<String, dynamic>>('/api/v1/tenant');
      _tenant = TenantInfo.fromJson(resp.data!);
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        _error = 'auth_error';
      } else {
        _error = 'network_error';
      }
    } catch (_) {
      _error = 'unknown_error';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// 更新租戶資料，完成後自動重拉最新狀態。
  /// [markAsOnboarded] 為 true 時後端會設定 onboarded_at = NOW()。
  Future<bool> patchTenant({
    String?  name,
    String?  contactEmail,
    String?  timezone,
    bool     markAsOnboarded = false,
  }) async {
    try {
      final body = <String, dynamic>{};
      if (name         != null) body['name']         = name;
      if (contactEmail != null) body['contactEmail'] = contactEmail;
      if (timezone     != null) body['timezone']     = timezone;
      if (markAsOnboarded)      body['markAsOnboarded'] = true;

      final resp = await _dio.patch<Map<String, dynamic>>(
        '/api/v1/tenant',
        data: body,
      );
      _tenant = TenantInfo.fromJson(resp.data!);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }
}
