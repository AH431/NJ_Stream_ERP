// ==============================================================================
// SalesOrderListScreen — 銷售訂單列表（Issue #9 / #12）
//
// 功能：
//   1. 監聽本地 Drift 訂單資料，即時更新列表
//   2. 顯示狀態 Chip（pending / confirmed / shipped / cancelled）
//   3. 確認訂單（sales / admin）：僅更新 status，不觸發 reserve
//   4. 預留庫存（sales / admin）：confirmed 後手動觸發，顯示庫存快照確認
//   5. 取消訂單（sales / admin）：若已 confirmed 則同時 enqueue cancel delta
// ==============================================================================

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../database/database.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../providers/sync_provider.dart';
import 'reserve_inventory_dialog.dart';
import 'ship_order_dialog.dart';

class SalesOrderListScreen extends StatefulWidget {
  const SalesOrderListScreen({super.key});

  @override
  State<SalesOrderListScreen> createState() => _SalesOrderListScreenState();
}

class _SalesOrderListScreenState extends State<SalesOrderListScreen> {
  Map<int, String> _customerMap = {};

  @override
  void initState() {
    super.initState();
    _loadCustomerMap();
  }

  Future<void> _loadCustomerMap() async {
    final db = context.read<AppDatabase>();
    final customers = await db.getActiveCustomers();
    if (mounted) {
      setState(() {
        _customerMap = {for (final c in customers) c.id: c.name};
      });
    }
  }

  // ─── 狀態 Chip ──────────────────────────────────────────────────────────────

  Widget _buildStatusLabel(String status) {
    final (label, icon, color) = switch (status) {
      'confirmed' => ('已確認', Icons.check_circle_outline,  Colors.blue),
      'shipped'   => ('已出貨', Icons.local_shipping_outlined, Colors.green),
      'cancelled' => ('已取消', Icons.cancel_outlined,        Colors.red),
      _           => ('待處理', Icons.schedule,               Colors.grey),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  // ─── 確認訂單 ───────────────────────────────────────────────────────────────

  Future<void> _confirmOrder(BuildContext context, SalesOrder order) async {
    // 確認 dialog（防止誤觸）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('確認訂單'),
        content: const Text(
          '確認後訂單狀態將變更為「已確認」。\n'
          '庫存預留需在確認後另行執行。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認訂單'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final now  = DateTime.now().toUtc();

    // 本地樂觀更新
    await db.updateSalesOrderStatus(order.id, 'confirmed', confirmedAt: now);

    // enqueue sales_order:update（不含 reserve）
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'confirmed',
      'confirmedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('訂單已確認。請在訂單列表點選「預留庫存」執行庫存預留。')),
      );
    }
  }

  // ─── 預留庫存 ───────────────────────────────────────────────────────────────

  Future<void> _reserveInventory(BuildContext context, SalesOrder order) async {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    final quotation = await (db.select(db.quotations)
          ..where((t) => t.id.equals(order.quotationId!)))
        .getSingleOrNull();

    if (quotation == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到對應報價，請先同步後再執行預留。')),
        );
      }
      return;
    }

