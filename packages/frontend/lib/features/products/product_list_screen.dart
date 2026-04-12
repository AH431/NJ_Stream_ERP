// ==============================================================================
// ProductListScreen — 產品列表（無 Scaffold，嵌入 HomeScreen IndexedStack）
//
// 權限（PRD v0.8 §3）：
//   - 讀取：全角色（sales / warehouse / admin）
//   - 新增/刪除：僅 admin
// ==============================================================================

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dao/product_dao.dart';
import '../../database/database.dart';
import '../../database/schema.dart';
import '../../providers/sync_provider.dart';

class ProductListScreen extends StatelessWidget {
  const ProductListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final canEdit = context.watch<SyncProvider>().role == 'admin';

    return StreamBuilder<List<Product>>(
      stream: db.watchActiveProducts(),
      builder: (context, snapshot) {
        // ── 載入中 ──────────────────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final products = snapshot.data ?? [];

        // ── 空狀態 ──────────────────────────────────────────────────────────
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '尚無產品資料',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  Text(
                    '點擊右下角 ＋ 新增第一個產品',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ],
            ),
          );
        }

        // ── 清單 ────────────────────────────────────────────────────────────
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: products.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (ctx, index) {
            final product = products[index];

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
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
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 單價顯示
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'NT\$ ${Decimal.parse(product.unitPrice).toStringAsFixed(0)}',
                        style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: Theme.of(ctx).colorScheme.primary,
                            ),
                      ),
                      if (product.minStockLevel > 0)
                        Text(
                          '警示：${product.minStockLevel} 件',
                          style:
                              Theme.of(ctx).textTheme.labelSmall?.copyWith(
                                    color: Theme.of(ctx)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                    ],
                  ),
                  // 尚未同步標示
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
                  // 刪除按鈕（admin only）
                  if (canEdit) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '刪除產品',
                      onPressed: () => _softDelete(
                        ctx,
                        product,
                        db,
                        context.read<SyncProvider>(),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  // --------------------------------------------------------------------------
  // 軟刪除（operationType: delete）
  // --------------------------------------------------------------------------

  Future<void> _softDelete(
    BuildContext listCtx,
    Product product,
    AppDatabase db,
    SyncProvider sync,
  ) async {
    final confirmed = await showDialog<bool>(
      context: listCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除產品'),
        content: Text('確定要將「${product.name}」設為已刪除？'),
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

    if (confirmed != true) return;
    if (!listCtx.mounted) return;

    final now = DateTime.now().toUtc();

    await db.softDeleteProduct(product.id, now);

    final payload = {
      'id': product.id,
      'name': product.name,
      'sku': product.sku,
      'unitPrice': product.unitPrice, // 已是 'xxx.xx' 字串格式
      'minStockLevel': product.minStockLevel,
      'createdAt': product.createdAt.toUtc().toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': now.toIso8601String(),
    };
    await sync.enqueueDelete('product', product.id, payload);

    if (listCtx.mounted) {
      ScaffoldMessenger.of(listCtx).showSnackBar(
        SnackBar(
          content: Text('「${product.name}」已刪除（等待同步）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
