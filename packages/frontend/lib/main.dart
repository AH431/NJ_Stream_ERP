import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

import 'core/app_strings.dart';
import 'core/app_theme.dart';
import 'database/database.dart';
import 'features/customers/customer_form_screen.dart';
import 'features/customers/customer_list_screen.dart';
import 'features/products/product_form_screen.dart';
import 'features/quotations/quotation_form_screen.dart';
import 'features/quotations/quotation_list_screen.dart';
import 'features/sales_orders/sales_order_list_screen.dart';
import 'features/inventory/inventory_list_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/settings/dev_settings_screen.dart';
import 'providers/sync_provider.dart';
import 'providers/analytics_provider.dart';
import 'providers/anomaly_provider.dart';
import 'providers/rfm_provider.dart';
import 'providers/ar_provider.dart';
import 'providers/ai_provider.dart';
import 'providers/forecast_provider.dart';
import 'providers/tenant_provider.dart';
import 'features/notifications/notification_screen.dart';
import 'features/ar/ar_screen.dart';
import 'features/ai/chat_screen.dart';
import 'services/fcm_service.dart';

// ==============================================================================
// 程式入口
// ==============================================================================

// 全域 NavigatorKey：
//   MaterialApp 以外的程式碼（如 FcmService）需要操作導覽時，
//   透過此 key 取得 NavigatorState，避免持有 BuildContext 的生命週期問題
final _navigatorKey = GlobalKey<NavigatorState>();

// ── AppBar Badge 樣式常數 ──────────────────────────────────────────────────────
// 統一定義鈴鐺與同步按鈕上的數字徽章外觀，確保兩處視覺一致

// Badge 相對圖示的偏移量（向左 4px、向下 2px），使徽章壓在圖示右上角
const _appBarBadgeOffset = Offset(-6, 4);
// 徽章圓圈直徑（高度）
const _appBarBadgeLargeSize = 12.0;
// 徽章文字容器寬度（與高度相同形成正方形，避免兩位數撐寬）
const _appBarBadgeWidth = 12.0;
// 徽章文字樣式：8px 超小字、行高 1 避免多餘空白撐高容器
const _appBarBadgeTextStyle = TextStyle(fontSize: 8, height: 1);

