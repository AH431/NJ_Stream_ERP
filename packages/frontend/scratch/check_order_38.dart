
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:nj_stream_erp_frontend/database/database.dart';

void main() async {
  final dbFile = File('c:/Users/archi/Documents/nj_stream_erp.sqlite'); // Correct path from database.dart _openConnection
  // Actually, database.dart says:
  // final dir = await getApplicationDocumentsDirectory();
  // final file = File(p.join(dir.path, 'nj_stream_erp.sqlite'));
  
  // On Windows, getApplicationDocumentsDirectory is usually C:\Users\<user>\Documents
  
  final db = AppDatabase.forTesting(NativeDatabase(dbFile));

  final order = await (db.select(db.salesOrders)..where((t) => t.id.equals(38))).getSingleOrNull();
  if (order == null) {
    print('Order #38 not found.');
    return;
  }

  print('Order #38:');
  print('  Status: ${order.status}');
  print('  Created At: ${order.createdAt}');
  print('  Updated At: ${order.updatedAt}');
  print('  Deleted At: ${order.deletedAt}');

  final items = await (db.select(db.orderItems)..where((t) => t.orderId.equals(38))).get();
  print('Items for #38: ${items.length}');
  for (final item in items) {
    print('  - Product ID: ${item.productId}, Qty: ${item.quantity}');
  }

  await db.close();
}
