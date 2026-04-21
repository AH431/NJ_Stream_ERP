// ==============================================================================
// CustomerListScreen — 客戶列表（無 Scaffold，嵌入 HomeScreen IndexedStack）
//
// 設計說明：
//   - StreamBuilder 監聽 CustomerDao.watchActiveCustomers()，即時更新
//   - 角色控制：sales/admin 才顯示新增（FAB 由 HomeScreen 管理）、刪除
//   - 軟刪除：長按進入選取模式 → 頂部工具列批次刪除
//   - ListView 底部留 88px 避免 FAB 遮住最後一列
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/document_actions.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/database.dart';
import '../../providers/sync_provider.dart';

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<Customer> _customers = [];

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
    final s     = context.read<AppStrings>();
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ds = ctx.read<AppStrings>();
        return AlertDialog(
          title: Text(ds.custDelTitle),
          content: Text(ds.isEnglish
              ? 'Delete $count customers? This cannot be undone.'
              : '確定要刪除 $count 位客戶？此操作無法復原。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.btnCancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
                foregroundColor: Theme.of(ctx).colorScheme.onError,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ds.btnDelete),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();

    for (final id in _selectedIds) {
      final c = _customers.where((c) => c.id == id).firstOrNull;
      if (c == null) continue;

      await db.softDeleteCustomer(id, now);
      await sync.enqueueDelete('customer', id, {
        'id': c.id,
        'name': c.name,
        'contact': c.contact,
        'taxId': c.taxId,
        'createdAt': c.createdAt.toUtc().toIso8601String(),
        'updatedAt': now.toIso8601String(),
        'deletedAt': now.toIso8601String(),
      });
    }

    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.isEnglish
              ? '$count customers deleted (pending sync).'
              : '已刪除 $count 位客戶（等待同步）'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Widget _buildSelectionBar(BuildContext context, bool canEdit) {
    final s = AppStrings.of(context);
    return ColoredBox(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: s.isEnglish ? 'Exit selection' : '離開選取',
            onPressed: _exitSelectionMode,
          ),
          Expanded(
            child: Text(
              s.isEnglish
                  ? '${_selectedIds.length} selected'
                  : '已選取 ${_selectedIds.length} 項',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (canEdit)
            TextButton.icon(
              onPressed: _selectedIds.isEmpty ? null : () => _batchDelete(context),
              icon: const Icon(Icons.delete_outline, size: 18),
              label: Text(s.btnDelete),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── 軟刪除（單筆，保留供非選取模式使用，目前已移至批次）─────────────────────

  Widget _buildSubtitle(Customer c, AppStrings s) {
    final parts = <String>[];
    if (c.contact != null) parts.add(c.contact!);
    if (c.taxId != null) parts.add('${s.custTaxId}${c.taxId!}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  ·  '));
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
    final db     = context.read<AppDatabase>();
    final sync   = context.watch<SyncProvider>();
    final role   = sync.role ?? '';
    final canEdit = role == 'sales' || role == 'admin';

    return StreamBuilder<List<Customer>>(
      stream: db.watchActiveCustomers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final customers = snapshot.data ?? [];
        _customers = customers;

        if (customers.isEmpty) {
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
                      Icon(Icons.people_outline, size: 72,
                          color: Theme.of(context).colorScheme.outline),
                      const SizedBox(height: 16),
                      Text(s.custEmptyTitle,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              color: Theme.of(context).colorScheme.onSurfaceVariant)),
                      if (canEdit) ...[
                        const SizedBox(height: 8),
                        Text(s.custEmptyAdd,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context).colorScheme.outline)),
                      ],
                      const SizedBox(height: 8),
                      Text(s.custEmptySync,
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
            if (_selectionMode) _buildSelectionBar(context, canEdit),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => sync.pullData(),
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  // 底部留 88px，避免 FAB 遮住最後一列
                  padding: const EdgeInsets.only(top: 8, bottom: 88),
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                  itemBuilder: (ctx, index) {
                    final customer = customers[index];
                    final isSelected = _selectedIds.contains(customer.id);
                    // 離線新增（id < 0）不可選取刪除
                    final isSelectable = canEdit && customer.id > 0;
                    final initial = customer.name.isNotEmpty ? customer.name[0] : '?';

                    return GestureDetector(
                      onLongPress: (!_selectionMode && isSelectable)
                          ? () => _enterSelectionMode(customer.id)
                          : null,
                      child: ListTile(
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        selected: isSelected,
                        onTap: (_selectionMode && isSelectable)
                            ? () => _toggleItem(customer.id)
                            : null,
                        leading: _selectionMode && isSelectable
                            ? Checkbox(
                                value: isSelected,
                                onChanged: (_) => _toggleItem(customer.id),
                                visualDensity: VisualDensity.compact,
                              )
                            : CircleAvatar(
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
                        subtitle: _buildSubtitle(customer, s),
                        trailing: _selectionMode
                            ? null
                            : Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (customer.id < 0)
                                    Tooltip(
                                      message: s.custTooltipSync,
                                      child: const Icon(
                                        Icons.cloud_upload_outlined,
                                        size: 16,
                                        color: Colors.orange,
                                      ),
                                    ),
                                  if (canEdit && customer.id > 0)
                                    IconButton(
                                      icon: const Icon(Icons.receipt_long_outlined),
                                      tooltip: s.custTooltipEmail,
                                      color: Colors.teal,
                                      onPressed: () => pickMonthAndSendStatement(
                                        ctx,
                                        customerId: customer.id,
                                      ),
                                    ),
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