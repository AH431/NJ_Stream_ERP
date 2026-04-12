/// 手動驗證腳本 — 測試 Login / Token / Push Flow
/// 執行：dart run tools/test_sync.dart
/// 前提：後端已啟動（docker-compose up -d + pnpm dev）
///       seed 帳號已建立（npx tsx scripts/seed-test-user.ts）
library;

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../lib/database/database.dart';
import '../lib/providers/sync_provider.dart';

// ── 測試帳號（對應 seed-test-user.ts） ──────────────────────────────────────
//
//  username          password     role        isActive
//  ───────────────── ──────────── ─────────── ────────
//  sales_test        P@ssw0rd!    sales       true
//  warehouse_test    P@ssw0rd!    warehouse   true
//  admin_test        P@ssw0rd!    admin       true
//  disabled_user     P@ssw0rd!    sales       false   ← 預期 login 失敗

const _testAccounts = [
  ('sales_test',     'P@ssw0rd!', 'sales'),
  ('warehouse_test', 'P@ssw0rd!', 'warehouse'),
  ('admin_test',     'P@ssw0rd!', 'admin'),
];

const _disabledAccount = ('disabled_user', 'P@ssw0rd!');

Future<void> main() async {
  print('=== NJ_Stream_ERP SyncProvider 手動驗證腳本 ===\n');

  for (final (username, password, expectedRole) in _testAccounts) {
    await _runLoginTest(username, password, expectedRole);
  }

  await _runDisabledTest(_disabledAccount.$1, _disabledAccount.$2);
}

// ── 正常帳號測試 ─────────────────────────────────────────────────────────────

Future<void> _runLoginTest(
  String username,
  String password,
  String expectedRole,
) async {
  print('── [$username] ──────────────────────────');

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final dio = Dio();
  const storage = FlutterSecureStorage();
  final provider = SyncProvider(db: db, dio: dio, storage: storage);

  try {
    print('Step 1: Login...');
    final ok = await provider.login(username, password);

    if (!ok) {
      print('❌ Login 失敗（預期成功）');
      return;
    }

    print('✅ Login 成功');
    print('   isLoggedIn: ${provider.isLoggedIn}');
    print('   userId:     ${provider.userId}');
    print('   role:       ${provider.role}');

    if (provider.role != expectedRole) {
      print('⚠️  role 不符！期望 $expectedRole，實際 ${provider.role}');
    } else {
      print('✅ role 正確');
    }

    print('\nStep 2: pushPendingOperations（空佇列）...');
    await provider.pushPendingOperations();
    print('   status:       ${provider.state.status}');
    print('   pendingCount: ${provider.state.pendingCount}');
    if (provider.state.errorMessage != null) {
      print('   error: ${provider.state.errorMessage}');
    }
  } catch (e, stack) {
    print('❌ 例外: $e');
    print(stack);
  } finally {
    await db.close();
    print('');
  }
}

// ── 停用帳號測試 ─────────────────────────────────────────────────────────────

Future<void> _runDisabledTest(String username, String password) async {
  print('── [$username] (停用帳號，預期 login 失敗) ──');

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final dio = Dio();
  const storage = FlutterSecureStorage();
  final provider = SyncProvider(db: db, dio: dio, storage: storage);

  try {
    final ok = await provider.login(username, password);
    if (!ok) {
      print('✅ Login 正確被拒絕（isActive=false）');
    } else {
      print('❌ 停用帳號竟然 login 成功！請檢查後端');
    }
  } finally {
    await db.close();
    print('');
  }

  print('=== 測試結束 ===');
}
