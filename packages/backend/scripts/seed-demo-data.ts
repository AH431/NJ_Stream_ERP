/**
 * Phase 2 手機實測 Demo 資料 Seed
 *
 * 建立 7 個月（2025-10 ～ 2026-04）的完整商業資料，
 * 涵蓋所有 Analytics 圖表所需的 sales_orders / order_items / quotations。
 *
 * 執行前提：需先執行 seed-test-user.ts（需要 admin_test 帳號）
 * 執行: npx tsx scripts/seed-demo-data.ts
 * 冪等性: 偵測到 SKU=TUBE-A001 時自動跳過
 */

import 'dotenv/config';
import { drizzle }  from 'drizzle-orm/postgres-js';
import postgres      from 'postgres';
import { eq, and, isNull } from 'drizzle-orm';
import * as schema   from '../src/schemas/index.js';

const sqlClient = postgres(process.env.DATABASE_URL!);
const db = drizzle(sqlClient, { schema });

// ── 工具函式 ───────────────────────────────────────────────
/** 建立指定日期的 UTC Date（時間固定 08:00:00）*/
const d = (y: number, m: number, day: number) =>
  new Date(`${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}T08:00:00.000Z`);

// ── Step 0: Guard - 確認 admin_test 存在 ──────────────────
const [adminUser] = await db
  .select({ id: schema.users.id })
  .from(schema.users)
  .where(and(eq(schema.users.username, 'admin_test'), isNull(schema.users.deletedAt)));

if (!adminUser) {
  console.error('❌ admin_test 不存在，請先執行 seed-test-user.ts');
  await sqlClient.end();
  process.exit(1);
}
const adminId = adminUser.id;

// ── Step 0: Guard - 冪等性檢查 ────────────────────────────
const [existingProduct] = await db
  .select({ id: schema.products.id })
  .from(schema.products)
  .where(eq(schema.products.sku, 'TUBE-A001'));

if (existingProduct) {
  console.log('⚠️  Demo 資料已存在（TUBE-A001），跳過 seed。');
  await sqlClient.end();
  process.exit(0);
}

// ── Step 1: 產品（5 種，含成本價，2 個低庫存） ──────────────
const insertedProducts = await db.insert(schema.products).values([
  { name: '精密管材 A 型', sku: 'TUBE-A001',  unitPrice: '2500.00', costPrice: '1850.00', minStockLevel: 50  },
  { name: '角型鋼材 B 型', sku: 'ANGLE-B002', unitPrice: '980.00',  costPrice: '720.00',  minStockLevel: 100 },
  { name: '板材 C 型',    sku: 'PLATE-C003', unitPrice: '1800.00', costPrice: '1300.00', minStockLevel: 80  },
  { name: '特殊材料 D 型', sku: 'SPEC-D004',  unitPrice: '5200.00', costPrice: '3800.00', minStockLevel: 20  },
  { name: '標準零件 E 型', sku: 'PART-E005',  unitPrice: '480.00',  costPrice: '350.00',  minStockLevel: 200 },
]).returning({ id: schema.products.id });

const [p0, p1, p2, p3, p4] = insertedProducts.map((r) => r.id);
console.log(`✅ Products (${insertedProducts.length}): ${[p0, p1, p2, p3, p4].join(', ')}`);

// ── Step 2: 客戶（5 家公司）────────────────────────────────
const insertedCustomers = await db.insert(schema.customers).values([
  { name: '台灣精工企業有限公司', contact: '張志明', email: 'contact@tw-seiko.example',    taxId: '10001001', paymentTermsDays: 30 },
  { name: '建弘工程股份有限公司', contact: '林雅惠', email: 'purchase@jianhong.example',   taxId: '10002002', paymentTermsDays: 45 },
  { name: '鋒茂科技有限公司',    contact: '陳建國', email: 'order@fengmao.example',        taxId: '10003003', paymentTermsDays: 30 },
  { name: '聚隆製造有限公司',    contact: '黃明達', email: 'procurement@julong.example',   taxId: '10004004', paymentTermsDays: 60 },
  { name: '允昇工業股份有限公司', contact: '吳芳儀', email: 'supply@yunsheng.example',      taxId: '10005005', paymentTermsDays: 30 },
]).returning({ id: schema.customers.id });

