// ==============================================================================
// NotificationScreen — Phase 2 P2-ALT
//
// 顯示後端 AnomalyScanner 產生的未解決異常清單。
// 支援依嚴重度篩選、標記已解決。
// 由 AppBar 鈴鐺圖示進入（push route），不佔用底部 tab。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/anomaly_provider.dart';

// ══════════════════════════════════════════════════════════════════════════════
// NotificationScreen（StatefulWidget）
//
// 整頁採 push route，搭配 WidgetsBindingObserver 偵測 App 回到前景時
// 自動重新抓取異常資料，確保資料不過舊。
// ══════════════════════════════════════════════════════════════════════════════
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with WidgetsBindingObserver {
  // 目前選中的篩選條件；'all' 表示顯示全部，其餘值對應嚴重度字串
  String _filter = 'all'; // all / critical / high / medium

  // ────────────────────────────────────────────────────────────────────────────
  // initState：
  //   1. 注冊 WidgetsBindingObserver，監聽 App 生命週期事件
  //   2. addPostFrameCallback：等 Widget 樹完成首次 build 後再讀 context，
  //      避免在 build 期間觸發 Provider 更新而報 "setState during build" 錯誤
  // ────────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AnomalyProvider>().fetchAnomalies(force: true);
      }
    });
  }

  // ────────────────────────────────────────────────────────────────────────────
  // dispose：移除生命週期觀察者，防止 Widget 銷毀後仍收到回調而呼叫 setState
  // ────────────────────────────────────────────────────────────────────────────
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ────────────────────────────────────────────────────────────────────────────
  // didChangeAppLifecycleState：
  //   App 從背景回到前景（resumed）時強制重新抓取，確保資料新鮮
  // ────────────────────────────────────────────────────────────────────────────
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<AnomalyProvider>().fetchAnomalies(force: true);
    }
  }

  // ────────────────────────────────────────────────────────────────────────────
  // build：
  //   整體結構為 Scaffold → Column
  //     ┌─ AppBar：標題 + 載入中 spinner（僅 isLoading 時顯示於右側）
  //     ├─ _FilterBar：水平可捲動的嚴重度篩選 Chip 列（固定，不隨清單捲動）
  //     └─ Expanded → _buildBody：依 Provider 狀態渲染不同 UI
  // ────────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final s        = AppStrings.of(context);
    final provider = context.watch<AnomalyProvider>();

    // 根據 _filter 篩選清單；'all' 直接使用原始清單，避免不必要的 where 迭代
    final filtered = _filter == 'all'
        ? provider.items
        : provider.items.where((a) => a.severity == _filter).toList();

    return Scaffold(
      // ── AppBar ──────────────────────────────────────────────────────────────
      // 右側 actions：isLoading 時顯示 18×18 小 spinner；
      // 不阻塞整頁，讓使用者感知背景正在刷新
      appBar: AppBar(
        title: Text(s.notifTitle),
        actions: [
          if (provider.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),

      // ── Body：Column 垂直排列篩選列與清單 ──────────────────────────────────
      body: Column(
        children: [
          // 篩選 Chip 列（高度固定，不隨清單捲動）
          _FilterBar(
            current: _filter,
            items:  provider.items,
            onChanged: (v) => setState(() => _filter = v),
          ),
          // 清單區域：Expanded 佔用 Column 中剩餘所有垂直空間
          Expanded(
            child: _buildBody(context, s, provider, filtered),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────────────────────────────────
  // _buildBody：根據 Provider 狀態選擇渲染策略
  //
  //   狀態優先順序（由上至下檢查）：
  //     1. isLoading && items 為空 → 全頁 CircularProgressIndicator（首次載入）
  //     2. error == 'auth_error'   → 顯示認證失敗提示文字
  //     3. filtered 為空           → 空狀態：綠色勾圖示 + 說明文字
  //     4. 正常有資料              → RefreshIndicator 包裹的卡片 ListView
  // ────────────────────────────────────────────────────────────────────────────
  Widget _buildBody(
    BuildContext context,
    AppStrings s,
    AnomalyProvider provider,
    List<AnomalyItem> filtered,
  ) {
    // 狀態 1：首次載入中（清單仍空）→ 全頁 spinner，避免顯示空白畫面
    if (provider.isLoading && provider.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // 狀態 2：認證失敗（token 過期或無讀取權限）→ 顯示純文字錯誤說明
    if (provider.error == 'auth_error') {
      return Center(child: Text(s.notifAuthError));
    }

    // 狀態 3：篩選後為空（該嚴重度無資料，或全部已解決）
    // 以大型 check icon + 文字傳達「目前無待處理異常」的正面訊息
    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min, // 只佔內容所需高度，垂直方向置中
          children: [
            // 綠色勾圓：視覺強調「一切正常」
            const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            Text(s.notifEmpty, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }

    // 狀態 4：正常有資料 → 支援下拉刷新的卡片清單
    // RefreshIndicator：下拉時呼叫 force fetch，讓使用者可手動觸發更新
    return RefreshIndicator(
      onRefresh: () => provider.fetchAnomalies(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filtered.length,
        // 卡片間距 6px：視覺上區隔但不過鬆，維持緊湊感
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) => _AnomalyCard(
          item: filtered[i],
          onResolve: () async {
            // 提前在 async 前取得 messenger，
            // 避免 await 後 context 已 deactivated（use_build_context_synchronously lint）
            final messenger = ScaffoldMessenger.of(context);
            final ok = await provider.resolve(filtered[i].id);
            // 成功時清單自動移除卡片（Provider notifyListeners），失敗才顯示 SnackBar
            if (mounted && !ok) {
              messenger.showSnackBar(SnackBar(
                content: Text(s.notifResolveFailed),
              ));
            }
          },
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _FilterBar（嚴重度篩選列）
//
// UI 結構：
//   SingleChildScrollView（scrollDirection: horizontal）
//     └─ Row
//          └─ [all, critical, high, medium] × FilterChip（含數量徽章）
//
// 每個 Chip 顯示「標籤 (n 筆)」，選中時以對應嚴重度色調著色。
// 水平捲動設計確保小螢幕不截斷 Chip。
// ══════════════════════════════════════════════════════════════════════════════
class _FilterBar extends StatelessWidget {
  final String current;            // 目前選中的篩選值
  final List<AnomalyItem> items;   // 全部（未過濾）清單，用於計算各類別數量
  final ValueChanged<String> onChanged; // 使用者點擊 Chip 後通知父層更新 _filter

  const _FilterBar({
    required this.current,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);

    // 預先計算各嚴重度數量，渲染時直接查表，不在 map 裡重複 where 迭代
    final counts = {
      'all':      items.length,
      'critical': items.where((a) => a.severity == 'critical').length,
      'high':     items.where((a) => a.severity == 'high').length,
      'medium':   items.where((a) => a.severity == 'medium').length,
    };

    // i18n 標籤對應表
    final labels = {
      'all':      s.notifFilterAll,
      'critical': s.notifFilterCritical,
      'high':     s.notifFilterHigh,
      'medium':   s.notifFilterMedium,
    };

    // SingleChildScrollView 讓 Chip 列在小螢幕上可橫向捲動，不截斷也不換行
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: ['all', 'critical', 'high', 'medium'].map((key) {
          final count    = counts[key] ?? 0;
          final selected = current == key;

          return Padding(
            padding: const EdgeInsets.only(right: 8), // Chip 之間的水平間距
            child: FilterChip(
              // 顯示「標籤 (n 筆)」，讓使用者一眼掌握各類別資料量
              label: Text('${labels[key]} ($count)'),
              selected: selected,
              // 統一由父層管理 _filter 狀態，Chip 本身不持有選中狀態
              onSelected: (_) => onChanged(key),
              // 選中背景：嚴重度色彩 × 16% 透明（withAlpha(40)），低調但有色調區別
              selectedColor: _severityColor(key).withAlpha(40),
              // 勾選圖示：與嚴重度色彩一致，強化視覺關聯
              checkmarkColor: _severityColor(key),
              labelStyle: TextStyle(
                fontSize: 12,
                // 選中時：文字改為嚴重度色彩 + 加粗；未選中維持 Theme 預設樣式
                color:      selected ? _severityColor(key) : null,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 嚴重度 → 代表色；'all' 與未知值統一用 blueGrey 中性色
  Color _severityColor(String sev) {
    switch (sev) {
      case 'critical': return Colors.red;
      case 'high':     return Colors.orange;
      case 'medium':   return Colors.amber;
      default:         return Colors.blueGrey;
    }
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// _AnomalyCard（單筆異常卡片）
//
// UI 結構（Card → Padding → Row）：
//   ┌─ Icon（嚴重度圖示，20px，頂部微調 top:2 對齊標題行）
//   ├─ Expanded Column（主要資訊區）
//   │    ├─ Row  [類型 Badge（色塊）] [實體描述（ellipsis 截斷）]
//   │    ├─ Text  異常說明文字（13px）
//   │    └─ Text  建立時間相對格式（10px，次要色）
//   └─ TextButton「標記解決」（最小高度 32，確保觸控區域）
//
// 卡片邊框顏色隨嚴重度變化（31% 透明），強化視覺層級感而不過於突兀。
// ══════════════════════════════════════════════════════════════════════════════
class _AnomalyCard extends StatelessWidget {
  final AnomalyItem item;
  final VoidCallback onResolve; // 「解決」行為由父層注入，保持卡片無狀態

  const _AnomalyCard({required this.item, required this.onResolve});

  // const Map 宣告為 static，避免每次 build 重新配置物件
  static const _sevColors = {
    'critical': Colors.red,
    'high':     Colors.orange,
    'medium':   Colors.amber,
  };

  static const _sevIcons = {
    'critical': Icons.error,         // 紅色驚嘆號圓圈，視覺最強
    'high':     Icons.warning,       // 橘色三角警示
    'medium':   Icons.info_outline,  // 琥珀色 i 圖示，視覺最弱
  };

  @override
  Widget build(BuildContext context) {
    final s       = AppStrings.of(context);
    final color   = _sevColors[item.severity] ?? Colors.blueGrey; // 未知嚴重度退回中性色
    final icon    = _sevIcons[item.severity]  ?? Icons.circle_notifications;
    // notifMessage 組合 alertType + detail + message 為完整說明句
    final message = s.notifMessage(item.alertType, item.detail, item.message);

    return Card(
      // margin: zero — 外部 ListView 的 padding 已處理卡片間距，此處不重複加 margin
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        // 彩色邊框：嚴重度色彩 × 31% 透明（withAlpha(80)），辨識度足夠且不刺眼
        side: BorderSide(color: color.withAlpha(80), width: 1),
      ),
      child: Padding(
        // 左右不對稱：左 12 / 右 8，為右側按鈕保留更緊湊的視覺空間
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start, // 圖示與文字頂部對齊
          children: [

            // ── 左側：嚴重度圖示 ───────────────────────────────────────────
            // top: 2 微調讓圖示視覺上與 Badge 標題行垂直置中
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(icon, color: color, size: 20),
            ),

            // ── 中間：主要內容（Expanded 佔滿剩餘橫向空間）─────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [

                  // ── 第一行：類型 Badge + 實體描述 ─────────────────────────
                  Row(
                    children: [
                      // 類型 Badge：圓角色塊
                      // 背景色 = 嚴重度色彩 × 10% 透明（withAlpha(25)），質感標籤效果
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: color.withAlpha(25),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _alertTypeLabel(item.alertType, s),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: color, // 文字色與邊框一致，強化嚴重度辨識
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      // 實體描述（如「商品 #42」）：
                      // Flexible 防止長文字推擠 Badge，末端以 ellipsis 截斷
                      Flexible(
                        child: Text(
                          _entityLabel(item.entityType, item.entityId, s),
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 5),

                  // ── 第二行：異常說明文字（主要資訊，13px，預設文字色）────────
                  Text(message, style: const TextStyle(fontSize: 13)),

                  const SizedBox(height: 4),

                  // ── 第三行：建立時間（相對格式，10px，次要色）──────────────
                  // notifTimeAgo 將 DateTime 轉為「3 小時前」等人可讀字串
                  Text(
                    _formatDate(item.createdAt, s),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                  ),
                ],
              ),
            ),

            // ── 右側：「標記解決」按鈕 ────────────────────────────────────
            // TextButton 而非 IconButton：文字更清晰傳達操作語意
            // padding 壓縮橫向佔位，minimumSize 高度 32 確保觸控區域符合 HIG
            TextButton(
              onPressed: onResolve,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text(s.notifBtnResolve, style: const TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  // 以下三個方法均委派給 AppStrings，統一處理 i18n 與格式化邏輯
  String _alertTypeLabel(String type, AppStrings s) => s.notifAlertTypeLabel(type);
  String _entityLabel(String type, int id, AppStrings s) => s.notifEntityLabel(type, id);
  String _formatDate(DateTime dt, AppStrings s) => s.notifTimeAgo(dt);
}
