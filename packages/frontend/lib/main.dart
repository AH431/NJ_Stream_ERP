import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'database/database.dart';
import 'providers/sync_provider.dart';

// ==============================================================================
// 程式入口
// ==============================================================================

void main() {
  // Flutter binding 必須在任何 Flutter API 呼叫之前初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 建立全域唯一的核心物件（AppDatabase 與 Dio 的生命週期 = App 生命週期）
  final db = AppDatabase();
  final dio = Dio();
  const storage = FlutterSecureStorage();

  runApp(
    // MultiProvider：將所有共用狀態注入 Widget tree
    // 子 Widget 可透過 context.read<T>() / context.watch<T>() 存取
    MultiProvider(
      providers: [
        // ── AppDatabase ──────────────────────────────────────────────────────
        // Provider（非 ChangeNotifier）：只提供存取，不觸發 rebuild
        Provider<AppDatabase>(
          create: (_) => db,
          // App 關閉時正確釋放資料庫連線
          dispose: (_, db) => db.close(),
        ),

        // ── SyncProvider ─────────────────────────────────────────────────────
        // ChangeNotifierProvider：狀態改變時通知所有監聽的 Widget
        // 依賴 AppDatabase / Dio / FlutterSecureStorage，全部透過建構子注入
        ChangeNotifierProvider<SyncProvider>(
          create: (_) => SyncProvider(
            db: db,
            dio: dio,
            storage: storage,
          ),
        ),
      ],
      child: const NjStreamErpApp(),
    ),
  );
}

// ==============================================================================
// 根 Widget
// ==============================================================================

class NjStreamErpApp extends StatelessWidget {
  const NjStreamErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NJ Stream ERP',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      // 根據登入狀態決定起始畫面
      // isLoggedIn 由 SyncProvider 的 _loadTokens() 在啟動時讀取 SecureStorage 決定
      home: context.watch<SyncProvider>().isLoggedIn
          ? const HomeplaceholderScreen()
          : const LoginPlaceholderScreen(),
    );
  }
}

// ==============================================================================
// 暫時 Placeholder 畫面（等 features/ 模組建立後替換）
// ==============================================================================

class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NJ Stream ERP — Login')),
      body: const Center(
        // TODO: 替換為 lib/features/auth/login_screen.dart
        child: Text('LoginScreen（待實作）'),
      ),
    );
  }
}

class HomeplaceholderScreen extends StatelessWidget {
  const HomeplaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('NJ Stream ERP'),
        actions: [
          // 同步狀態指示
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(
              sync.state.status == SyncStatus.syncing
                  ? Icons.sync
                  : sync.state.status == SyncStatus.failed
                      ? Icons.sync_problem
                      : Icons.sync_outlined,
            ),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('歡迎，${sync.role ?? '未知角色'}（ID: ${sync.userId})'),
            const SizedBox(height: 8),
            Text('Sync 狀態：${sync.state.status.name}'),
            Text('待推送：${sync.state.pendingCount} 筆'),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => context.read<SyncProvider>().pushPendingOperations(),
              icon: const Icon(Icons.sync),
              label: const Text('立即同步'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => context.read<SyncProvider>().logout(),
              child: const Text('登出'),
            ),
          ],
        ),
      ),
    );
  }
}
