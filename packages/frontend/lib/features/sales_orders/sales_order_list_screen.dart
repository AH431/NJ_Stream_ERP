// ==============================================================================
// SalesOrderListScreen — 銷售訂單列表（Issue #9 / #12）
//
// 功能：
//   1. 監聽本地 Drift 訂單資料，即時更新列表
//   2. 顯示狀態 Chip（pending / confirmed / shipped / cancelled）
//   3. 確認訂單（sales / admin）：僅更新 status，不觸發 reserve
//   4. 預留庫存（sales / admin）：confirmed 後手動觸發，顯示庫存快照確認
//   5. 取消訂單：長按進入選取模式 → 頂部工具列批次取消（sales / admin）
// ==============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../core/document_actions.dart';
import '../../database/database.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/dao/inventory_items_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../database/dao/sales_order_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../providers/sync_provider.dart';
import 'reserve_inventory_dialog.dart' show ReserveInventoryDialog, ReserveDialogAction;
import 'ship_order_dialog.dart';

class SalesOrderListScreen extends StatefulWidget {
  const SalesOrderListScreen({super.key});

  @override
  State<SalesOrderListScreen> createState() => _SalesOrderListScreenState();
}

class _SalesOrderListScreenState extends State<SalesOrderListScreen> {
  Map<int, String> _customerMap = {};
  StreamSubscription<List<Customer>>? _customerSub;

  // 選取模式
  bool _selectionMode = false;
  final Set<int> _selectedIds = {};
  List<SalesOrder> _orders = [];  // 供批次取消使用

  @override
  void initState() {
    super.initState();
    final db = context.read<AppDatabase>();
    _customerSub = db.watchActiveCustomers().listen((customers) {
      if (mounted) {
        setState(() {
          _customerMap = {for (final c in customers) c.id: c.name};
        });
      }
    });
  }