const [c0, c1, c2, c3, c4] = insertedCustomers.map((r) => r.id);
console.log(`✅ Customers (${insertedCustomers.length}): ${[c0, c1, c2, c3, c4].join(', ')}`);

// ── Step 3: 庫存（p1 角型鋼材 B、p3 特殊材料 D 低庫存警示）─
await db.insert(schema.inventoryItems).values([
  { productId: p0, warehouseId: 1, quantityOnHand: 180, quantityReserved: 20,  minStockLevel: 50  }, // available=160 OK
  { productId: p1, warehouseId: 1, quantityOnHand: 85,  quantityReserved: 30,  minStockLevel: 100 }, // available=55  ⚠️ LOW
  { productId: p2, warehouseId: 1, quantityOnHand: 220, quantityReserved: 40,  minStockLevel: 80  }, // available=180 OK
  { productId: p3, warehouseId: 1, quantityOnHand: 15,  quantityReserved: 5,   minStockLevel: 20  }, // available=10  ⚠️ LOW
  { productId: p4, warehouseId: 1, quantityOnHand: 650, quantityReserved: 100, minStockLevel: 200 }, // available=550 OK
]);
console.log('✅ Inventory items inserted (2 low-stock items: p1, p3)');

// ── Step 4: Sales Orders + Order Items（7 個月）─────────────
type OrderItem = { productId: number; qty: number; price: number };
type OrderSpec = {
  customerId: number;
  status: 'shipped' | 'confirmed' | 'pending';
  paymentStatus: 'paid' | 'unpaid';
  createdAt: Date;
  confirmedAt?: Date;
  shippedAt?: Date;
  paidAt?: Date;
  items: OrderItem[];
};