// ── _buildAppBarBadgeLabel ────────────────────────────────────────────────────
// 建立 AppBar 徽章內的數字標籤 Widget
//   - count > 9 顯示 '9+'，防止兩位數撐破圓形徽章
//   - FittedBox(scaleDown) 確保文字在固定尺寸容器內自動縮放，不溢出
Widget _buildAppBarBadgeLabel(int count) {
  final label = count > 9 ? '9+' : '$count';

  return SizedBox(
    width: _appBarBadgeWidth,
    height: _appBarBadgeLargeSize,
    child: Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: _appBarBadgeTextStyle,
        ),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// main()：應用程式啟動入口
//
// 初始化順序（有嚴格依賴關係，不可任意調換）：
//   1. WidgetsFlutterBinding.ensureInitialized()  — Flutter binding 基礎
//   2. FcmService.initialize()                    — 背景通知 handler（必須在 Firebase 前）
//   3. Firebase.initializeApp()                   — Firebase SDK
//   4. FcmService.setup()                         — 前景通知 + 點擊路由
//   5. AppStrings.init()                          — 語言設定（runApp 前載入，避免閃爍）
//   6. runApp(MultiProvider(...))                 — 注入所有 Provider 後啟動 Widget tree
// ══════════════════════════════════════════════════════════════════════════════
Future<void> main() async {
  // Flutter binding 必須在任何 Flutter API 呼叫之前初始化
  WidgetsFlutterBinding.ensureInitialized();

  // FCM background handler 必須在 Firebase.initializeApp() 之前註冊
  FcmService.initialize();
  await Firebase.initializeApp();
  await FcmService.setup(_navigatorKey);

  // 建立全域唯一的核心物件（AppDatabase 與 Dio 的生命週期 = App 生命週期）
  final db = AppDatabase();
  final dio = Dio();
  const storage = FlutterSecureStorage();

  // 語言設定在 runApp 前載入，確保 Activity recreation 後語言設定仍保留
  final appStrings = AppStrings(storage);
  await appStrings.init();

  runApp(
    // ── MultiProvider ─────────────────────────────────────────────────────────
    // 將所有共用狀態注入 Widget tree 頂層，子 Widget 可透過：
    //   context.read<T>()   — 一次性讀取，不訂閱更新
    //   context.watch<T>()  — 訂閱更新，Provider 變更時觸發 rebuild
    MultiProvider(
      providers: [

        // ── AppDatabase ───────────────────────────────────────────────────────
        // 普通 Provider（非 ChangeNotifier）：只提供存取，不觸發 rebuild
        // dispose callback 確保 App 關閉時正確釋放 SQLite 連線
        Provider<AppDatabase>(
          create: (_) => db,
          dispose: (_, db) => db.close(),
        ),

        // ── SyncProvider ──────────────────────────────────────────────────────
        // 管理登入狀態、同步佇列、pendingCount
        // 其他 ProxyProvider 都依賴 SyncProvider.authenticatedDio，
        // 因此 SyncProvider 必須排在所有 ProxyProvider 之前
        ChangeNotifierProvider<SyncProvider>(
          create: (_) => SyncProvider(
            db: db,
            dio: dio,
            storage: storage,
          ),
        ),

        // ── AnalyticsProvider ─────────────────────────────────────────────────
        // Phase 2 P2-VIS：聚合圖表資料（15 分鐘記憶體快取）
        // ProxyProvider：當 SyncProvider 變更（如重新登入）時自動更新 dio 引用
        ChangeNotifierProxyProvider<SyncProvider, AnalyticsProvider>(
          create: (ctx) => AnalyticsProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? AnalyticsProvider(dio: sync.authenticatedDio),
        ),

        // ── AnomalyProvider ───────────────────────────────────────────────────
        // Phase 2 P2-ALT：異常通知（5 分鐘記憶體快取）
        // urgentCount（critical + high）驅動 AppBar 鈴鐺 Badge 的顯示
        ChangeNotifierProxyProvider<SyncProvider, AnomalyProvider>(
          create: (ctx) => AnomalyProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? AnomalyProvider(dio: sync.authenticatedDio),
        ),

        // ── RfmProvider ───────────────────────────────────────────────────────
        // Phase 2 P2-CRM：RFM 分數與客戶分級（15 分鐘記憶體快取）
        ChangeNotifierProxyProvider<SyncProvider, RfmProvider>(
          create: (ctx) => RfmProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? RfmProvider(dio: sync.authenticatedDio),
        ),

        // ── ArProvider ────────────────────────────────────────────────────────
        // Phase 2 P2-ACC：應收帳款摘要（Admin 專用，5 分鐘記憶體快取）
        ChangeNotifierProxyProvider<SyncProvider, ArProvider>(
          create: (ctx) => ArProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? ArProvider(dio: sync.authenticatedDio),
        ),

        // ── ForecastProvider ──────────────────────────────────────────────────
        // Phase 4 PR-5 M5.1/M5.2：需求預測（補貨警示 + 單品 12 週預測，15 分鐘快取）
        ChangeNotifierProxyProvider<SyncProvider, ForecastProvider>(
          create: (ctx) => ForecastProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? ForecastProvider(dio: sync.authenticatedDio),
        ),

        // ── AiProvider ────────────────────────────────────────────────────────
        // Phase 3 M1.3：SSE 串流聊天（所有登入角色可用）
        ChangeNotifierProxyProvider<SyncProvider, AiProvider>(
          create: (ctx) => AiProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? AiProvider(dio: sync.authenticatedDio),
        ),

        // ── TenantProvider ────────────────────────────────────────────────────
        // Phase 4 PR-7 M7.2：取得租戶入駐狀態，Banner / OnboardingScreen 使用
        ChangeNotifierProxyProvider<SyncProvider, TenantProvider>(
          create: (ctx) => TenantProvider(
            dio: ctx.read<SyncProvider>().authenticatedDio,
          ),
          update: (_, sync, prev) =>
              prev ?? TenantProvider(dio: sync.authenticatedDio),
        ),

        // ── AppStrings ────────────────────────────────────────────────────────
        // 語言切換（zh / en），setEnglish(bool) 觸發全 App rebuild
        // 已在 main() await init()，Activity recreation 後語言設定仍還原
        // 使用 .value constructor 共享已初始化的實例，不重複建立
        ChangeNotifierProvider<AppStrings>.value(value: appStrings),
      ],
      child: const NjStreamErpApp(),
    ),
  );
}

// ==============================================================================
// NjStreamErpApp（根 Widget）
//
// UI 結構：
//   MaterialApp
//     ├─ theme: AppTheme.light（全局 Material 3 主題）
//     ├─ builder: Container + backgroundGradient（全局漸層背景，疊在所有路由底層）
//     ├─ home: isLoggedIn → HomeScreen or LoginScreen（由 SyncProvider 驅動）
//     └─ routes: { '/notifications': NotificationScreen }（FCM 點擊導向用）
// ==============================================================================

class NjStreamErpApp extends StatelessWidget {
  const NjStreamErpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NJ Stream ERP',
      // 隱藏右上角 debug 紅色 banner
      debugShowCheckedModeBanner: false,
      // 全域 NavigatorKey：供 FcmService 在 Widget tree 外部執行路由跳轉
      navigatorKey: _navigatorKey,
      // 全局 Material 3 淺色主題（色彩、字型、圓角等均在 AppTheme.light 中定義）
      theme: AppTheme.light,
      // builder：在所有路由頁面底層疊加漸層背景，
      // 每個 Scaffold 將 backgroundColor 設為 transparent 後即可透出此漸層
      builder: (context, child) => Container(
        decoration: const BoxDecoration(
          gradient: AppTheme.backgroundGradient,
        ),
        child: child!,
      ),
      // 根據登入狀態決定起始畫面：
      //   isLoggedIn 由 SyncProvider._loadTokens() 在啟動時從 SecureStorage 讀取，
      //   登入 / 登出後 SyncProvider notifyListeners() 觸發此處 rebuild 切換畫面
      home: context.watch<SyncProvider>().isLoggedIn
          ? const HomeScreen()
          : const LoginScreen(),
      // FCM 通知點擊後，FcmService 透過 _navigatorKey 推送此具名路由
      routes: {
        '/notifications': (_) => const NotificationScreen(),
      },
    );
  }
}



