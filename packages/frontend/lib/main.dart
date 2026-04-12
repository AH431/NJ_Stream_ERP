import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'database/database.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/customers/customer_list_screen.dart';
import 'features/products/product_form_screen.dart';
import 'features/products/product_list_screen.dart';
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
          ? const HomeScreen()
          : const LoginPlaceholderScreen(),
    );
  }
}

// ==============================================================================
// 暫時 Placeholder 畫面（登入頁待 Issue #6 完整實作 Login UI 後替換）
// ==============================================================================

class LoginPlaceholderScreen extends StatelessWidget {
  const LoginPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('NJ Stream ERP — 登入')),
      body: const Center(
        // TODO Issue #6：替換為 lib/features/auth/login_screen.dart
        child: Text('LoginScreen（待實作）'),
      ),
    );
  }
}

// ==============================================================================
// HomeScreen — 主畫面（登入後顯示）
//
// 一層 Scaffold 提供全局 AppBar + BottomNavigationBar，
// CustomerListScreen / ProductListScreen 內嵌於 IndexedStack，不含自身 Scaffold。
// 角色控制：
//   - sales / admin ：客戶 tab 顯示 FAB
//   - admin 只：產品 tab 顯示 FAB
//   - warehouse ：全部 tab 無 FAB（唯讀）
// ==============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const _titles = ['客戶管理', '產品管理'];

  @override
  Widget build(BuildContext context) {
    final sync = context.watch<SyncProvider>();
    final role = sync.role ?? '';
    final pending = sync.state.pendingCount;

    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_selectedIndex]),
        actions: [
          // 同步狀態 badge + 推送按鈕
          Badge(
            isLabelVisible: pending > 0,
            label: Text('$pending'),
            child: IconButton(
              icon: Icon(
                sync.state.status == SyncStatus.syncing
                    ? Icons.sync
                    : sync.state.status == SyncStatus.failed
                        ? Icons.sync_problem
                        : Icons.cloud_upload_outlined,
              ),
              tooltip: sync.state.status == SyncStatus.failed
                  ? '同步失敗：${sync.state.errorMessage}'
                  : pending > 0
                      ? '推送 $pending 筆待同步操作'
                      : '已同步',
              onPressed: sync.state.status == SyncStatus.syncing
                  ? null
                  : () => sync.pushPendingOperations(),
            ),
          ),
          // 登出
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: () => _confirmLogout(context, sync),
          ),
        ],
      ),

      // IndexedStack 保持各 tab 狀態（保持 Scroll 位置、不重建 Stream）
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          CustomerListScreen(),
          ProductListScreen(),
        ],
      ),

      floatingActionButton: _buildFab(context, role),

      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: '客戶',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2),
            label: '產品',
          ),
        ],
      ),
    );
  }

  // FAB 按角色與現作 tab 動態顯示
  Widget? _buildFab(BuildContext context, String role) {
    if (_selectedIndex == 0 && (role == 'sales' || role == 'admin')) {
      return FloatingActionButton(
        heroTag: 'fab_customer',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
        ),
        tooltip: '新增客戶',
        child: const Icon(Icons.person_add_outlined),
      );
    }
    if (_selectedIndex == 1 && role == 'admin') {
      return FloatingActionButton(
        heroTag: 'fab_product',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductFormScreen()),
        ),
        tooltip: '新增產品',
        child: const Icon(Icons.add),
      );
    }
    return null;
  }

  // 登出確認對話框（有待同步資料時會提示）
  Future<void> _confirmLogout(BuildContext context, SyncProvider sync) async {
    final pending = sync.state.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('確認登出'),
        content: Text(
          pending > 0
              ? '您有 $pending 筆操作尚未同步。\n登出後、這些操作將在下次登入後繼續同步。\n確定登出嗎？'
              : '確定登出嗎？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('登出'),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await sync.logout();
    }
  }
}