const orderSpecs: OrderSpec[] = [
  // ── 2025-10 October，目標 ~NT$463,000 ──────────────────
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,10,5), confirmedAt: d(2025,10,8), shippedAt: d(2025,10,15), paidAt: d(2025,10,20),
    items: [{ productId: p0, qty: 20, price: 2500 }, { productId: p2, qty: 50, price: 1800 }],
    // 50,000 + 90,000 = 140,000
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,10,12), confirmedAt: d(2025,10,15), shippedAt: d(2025,10,22), paidAt: d(2025,10,28),
    items: [{ productId: p1, qty: 100, price: 980 }, { productId: p4, qty: 200, price: 480 }],
    // 98,000 + 96,000 = 194,000
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,10,20), confirmedAt: d(2025,10,23), shippedAt: d(2025,10,28), paidAt: d(2025,11,5),
    items: [{ productId: p3, qty: 20, price: 5200 }, { productId: p0, qty: 10, price: 2500 }],
    // 104,000 + 25,000 = 129,000
  },
  // Oct Total: 463,000

  // ── 2025-11 November，目標 ~NT$646,500 ─────────────────
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,3), confirmedAt: d(2025,11,6), shippedAt: d(2025,11,12), paidAt: d(2025,11,18),
    items: [{ productId: p2, qty: 100, price: 1800 }, { productId: p1, qty: 60, price: 980 }],
    // 180,000 + 58,800 = 238,800
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,8), confirmedAt: d(2025,11,11), shippedAt: d(2025,11,18), paidAt: d(2025,11,25),
    items: [{ productId: p0, qty: 30, price: 2500 }, { productId: p4, qty: 150, price: 480 }],
    // 75,000 + 72,000 = 147,000
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,15), confirmedAt: d(2025,11,18), shippedAt: d(2025,11,25), paidAt: d(2025,12,2),
    items: [{ productId: p3, qty: 25, price: 5200 }, { productId: p1, qty: 40, price: 980 }],
    // 130,000 + 39,200 = 169,200
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,22), confirmedAt: d(2025,11,25), shippedAt: d(2025,11,29), paidAt: d(2025,12,10),
    items: [{ productId: p0, qty: 15, price: 2500 }, { productId: p2, qty: 30, price: 1800 }],
    // 37,500 + 54,000 = 91,500
  },
  // Nov Total: 646,500

  // ── 2025-12 December，目標 ~NT$826,900 ─────────────────
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,2), confirmedAt: d(2025,12,5), shippedAt: d(2025,12,10), paidAt: d(2025,12,20),
    items: [{ productId: p3, qty: 30, price: 5200 }, { productId: p0, qty: 25, price: 2500 }],
    // 156,000 + 62,500 = 218,500
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,8), confirmedAt: d(2025,12,11), shippedAt: d(2025,12,16), paidAt: d(2025,12,28),
    items: [{ productId: p2, qty: 120, price: 1800 }, { productId: p4, qty: 200, price: 480 }],
    // 216,000 + 96,000 = 312,000
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,15), confirmedAt: d(2025,12,18), shippedAt: d(2025,12,23), paidAt: d(2026,1,5),
    items: [{ productId: p1, qty: 80, price: 980 }, { productId: p0, qty: 20, price: 2500 }],
    // 78,400 + 50,000 = 128,400
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,20), confirmedAt: d(2025,12,23), shippedAt: d(2025,12,26), paidAt: d(2026,1,8),
    items: [{ productId: p3, qty: 15, price: 5200 }, { productId: p2, qty: 50, price: 1800 }],
    // 78,000 + 90,000 = 168,000
  },
  // Dec Total: 826,900

  // ── 2026-01 January，目標 ~NT$389,700 ──────────────────
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,6), confirmedAt: d(2026,1,9), shippedAt: d(2026,1,14), paidAt: d(2026,1,25),
    items: [{ productId: p4, qty: 300, price: 480 }, { productId: p1, qty: 50, price: 980 }],
    // 144,000 + 49,000 = 193,000
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,15), confirmedAt: d(2026,1,18), shippedAt: d(2026,1,23), paidAt: d(2026,2,3),
    items: [{ productId: p0, qty: 15, price: 2500 }, { productId: p2, qty: 40, price: 1800 }],
    // 37,500 + 72,000 = 109,500
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,22), confirmedAt: d(2026,1,25), shippedAt: d(2026,1,28), paidAt: d(2026,2,8),
    items: [{ productId: p1, qty: 40, price: 980 }, { productId: p4, qty: 100, price: 480 }],
    // 39,200 + 48,000 = 87,200
  },
  // Jan Total: 389,700

  // ── 2026-02 February，目標 ~NT$580,200 ─────────────────
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,3), confirmedAt: d(2026,2,6), shippedAt: d(2026,2,12), paidAt: d(2026,2,22),
    items: [{ productId: p3, qty: 20, price: 5200 }, { productId: p0, qty: 18, price: 2500 }],
    // 104,000 + 45,000 = 149,000
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,10), confirmedAt: d(2026,2,13), shippedAt: d(2026,2,19), paidAt: d(2026,3,1),
    items: [{ productId: p2, qty: 80, price: 1800 }, { productId: p1, qty: 70, price: 980 }],
    // 144,000 + 68,600 = 212,600
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,18), confirmedAt: d(2026,2,21), shippedAt: d(2026,2,25), paidAt: d(2026,3,5),
    items: [{ productId: p0, qty: 22, price: 2500 }, { productId: p4, qty: 120, price: 480 }],
    // 55,000 + 57,600 = 112,600
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,24), confirmedAt: d(2026,2,26), shippedAt: d(2026,2,28), paidAt: d(2026,3,10),
    items: [{ productId: p3, qty: 10, price: 5200 }, { productId: p2, qty: 30, price: 1800 }],
    // 52,000 + 54,000 = 106,000
  },
  // Feb Total: 580,200

  // ── 2026-03 March，目標 ~NT$719,600 ────────────────────
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,3), confirmedAt: d(2026,3,6), shippedAt: d(2026,3,12), paidAt: d(2026,3,22),
    items: [{ productId: p0, qty: 35, price: 2500 }, { productId: p2, qty: 60, price: 1800 }],
    // 87,500 + 108,000 = 195,500
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,10), confirmedAt: d(2026,3,13), shippedAt: d(2026,3,18), paidAt: d(2026,3,28),
    items: [{ productId: p3, qty: 22, price: 5200 }, { productId: p1, qty: 80, price: 980 }],
    // 114,400 + 78,400 = 192,800
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,17), confirmedAt: d(2026,3,20), shippedAt: d(2026,3,25), paidAt: d(2026,4,4),
    items: [{ productId: p4, qty: 250, price: 480 }, { productId: p2, qty: 50, price: 1800 }],
    // 120,000 + 90,000 = 210,000
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,24), confirmedAt: d(2026,3,27), shippedAt: d(2026,3,30), paidAt: d(2026,4,8),
    items: [{ productId: p0, qty: 25, price: 2500 }, { productId: p1, qty: 60, price: 980 }],
    // 62,500 + 58,800 = 121,300
  },
  // Mar Total: 719,600

  // ── 2026-04 April（當月）：2 shipped + 1 confirmed + 1 pending
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,2), confirmedAt: d(2026,4,5), shippedAt: d(2026,4,10), paidAt: d(2026,4,18),
    items: [{ productId: p3, qty: 15, price: 5200 }, { productId: p2, qty: 40, price: 1800 }],
    // 78,000 + 72,000 = 150,000  ← soApr1
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,8), confirmedAt: d(2026,4,11), shippedAt: d(2026,4,16), paidAt: d(2026,4,24),
    items: [{ productId: p0, qty: 18, price: 2500 }, { productId: p1, qty: 50, price: 980 }],
    // 45,000 + 49,000 = 94,000  ← soApr2
  },
  {
    customerId: c2, status: 'confirmed', paymentStatus: 'unpaid',
    createdAt: d(2026,4,15), confirmedAt: d(2026,4,18),
    items: [{ productId: p2, qty: 60, price: 1800 }, { productId: p4, qty: 100, price: 480 }],
    // 108,000 + 48,000 = 156,000  ← soApr3
  },
  {
    customerId: c0, status: 'pending', paymentStatus: 'unpaid',
    createdAt: d(2026,4,20),
    items: [{ productId: p3, qty: 10, price: 5200 }],
    // 52,000  ← soApr4
  },
  // Apr Total (confirmed+shipped in revenue): 400,000
];