// ==============================================================================
// HomeScreen — 主畫面（登入後顯示）
//
// UI 結構：
//   Scaffold
//     ├─ AppBar
//     │    ├─ title: 主標題（navXxx）+ 子標題（titleXxx 功能說明）
//     │    └─ actions
//     │         ├─ _AnomalyBell（鈴鐺 + urgentCount Badge）
//     │         ├─ 同步按鈕（Icon 隨狀態三態 + pendingCount Badge）
//     │         └─ PopupMenuButton（AR / Dev Settings / 登出）
//     ├─ body: IndexedStack（保持各 tab Widget 狀態，不在切換時 dispose）
//     │    └─ [Dashboard, Customer, Quotation, SalesOrder, Inventory+Products, AI]
//     ├─ floatingActionButton: _buildFab（依角色 + tab 動態顯示或隱藏）
//     └─ bottomNavigationBar: NavigationBar Material 3（6 個 tab）
//
// 角色控制（FAB 顯示邏輯）：
//   tab 1（客戶）        + sales / admin   → 新增客戶 FAB
//   tab 2（報價）        + sales / admin   → 新增報價單 FAB
//   tab 4（庫存＆商品）  + admin 專屬      → 新增品項 FAB
//   其餘組合                               → null（不顯示 FAB）
// ==============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // 目前選中的底部 tab 索引（0 = Dashboard … 5 = Inventory）
  int _selectedIndex = 0;

  // ────────────────────────────────────────────────────────────────────────────
  // initState：
  //   登入後在首幀完成後觸發背景資料預取，不阻塞 UI 渲染：
  //   - AnomalyProvider.fetchAnomalies()：初始化鈴鐺 Badge 計數
  //   - TenantProvider.fetchTenant()：決定是否顯示入駐引導 Banner
  // ────────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    // 登入後觸發異常通知首次拉取（背景，不阻塞 UI）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AnomalyProvider>().fetchAnomalies();
        context.read<TenantProvider>().fetchTenant();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final sync    = context.watch<SyncProvider>();
    final s       = AppStrings.of(context);
    final role    = sync.role ?? '';
    final pending = sync.state.pendingCount; // 待同步操作數量，驅動同步按鈕 Badge

    // AppBar 主標題（與底部 tab 完全一致）+ 副標題（功能範疇說明）
    final titles = [
      s.navDashboard,   s.navCustomers,   s.navQuotations,
      s.navOrders,      s.navInventory,   s.navAiChat,
    ];
    final subtitles = [
      s.titleDashboard,   s.titleCustomers,   s.titleQuotations,
      s.titleOrders,      s.titleInventory,   s.titleAiChat,
    ];

    // ── 跨畫面 Tab 跳轉請求 ──────────────────────────────────────────────────
    // 子頁面（如報價單「轉銷售訂單」）可設定 SyncProvider.pendingTabSwitch，
    // 下一幀由此處消費並跳轉至對應 tab；消費後立即清除避免重複觸發
    final requestedTab = sync.pendingTabSwitch;
    if (requestedTab != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() => _selectedIndex = requestedTab);
        sync.clearTabSwitch();
      });
    }

    return Scaffold(
      // ── AppBar ──────────────────────────────────────────────────────────────
      appBar: AppBar(
        toolbarHeight: 52, // [TUNE] AppBar 高度（預設 56，最小建議 48）
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              titles[_selectedIndex],
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              subtitles[_selectedIndex],
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [

          // 1. 異常通知鈴鐺（Phase 2 P2-ALT）
          //    urgentCount > 0 時顯示紅色數字 Badge；
          //    點擊以 push route 方式進入 NotificationScreen，不佔用底部 tab
          _AnomalyBell(onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            );
          }),

          // 2. 同步狀態按鈕 + pendingCount Badge
          //    Icon 三態：
          //      syncing   → Icons.sync（旋轉感，暗示正在進行）
          //      failed    → Icons.sync_problem（警示有錯誤）
          //      idle/done → Icons.cloud_upload_outlined（預設待命）
          //    Tooltip 三態對應：失敗訊息 / 待同步筆數 / 「已同步」提示
          //    onPressed：syncing 時設為 null 禁用，其餘觸發 pushPendingOperations
          Badge(
            isLabelVisible: pending > 0,
            alignment: AlignmentDirectional.topEnd,
            offset: _appBarBadgeOffset,
            padding: EdgeInsets.zero,
            smallSize: 0,
            largeSize: _appBarBadgeLargeSize,
            label: _buildAppBarBadgeLabel(pending),
            child: IconButton(
              icon: Icon(
                sync.state.status == SyncStatus.syncing
                    ? Icons.sync
                    : sync.state.status == SyncStatus.failed
                        ? Icons.sync_problem
                        : Icons.cloud_upload_outlined,
              ),
              tooltip: sync.state.status == SyncStatus.failed
                  ? s.tooltipSyncFailed(sync.state.errorMessage ?? '')
                  : pending > 0
                      ? s.tooltipSyncPending(pending)
                      : s.tooltipSynced,
              onPressed: sync.state.status == SyncStatus.syncing
                  ? null
                  : () => sync.pushPendingOperations(),
            ),
          ),

          // 3. 溢出選單（低頻操作，避免 AppBar 過擁擠）
          //    項目依角色動態組裝：
          //      admin 才看得到「應收帳款」（ArScreen）
          //      所有角色：AI 聊天、開發者設定（後端 URL 切換等工具）
          //      Divider + 登出（紅色強調，視覺防止誤觸）
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'dev_settings') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DevSettingsScreen()),
                );
              } else if (value == 'ar') {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ArScreen()),
                );
              } else if (value == 'logout') {
                _confirmLogout(context, sync, s);
              }
            },
            itemBuilder: (_) => [
              // 應收帳款：僅 admin 可見
              if (role == 'admin')
                PopupMenuItem(
                  value: 'ar',
                  child: Row(
                    children: [
                      const Icon(Icons.account_balance_wallet_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text(s.menuAr),
                    ],
                  ),
                ),
              // 開發者設定：所有登入角色可見
              PopupMenuItem(
                value: 'dev_settings',
                child: Row(
                  children: [
                    const Icon(Icons.settings_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text(s.menuDevSettings),
                  ],
                ),
              ),
              // 視覺分隔線：將危險操作（登出）與功能項目隔開
              const PopupMenuDivider(),
              // 登出：紅色圖示 + 紅色文字，視覺強調不可逆操作
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text(s.tooltipLogout,
                        style: TextStyle(color: Colors.red.shade700)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),

      // ── Body：IndexedStack ──────────────────────────────────────────────────
      // IndexedStack 同時保持所有子頁面的 Widget 狀態（Scroll 位置、Stream 訂閱），
      // 切換 tab 時只改變可見子項，不觸發 dispose/initState，
      // 代價是 6 個子頁面同時存在於記憶體中
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          DashboardScreen(),      // tab 0
          CustomerListScreen(),   // tab 1
          QuotationListScreen(),  // tab 2
          SalesOrderListScreen(), // tab 3
          InventoryListScreen(),  // tab 4：庫存＆商品
          ChatScreen(),           // tab 5：AI
        ],
      ),

      // FAB：依角色與目前 tab 動態決定是否顯示及顯示何種按鈕
      floatingActionButton: _buildFab(context, role, s),

      // ── BottomNavigationBar：NavigationBar（Material 3）──────────────────────
      // 各 NavigationDestination 使用 outlined（未選）/ filled（選中）圖示雙態，
      // 符合 Material 3 的 Icon 設計語言
      bottomNavigationBar: NavigationBar(
        height: 64, // [TUNE] NavigationBar 高度（預設 80，icon+label 最小建議 60）
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.dashboard_outlined),
            selectedIcon: const Icon(Icons.dashboard),
            label: s.navDashboard,
          ),
          NavigationDestination(
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people),
            label: s.navCustomers,
          ),
          NavigationDestination(
            icon: const Icon(Icons.receipt_long_outlined),
            selectedIcon: const Icon(Icons.receipt_long),
            label: s.navQuotations,
          ),
          NavigationDestination(
            icon: const Icon(Icons.shopping_bag_outlined),
            selectedIcon: const Icon(Icons.shopping_bag),
            label: s.navOrders,
          ),
          NavigationDestination(
            icon: const Icon(Icons.warehouse_outlined),
            selectedIcon: const Icon(Icons.warehouse),
            label: s.navInventory,
          ),
          NavigationDestination(
            icon: const Icon(Icons.chat_bubble_outline),
            selectedIcon: const Icon(Icons.chat_bubble),
            label: s.navAiChat,
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // _buildFab：依「目前 tab + 角色」組合決定 FAB 種類
  //
  //   heroTag：每個 FAB 使用唯一字串，避免同頁面同時存在多個 FAB 時
  //   Hero 動畫因重複 tag 而拋出例外
  // ────────────────────────────────────────────────────────────────────────────
  Widget? _buildFab(BuildContext context, String role, AppStrings s) {
    if (_selectedIndex == 1 && (role == 'sales' || role == 'admin')) {
      return FloatingActionButton(
        heroTag: 'fab_customer',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerFormScreen()),
        ),
        tooltip: s.fabAddCustomer,
        child: const Icon(Icons.person_add_outlined),
      );
    }
    if (_selectedIndex == 2 && (role == 'sales' || role == 'admin')) {
      return FloatingActionButton(
        heroTag: 'fab_quotation',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const QuotationFormScreen()),
        ),
        tooltip: s.fabAddQuotation,
        child: const Icon(Icons.note_add_outlined),
      );
    }
    if (_selectedIndex == 4 && role == 'admin') {
      return FloatingActionButton(
        heroTag: 'fab_product',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const ProductFormScreen()),
        ),
        tooltip: s.fabAddProduct,
        child: const Icon(Icons.library_add_outlined),
      );
    }
    return null;
  }

  // ────────────────────────────────────────────────────────────────────────────
  // _confirmLogout：登出確認對話框
  //
  //   AlertDialog 內容顯示待同步筆數（logoutBody），
  //   提醒使用者登出將丟失未推送的本地資料。
  //   確認後呼叫 SyncProvider.logout()，觸發 isLoggedIn = false，
  //   NjStreamErpApp.build() 監聽到變化後自動切換至 LoginScreen。
  // ────────────────────────────────────────────────────────────────────────────
  Future<void> _confirmLogout(
      BuildContext context, SyncProvider sync, AppStrings s) async {
    final pending = sync.state.pendingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.logoutTitle),
        // logoutBody 根據 pending 數量動態產生警告文字（0 筆時說明無資料損失）
        content: Text(s.logoutBody(pending)),
        actions: [
          // 取消：不執行任何操作，回傳 false
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          // 確認登出：FilledButton 視覺權重高於 TextButton，引導使用者注意此操作
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.btnLogout),
          ),
        ],
      ),
    );
    if (confirmed == true && context.mounted) {
      await sync.logout();
    }
  }
}

