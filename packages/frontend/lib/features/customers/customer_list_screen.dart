// ==============================================================================
// CustomerListScreen — 客戶列表（無 Scaffold，嵌入 HomeScreen IndexedStack）
//
// 設計說明：
//   - StreamBuilder 監聽 CustomerDao.watchActiveCustomers()，即時更新
//   - 角色控制：sales/admin 才顯示新增（FAB 由 HomeScreen 管理）、刪除按鈕
//   - 軟刪除使用 operationType: delete（依 api-contract-sync-v1.6.yaml）
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/dao/customer_dao.dart';
import '../../database/database.dart';
import '../../database/schema.dart';
import '../../providers/sync_provider.dart';

class CustomerListScreen extends StatelessWidget {
  const CustomerListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.read<AppDatabase>();
    final role = context.watch<SyncProvider>().role ?? '';
    final canEdit = role == 'sales' || role == 'admin';

    return StreamBuilder<List<Customer>>(
      stream: db.watchActiveCustomers(),
      builder: (context, snapshot) {
        // ── 載入中 ──────────────────────────────────────────────────────────
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final customers = snapshot.data ?? [];

        // ── 空狀態 ──────────────────────────────────────────────────────────
        if (customers.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 72,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  '尚無客戶資料',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                if (canEdit) ...[
                  const SizedBox(height: 8),
                  Text(
                    '點擊右下角 ＋ 新增第一位客戶',
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
          itemCount: customers.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (ctx, index) {
            final customer = customers[index];
            final initial = customer.name.isNotEmpty ? customer.name[0] : '?';

            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(ctx).colorScheme.primaryContainer,
                child: Text(
                  initial,
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              title: Text(
                customer.name,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: _buildSubtitle(customer),
              // 負數 id 表示尚未同步到後端（離線新增）
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (customer.id < 0)
                    Tooltip(
                      message: '等待同步',
                      child: Icon(
                        Icons.cloud_upload_outlined,
                        size: 16,
                        color: Theme.of(ctx).colorScheme.tertiary,
                      ),
                    ),
                  if (canEdit)
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: '刪除客戶',
                      onPressed: () => _softDelete(
                        ctx,
                        customer,
                        db,
                        context.read<SyncProvider>(),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget? _buildSubtitle(Customer c) {
    final parts = <String>[];
    if (c.contact != null) parts.add(c.contact!);
    if (c.taxId != null) parts.add('統編：${c.taxId!}');
    if (parts.isEmpty) return null;
    return Text(parts.join('  ·  '));
  }

  // --------------------------------------------------------------------------
  // 軟刪除（operationType: delete 對應 Sync Contract）
  // --------------------------------------------------------------------------

  Future<void> _softDelete(
    BuildContext listCtx,
    Customer customer,
    AppDatabase db,
    SyncProvider sync,
  ) async {
    final confirmed = await showDialog<bool>(
      context: listCtx,
      builder: (ctx) => AlertDialog(
        title: const Text('刪除客戶'),
        content: Text(
          '確定要將「${customer.name}」設為已刪除？\n此操作將在下次同步時更新至伺服器。',
        ),
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

    // 1. 本地 Drift 軟刪除
    await db.softDeleteCustomer(customer.id, now);

    // 2. 排入 PendingOperations（operationType: delete，payload 為完整快照）
    //    注意：依合約，delete 操作 payload 為完整 entity 快照，含 deletedAt 非 null
    final payload = {
      'id': customer.id,
      'name': customer.name,
      'contact': customer.contact,
      'taxId': customer.taxId,
      'createdAt': customer.createdAt.toUtc().toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': now.toIso8601String(),
    };
    await sync.enqueueDelete('customer', customer.id, payload);

    // 3. 介面回饋
    if (listCtx.mounted) {
      ScaffoldMessenger.of(listCtx).showSnackBar(
        SnackBar(
          content: Text('「${customer.name}」已刪除（等待同步）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