// 批次插入（逐一建立以取得 ID 對應 items）
const soIds: number[] = [];
for (const spec of orderSpecs) {
  const [so] = await db.insert(schema.salesOrders).values({
    customerId:    spec.customerId,
    createdBy:     adminId,
    status:        spec.status,
    paymentStatus: spec.paymentStatus,
    confirmedAt:   spec.confirmedAt,
    shippedAt:     spec.shippedAt,
    paidAt:        spec.paidAt,
    createdAt:     spec.createdAt,
    updatedAt:     spec.shippedAt ?? spec.confirmedAt ?? spec.createdAt,
  }).returning({ id: schema.salesOrders.id });

  await db.insert(schema.orderItems).values(
    spec.items.map((item) => ({
      salesOrderId: so.id,
      productId:    item.productId,
      quantity:     item.qty,
      unitPrice:    item.price.toFixed(2),
      subtotal:     (item.qty * item.price).toFixed(2),
    })),
  );
  soIds.push(so.id);
}

// soIds 對應: [0..21]=已出貨歷史, [22]=soApr1, [23]=soApr2, [24]=soApr3, [25]=soApr4
const soApr1 = soIds[22];
const soApr2 = soIds[23];
const soApr3 = soIds[24];
const soApr4 = soIds[25];

console.log(`✅ Sales orders (${orderSpecs.length}) + order items inserted`);
console.log(`   Apr IDs: Apr1=${soApr1}, Apr2=${soApr2}, Apr3=${soApr3}, Apr4=${soApr4}`);

