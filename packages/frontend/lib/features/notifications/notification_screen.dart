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

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  String _filter = 'all'; // all / critical / high / medium

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        context.read<AnomalyProvider>().fetchAnomalies(force: true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final s        = AppStrings.of(context);
    final provider = context.watch<AnomalyProvider>();

    final filtered = _filter == 'all'
        ? provider.items
        : provider.items.where((a) => a.severity == _filter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(s.isEnglish ? 'Notifications' : '異常通知'),
        actions: [
          if (provider.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(child: SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))),
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => provider.fetchAnomalies(force: true),
            ),
        ],
      ),
      body: Column(
        children: [
          // ── 篩選 Chip 列 ────────────────────────────────
          _FilterBar(
            current: _filter,
            items:  provider.items,
            onChanged: (v) => setState(() => _filter = v),
          ),
          // ── 清單 ────────────────────────────────────────
          Expanded(
            child: _buildBody(context, s, provider, filtered),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AppStrings s,
    AnomalyProvider provider,
    List<AnomalyItem> filtered,
  ) {
    if (provider.isLoading && provider.items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (provider.error == 'auth_error') {
      return Center(child: Text(s.isEnglish
          ? 'Please log in to view notifications.'
          : '請先登入以查看異常通知。'));
    }

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
            const SizedBox(height: 12),
            Text(
              s.isEnglish ? 'No anomalies found.' : '目前沒有異常通知。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => provider.fetchAnomalies(force: true),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) => _AnomalyCard(
          item: filtered[i],
          onResolve: () async {
            final messenger = ScaffoldMessenger.of(context);
            final ok = await provider.resolve(filtered[i].id);
            if (mounted && !ok) {
              messenger.showSnackBar(SnackBar(
                content: Text(s.isEnglish ? 'Failed to resolve.' : '標記失敗，請重試。'),
              ));
            }
          },
        ),
      ),
    );
  }
}

// ── 篩選列 ───────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  final String current;
  final List<AnomalyItem> items;
  final ValueChanged<String> onChanged;

  const _FilterBar({
    required this.current,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    final counts = {
      'all':      items.length,
      'critical': items.where((a) => a.severity == 'critical').length,
      'high':     items.where((a) => a.severity == 'high').length,
      'medium':   items.where((a) => a.severity == 'medium').length,
    };

    final labels = s.isEnglish
        ? {'all': 'All', 'critical': 'Critical', 'high': 'High', 'medium': 'Medium'}
        : {'all': '全部',  'critical': '緊急',    'high': '高',    'medium': '中'};

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: ['all', 'critical', 'high', 'medium'].map((key) {
          final count = counts[key] ?? 0;
          final selected = current == key;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilterChip(
              label: Text('${labels[key]} ($count)'),
              selected: selected,
              onSelected: (_) => onChanged(key),
              selectedColor: _severityColor(key).withAlpha(40),
              checkmarkColor: _severityColor(key),
              labelStyle: TextStyle(
                fontSize: 12,
                color: selected ? _severityColor(key) : null,
                fontWeight: selected ? FontWeight.w600 : null,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _severityColor(String sev) {
    switch (sev) {
      case 'critical': return Colors.red;
      case 'high':     return Colors.orange;
      case 'medium':   return Colors.amber;
      default:         return Colors.blueGrey;
    }
  }
}

// ── 異常卡片 ─────────────────────────────────────────────

class _AnomalyCard extends StatelessWidget {
  final AnomalyItem item;
  final VoidCallback onResolve;

  const _AnomalyCard({required this.item, required this.onResolve});

  static const _sevColors = {
    'critical': Colors.red,
    'high':     Colors.orange,
    'medium':   Colors.amber,
  };

  static const _sevIcons = {
    'critical': Icons.error,
    'high':     Icons.warning,
    'medium':   Icons.info_outline,
  };

  @override
  Widget build(BuildContext context) {
    final s     = AppStrings.of(context);
    final color = _sevColors[item.severity] ?? Colors.blueGrey;
    final icon  = _sevIcons[item.severity]  ?? Icons.circle_notifications;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: color.withAlpha(80), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 嚴重度圖示
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 10),
              child: Icon(icon, color: color, size: 20),
            ),
            // 內容
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 標題行
                  Row(
                    children: [
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
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _entityLabel(item.entityType, item.entityId, s),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  // 說明文字
                  Text(item.message, style: const TextStyle(fontSize: 13)),
                  // 建立時間
                  const SizedBox(height: 4),
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
            // 解決按鈕
            TextButton(
              onPressed: onResolve,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
              ),
              child: Text(
                s.isEnglish ? 'Resolve' : '已解決',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _alertTypeLabel(String type, AppStrings s) {
    if (s.isEnglish) return type;
    const map = {
      'LONG_PENDING_ORDER':  '訂單停滯',
      'NEGATIVE_AVAILABLE':  '庫存異常',
      'STOCKOUT_PROLONGED':  '長期缺貨',
    };
    return map[type] ?? type;
  }

  String _entityLabel(String type, int id, AppStrings s) {
    if (s.isEnglish) {
      return '$type #$id';
    }
    const map = {
      'sales_order':    '訂單',
      'inventory_item': '庫存',
      'customer':       '客戶',
    };
    return '${map[type] ?? type} #$id';
  }

  String _formatDate(DateTime dt, AppStrings s) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 60) {
      return s.isEnglish ? '${diff.inMinutes}m ago' : '${diff.inMinutes} 分鐘前';
    }
    if (diff.inHours < 24) {
      return s.isEnglish ? '${diff.inHours}h ago' : '${diff.inHours} 小時前';
    }
    return s.isEnglish
        ? '${diff.inDays}d ago'
        : '${diff.inDays} 天前';
  }
}
