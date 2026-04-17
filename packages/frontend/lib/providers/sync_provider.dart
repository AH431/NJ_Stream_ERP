import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart' hide Column;
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:jwt_decoder/jwt_decoder.dart';

import '../core/constants.dart';
import '../database/database.dart';
import '../database/dao/customer_dao.dart';
import '../database/dao/product_dao.dart';
import '../database/dao/quotation_dao.dart';
import '../database/dao/sales_order_dao.dart';
import '../database/dao/inventory_items_dao.dart';
import '../database/dao/remap_dao.dart';
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
  static const _apiBaseUrlKey  = 'dev_api_base_url'; // Issue #36：執行時可覆寫的 API URL
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

  // ====================== Tab 切換請求 ======================

  int? _pendingTabSwitch;
  int? get pendingTabSwitch => _pendingTabSwitch;

  void requestTabSwitch(int index) {
    _pendingTabSwitch = index;
    notifyListeners();
  }

  void clearTabSwitch() {
    _pendingTabSwitch = null;
  }

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

  /// 啟動時讀取 SecureStorage 期間為 true，避免 async 間隙誤跳 LoginScreen
  bool _isInitializing = true;
  bool get isInitializing => _isInitializing;

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

  /// 目前生效的 API Base URL（執行時覆寫優先，否則回落編譯期常數）
  String get currentApiBaseUrl => _dio.options.baseUrl;

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
    // Issue #36：若使用者曾手動設定過 API URL，優先套用（覆蓋 _initDio 設定的編譯期常數）
    final storedUrl = await _storage.read(key: _apiBaseUrlKey);
    if (storedUrl != null && storedUrl.isNotEmpty) {
      _dio.options.baseUrl = storedUrl;
    }

    final stored = await _storage.read(key: _accessTokenKey);
    if (stored != null) {
      _setToken(stored); // 同時設定 _currentAccessToken 與 _jwtPayload
      _scheduleProactiveRefresh();
    }
    _isInitializing = false;
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
    await _storage.delete(key: _accessTokenKey);
    await _storage.delete(key: _refreshTokenKey);
    await _storage.delete(key: 'last_sync_at');
    _emit(const SyncState());
  }

  // ----------------------------------------------------------------------------
  // Issue #36：API Base URL 執行時更新
  // ----------------------------------------------------------------------------

  /// 更新 API Base URL（立即生效 + 持久化到 SecureStorage）
  /// 下次啟動 App 時 _loadTokens 會自動套用儲存的 URL
  Future<void> updateApiBaseUrl(String url) async {
    final trimmed = url.trim();
    if (trimmed.isEmpty) return;
    _dio.options.baseUrl = trimmed;
    await _storage.write(key: _apiBaseUrlKey, value: trimmed);
    notifyListeners();
  }

  /// 重置為編譯期預設值（清除 SecureStorage 中的覆寫值）
  Future<void> resetApiBaseUrl() async {
    _dio.options.baseUrl = kApiBaseUrl;
    await _storage.delete(key: _apiBaseUrlKey);
    notifyListeners();
  }

  // ----------------------------------------------------------------------------
  // Issue #17：定期清理舊記錄
  // ----------------------------------------------------------------------------

  /// 清理後端超齡記錄 + 本地已完成的 pending_operations（須 admin 角色）。
  ///
  /// 後端：processed_operations > 30 天、各 entity 軟刪除記錄 > 30 天
  /// 本地：pending_operations status = 'succeeded' 且 lastAttemptAt > 7 天前
  ///
  /// 回傳清理結果摘要（含後端 + 本地筆數），供 DevSettingsScreen 顯示。
  Future<Map<String, dynamic>> performCleanup() async {
    final token = await _getValidToken();
    if (token == null) throw Exception('尚未登入');

    // 1. 呼叫後端 cleanup API
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/cleanup',
    );
    final backendResult = response.data ?? {};

    // 2. 清理本地 pending_operations：succeeded 且 lastAttemptAt 超過 7 天
    // lastAttemptAt 以 ISO8601 文字儲存，UTC ISO8601 字串可直接做字典序比較
    final cutoffStr = DateTime.now().toUtc()
        .subtract(const Duration(days: 7))
        .toIso8601String();
    final localDeleted = await (_db.delete(_db.pendingOperations)
          ..where((t) =>
              t.status.equals('succeeded') &
              t.lastAttemptAt.isSmallerOrEqualValue(cutoffStr)))
        .go();

    return {
      ...backendResult,
      'localDeletedSucceeded': localDeleted,
    };
  }

  // ----------------------------------------------------------------------------
  // Issue #16：CSV 資料匯入
  // ----------------------------------------------------------------------------

  /// 上傳 CSV 檔案至後端 /admin/import（須 admin 角色）。
  /// [type]：'product' | 'customer' | 'inventory'
  /// 回傳後端解析結果：{ type, succeeded, failed: [{ row, reason }] }
  Future<Map<String, dynamic>> uploadImportCsv({
    required String type,
    required String fileName,
    required List<int> csvBytes,
  }) async {
    final token = await _getValidToken();
    if (token == null) throw Exception('尚未登入');

    final formData = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        csvBytes,
        filename: fileName,
        contentType: DioMediaType('text', 'csv'),
      ),
    });

    final response = await _dio.post<Map<String, dynamic>>(
      '/api/v1/admin/import',
      queryParameters: {'type': type},
      data: formData,
    );
    return response.data ?? {};
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
        operationType: const Value('create'),
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
        operationType: const Value('delete'), // 依合約：軟刪除用 'delete'（非 'update'）
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
        operationType: const Value('update'),
        payload: Value(jsonEncode(payload)),
        createdAt: Value(now),
        relatedEntityId: Value('$entityType:$entityId'),
      ),
    );
    final count = await _countPending();
    _emit(_state.copyWith(pendingCount: count));
  }

  /// 排入「庫存異動」操作到離線佇列（Issue #9）
  /// [entityType]：固定為 'inventory_delta'
  /// [deltaType]：'reserve' | 'cancel' | 'out' | 'in'
  /// [payload]：{ productId, amount }（inventoryItemId 選填）
  Future<void> enqueueDeltaUpdate(
    String entityType,
    String deltaType,
    Map<String, dynamic> payload,
  ) async {
    final opId = _uuid.v4();
    final now = DateTime.now().toUtc();
    await _db.into(_db.pendingOperations).insert(
      PendingOperationsCompanion(
        operationId: Value(opId),
        entityType: Value(entityType),
        operationType: const Value('delta_update'),
        deltaType: Value(deltaType),
        payload: Value(jsonEncode(payload)),
        createdAt: Value(now),
        relatedEntityId: Value('$entityType:${payload["productId"]}'),
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
              'entityType': op.entityType,
              'operationType': op.operationType,
              if (op.deltaType != null) 'deltaType': op.deltaType,
              // payload 在本地以 JSON 字串存儲，傳送前反序列化為 Map
              'payload': jsonDecode(op.payload),
              'createdAt': op.createdAt.toUtc().toIso8601String(),
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
      // 409 Conflict：後端偵測到 INSUFFICIENT_STOCK，解析 body 後強制 Pull
      if (e.type == DioExceptionType.badResponse &&
          e.response?.statusCode == 409) {
        await _processPushResponse(batch, e.response?.data as Map<String, dynamic>?);
        // 強制 Pull：409 代表伺服器庫存已改變，前端必須取得最新狀態
        // ignore: unawaited_futures
        pullData();
        return;
      }
      // 其他網路層錯誤：全批回退 pending，等下次重試
      await _markBatch(batch, 'pending', incrementRetry: true);
      throw Exception('Network error: ${e.message}');
    }

    await _processPushResponse(batch, response.data);
  }

  /// 解析 push 回傳的 {succeeded, failed, idMap} 並更新各 op 狀態。
  /// 供 200 與 409 共用，避免重複邏輯。
  ///
  /// Pass 1：依後端結果逐筆標記 succeeded / failed。
  /// Pass 2：針對 succeeded 的 create op，從 idMap 取得 server 配發 ID，
  ///         執行本地負數 ID → server ID 的替換，並修正相關外鍵與 pending payloads。
  Future<void> _processPushResponse(
    List<PendingOperation> batch,
    Map<String, dynamic>? data,
  ) async {
    final succeeded = (data?['succeeded'] as List<dynamic>?)?.cast<String>() ?? [];
    final failedList = (data?['failed'] as List<dynamic>?) ?? [];
    final idMap = (data?['idMap'] as Map<String, dynamic>?) ?? {};

    // Pass 1: 標記所有 op 的最終狀態
    for (final op in batch) {
      if (succeeded.contains(op.operationId)) {
        await _updateOpStatus(op, 'succeeded');
        continue;
      }

      final failureInfo = failedList.firstWhere(
        (f) => f['operationId'] == op.operationId,
        orElse: () => null,
      );

      if (failureInfo == null) {
        await _updateOpStatus(op, 'failed',
            error: 'Missing result from server');
      } else {
        await _handleError(op, failureInfo['code'] as String, failureInfo['server_state']);
      }
    }

    // Pass 2: 將 succeeded create op 的本地負數 ID 替換為 server 配發 ID
    // 必須在 Pass 1 完成後執行，確保所有狀態已確定再做 remap
    for (final op in batch) {
      if (!succeeded.contains(op.operationId)) continue;
      if (op.operationType != 'create') continue;

      final serverIdRaw = idMap[op.operationId];
      if (serverIdRaw == null) continue;
      final serverId = serverIdRaw is int
          ? serverIdRaw
          : int.tryParse(serverIdRaw.toString());
      if (serverId == null) continue;

      final localPayload = jsonDecode(op.payload) as Map<String, dynamic>;
      final localId = localPayload['id'] as int?;
      if (localId == null || localId >= 0) continue; // 只處理負數臨時 ID

      await _applyIdRemap(op.entityType, localId, serverId);
    }
  }

  // --------------------------------------------------------------------------
  // ID Remap 輔助方法（Issue #34）
  // --------------------------------------------------------------------------

  /// 將本地負數 ID 替換為 server 配發的正數 ID：
  ///   1. DB entity 表：delete localId row + insert serverId row（含相關 FK 更新）
  ///   2. pending_operations.relatedEntityId 字串更新
  ///   3. pending_operations.payload 中的外鍵欄位更新；
  ///      若 op 本身是 failed create（因外鍵引用失敗），重置為 pending 以便重試
  Future<void> _applyIdRemap(
      String entityType, int localId, int serverId) async {
    // 1. 更新 entity 表 + 相關 FK
    await _db.remapEntityId(entityType, localId, serverId);

    // 2. 更新 pending_operations.relatedEntityId
    await _db.updatePendingRelatedEntityId(entityType, localId, serverId);

    // 3. 更新 pending_operations payload 中引用此 localId 的欄位
    //    customer  → 其他 op 的 customerId 欄位
    //    quotation → 其他 op 的 quotationId 欄位
    //    sales_order → 同 entityType op 的 id 欄位（update/delete ops）
    switch (entityType) {
      case 'customer':
        await _updatePendingPayloads('customerId', localId, serverId, null);
      case 'quotation':
        await _updatePendingPayloads('quotationId', localId, serverId, null);
      case 'sales_order':
        await _updatePendingPayloads('id', localId, serverId, 'sales_order');
    }
  }

  /// 掃描 pending_operations，將 payload 中 [fieldName] == [localId] 的欄位
  /// 替換為 [serverId]。若 op 是 failed create（外鍵引用錯誤），重置為 pending。
  ///
  /// [entityTypeFilter]：若非 null，只處理指定 entityType 的 ops（用於 sales_order:id 欄位）
  Future<void> _updatePendingPayloads(
    String fieldName,
    int localId,
    int serverId,
    String? entityTypeFilter,
  ) async {
    final query = _db.select(_db.pendingOperations);
    if (entityTypeFilter != null) {
      query.where((t) => t.entityType.equals(entityTypeFilter));
    }
    final ops = await query.get();

    for (final op in ops) {
      try {
        final payload = jsonDecode(op.payload) as Map<String, dynamic>;
        if (payload[fieldName] != localId) continue;

        payload[fieldName] = serverId;

        // failed create op → 外鍵依賴已修復，重置為 pending 以便下次 push 重試
        final resetToPending =
            op.status == 'failed' && op.operationType == 'create';
        final newStatus = resetToPending ? 'pending' : op.status;

        await (_db.update(_db.pendingOperations)
              ..where((t) => t.id.equals(op.id)))
            .write(PendingOperationsCompanion(
          payload: Value(jsonEncode(payload)),
          status: Value(newStatus),
          errorMessage:
              resetToPending ? const Value(null) : const Value.absent(),
        ));
      } catch (_) {
        // 忽略 malformed payload，不影響其他 op 的處理
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
        // sales_order:create 被拒絕時回滾本地記錄，避免殘留無法操作的訂單
        if (op.entityType == 'sales_order' && op.operationType == 'create') {
          final payload = jsonDecode(op.payload) as Map<String, dynamic>;
          final localId    = payload['id'] as int?;
          final quotationId = payload['quotationId'] as int?;
          if (localId != null) {
            await _db.softDeleteLocalSalesOrder(localId);
          }
          if (quotationId != null) {
            await _db.updateQuotationStatus(quotationId, 'draft');
          }
        }
        await _updateOpStatus(op, 'failed', error: errorCode);
        return;

      // INSUFFICIENT_STOCK：標記 failed（同步協定 v1.6 §6 Fail-to-Pull）
      // 後端回 409 時，_pushBatch 已在呼叫端觸發 pullData()；
      // 此處保留作為防禦性兜底（未來協定調整或直接呼叫 _handleError 的情境）
      case 'INSUFFICIENT_STOCK':
        await _updateOpStatus(op, 'failed', error: errorCode);
        // reserve 失敗 → 清除本地 reservedAt，重新鎖定「出貨」按鈕
        if (op.deltaType == 'reserve') {
          final payload = jsonDecode(op.payload) as Map<String, dynamic>;
          final orderId = payload['orderId'] as int?;
          if (orderId != null) {
            await _db.clearSalesOrderReserved(orderId);
          } else {
            // 舊版 op 無 orderId：push 中觸發，先標記後由 pullData cleanup 收尾
            await _cleanupStaleReservedOrders();
          }
        }
        return;

      // DATA_CONFLICT：標記 failed，人工介入
      case 'DATA_CONFLICT':
        await _updateOpStatus(op, 'failed', error: errorCode);
        return;

      default:
        // 未知錯誤：incremental retry
        await _updateOpStatus(op, 'pending',
            error: errorCode, incrementRetry: true);
        return;
    }
  }

  // ----------------------------------------------------------------------------
  // Force Overwrite（各 entity DAO upsert 待各 feature 建好後填入）
  Future<void> _applyForceOverwrite(
      String entityType, dynamic serverState) async {
    final data = serverState as Map<String, dynamic>;
    if (entityType == 'customer') {
      await _db.upsertCustomerFromServer(CustomersCompanion(
        id: Value(data['id'] as int),
        name: Value(data['name'] as String),
        contact: Value(data['contact'] as String?),
        taxId: Value(data['taxId'] as String?),
        createdAt: Value(DateTime.parse(data['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
        deletedAt: Value(data['deletedAt'] != null ? DateTime.parse(data['deletedAt'] as String) : null),
      ));
    } else if (entityType == 'product') {
      await _db.upsertProductFromServer(ProductsCompanion(
        id: Value(data['id'] as int),
        name: Value(data['name'] as String),
        sku: Value(data['sku'] as String),
        unitPrice: Value(Decimal.parse(data['unitPrice'] as String)),
        minStockLevel: Value(data['minStockLevel'] as int),
        createdAt: Value(DateTime.parse(data['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
        deletedAt: Value(data['deletedAt'] != null ? DateTime.parse(data['deletedAt'] as String) : null),
      ));
    } else if (entityType == 'quotation') {
      // items 欄位：Pull 回傳 [] (W5 Issue #10 補完)；Force Overwrite 時保留現有 items
      final rawItems = data['items'];
      final itemsJson = (rawItems is List)
          ? jsonEncode(rawItems)
          : (rawItems as String? ?? '[]');
      await _db.upsertQuotationFromServer(QuotationsCompanion(
        id: Value(data['id'] as int),
        customerId: Value(data['customerId'] as int),
        createdBy: Value(data['createdBy'] as int),
        items: Value(itemsJson),
        totalAmount: Value(Decimal.parse(data['totalAmount'] as String)),
        taxAmount: Value(Decimal.parse(data['taxAmount'] as String)),
        status: Value(data['status'] as String),
        convertedToOrderId: Value(data['convertedToOrderId'] as int?),
        createdAt: Value(DateTime.parse(data['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
        deletedAt: Value(data['deletedAt'] != null ? DateTime.parse(data['deletedAt'] as String) : null),
      ));
    } else if (entityType == 'sales_order') {
      await _db.upsertSalesOrderFromServer(SalesOrdersCompanion(
        id: Value(data['id'] as int),
        quotationId: Value(data['quotationId'] as int?),
        customerId: Value(data['customerId'] as int),
        createdBy: Value(data['createdBy'] as int),
        status: Value(data['status'] as String),
        confirmedAt: Value(data['confirmedAt'] != null ? DateTime.parse(data['confirmedAt'] as String) : null),
        shippedAt: Value(data['shippedAt'] != null ? DateTime.parse(data['shippedAt'] as String) : null),
        createdAt: Value(DateTime.parse(data['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
        deletedAt: Value(data['deletedAt'] != null ? DateTime.parse(data['deletedAt'] as String) : null),
      ));
    } else if (entityType == 'inventory_item') {
      await _db.upsertInventoryItemFromServer(InventoryItemsCompanion(
        id: Value(data['id'] as int),
        productId: Value(data['productId'] as int),
        warehouseId: Value(data['warehouseId'] as int),
        quantityOnHand: Value(data['quantityOnHand'] as int),
        quantityReserved: Value(data['quantityReserved'] as int),
        minStockLevel: Value(data['minStockLevel'] as int),
        createdAt: Value(DateTime.parse(data['createdAt'] as String)),
        updatedAt: Value(DateTime.parse(data['updatedAt'] as String)),
      ));
    }
    debugPrint('[SyncProvider] Force Overwrite: $entityType id=${data['id']}');
  }

  // ----------------------------------------------------------------------------
  // Pull / Refresh （Issue #6 拉取機制）
  // ----------------------------------------------------------------------------

  Future<void> pullData() async {
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

      final lastSyncStr = await _storage.read(key: 'last_sync_at');
      
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/v1/sync/pull',
        queryParameters: {
          if (lastSyncStr != null) 'since': lastSyncStr,
          'entityTypes': 'customer,product,quotation,sales_order,inventory_delta',
        },
      );

      final data = response.data ?? {};
      final rawCustomers      = (data['customers']      as List?)?.cast<Map<String, dynamic>>() ?? [];
      final rawProducts       = (data['products']       as List?)?.cast<Map<String, dynamic>>() ?? [];
      final rawQuotations     = (data['quotations']     as List?)?.cast<Map<String, dynamic>>() ?? [];
      final rawSalesOrders    = (data['salesOrders']    as List?)?.cast<Map<String, dynamic>>() ?? [];
      final rawInventoryItems = (data['inventoryItems'] as List?)?.cast<Map<String, dynamic>>() ?? [];

      // 使用 transaction 包裹整批 Pull 寫入，提升效能並保證原子性
      await _db.transaction(() async {
        // 清除本地 orphan ID < 0 以免雙胞胎（防護機制）
        final pendingOps = await (_db.select(_db.pendingOperations)..where((t) => t.status.equals('pending'))).get();
        final relatedIds = pendingOps.map((op) => op.relatedEntityId ?? '').where((id) => id.isNotEmpty).toList();
        await _db.clearOrphanedOfflineCustomers(relatedIds);
        await _db.clearOrphanedOfflineProducts(relatedIds);
        await _db.clearOrphanedOfflineQuotations(relatedIds);

        for (var c in rawCustomers) {
          await _applyForceOverwrite('customer', c);
        }
        for (var p in rawProducts) {
          await _applyForceOverwrite('product', p);
        }
        for (var q in rawQuotations) {
          await _applyForceOverwrite('quotation', q);
        }
        for (var s in rawSalesOrders) {
          await _applyForceOverwrite('sales_order', s);
        }
        for (var inv in rawInventoryItems) {
          await _applyForceOverwrite('inventory_item', inv);
        }
      });

      await _storage.write(key: 'last_sync_at', value: DateTime.now().toUtc().toIso8601String());

      // 清理 stale reservedAt：舊版 reserve op 無 orderId，失敗後 reservedAt 殘留
      await _cleanupStaleReservedOrders();

      final remaining = await _countPending();
      _emit(_state.copyWith(
        status: SyncStatus.success,
        pendingCount: remaining,
      ));
    } catch (e) {
      debugPrint('[SyncProvider] Pull error: $e');
      _emit(_state.copyWith(
        status: SyncStatus.failed,
        errorMessage: 'Pull failed: $e',
      ));
    }
  }

  // ----------------------------------------------------------------------------
  // Stale-state cleanup
  // ----------------------------------------------------------------------------

  /// Pull 後掃描 failed inventory_delta:reserve ops，清除殘留的本地 reservedAt。
  /// 舊版 op payload 無 orderId；以 productId 比對報價明細找出對應訂單。
  Future<void> _cleanupStaleReservedOrders() async {
    final failedReserveOps = await (_db.select(_db.pendingOperations)
          ..where((t) => t.status.equals('failed'))
          ..where((t) => t.entityType.equals('inventory_delta'))
          ..where((t) => t.deltaType.equals('reserve')))
        .get();

    if (failedReserveOps.isEmpty) return;

    final reservedOrders = await (_db.select(_db.salesOrders)
          ..where((t) => t.reservedAt.isNotNull())
          ..where((t) => t.status.equals('confirmed')))
        .get();

    if (reservedOrders.isEmpty) return;

    for (final op in failedReserveOps) {
      final payload = jsonDecode(op.payload) as Map<String, dynamic>;
      final orderId = payload['orderId'] as int?;

      if (orderId != null) {
        // New-style op: clear directly
        await _db.clearSalesOrderReserved(orderId);
        continue;
      }

      // Old-style op (no orderId): match by productId → quotation items
      final productId = payload['productId'] as int?;
      if (productId == null) continue;

      for (final order in reservedOrders) {
        if (order.quotationId == null) continue;
        final quot = await (_db.select(_db.quotations)
              ..where((t) => t.id.equals(order.quotationId!)))
            .getSingleOrNull();
        if (quot == null) continue;
        try {
          final items = jsonDecode(quot.items) as List<dynamic>;
          if (items.any((i) => (i as Map<String, dynamic>)['productId'] == productId)) {
            await _db.clearSalesOrderReserved(order.id);
          }
        } catch (_) {}
      }
    }
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
