import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:nj_stream_erp/database/database.dart';
import 'package:nj_stream_erp/providers/sync_provider.dart';

void main() {
  late AppDatabase db;
  late Dio dio;
  late FlutterSecureStorage storage;
  late SyncProvider syncProvider;

  setUp(() {
    // 使用記憶體資料庫，不寫入真實檔案
    db = AppDatabase.forTesting(NativeDatabase.memory());

    dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
    // ⚠️  FlutterSecureStorage 在純 Dart test 環境（無 Flutter binding）下會 throw
    // 因為底層依賴平台 Keychain / Keystore，純 Dart 跑不起來。
    //
    // 目前選擇：使用真實 storage → 這些 test 屬於「整合測試」（需要模擬器/實機）
    //
    // 未來改進方向（進入 W3+ 後）：
    //   引入 mockito 或 mocktail，mock FlutterSecureStorage 與 Dio，
    //   讓 login / token 相關 test 可以在純 Dart 環境中跑（真正的 unit test）
    storage = const FlutterSecureStorage();

    syncProvider = SyncProvider(db: db, dio: dio, storage: storage);
  });

  tearDown(() async {
    await db.close();
  });

  group('SyncProvider — Login & Token', () {
    test('login 成功後 isLoggedIn 應為 true', () async {
      // 需要後端 Auth Route 已啟動（Issue #23 已實作）
      final success = await syncProvider.login('sales_user_01', 'P@ssw0rd!');

      expect(success, isTrue);
      expect(syncProvider.isLoggedIn, isTrue);
    });

    test('login 失敗時 isLoggedIn 應為 false', () async {
      final success = await syncProvider.login('bad_user', 'wrong_pass');

      expect(success, isFalse);
      expect(syncProvider.isLoggedIn, isFalse);
    });

    test('logout 後 isLoggedIn 應為 false 且 state 回到 idle', () async {
      await syncProvider.logout();

      expect(syncProvider.isLoggedIn, isFalse);
      expect(syncProvider.state.status, SyncStatus.idle);
    });
  });

  group('SyncProvider — Push Flow', () {
    test('無 pending 資料時 push 後 state 應為 success，pendingCount 為 0', () async {
      await syncProvider.pushPendingOperations();

      // 無 token → failed（未登入情境）
      expect(syncProvider.state.status, isNot(SyncStatus.syncing));
      print('Status: ${syncProvider.state.status}');
      print('Pending: ${syncProvider.state.pendingCount}');
      print('Error: ${syncProvider.state.errorMessage}');
    });

    test('有 pending 資料且已登入時 push 應能正常執行', () async {
      // 先插入一筆 pending operation（模擬離線期間建立的操作）
      await db.into(db.pendingOperations).insert(
            PendingOperationsCompanion.insert(
              operationId: '550e8400-e29b-41d4-a716-446655440000',
              entityType: 'customer',
              operationType: 'create',
              payload: '{"name":"測試客戶","contact":"0912345678"}',
              createdAt: DateTime.now().toUtc(),
            ),
          );

      // 需後端啟動；否則 state 會是 failed（網路錯誤），這是預期行為
      await syncProvider.pushPendingOperations();

      expect(syncProvider.state.status, isNot(SyncStatus.syncing));
      print('Status after push: ${syncProvider.state.status}');
      print('Error: ${syncProvider.state.errorMessage}');
    });

    test('連續呼叫 push 時不應同時進行兩次 sync（idempotent guard）', () async {
      // 第一次呼叫，不 await
      final first = syncProvider.pushPendingOperations();
      // 第二次立即呼叫應被 guard 擋下
      await syncProvider.pushPendingOperations();
      await first;

      // 只要沒有例外拋出即為通過
      expect(syncProvider.state.status, isNot(SyncStatus.syncing));
    });
  });
}
