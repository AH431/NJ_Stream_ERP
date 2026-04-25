// ==============================================================================
// CustomerListScreen — 客戶列表（無 Scaffold，嵌入 HomeScreen IndexedStack）
//
// 設計說明：
//   - StreamBuilder 監聽 CustomerDao.watchActiveCustomers()，即時更新
//   - 角色控制：sales/admin 才顯示新增（FAB 由 HomeScreen 管理）、刪除
//   - 軟刪除：長按進入選取模式 → 頂部工具列批次刪除
//   - ListView 底部留 88px 避免 FAB 遮住最後一列
//   - Phase 2 P2-CRM：sales/admin 可見 RFM 分級標籤、排序、流失風險篩選
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/document_actions.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/database.dart';
import '../../providers/rfm_provider.dart';
import '../../providers/sync_provider.dart';
import 'customer_detail_screen.dart';
import 'customer_form_screen.dart';

// ── 排序模式 ──────────────────────────────────────────────

enum _SortMode { nameAsc, rfmDesc, lastOrderAsc }

class CustomerListScreen extends StatefulWidget {
  const CustomerListScreen({super.key});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<Customer> _customers = [];

  _SortMode _sortMode      = _SortMode.nameAsc;
  bool      _churnOnly     = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final role = context.read<SyncProvider>().role ?? '';
      if (role == 'sales' || role == 'admin') {
        context.read<RfmProvider>().fetchRfm();
      }
    });
  }

  // ── 排序 / 篩選 ─────────────────────────────────────────

  List<Customer> _sorted(List<Customer> raw, Map<int, RfmItem> rfm) {
    var list = List<Customer>.from(raw);

    if (_churnOnly) {
      list = list.where((c) => rfm[c.id]?.tier == '流失風險').toList();
    }

    switch (_sortMode) {
      case _SortMode.nameAsc:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _SortMode.rfmDesc:
        list.sort((a, b) {
          final sa = rfm[a.id]?.rfmScore ?? -1;
          final sb = rfm[b.id]?.rfmScore ?? -1;
          return sb.compareTo(sa);
        });
      case _SortMode.lastOrderAsc:
        list.sort((a, b) {
          final da = rfm[a.id]?.daysSinceLastOrder ?? 9999;
          final db = rfm[b.id]?.daysSinceLastOrder ?? 9999;
          return da.compareTo(db);
        });
    }

    return list;
  }

  // ── 選取模式 ─────────────────────────────────────────────

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

  Widget _buildSubtitle(Customer c, AppStrings s) {
    final parts = <String>[];
    if (c.contact != null) parts.add(c.contact!);
    if (c.taxId != null) parts.add('${s.custTaxId}${c.taxId!}');
    if (parts.isEmpty) return const SizedBox.shrink();
    return Text(parts.join('  ·  '));
  }

  // ── build ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s       = AppStrings.of(context);
    final db      = context.read<AppDatabase>();
    final sync    = context.watch<SyncProvider>();
    final role    = sync.role ?? '';
    final canEdit = role == 'sales' || role == 'admin';
    final canCrm  = canEdit; // sales / admin 才能看 RFM

    final rfmProvider = canCrm ? context.watch<RfmProvider>() : null;
    final rfm = rfmProvider?.itemsById ?? {};

    return StreamBuilder<List<Customer>>(
      stream: db.watchActiveCustomers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final raw = snapshot.data ?? [];
        _customers = raw;
        final customers = _sorted(raw, rfm);

        if (customers.isEmpty && raw.isEmpty) {
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
            if (!_selectionMode && canCrm)
              _RfmControlBar(
                sortMode:  _sortMode,
                churnOnly: _churnOnly,
                onSort:    (m) => setState(() => _sortMode  = m),
                onFilter:  (v) => setState(() => _churnOnly = v),
              ),
            // 篩選後無結果時提示
            if (customers.isEmpty)
              Expanded(
                child: Center(
                  child: Text(
                    s.isEnglish ? 'No customers match the filter.' : '沒有符合篩選條件的客戶。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    await sync.pullData();
                    if (canCrm && context.mounted) {
                      await context.read<RfmProvider>().fetchRfm(force: true);
                    }
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(top: 8, bottom: 88),
                    itemCount: customers.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
                    itemBuilder: (ctx, index) {
                      final customer = customers[index];
                      final isSelected   = _selectedIds.contains(customer.id);
                      final isSelectable = canEdit && customer.id > 0;
                      final initial      = customer.name.isNotEmpty ? customer.name[0] : '?';
                      final rfmItem      = rfm[customer.id];

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
                              : () => Navigator.push(
                                    ctx,
                                    MaterialPageRoute(
                                      builder: (_) => CustomerDetailScreen(
                                          customer: customer),
                                    ),
                                  ),
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
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  customer.name,
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (rfmItem != null) ...[
                                const SizedBox(width: 6),
                                _TierBadge(tier: rfmItem.tier),
                              ],
                            ],
                          ),
                          subtitle: _buildSubtitle(customer, s),
                          trailing: _selectionMode
                              ? null
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (canEdit)
                                      IconButton(
                                        icon: const Icon(Icons.edit_outlined),
                                        tooltip: s.custTooltipEdit,
                                        color: Theme.of(ctx).colorScheme.primary,
                                        onPressed: () => Navigator.push(
                                          ctx,
                                          MaterialPageRoute(
                                            builder: (_) => CustomerFormScreen(
                                              customer: customer,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (customer.id < 0)
                                      Tooltip(
                                        message: s.custTooltipSync,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 8),
                                          child: Icon(
                                            Icons.cloud_upload_outlined,
                                            size: 16,
                                            color: Colors.orange,
                                          ),
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

// ── RFM 控制列（排序 + 篩選） ─────────────────────────────

class _RfmControlBar extends StatelessWidget {
  final _SortMode              sortMode;
  final bool                   churnOnly;
  final ValueChanged<_SortMode> onSort;
  final ValueChanged<bool>      onFilter;

  const _RfmControlBar({
    required this.sortMode,
    required this.churnOnly,
    required this.onSort,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          const Icon(Icons.sort, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          DropdownButton<_SortMode>(
            value: sortMode,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: [
              DropdownMenuItem(
                value: _SortMode.nameAsc,
                child: Text(s.isEnglish ? 'Name A-Z' : '名稱 A-Z',
                    style: const TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: _SortMode.rfmDesc,
                child: Text(s.isEnglish ? 'RFM high→low' : 'RFM 高→低',
                    style: const TextStyle(fontSize: 13)),
              ),
              DropdownMenuItem(
                value: _SortMode.lastOrderAsc,
                child: Text(s.isEnglish ? 'Last order (recent first)' : '最後下單（近→遠）',
                    style: const TextStyle(fontSize: 13)),
              ),
            ],
            onChanged: (v) { if (v != null) onSort(v); },
          ),
          const Spacer(),
          FilterChip(
            label: Text(
              s.isEnglish ? 'Churn risk only' : '僅顯示流失風險',
              style: const TextStyle(fontSize: 12),
            ),
            selected: churnOnly,
            onSelected: onFilter,
            selectedColor: Colors.red.withAlpha(30),
            checkmarkColor: Colors.red,
            labelStyle: TextStyle(
              color:      churnOnly ? Colors.red : null,
              fontWeight: churnOnly ? FontWeight.w600 : null,
            ),
          ),
        ],
      ),
    );
  }
}

// ── RFM 分級標籤 ──────────────────────────────────────────

class _TierBadge extends StatelessWidget {
  final String tier;
  const _TierBadge({required this.tier});

  static const _colors = {
    'VIP':    Color(0xFF7B1FA2),
    '活躍':   Color(0xFF2E7D32),
    '觀察':   Color(0xFFE65100),
    '流失風險': Color(0xFFC62828),
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[tier] ?? Colors.blueGrey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color:        color.withAlpha(22),
        border:       Border.all(color: color.withAlpha(100)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        tier,
        style: TextStyle(
          fontSize:   10,
          color:      color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
