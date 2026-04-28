/**
 * Heatmap 空缺補丁 - 補齊 5 家公司前 6 個月的空缺月份訂單
 *
 * 目前空缺（Nov 2025 - Apr 2026 視窗）：
 *   c1 建弘工程: 2025-12, 2026-03
 *   c2 鋒茂科技: 2025-11, 2026-02
 *   c3 聚隆製造: 2026-01, 2026-04
 *   c4 允昇工業: 2026-01
 *
 * 執行前提：需先執行 seed-demo-data.ts
 * 執行: npx tsx scripts/seed-heatmap-patch.ts
 * 冪等性: 偵測到 c1 在 2025-12 已有訂單時自動跳過
 */

import 'dotenv/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq, and, isNull, gte, lt } from 'drizzle-orm';
import * as schema from '../src/schemas/index.js';

const sqlClient = postgres(process.env.DATABASE_URL!);
const db = drizzle(sqlClient, { schema });

const d = (y: number, m: number, day: number) =>
  new Date(`${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}T08:00:00.000Z`);

// ── Step 0: Guard - admin_test ─────────────────────────────
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

// ── Step 1: 查出客戶 IDs ───────────────────────────────────
const allCustomers = await db
  .select({ id: schema.customers.id, name: schema.customers.name })
  .from(schema.customers)
  .where(isNull(schema.customers.deletedAt));

const cMap = new Map(allCustomers.map((c) => [c.name, c.id]));
const c1 = cMap.get('Jianhong Engineering Corp.')!;
const c2 = cMap.get('Fengmao Technology Co., Ltd.')!;
const c3 = cMap.get('Julong Manufacturing Ltd.')!;
const c4 = cMap.get('Yunsheng Industrial Corp.')!;

if (!c1 || !c2 || !c3 || !c4) {
  console.error('❌ 找不到必要客戶，請先執行 seed-demo-data.ts');
  await sqlClient.end();
  process.exit(1);
}

// ── Step 2: 查出產品 IDs ───────────────────────────────────
const allProducts = await db
  .select({ id: schema.products.id, sku: schema.products.sku })
  .from(schema.products)
  .where(isNull(schema.products.deletedAt));

const pMap = new Map(allProducts.map((p) => [p.sku, p.id]));
const p0 = pMap.get('TUBE-A001')!;
const p1 = pMap.get('ANGLE-B002')!;
const p2 = pMap.get('PLATE-C003')!;
const p3 = pMap.get('SPEC-D004')!;
const p4 = pMap.get('PART-E005')!;

if (!p0 || !p1 || !p2 || !p3 || !p4) {
  console.error('❌ 找不到必要產品，請先執行 seed-demo-data.ts');
  await sqlClient.end();
  process.exit(1);
}

// ── Step 3: 冪等性檢查（c1 在 2025-12 是否已有訂單）─────────
const existingCheck = await db
  .select({ id: schema.salesOrders.id })
  .from(schema.salesOrders)
  .where(
    and(
      eq(schema.salesOrders.customerId, c1),
      gte(schema.salesOrders.createdAt, d(2025, 12, 1)),
      lt(schema.salesOrders.createdAt, d(2026, 1, 1)),
      isNull(schema.salesOrders.deletedAt),
    ),
  );

if (existingCheck.length > 0) {
  console.log('⚠️  Heatmap 補丁已存在（c1 在 2025-12 已有訂單），跳過。');
  await sqlClient.end();
  process.exit(0);
}

// ── Step 4: 補丁訂單 ────────────────────────────────────────
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

