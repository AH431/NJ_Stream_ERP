// ==============================================================================
// ProductListScreen — 產品列表（無 Scaffold，嵌入 HomeScreen IndexedStack）
//
// 權限（PRD v0.8 §3）：
//   - 讀取：全角色（sales / warehouse / admin）
//   - 新增/刪除：僅 admin
//   - 軟刪除：長按進入選取模式 → 頂部工具列批次刪除
//   - ListView 底部留 88px 避免 FAB 遮住最後一列
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dao/product_dao.dart';
import '../../database/database.dart';
import '../../providers/sync_provider.dart';

class ProductListScreen extends StatefulWidget {
  const ProductListScreen({super.key});

  @override
  State<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends State<ProductListScreen> {
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<Product> _products = [];

  // ─── 選取模式 ────────────────────────────────────────────────────────────────

  void _enterSelectionMode(int id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  void _toggleItem(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  Future<void> _batchDelete(BuildContext context) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除產品'),
        content: Text('確定要刪除 $count 個產品？此操作無法復原，資料僅能從後台查詢。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('刪除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();

    for (final id in _selectedIds) {
      final p = _products.where((p) => p.id == id).firstOrNull;
      if (p == null) continue;

      await db.softDeleteProduct(id, now);
      await sync.enqueueDelete('product', id, {
        'id': p.id,
        'name': p.name,
        'sku': p.sku,
        'unitPrice': p.unitPrice.toStringAsFixed(2),
        'minStockLevel': p.minStockLevel,
        'createdAt': p.createdAt.toUtc().toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'deletedAt': now.toIso8601String(),
      });
    }

    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已刪除 $count 個產品（等待同步）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSelectionBar(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: '離開選取',
            onPressed: _exitSelectionMode,
          ),
          Expanded(
            child: Text(
              '已選取 ${_selectedIds.length} 項',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          TextButton.icon(
            onPressed: _selectedIds.isEmpty ? null : () => _batchDelete(context),
            icon: const Icon(Icons.delete_outline, size: 18),
            label: const Text('刪除'),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db     = context.read<AppDatabase>();
    final sync   = context.watch<SyncProvider>();
    final canEdit = sync.role == 'admin';

    return StreamBuilder<List<Product>>(
      stream: db.watchActiveProducts(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data ?? [];
        _products = products;

        if (products.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => sync.pullData(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                const SizedBox(height: 120),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.inventory_2_outlined, size: 72,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text('尚無產品資料',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (canEdit) ...[
                        const SizedBox(height: 8),
                        Text('點擊右下角 ＋ 新增第一個產品',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline)),
                      ],
                      const SizedBox(height: 8),
                      Text('下拉以同步取得最新資料',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.outline)),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (_selectionMode) _buildSelectionBar(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => sync.pullData(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // 底部留 88px，避免 FAB 遮住最後一列
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  itemCount: products.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, index) {
                    final product = products[index];
                    final isSelected = _selectedIds.contains(product.id);
                    // 離線新增（id < 0）不可選取刪除
                    final isSelectable = canEdit && product.id > 0;

                    return GestureDetector(
                      onLongPress: (!_selectionMode && isSelectable)
                          ? () => _enterSelectionMode(product.id)
                          : null,
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        selected: isSelected,
                        onTap: (_selectionMode && isSelectable)
                            ? () => _toggleItem(product.id)
                            : null,
                        leading: _selectionMode && isSelectable
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleItem(product.id),
                                visualDensity: VisualDensity.compact,
                              )
                            : CircleAvatar(
                                backgroundColor:
                                    Theme.of(ctx).colorScheme.secondaryContainer,
                                child: Icon(
                                  Icons.inventory_2,
                                  color: Theme.of(ctx).colorScheme.onSecondaryContainer,
                                ),
                              ),
                        title: Text(
                          product.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text('SKU：${product.sku}'),
                        trailing: _selectionMode
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'NT\$ ${product.unitPrice.toStringAsFixed(0)}',
                                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              color: Theme.of(ctx).colorScheme.primary,
                                            ),
                                      ),
                                      if (product.minStockLevel > 0)
                                        Text(
                                          '警示：${product.minStockLevel} 件',
                                          style: Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                    ],
                                  ),
                                  if (product.id < 0) ...[
                                    const SizedBox(width: 4),
                                    Tooltip(
                                      message: '等待同步',
                                      child: Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 16,
                                        color: Theme.of(ctx).colorScheme.tertiary,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}