  @override
  void dispose() {
    _customerSub?.cancel();
    super.dispose();
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

  Future<void> _batchCancel(BuildContext context) async {
    final s     = context.read<AppStrings>();
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ds = ctx.read<AppStrings>();
        return AlertDialog(
          title: Text(ds.isEnglish ? 'Confirm Cancel Orders' : '確認取消訂單'),
          content: Text(ds.isEnglish
              ? 'Cancel $count orders? This cannot be undone.'
              : '確定要取消 $count 筆訂單？取消後資料僅能從後台查詢。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.isEnglish ? 'Back' : '返回'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ds.isEnglish ? 'Confirm Cancel' : '確認取消',
                  style: const TextStyle(color: Colors.red)),
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
      final order = _orders.where((o) => o.id == id).firstOrNull;
      if (order == null) continue;

      final wasConfirmed = order.status == 'confirmed';

      await db.updateSalesOrderStatus(id, 'cancelled');
      await sync.enqueueUpdate('sales_order', id, {
        'id': id,
        'status': 'cancelled',
        'updatedAt': now.toIso8601String(),
      });

      // 若原為 confirmed → 釋放庫存預留
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
            debugPrint('[SalesOrderListScreen] 批次取消：無法解析 items，cancel delta 未排入');
          }
        }
      }
    }

    _exitSelectionMode();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? '$count orders cancelled (pending sync).'
            : '已取消 $count 筆訂單，待同步後更新')),
      );
    }
  }

  Widget _buildSelectionBar(BuildContext context, String role) {
    final s         = AppStrings.of(context);
    final canCancel = role == 'sales' || role == 'admin';
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
              s.isEnglish ? '${_selectedIds.length} selected' : '已選取 ${_selectedIds.length} 項',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (canCancel)
            TextButton.icon(
              onPressed: _selectedIds.isEmpty ? null : () => _batchCancel(context),
              icon: const Icon(Icons.cancel_outlined, size: 18),
              label: Text(s.isEnglish ? 'Cancel Orders' : '取消訂單'),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  // ─── 狀態 Chip ──────────────────────────────────────────────────────────────

  Widget _buildStatusLabel(String status, AppStrings s) {
    final (label, icon, color) = switch (status) {
      'confirmed' => (s.orderStatusConfirmed, Icons.check_circle_outline,    Colors.blue),
      'shipped'   => (s.orderStatusShipped,   Icons.local_shipping_outlined, Colors.green),
      'cancelled' => (s.orderStatusCancelled, Icons.cancel_outlined,         Colors.red),
      _           => (s.orderStatusPending,   Icons.schedule,                Colors.grey),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ds = ctx.read<AppStrings>();
        return AlertDialog(
          title: Text(ds.btnConfirmOrder),
          content: Text(ds.isEnglish
              ? 'Order status will change to "Confirmed".\nInventory reservation must be done separately.'
              : '確認後訂單狀態將變更為「已確認」。\n庫存預留需在確認後另行執行。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.btnCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(ds.btnConfirmOrder),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;

    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();
    final s    = context.read<AppStrings>();
    final now  = DateTime.now().toUtc();

    await db.updateSalesOrderStatus(order.id, 'confirmed', confirmedAt: now);
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'confirmed',
      'confirmedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? 'Order confirmed. Tap "Reserve" to reserve inventory.'
            : '訂單已確認。請在訂單列表點選「預留庫存」執行庫存預留。')),
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
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'Quotation not found. Please sync first.'
              : '找不到對應報價，請先同步後再執行預留。')),
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
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'Cannot parse quotation items. Please sync again.'
              : '無法解析報價明細，請重新同步。')),
        );
      }
      return;
    }

    if (items.isEmpty) {
      if (context.mounted) {
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'No items in this quotation. Cannot reserve inventory.'
              : '此報價無明細，無法執行庫存預留。')),
        );
      }
      return;
    }

    final products   = await db.getActiveProducts();
    final productMap = <int, Product>{for (final p in products) p.id: p};

    final inventoryMap = <int, InventoryItem>{};
    for (final item in items) {
      final inv = await db.getInventoryItemByProductId(item.productId);
      if (inv != null) inventoryMap[item.productId] = inv;
    }

    if (!context.mounted) return;

    final action = await showDialog<ReserveDialogAction>(
      context: context,
      builder: (_) => ReserveInventoryDialog(
        order: order,
        items: items,
        productMap: productMap,
        inventoryMap: inventoryMap,
      ),
    );

    if (!context.mounted) return;

    switch (action) {
      case ReserveDialogAction.confirmed:
        for (final item in items) {
          await sync.enqueueDeltaUpdate('inventory_delta', 'reserve', {
            'productId': item.productId,
            'amount': item.quantity,
            'orderId': order.id,
          });
        }
        await db.markSalesOrderReserved(order.id);
        if (context.mounted) {
          final s = context.read<AppStrings>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.isEnglish
                ? 'Inventory reservation queued for sync.'
                : '庫存預留已排入待同步佇列')),
          );
        }

      case ReserveDialogAction.waitForStock:
        await db.markSalesOrderStockAlert(order.id);
        if (context.mounted) {
          final s = context.read<AppStrings>();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.isEnglish
                ? 'Marked as insufficient stock. Retry when restocked.'
                : '已標記庫存不足，等待到貨後可重新嘗試預留')),
          );
        }

      case ReserveDialogAction.splitOrder:
        await _doSplitOrder(context, db, sync, order);

      case null:
        break;
    }
  }

  Future<void> _doSplitOrder(
    BuildContext context,
    AppDatabase db,
    SyncProvider sync,
    SalesOrder order,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ds = ctx.read<AppStrings>();
        return AlertDialog(
          title: Text(ds.isEnglish ? 'Confirm Split Order' : '確認拆單'),
          content: Text(ds.isEnglish
              ? 'This order will be cancelled. Please create a new quotation and split the items.\n\nConfirm?'
              : '此訂單將被取消，請至報價管理建立新報價單並重新轉訂單。\n\n確定要拆單嗎？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(ds.isEnglish ? 'Back' : '返回'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange),
              child: Text(ds.isEnglish ? 'Confirm Split' : '確認拆單'),
            ),
          ],
        );
      },
    );
    if (confirm != true || !context.mounted) return;

    final s   = context.read<AppStrings>();
    final now = DateTime.now().toUtc();
    await db.updateSalesOrderStatus(order.id, 'cancelled');
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'cancelled',
      'updatedAt': now.toIso8601String(),
    });

    sync.requestTabSwitch(3);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? 'Order cancelled. Create a new quotation and split items.'
            : '訂單已取消，請建立新報價單並拆分品項後重新轉訂單')),
      );
    }
  }

  // ─── 出貨 ────────────────────────────────────────────────────────────────────

  Future<void> _shipOrder(BuildContext context, SalesOrder order) async {
    final db   = context.read<AppDatabase>();
    final sync = context.read<SyncProvider>();

    final quotation = await (db.select(db.quotations)
          ..where((t) => t.id.equals(order.quotationId!)))
        .getSingleOrNull();

    if (quotation == null) {
      if (context.mounted) {
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'Quotation not found. Please sync first.'
              : '找不到對應報價，請先同步再執行出貨。')),
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
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'Cannot parse quotation items. Please sync again.'
              : '無法解析報價明細，請重新同步。')),
        );
      }
      return;
    }

    if (items.isEmpty) {
      if (context.mounted) {
        final s = context.read<AppStrings>();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.isEnglish
              ? 'No order items found. Please sync again.'
              : '無法取得訂單明細，請重新同步後再試。')),
        );
      }
      return;
    }

    final products   = await db.getActiveProducts();
    final productMap = <int, Product>{for (final p in products) p.id: p};

    final inventoryMap = <int, InventoryItem>{};
    for (final item in items) {
      final inv = await db.getInventoryItemByProductId(item.productId);
      if (inv != null) inventoryMap[item.productId] = inv;
    }

    if (!context.mounted) return;

    await sync.pullData();
    if (!context.mounted) return;

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

    await db.updateSalesOrderStatus(order.id, 'shipped', shippedAt: now);
    await sync.enqueueUpdate('sales_order', order.id, {
      'id': order.id,
      'status': 'shipped',
      'shippedAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
    });

    for (final item in items) {
      await sync.enqueueDeltaUpdate('inventory_delta', 'out', {
        'productId': item.productId,
        'amount': item.quantity,
      });
    }

    if (context.mounted) {
      final s = context.read<AppStrings>();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.isEnglish
            ? 'Shipment complete. Inventory deduction queued for sync.'
            : '出貨完成，庫存扣除已排入待同步佇列')),
      );
    }
  }

  // ─── 訂單列表項目 ────────────────────────────────────────────────────────────

  Widget _buildOrderTile(SalesOrder order, String role) {
    final s            = AppStrings.of(context);
    final customerName = _customerMap[order.customerId] ??
        (s.isEnglish ? 'Customer #${order.customerId}' : '客戶 #${order.customerId}');
    final isOffline = order.id < 0;

    final canConfirm = (role == 'sales' || role == 'admin') &&
        order.status == 'pending' &&
        !isOffline &&
        order.quotationId != null;

    final hasStockAlert = order.stockAlertAt != null && order.reservedAt == null;

    final canReserve = (role == 'sales' || role == 'admin') &&
        order.status == 'confirmed' &&
        !isOffline &&
        order.quotationId != null &&
        order.reservedAt == null &&
        !hasStockAlert;

    final canShip = (role == 'warehouse' || role == 'admin') &&
        order.status == 'confirmed' &&
        !isOffline &&
        order.quotationId != null &&
        order.reservedAt != null;

    // 可選取取消：sales/admin、pending 或 confirmed、已同步
    final isSelectable = (role == 'sales' || role == 'admin') &&
        (order.status == 'pending' || order.status == 'confirmed') &&
        !isOffline;

    final isSelected = _selectedIds.contains(order.id);

    return GestureDetector(
      onLongPress: (!_selectionMode && isSelectable)
          ? () => _enterSelectionMode(order.id)
          : null,
      onTap: (_selectionMode && isSelectable) ? () => _toggleItem(order.id) : null,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        color: isSelected
            ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：(checkbox) + 客戶名 + 來源標記 + 離線 icon
              Row(
                children: [
                  if (_selectionMode && isSelectable)
                    Checkbox(
                      value: isSelected,
                      onChanged: (_) => _toggleItem(order.id),
                      visualDensity: VisualDensity.compact,
                    ),
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
                        s.orderFromQuot(order.quotationId!),
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
                  _buildStatusLabel(order.status, s),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.orderCreatedAt(_formatDate(order.createdAt)),
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              // 操作按鈕（選取模式下隱藏）
              if (!_selectionMode &&
                  (canConfirm || canReserve || hasStockAlert || canShip ||
                      (!isOffline && (role == 'sales' || role == 'admin')))) ...[
                const SizedBox(height: 4),
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 0,
                  runSpacing: 0,
                  children: [
                    if (!isOffline && (role == 'sales' || role == 'admin')) ...[
                      TextButton.icon(
                        onPressed: () => downloadAndOpenPdf(
                          context,
                          apiPath: '/api/v1/sales-orders/${order.id}/pdf',
                          filename: 'order-${order.id}.pdf',
                        ),
                        icon: const Icon(Icons.picture_as_pdf_outlined, size: 16),
                        label: Text(s.btnPdf),
                        style: TextButton.styleFrom(foregroundColor: Colors.deepOrange),
                      ),
                      TextButton.icon(
                        onPressed: () => sendEmail(
                          context,
                          apiPath: '/api/v1/sales-orders/${order.id}/send-email',
                        ),
                        icon: const Icon(Icons.email_outlined, size: 16),
                        label: Text(s.btnSendEmail),
                        style: TextButton.styleFrom(foregroundColor: Colors.teal),
                      ),
                    ],
                    if (canConfirm)
                      TextButton.icon(
                        onPressed: () => _confirmOrder(context, order),
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: Text(s.btnConfirmOrder),
                        style: TextButton.styleFrom(foregroundColor: Colors.blue),
                      ),
                    if (canReserve)
                      TextButton.icon(
                        onPressed: () => _reserveInventory(context, order),
                        icon: const Icon(Icons.inventory_outlined, size: 16),
                        label: Text(s.btnReserveInventory),
                        style: TextButton.styleFrom(foregroundColor: Colors.indigo),
                      ),
                    if (hasStockAlert)
                      TextButton.icon(
                        onPressed: () => _reserveInventory(context, order),
                        icon: const Icon(Icons.warning_amber_rounded, size: 16),
                        label: Text(s.btnInsufficientStock),
                        style: TextButton.styleFrom(foregroundColor: Colors.orange),
                      ),
                     if (canShip)
                      TextButton.icon(
                        onPressed: () => _shipOrder(context, order),
                        icon: const Icon(Icons.local_shipping_outlined, size: 16),
                        label: Text(s.btnShipOrder),
                        style: TextButton.styleFrom(foregroundColor: Colors.green),
                      ),
                  ],
                ),
              ],
            ],
          ),
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
    final s    = AppStrings.of(context);
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
        // 更新快取供批次取消使用
        _orders = orders;

        return Column(
          children: [
            if (_selectionMode) _buildSelectionBar(context, role),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => sync.pullData(),
                child: orders.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: [
                          const SizedBox(height: 120),
                          Center(
                            child: Text(
                              s.isEnglish
                                  ? 'No orders yet.\nPull to sync or convert from a quotation.'
                                  : '目前無訂單\n下拉以同步，或由報價轉入',
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
              ),
            ),
          ],
        );
      },
    );
  }
}