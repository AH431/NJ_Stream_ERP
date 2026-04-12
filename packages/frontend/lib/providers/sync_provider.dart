import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../core/constants.dart';
import '../database/database.dart';
import '../database/schema.dart';
import 'package:uuid/uuid.dart';

// ================================================
// 1. SyncStatus 列舉（同步狀態）
// ================================================

enum SyncStatus {
  idle,     // 閒置
  syncing,  // 正在推送
  success,  // 推送成功
  failed,   // 推送失敗
}

// ================================================
// 2. SyncState 狀態類別（用來通知 UI）
// ================================================

class SyncState {
  final SyncStatus status;
  final String? errorMessage;
  final int pendingCount;

  const SyncState({
    this.status = SyncStatus.idle,
    this.errorMessage,
    this.pendingCount = 0,
  });

  // 方便更新狀態的輔助方法
  SyncState copyWith({
    SyncStatus? status,
    String? errorMessage,
    int? pendingCount,
  }) {
    return SyncState(
      status: status ?? this.status,
      errorMessage: errorMessage,
      pendingCount: pendingCount ?? this.pendingCount,
    );
  }
}

// ==============================================================================
// SyncProvider — 整合版（Proactive Refresh + Full Sync Logic）
// ==============================================================================

class SyncProvider extends ChangeNotifier {
  // 依賴注入的三個核心物件
  final AppDatabase _db;
  final Dio _dio;
  final FlutterSecureStorage _storage;

  // 常數定義
  static const _accessTokenKey = 'jwt_access_token';
  static const _refreshTokenKey = 'jwt_refresh_token';
  static const _batchSize = 50; // Sync Contract §5：上限 50 筆

  // 離線新增臨時 id 計數器（負數，以區別後端配發的正整數 id）
  // Dart 單執行緒模型保證操作原子性，無需加鎖
  // W1–W2：離線新增後 id 為負數，Issue #6 pull 後以 server_state 覆蓋真實 id
  static int _localIdSeq = 0;

  /// 取得下一個離線臨時 id（負數遞減，保證唯一性）
  static int nextLocalId() => --_localIdSeq;

  // UUID 產生器（用於 operation.id）
  static const _uuid = Uuid();

  SyncState _state = const SyncState();
  SyncState get state => _state;

  // ====================== 核心狀態 ======================
  
  /// 目前有效的 Access Token（只存記憶體，不存入 Secure Storage）
  String? _currentAccessToken;

  /// 主動刷新用的 Timer
  Timer? _proactiveRefreshTimer;

  /// Refresh 進行中時的 Completer
  ///
  /// 為什麼用 Completer 而不是 bool flag：
  ///   - bool flag（_isRefreshing）：第二個呼叫者立即拿到 false → push 失敗
  ///   - Completer：第二個呼叫者等待第一個 refresh 完成後共享結果
  ///
  /// 情境範例：
  ///   Proactive Timer 觸發 refresh 的同時，push 也在執行 _getValidToken()
  ///   → 兩者都呼叫 _refreshToken()
  ///   → 第二個呼叫者等待 Completer，拿到 true 後繼續 push
  ///   → 不需要重複發送 refresh 請求
  Completer<bool>? _refreshCompleter;

  /// JWT payload 快取：避免每次存取 userId / role 時都重新 decode
  /// 在 _setToken() 時同步更新，在 logout() 時清除
  Map<String, dynamic>? _jwtPayload;

  // ====================== 公開 Getters ======================

  /// 是否已登入（有有效的 Access Token）
  bool get isLoggedIn => _currentAccessToken != null && !JwtDecoder.isExpired(_currentAccessToken!);

  /// 使用者 ID（從快取的 JWT payload 讀取，O(1)，不重新 decode）
  int? get userId {
    final raw = _jwtPayload?['userId'] ?? _jwtPayload?['sub'] ?? _jwtPayload?['id'];
    if (raw == null) return null;
    return raw is int ? raw : int.tryParse(raw.toString());
  }

  /// 使用者角色（sales / warehouse / admin）（從快取的 JWT payload 讀取）
  String? get role => _jwtPayload?['role'] as String?;