const patchSpecs: OrderSpec[] = [
  // ── c1 建弘工程: 2025-12（2 筆）──────────────────────────
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,7), confirmedAt: d(2025,12,10), shippedAt: d(2025,12,16), paidAt: d(2025,12,26),
    items: [{ productId: p0, qty: 12, price: 2500 }, { productId: p4, qty: 80, price: 480 }],
    // 30,000 + 38,400 = 68,400
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,18), confirmedAt: d(2025,12,21), shippedAt: d(2025,12,27), paidAt: d(2026,1,10),
    items: [{ productId: p2, qty: 25, price: 1800 }],
    // 45,000
  },

  // ── c2 鋒茂科技: 2025-11（2 筆）──────────────────────────
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,5), confirmedAt: d(2025,11,8), shippedAt: d(2025,11,14), paidAt: d(2025,11,22),
    items: [{ productId: p1, qty: 60, price: 980 }, { productId: p0, qty: 8, price: 2500 }],
    // 58,800 + 20,000 = 78,800
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,25), confirmedAt: d(2025,11,27), shippedAt: d(2025,11,30), paidAt: d(2025,12,8),
    items: [{ productId: p4, qty: 120, price: 480 }],
    // 57,600
  },

  // ── c3 聚隆製造: 2026-01（2 筆）──────────────────────────
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,9), confirmedAt: d(2026,1,12), shippedAt: d(2026,1,18), paidAt: d(2026,1,28),
    items: [{ productId: p2, qty: 45, price: 1800 }, { productId: p4, qty: 60, price: 480 }],
    // 81,000 + 28,800 = 109,800
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,20), confirmedAt: d(2026,1,23), shippedAt: d(2026,1,28), paidAt: d(2026,2,5),
    items: [{ productId: p0, qty: 10, price: 2500 }],
    // 25,000
  },

  // ── c4 允昇工業: 2026-01（1 筆）──────────────────────────
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,11), confirmedAt: d(2026,1,14), shippedAt: d(2026,1,20), paidAt: d(2026,1,30),
    items: [{ productId: p3, qty: 8, price: 5200 }, { productId: p1, qty: 40, price: 980 }],
    // 41,600 + 39,200 = 80,800
  },

  // ── c1 建弘工程: 2026-03（2 筆）──────────────────────────
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,5), confirmedAt: d(2026,3,8), shippedAt: d(2026,3,14), paidAt: d(2026,3,24),
    items: [{ productId: p3, qty: 12, price: 5200 }, { productId: p0, qty: 15, price: 2500 }],
    // 62,400 + 37,500 = 99,900
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,19), confirmedAt: d(2026,3,22), shippedAt: d(2026,3,27), paidAt: d(2026,4,5),
    items: [{ productId: p4, qty: 150, price: 480 }],
    // 72,000
  },

  // ── c2 鋒茂科技: 2026-02（2 筆）──────────────────────────
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,6), confirmedAt: d(2026,2,9), shippedAt: d(2026,2,15), paidAt: d(2026,2,25),
    items: [{ productId: p0, qty: 20, price: 2500 }, { productId: p1, qty: 30, price: 980 }],
    // 50,000 + 29,400 = 79,400
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,20), confirmedAt: d(2026,2,23), shippedAt: d(2026,2,27), paidAt: d(2026,3,8),
    items: [{ productId: p2, qty: 30, price: 1800 }],
    // 54,000
  },

  // ── c3 聚隆製造: 2026-04（2 筆）──────────────────────────
  {
    customerId: c3, status: 'confirmed', paymentStatus: 'unpaid',
    createdAt: d(2026,4,7), confirmedAt: d(2026,4,10),
    items: [{ productId: p2, qty: 35, price: 1800 }, { productId: p1, qty: 20, price: 980 }],
    // 63,000 + 19,600 = 82,600
  },
  {
    customerId: c3, status: 'pending', paymentStatus: 'unpaid',
    createdAt: d(2026,4,22),
    items: [{ productId: p3, qty: 5, price: 5200 }],
    // 26,000
  },
];

let inserted = 0;
for (const spec of patchSpecs) {
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
  inserted++;
}

console.log(`✅ Heatmap 補丁完成：新增 ${inserted} 筆訂單`);
console.log(`
  c1 建弘工程: 2025-12 (+2筆), 2026-03 (+2筆)
  c2 鋒茂科技: 2025-11 (+2筆), 2026-02 (+2筆)
  c3 聚隆製造: 2026-01 (+2筆), 2026-04 (+2筆)
  c4 允昇工業: 2026-01 (+1筆)

  Heatmap 6個月視窗（2025-11 ～ 2026-04）每家公司每月均有訂單 ✓
`);

await sqlClient.end();
