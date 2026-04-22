// ==============================================================================
// InventoryListScreen — 庫存快照列表（Issue #10）
//
// 功能：
//   1. 全角色唯讀：顯示每個產品的即時庫存快照
//   2. 顯示在庫 / 已預留 / 可出貨 三項數字
//   3. 低庫存警示：quantityOnHand <= minStockLevel 時顯示紅色標籤
//   4. Pull-to-refresh 更新庫存
//   5. Admin 長按進入選取模式 → 批次實體刪除孤立庫存記錄
//      （已刪除產品的殘存庫存由 DAO JOIN 自動過濾，此功能用於手動清理）
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../providers/sync_provider.dart';

class InventoryListScreen extends StatefulWidget {
  const InventoryListScreen({super.key});

  @override
  State<InventoryListScreen> createState() => _InventoryListScreenState();
}

class _InventoryListScreenState extends State<InventoryListScreen> {
  // productId → Product（一次性載入，避免 N+1）
  Map<int, Product> _productMap = {};

  // 選取模式（admin only）
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadProductMap();
  }

  Future<void> _loadProductMap() async {
    final db = context.read<AppDatabase>();
    final products = await db.getActiveProducts();
    if (mounted) {
      setState(() {
        _productMap = {for (final p in products) p.id: p};
      });
    }
  }

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
          title: Text(ds.isEnglish ? 'Confirm Delete' : '確認刪除'),
          content: Text(ds.isEnglish
              ? 'Delete $count inventory record(s) from local database? '
                'Records for active products will be restored on next sync.'
              : '確定從本地刪除 $count 筆庫存記錄？\n'
                '若對應產品仍在伺服器上，下次 Pull 後會自動還原。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.btnCancel),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ds.btnDelete,
                  style: const TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final db = context.read<AppDatabase>();
    for (final id in _selectedIds) {
      await db.deleteInventoryItem(id);
    }

    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.isEnglish
              ? '$count inventory record(s) deleted.'
              : '已刪除 $count 筆庫存記錄'),
        ),
      );
    }
  }

  // ─── 選取工具列 ──────────────────────────────────────────────────────────────

  Widget _buildSelectionBar(BuildContext context) {
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

  // ─── 低庫存警示 badge ────────────────────────────────────────────────────────

  Widget? _buildLowStockBadge(InventoryItem item, AppStrings s) {
    if (item.quantityOnHand > item.minStockLevel) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Text(
        s.invLowStockBadge,
        style: TextStyle(
            fontSize: 10,
            color: Colors.red.shade700,
            fontWeight: FontWeight.bold),
      ),
    );
  }

  // ─── 數量欄位 ────────────────────────────────────────────────────────────────

  Widget _buildQtyColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ─── 庫存列表項目 ────────────────────────────────────────────────────────────

  Widget _buildInventoryTile(InventoryItem item, String? role) {
    final s           = AppStrings.of(context);
    final product     = _productMap[item.productId];
    final productName = product?.name ??
        (s.isEnglish ? 'Product #${item.productId}' : '產品 #${item.productId}');
    final sku         = product?.sku ?? '—';
    final available   = item.quantityOnHand - item.quantityReserved;
    final lowStockBadge = _buildLowStockBadge(item, s);
    final isAdmin     = role == 'admin';
    final isSelected  = _selectedIds.contains(item.id);

    return GestureDetector(
      onLongPress: (isAdmin && !_selectionMode)
          ? () => _enterSelectionMode(item.id)
          : null,
      onTap: (_selectionMode && isAdmin) ? () => _toggleItem(item.id) : null,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: isSelected
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.4)
            : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：(checkbox) + 產品名稱 + 低庫存 badge
              Row(
                children: [
                  if (_selectionMode && isAdmin)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleItem(item.id),
                      visualDensity: VisualDensity.compact,
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(productName,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15)),
                        Text(sku,
                            style: const TextStyle(
                                fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                  if (lowStockBadge != null) lowStockBadge,
                ],
              ),
              const SizedBox(height: 12),
              // 第二行：三欄數量
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildQtyColumn(s.invColOnHand, item.quantityOnHand,
                      Colors.blue.shade700),
                  _buildQtyColumn(s.invColReserved, item.quantityReserved,
                      Colors.orange.shade700),
                  _buildQtyColumn(
                      s.invColAvailable,
                      available < 0 ? 0 : available,
                      Colors.green.shade700),
                ],
              ),
              // 低庫存時補充閾值說明
              if (lowStockBadge != null) ...[
                const SizedBox(height: 6),
                Text(
                  s.invMinStock(item.minStockLevel),
                  style: TextStyle(fontSize: 11, color: Colors.red.shade400),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final s    = AppStrings.of(context);
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final role = sync.role;

    return StreamBuilder<List<InventoryItem>>(
      stream: db.watchInventoryItems(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];

        return Column(
          children: [
            if (_selectionMode) _buildSelectionBar(context),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => sync.pullData(),
                child: items.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              s.invEmptyHint,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: items.length,
                        itemBuilder: (context, index) =>
                            _buildInventoryTile(items[index], role),
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}