  // ====================== 其他成員變數（如果還有） ======================
 
  // 建構子（使用依賴注入，方便之後測試與 mock）
  SyncProvider({
    required AppDatabase db,
    required Dio dio,
    required FlutterSecureStorage storage,
  })  : _db = db,
        _dio = dio,
        _storage = storage {
    _initDio();
    _loadTokens();
  }

  // ----------------------------------------------------------------------------
  // Dio 初始化：注入 token + 被動 refresh 備援
  // ----------------------------------------------------------------------------

  void _initDio() {
    _dio.options.baseUrl = kApiBaseUrl;
    _dio.options.connectTimeout = kConnectTimeout;
    _dio.options.receiveTimeout = kReceiveTimeout;

    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (_currentAccessToken != null) {
          options.headers['Authorization'] = 'Bearer $_currentAccessToken';
        }
        handler.next(options);
      },
      // 被動 refresh 作為 Proactive 的備援（401 時補刀）
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final refreshed = await _refreshToken();
          if (refreshed) {
            final opts = error.requestOptions;
            opts.headers['Authorization'] = 'Bearer $_currentAccessToken';
            return handler.resolve(await _dio.fetch(opts));
          }
        }
        handler.next(error);
      },
    ));
  }

  /// token 寫入與 payload 快取的唯一入口
  /// 所有設定 _currentAccessToken 的地方都應呼叫此方法，確保 _jwtPayload 同步更新
  void _setToken(String token) {
    _currentAccessToken = token;
    try {
      _jwtPayload = JwtDecoder.decode(token);
    } catch (e) {
      // decode 失敗視為無效 token
      debugPrint('[SyncProvider] Failed to decode token: $e');
      _currentAccessToken = null;
      _jwtPayload = null;
    }
  }

  Future<void> _loadTokens() async {
    final stored = await _storage.read(key: _accessTokenKey);
    if (stored != null) {
      _setToken(stored); // 同時設定 _currentAccessToken 與 _jwtPayload
      _scheduleProactiveRefresh();
    }
    notifyListeners();
  }

  // ----------------------------------------------------------------------------
  // Proactive Refresh：在過期前 5 分鐘自動刷新（Issue #3 AC）
  // ----------------------------------------------------------------------------

  void _scheduleProactiveRefresh() {
    _proactiveRefreshTimer?.cancel();
    if (_currentAccessToken == null) return;

    final expiryDate = JwtDecoder.getExpirationDate(_currentAccessToken!);
    final secondsToExpiry = expiryDate.difference(DateTime.now()).inSeconds;

    if (secondsToExpiry <= 300) {
      // 已接近過期 → 立即刷新
      _refreshToken();
      return;
    }

    final refreshIn = Duration(seconds: secondsToExpiry - 300);
    _proactiveRefreshTimer = Timer(refreshIn, () { _refreshToken(); });
  }

  Future<bool> _refreshToken() async {
    // 若已有進行中的 refresh，等待其結果而不是重複發請求
    if (_refreshCompleter != null) {
      return _refreshCompleter!.future;
    }

    _refreshCompleter = Completer<bool>();

    try {
      final refreshToken = await _storage.read(key: _refreshTokenKey);
      if (refreshToken == null) {
        _refreshCompleter!.complete(false);
        return false;
      }

      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/refresh',
        data: {'refreshToken': refreshToken},
      );

      final newAccess = response.data?['accessToken'] as String?;
      final newRefresh = response.data?['refreshToken'] as String?;

      if (newAccess != null) {
        _setToken(newAccess); // 同時更新 _currentAccessToken + _jwtPayload
        await _storage.write(key: _accessTokenKey, value: newAccess);
        if (newRefresh != null) {
          // 後端目前不做 token rotation，newRefresh 通常為 null（預留擴充）
          await _storage.write(key: _refreshTokenKey, value: newRefresh);
        }
        _scheduleProactiveRefresh();
        notifyListeners();
        _refreshCompleter!.complete(true);
        return true;
      }

      _refreshCompleter!.complete(false);
      return false;
    } on DioException catch (e) {
      final code = e.response?.data?['code'];
      if (e.response?.statusCode == 403 && code == 'ACCOUNT_DISABLED') {
        await logout();
      } else if (code == 'REFRESH_TOKEN_EXPIRED') {
        await logout();
      }
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      debugPrint('[SyncProvider] Refresh error: $e');
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      // 無論結果如何，清除 Completer，讓下次 refresh 可以重新開始
      _refreshCompleter = null;
    }
  }

  Future<String?> _getValidToken() async {
    if (_currentAccessToken != null &&
        !JwtDecoder.isExpired(_currentAccessToken!)) {
      return _currentAccessToken;
    }
    final refreshed = await _refreshToken();
    return refreshed ? _currentAccessToken : null;
  }

  // ----------------------------------------------------------------------------
  // 登入
  // ----------------------------------------------------------------------------

  Future<bool> login(String username, String password) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/auth/login',
        data: {'username': username, 'password': password},
      );
      final access = response.data?['accessToken'] as String?;
      final refresh = response.data?['refreshToken'] as String?;

      if (access == null || refresh == null) return false;

      _setToken(access); // 同時更新 _currentAccessToken + _jwtPayload
      await _storage.write(key: _accessTokenKey, value: access);
      await _storage.write(key: _refreshTokenKey, value: refresh);
      _scheduleProactiveRefresh();
      notifyListeners();
      return true;
    } on DioException {
      return false;
    }
  }

  // ----------------------------------------------------------------------------
  // 登出
  // ----------------------------------------------------------------------------

  Future<void> logout() async {
    _proactiveRefreshTimer?.cancel();
    _currentAccessToken = null;
    _jwtPayload = null; // 清除快取，確保 userId / role getter 回傳 null
    await _storage.deleteAll();
    _emit(const SyncState());
  }

  // ----------------------------------------------------------------------------
  // 離線佇列：enqueue 方法（供 Feature Screen 呼叫）
  // ----------------------------------------------------------------------------

  /// 排入「建立」操作到離線佇列
  /// [entityType]：customer / product / quotation / sales_order / inventory_delta
  /// [payload]：完整 entity 快照（含 id, createdAt, updatedAt, deletedAt）
  Future<void> enqueueCreate(
    String entityType,
    Map<String, dynamic> payload,
  ) async {
    final opId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.pendingOperations).insert(
      PendingOperationsCompanion(
        operationId: Value(opId),
        entityType: Value(entityType),
        operationType: Value('create'),
        payload: Value(jsonEncode(payload)),
        createdAt: Value(now),
        relatedEntityId: Value('$entityType:${payload["id"]}'),
      ),
    );
    final count = await _countPending();
    _emit(_state.copyWith(pendingCount: count));
  }

  /// 排入「軟刪除」操作到離線佇列
  /// operationType 必須為 'delete'（對應 api-contract-sync-v1.6.yaml OperationType enum）
  /// [payload]：完整 entity 快照，deletedAt 欄位必須非 null
  Future<void> enqueueDelete(
    String entityType,
    int entityId,
    Map<String, dynamic> payload,
  ) async {
    assert(
      payload['deletedAt'] != null,
      'enqueueDelete: payload.deletedAt 不得為 null（軟刪除必須包含 deletedAt）',
    );
    final opId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.pendingOperations).insert(
      PendingOperationsCompanion(
        operationId: Value(opId),
        entityType: Value(entityType),
        operationType: Value('delete'), // 依合約：軟刪除用 'delete'（非 'update'）
        payload: Value(jsonEncode(payload)),
        createdAt: Value(now),
        relatedEntityId: Value('$entityType:$entityId'),
      ),
    );
    final count = await _countPending();
    _emit(_state.copyWith(pendingCount: count));
  }

  /// 排入「更新」操作到離線佇列（備用，Issue #5 後半部使用）
  /// [payload]：完整 entity 快照（LWW 以 updatedAt 判斷，後端依此覆蓋）
  Future<void> enqueueUpdate(
    String entityType,
    int entityId,
    Map<String, dynamic> payload,
  ) async {
    final opId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.pendingOperations).insert(
      PendingOperationsCompanion(
        operationId: Value(opId),
        entityType: Value(entityType),
        operationType: Value('update'),
        payload: Value(jsonEncode(payload)),
        createdAt: Value(now),
        relatedEntityId: Value('$entityType:$entityId'),
      ),
    );
    final count = await _countPending();
    _emit(_state.copyWith(pendingCount: count));
  }

  /// 監聽 pending 操作數量（供 AppBar badge 使用）
  Stream<int> watchPendingCount() {
    return (_db.select(_db.pendingOperations)
          ..where((t) => t.status.equals('pending')))
        .watch()
        .map((rows) => rows.length);
  }

  // ----------------------------------------------------------------------------
  // 核心同步：pushPendingOperations
  // ----------------------------------------------------------------------------

  Future<void> pushPendingOperations() async {
    if (_state.status == SyncStatus.syncing) return;

    _emit(_state.copyWith(status: SyncStatus.syncing, errorMessage: null));

    try {
      final token = await _getValidToken();
      if (token == null) {
        _emit(_state.copyWith(
          status: SyncStatus.failed,
          errorMessage: 'No valid token. Please log in again.',
        ));
        return;
      }

      bool hasMore = true;
      while (hasMore) {
        final batch = await _fetchBatch();
        if (batch.isEmpty) break;

        await _pushBatch(batch);
        hasMore = batch.length == _batchSize;
      }

      final remaining = await _countPending();
      _emit(_state.copyWith(
        status: SyncStatus.success,
        pendingCount: remaining,
      ));
    } catch (e) {
      _emit(_state.copyWith(
        status: SyncStatus.failed,
        errorMessage: e.toString(),
      ));
    }
  }

  // ----------------------------------------------------------------------------
  // 批次讀取（pending，依 id 升序 → 保證嚴格物理順序）
  // ----------------------------------------------------------------------------

  Future<List<PendingOperation>> _fetchBatch() async {
    return (_db.select(_db.pendingOperations)
          ..where((t) => t.status.equals('pending'))
          ..orderBy([(t) => OrderingTerm.asc(t.id)])
          ..limit(_batchSize))
        .get();
  }

  // ----------------------------------------------------------------------------
  // 推送單一批次並逐筆處理結果
  // token 不作為參數傳入：Dio interceptor 在 onRequest 中已自動注入
  // Authorization header，此處無需重複設定
  // ----------------------------------------------------------------------------

  Future<void> _pushBatch(List<PendingOperation> batch) async {
    await _markBatch(batch, 'syncing');

    // 對齊 Sync Contract §5 的 operation 欄位結構
    final payload = batch
        .map((op) => {
              'id': op.operationId,
              'entity': op.entityType,
              'operation': op.operationType,
              // 僅庫存 delta 操作才有 delta_type（in/reserve/cancel/out）
              if (op.deltaType != null) 'delta_type': op.deltaType,
              // relatedEntityId 供後端快速定位關聯 entity（e.g. "customer:101"）
              if (op.relatedEntityId != null)
                'related_entity_id': op.relatedEntityId,
              // payload 在本地以 JSON 字串存儲，傳送前反序列化為 Map
              'payload': jsonDecode(op.payload),
              'created_at': op.createdAt.toUtc().toIso8601String(),
            })
        .toList();

    late final Response<Map<String, dynamic>> response;
    try {
      response = await _dio.post<Map<String, dynamic>>(
        '/api/v1/sync/push',
        data: {'operations': payload},
        // 不需要 Options(headers:...)，interceptor 已處理 Authorization
      );
    } on DioException catch (e) {
      // 網路層錯誤：全批回退 pending，等下次重試
      await _markBatch(batch, 'pending', incrementRetry: true);
      throw Exception('Network error: ${e.message}');
    }

    final results = (response.data?['results'] as List<dynamic>?) ?? [];

    for (final op in batch) {
      final result = results.firstWhere(
        (r) => r['id'] == op.operationId,
        orElse: () => null,
      );

      if (result == null) {
        await _updateOpStatus(op, 'failed',
            error: 'Missing result from server');
        continue;
      }

      final errorCode = result['error_code'] as String?;
      if (errorCode == null) {
        await _updateOpStatus(op, 'succeeded');
      } else {
        await _handleError(op, errorCode, result['server_state']);
      }
    }
  }

  // ----------------------------------------------------------------------------
  // 錯誤處理（Sync Contract §6）
  // ----------------------------------------------------------------------------

  Future<void> _handleError(
    PendingOperation op,
    String errorCode,
    dynamic serverState,
  ) async {
    switch (errorCode) {
      // Force Overwrite：用 server_state 覆蓋本地，不重試
      case 'FORBIDDEN_OPERATION':
      case 'PERMISSION_DENIED':
      case 'VALIDATION_ERROR':
        if (serverState != null) {
          await _applyForceOverwrite(op.entityType, serverState);
        }
        await _updateOpStatus(op, 'failed', error: errorCode);

      // INSUFFICIENT_STOCK：標記 failed，UI 層提示 Force Pull
      case 'INSUFFICIENT_STOCK':
        await _updateOpStatus(op, 'failed', error: errorCode);

      // DATA_CONFLICT：標記 failed，人工介入
      case 'DATA_CONFLICT':
        await _updateOpStatus(op, 'failed', error: errorCode);

      default:
        // 未知錯誤：incremental retry
        await _updateOpStatus(op, 'pending',
            error: errorCode, incrementRetry: true);
    }
  }

  // ----------------------------------------------------------------------------
  // Force Overwrite（各 entity DAO upsert 待各 feature 建好後填入）
  // ----------------------------------------------------------------------------

  Future<void> _applyForceOverwrite(
      String entityType, dynamic serverState) async {
    // TODO: 依 entityType 分派到各 DAO 執行 upsert
    // if (entityType == 'customer') await _db.upsertCustomer(serverState);
    debugPrint('[SyncProvider] Force Overwrite: $entityType');
  }

  // ----------------------------------------------------------------------------
  // DB 輔助
  // ----------------------------------------------------------------------------

  Future<void> _markBatch(
    List<PendingOperation> batch,
    String status, {
    bool incrementRetry = false,
  }) async {
    if (incrementRetry) {
      // 各筆 retryCount 不同，無法合併為一條 SQL，只能逐筆更新
      for (final op in batch) {
        await (_db.update(_db.pendingOperations)
              ..where((t) => t.id.equals(op.id)))
            .write(PendingOperationsCompanion(
          status: Value(status),
          retryCount: Value(op.retryCount + 1),
        ));
      }
    } else {
      // 不需要 incrementRetry：單條 WHERE id IN (...)，一次 SQL 更新全批
      // 比 N 次獨立 UPDATE 效率高出 N 倍（省去 N-1 次 round-trip）
      final ids = batch.map((op) => op.id).toList();
      await (_db.update(_db.pendingOperations)
            ..where((t) => t.id.isIn(ids)))
          .write(PendingOperationsCompanion(status: Value(status)));
    }
  }

  Future<void> _updateOpStatus(
    PendingOperation op,
    String status, {
    String? error,
    bool incrementRetry = false,
  }) async {
    await (_db.update(_db.pendingOperations)
          ..where((t) => t.id.equals(op.id)))
        .write(PendingOperationsCompanion(
      status: Value(status),
      lastAttemptAt: Value(DateTime.now().toUtc()),
      errorMessage: Value(error),
      retryCount:
          incrementRetry ? Value(op.retryCount + 1) : const Value.absent(),
    ));
  }

  /// SELECT COUNT(*) 查詢：只回傳數字，不載入任何 row 資料
  /// 相較原本的 .get().length，省去所有欄位的序列化 / 傳輸成本
  Future<int> _countPending() async {
    final countExp = _db.pendingOperations.id.count();
    final query = _db.selectOnly(_db.pendingOperations)
      ..addColumns([countExp])
      ..where(_db.pendingOperations.status.equals('pending'));
    final row = await query.getSingle();
    return row.read(countExp) ?? 0;
  }

  void _emit(SyncState newState) {
    _state = newState;
    notifyListeners();
  }

  @override
  void dispose() {
    _proactiveRefreshTimer?.cancel();
    super.dispose();
  }
}