    List<QuotationItemModel> items = [];
    try {
      final rawList = jsonDecode(quotation.items) as List<dynamic>;
      items = rawList
          .cast<Map<String, dynamic>>()
          .map(QuotationItemModel.fromJson)
          .toList();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法解析報價明細，請重新同步。')),
        );
      }
      return;
    }

    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('此報價無明細，無法執行庫存預留。')),
        );
      }
      return;
    }

    // 建立 productMap + inventoryMap
    final products   = await db.getActiveProducts();
    final productMap = <int, Product>{for (final p in products) p.id: p};

    final inventoryMap = <int, InventoryItem>{};
    for (final item in items) {
      final inv = await db.getInventoryItemByProductId(item.productId);
      if (inv != null) inventoryMap[item.productId] = inv;
    }

    if (!context.mounted) return;

    // 顯示 ReserveInventoryDialog
    final reserveConfirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ReserveInventoryDialog(
        order: order,
        items: items,
        productMap: productMap,
        inventoryMap: inventoryMap,
      ),
    );

    if (reserveConfirmed != true) return;

    // enqueue inventory_delta:reserve × N
    for (final item in items) {
      await sync.enqueueDeltaUpdate('inventory_delta', 'reserve', {
        'productId': item.productId,
        'amount': item.quantity,
      });
    }

    // 標記本地已預留，解鎖「出貨」按鈕
    await db.markSalesOrderReserved(order.id);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('庫存預留已排入待同步佇列')),
      );
    }
  }

  // ─── 取消訂單 ───────────────────────────────────────────────────────────────

  Future<void> _cancelOrder(BuildContext context, SalesOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('取消訂單'),
        content: Text(
          order.status == 'confirmed'
              ? '此訂單已確認，取消後將釋放庫存預留，確定要取消？'
              : '確定要取消此訂單？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('返回'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('確認取消', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final wasConfirmed = order.status == 'confirmed';
    final now = DateTime.now().toUtc();

    // 本地樂觀更新
    await db.updateSalesOrderStatus(order.id, 'cancelled');

    // enqueue sales_order:update
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'cancelled',
      'updatedAt': now.toIso8601String(),
    });

    // 若原為 confirmed → 釋放庫存預留（cancel delta）
    if (wasConfirmed && order.quotationId != null) {
      final quotation = await (db.select(db.quotations)
            ..where((t) => t.id.equals(order.quotationId!)))
          .getSingleOrNull();

      if (quotation != null) {
        try {
          final rawList = jsonDecode(quotation.items) as List<dynamic>;
          final items = rawList
              .cast<Map<String, dynamic>>()
              .map(QuotationItemModel.fromJson)
              .toList();

          for (final item in items) {
            await sync.enqueueDeltaUpdate('inventory_delta', 'cancel', {
              'productId': item.productId,
              'amount': item.quantity,
            });
          }
        } catch (_) {
          // items 解析失敗：cancel delta 無法排入，後台需手動核對
          debugPrint('[SalesOrderListScreen] 取消訂單：無法解析 items，cancel delta 未排入');
        }
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('訂單已取消，庫存預留釋放已排入待同步佇列')),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('訂單已取消')),
        );
      }
    }
  }

  // ─── 出貨 ────────────────────────────────────────────────────────────────────

  Future<void> _shipOrder(BuildContext context, SalesOrder order) async {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    // 讀取報價明細
    final quotation = await (db.select(db.quotations)
          ..where((t) => t.id.equals(order.quotationId!)))
        .getSingleOrNull();

    if (quotation == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('找不到對應報價，請先同步再執行出貨。')),
        );
      }
      return;
    }

    List<QuotationItemModel> items = [];
    try {
      final rawList = jsonDecode(quotation.items) as List<dynamic>;
      items = rawList
          .cast<Map<String, dynamic>>()
          .map(QuotationItemModel.fromJson)
          .toList();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法解析報價明細，請重新同步。')),
        );
      }
      return;
    }

    if (items.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('無法取得訂單明細，請重新同步後再試。')),
        );
      }
      return;
    }

    // 建立 productMap + inventoryMap
    final products   = await db.getActiveProducts();
    final productMap = <int, Product>{for (final p in products) p.id: p};

    final inventoryMap = <int, InventoryItem>{};
    for (final item in items) {
      final inv = await db.getInventoryItemByProductId(item.productId);
      if (inv != null) inventoryMap[item.productId] = inv;
    }

    if (!context.mounted) return;

    // 出貨前先 Pull，確保本地庫存快照（reserved/onHand）與伺服器一致
    await sync.pullData();
    if (!context.mounted) return;

    // 顯示 ShipOrderDialog（onHand / reserved 雙扣預覽）
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => ShipOrderDialog(
        order: order,
        items: items,
        productMap: productMap,
        inventoryMap: inventoryMap,
      ),
    );

    if (confirmed != true) return;

    final now = DateTime.now().toUtc();

    // 本地樂觀更新
    await db.updateSalesOrderStatus(order.id, 'shipped', shippedAt: now);

    // enqueue sales_order:update
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'shipped',
      'shippedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    // enqueue inventory_delta:out × N（同時扣 onHand 與 reserved）
    for (final item in items) {
      await sync.enqueueDeltaUpdate('inventory_delta', 'out', {
        'productId': item.productId,
        'amount': item.quantity,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('出貨完成，庫存扣除已排入待同步佇列')),
      );
    }
  }

  // ─── 訂單列表項目 ────────────────────────────────────────────────────────────

  Widget _buildOrderTile(SalesOrder order, String role) {
    final customerName = _customerMap[order.customerId] ?? '客戶 #${order.customerId}';
    final isOffline = order.id < 0;

    // 確認訂單：sales/admin、status=pending、已同步(id>0)、有 quotationId
    final canConfirm = (role == 'sales' || role == 'admin') &&
        order.status == 'pending' &&
        !isOffline &&
        order.quotationId != null;

    // 預留庫存：sales/admin、status=confirmed、已同步、有 quotationId、尚未預留
    final canReserve = (role == 'sales' || role == 'admin') &&
        order.status == 'confirmed' &&
        !isOffline &&
        order.quotationId != null &&
        order.reservedAt == null; // 已預留則隱藏，防止重複 enqueue reserve delta

    // 出貨：warehouse/admin、status=confirmed、已同步、有 quotationId、且已預留庫存
    final canShip = (role == 'warehouse' || role == 'admin') &&
        order.status == 'confirmed' &&
        !isOffline &&
        order.quotationId != null &&
        order.reservedAt != null;

    // 取消訂單：sales/admin、status=pending 或 confirmed、已同步
    final canCancel = (role == 'sales' || role == 'admin') &&
        (order.status == 'pending' || order.status == 'confirmed') &&
        !isOffline;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 第一行：客戶名 + 來源標記 + 離線 icon
            Row(
              children: [
                Expanded(
                  child: Text(
                    customerName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                if (order.quotationId != null)
                  Container(
                    margin: const EdgeInsets.only(right: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: Text(
                      '報價轉入 #${order.quotationId}',
                      style: TextStyle(fontSize: 10, color: Colors.orange.shade700),
                    ),
                  ),
                Icon(
                  isOffline ? Icons.cloud_upload_outlined : Icons.cloud_done_outlined,
                  size: 18,
                  color: isOffline ? Colors.orange : Colors.green,
                ),
              ],
            ),
            const SizedBox(height: 6),
            // 第二行：狀態 Chip + 訂單日期
            Row(
              children: [
                _buildStatusLabel(order.status),
                const SizedBox(width: 8),
                Text(
                  '建立：${_formatDate(order.createdAt)}',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
            // 操作按鈕（有權限才顯示）
            if (canConfirm || canReserve || canShip || canCancel) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (canConfirm)
                    TextButton.icon(
                      onPressed: () => _confirmOrder(context, order),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: const Text('確認訂單'),
                      style: TextButton.styleFrom(foregroundColor: Colors.blue),
                    ),
                  if (canReserve)
                    TextButton.icon(
                      onPressed: () => _reserveInventory(context, order),
                      icon: const Icon(Icons.inventory_outlined, size: 16),
                      label: const Text('預留庫存'),
                      style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                    ),
                  if (canShip)
                    TextButton.icon(
                      onPressed: () => _shipOrder(context, order),
                      icon: const Icon(Icons.local_shipping_outlined, size: 16),
                      label: const Text('出貨'),
                      style: TextButton.styleFrom(foregroundColor: Colors.green),
                    ),
                  if (canCancel)
                    TextButton.icon(
                      onPressed: () => _cancelOrder(context, order),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('取消'),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  // ─── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final role = sync.role ?? '';

    return StreamBuilder<List<SalesOrder>>(
      stream: db.watchActiveSalesOrders(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final orders = snapshot.data ?? [];

        return RefreshIndicator(
          onRefresh: () => sync.pullData(),
          child: orders.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Center(
                      child: Text(
                        '目前無訂單\n下拉以同步，或由報價轉入',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: orders.length,
                  itemBuilder: (context, index) =>
                      _buildOrderTile(orders[index], role),
                ),
        );
      },
    );
  }
}