// ==============================================================================
// _AnomalyBell — AppBar 異常通知鈴鐺
//
// UI 結構：
//   Badge
//     └─ IconButton（Icons.notifications_outlined）
//
// 顯示邏輯：
//   urgentCount（critical + high 合計）> 0 → 顯示紅色數字 Badge
//   urgentCount == 0                         → Badge 隱藏，僅顯示鈴鐺圖示
//
// Tooltip 二態：
//   urgentCount > 0  → 「X 筆緊急異常」（tooltipUrgentAnomalies）
//   urgentCount == 0 → 「通知」（tooltipNotifications）
//
// onTap 由 HomeScreen 傳入（push to NotificationScreen），
// 讓 _AnomalyBell 保持無路由依賴的純 UI Widget，方便單獨測試
// ==============================================================================

class _AnomalyBell extends StatelessWidget {
  final VoidCallback onTap;

  const _AnomalyBell({required this.onTap});

  @override
  Widget build(BuildContext context) {
    // watch urgentCount：有新異常時自動 rebuild Badge 數字
    final urgentCount = context.watch<AnomalyProvider>().urgentCount;
    final s = AppStrings.of(context);

    return Badge(
      isLabelVisible: urgentCount > 0,
      alignment: AlignmentDirectional.topEnd,
      offset: _appBarBadgeOffset,
      padding: EdgeInsets.zero,
      smallSize: 0,
      largeSize: _appBarBadgeLargeSize,
      // 共用 _buildAppBarBadgeLabel，超過 9 顯示 '9+'，確保不撐破圓形徽章
      label: _buildAppBarBadgeLabel(urgentCount),
      child: IconButton(
        icon: const Icon(Icons.notifications_outlined),
        tooltip: urgentCount > 0
            ? s.tooltipUrgentAnomalies(urgentCount)
            : s.tooltipNotifications,
        onPressed: onTap,
      ),
    );
  }
}
