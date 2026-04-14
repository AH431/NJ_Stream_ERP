// ==============================================================================
// InventoryListScreen — 庫存快照列表（Issue #10）
//
// 功能：
//   1. 全角色唯讀：顯示每個產品的即時庫存快照
//   2. 顯示在庫 / 已預留 / 可出貨 三項數字
//   3. 低庫存警示：quantityOnHand <= minStockLevel 時顯示紅色標籤
//   4. Pull-to-refresh 更新庫存
//
// 入庫（type: in）功能留 Issue #11。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  // ─── 低庫存警示 badge ────────────────────────────────────────────────────────

  Widget? _buildLowStockBadge(InventoryItem item) {
    if (item.quantityOnHand > item.minStockLevel) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Text(
        '⚠ 低庫存',
        style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontWeight: FontWeight.bold),
      ),
    );
  }

  // ─── 數量欄位 ────────────────────────────────────────────────────────────────

  Widget _buildQtyColumn(String label, int value, Color color) {
    return Column(
      children: [
        Text('$value',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
      ],
    );
  }

  // ─── 庫存列表項目 ────────────────────────────────────────────────────────────

  Widget _buildInventoryTile(InventoryItem item) {
    final product = _productMap[item.productId];
    final productName = product?.name ?? '產品 #${item.productId}';
    final sku = product?.sku ?? '—';
    final available = item.quantityOnHand - item.quantityReserved;
    final lowStockBadge = _buildLowStockBadge(item);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：產品名稱 + 低庫存 badge
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(productName,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(sku,
                          style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
                _buildQtyColumn('在庫', item.quantityOnHand, Colors.blue.shade700),
                _buildQtyColumn('已預留', item.quantityReserved, Colors.orange.shade700),
                _buildQtyColumn('可出貨', available < 0 ? 0 : available, Colors.green.shade700),
              ],
            ),
            // 低庫存時補充閾值說明
            if (lowStockBadge != null) ...[
              const SizedBox(height: 6),
              Text(
                '最低庫存閾值：${item.minStockLevel}',
                style: TextStyle(fontSize: 11, color: Colors.red.shade400),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    return StreamBuilder<List<InventoryItem>>(
      stream: db.watchInventoryItems(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final items = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () => sync.pullData(),
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Text(
                        '尚無庫存記錄\n下拉以同步取得最新庫存資料',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  itemBuilder: (context, index) =>
                      _buildInventoryTile(items[index]),
                ),
        );
      },
    );
  }
}