// ── Step 5: Quotations（近 30 天，漏斗驗收用）─────────────
// 12 筆報價：4 轉換 + 3 到期 + 5 進行中 → 轉換率 33.3%，平均轉換 7.5 天
await db.insert(schema.quotations).values([
  // 已轉換（4 筆），convertedToOrderId → 四張四月訂單
  {
    customerId: c1, createdBy: adminId,
    totalAmount: '157500.00', taxAmount: '7875.00',
    status: 'converted', convertedToOrderId: soApr1,
    createdAt: d(2026,3,28), updatedAt: d(2026,4,2),
    // 5 天轉換
  },
  {
    customerId: c4, createdBy: adminId,
    totalAmount: '98700.00', taxAmount: '4935.00',
    status: 'converted', convertedToOrderId: soApr2,
    createdAt: d(2026,3,30), updatedAt: d(2026,4,8),
    // 9 天轉換
  },
  {
    customerId: c2, createdBy: adminId,
    totalAmount: '163800.00', taxAmount: '8190.00',
    status: 'converted', convertedToOrderId: soApr3,
    createdAt: d(2026,4,3), updatedAt: d(2026,4,15),
    // 12 天轉換
  },
  {
    customerId: c0, createdBy: adminId,
    totalAmount: '54600.00', taxAmount: '2730.00',
    status: 'converted', convertedToOrderId: soApr4,
    createdAt: d(2026,4,16), updatedAt: d(2026,4,20),
    // 4 天轉換
  },
  // 已到期（3 筆）
  {
    customerId: c3, createdBy: adminId,
    totalAmount: '88000.00', taxAmount: '4400.00',
    status: 'expired',
    createdAt: d(2026,4,1), updatedAt: d(2026,4,15),
  },
  {
    customerId: c4, createdBy: adminId,
    totalAmount: '210000.00', taxAmount: '10500.00',
    status: 'expired',
    createdAt: d(2026,4,5), updatedAt: d(2026,4,19),
  },
  {
    customerId: c1, createdBy: adminId,
    totalAmount: '45000.00', taxAmount: '2250.00',
    status: 'expired',
    createdAt: d(2026,4,14), updatedAt: d(2026,4,22),
  },
  // 進行中：sent（3 筆）
  {
    customerId: c2, createdBy: adminId,
    totalAmount: '320000.00', taxAmount: '16000.00',
    status: 'sent',
    createdAt: d(2026,4,8), updatedAt: d(2026,4,9),
  },
  {
    customerId: c0, createdBy: adminId,
    totalAmount: '62000.00', taxAmount: '3100.00',
    status: 'sent',
    createdAt: d(2026,4,12), updatedAt: d(2026,4,13),
  },
  {
    customerId: c3, createdBy: adminId,
    totalAmount: '148000.00', taxAmount: '7400.00',
    status: 'sent',
    createdAt: d(2026,4,20), updatedAt: d(2026,4,21),
  },
  // 進行中：draft（2 筆）
  {
    customerId: c3, createdBy: adminId,
    totalAmount: '178000.00', taxAmount: '8900.00',
    status: 'draft',
    createdAt: d(2026,4,10), updatedAt: d(2026,4,10),
  },
  {
    customerId: c4, createdBy: adminId,
    totalAmount: '95000.00', taxAmount: '4750.00',
    status: 'draft',
    createdAt: d(2026,4,18), updatedAt: d(2026,4,18),
  },
]);
console.log('✅ Quotations (12) inserted');

// ── Summary ────────────────────────────────────────────────
console.log(`
╔══════════════════════════════════════════════════════╗
║        Phase 2 Demo 資料 Seed 完成                   ║
╠══════════════════════════════════════════════════════╣
║  Products  : 5 種（p1角型鋼材B、p3特殊材料D 低庫存）  ║
║  Customers : 5 家                                    ║
║  Sales Orders : 26 筆                                ║
║    ├ shipped  : 22 筆（歷史 + 4月前兩筆）             ║
║    ├ confirmed:  1 筆（4月第 3 筆）                   ║
║    └ pending  :  1 筆（4月第 4 筆）                   ║
║  月度營收（confirmed+shipped）:                       ║
║    2025-10: ~NT$ 463,000                             ║
║    2025-11: ~NT$ 646,500                             ║
║    2025-12: ~NT$ 826,900  ← 年末高峰                 ║
║    2026-01: ~NT$ 389,700                             ║
║    2026-02: ~NT$ 580,200                             ║
║    2026-03: ~NT$ 719,600                             ║
║    2026-04: ~NT$ 400,000  （當月進行中）              ║
║  Quotations : 12 筆（近 30 天）                       ║
║    ├ converted: 4（33.3%）                           ║
║    ├ expired  : 3                                    ║
║    └ pending  : 5（sent×3 + draft×2）                ║
║    平均轉換天數 : 7.5 天                              ║
╚══════════════════════════════════════════════════════╝
`);

await sqlClient.end();