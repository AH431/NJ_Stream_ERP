/**
 * Production English Dataset Seed
 *
 * Clears all non-user tables, then seeds:
 *   - 20 IoT / electronics products (USD pricing)
 *   - 12 B2B customers
 *   - Inventory for all 20 products (2 low-stock items for anomaly demo)
 *   - 45 sales orders across 6 months (Nov 2025 – Apr 2026)
 *   - 12 quotations (recent 30 days, ~33 % conversion rate)
 *   - Duplicate-pending anomaly pair for UI demo
 *
 * Prerequisites: seed-test-user.ts must have run first (requires admin_test account).
 * Run: npx tsx scripts/seed-production-en.ts
 */

/// <reference types="node" />

import 'dotenv/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq, and, isNull, sql } from 'drizzle-orm';
import * as schema from '../src/schemas/index.js';
import { runAnomalyScanner } from '../src/services/anomaly_scanner.service.js';

const sqlClient = postgres(process.env.DATABASE_URL!);
const db = drizzle(sqlClient, { schema });

// ── Helpers ────────────────────────────────────────────────
const d = (y: number, m: number, day: number) =>
  new Date(`${y}-${String(m).padStart(2, '0')}-${String(day).padStart(2, '0')}T08:00:00.000Z`);
const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000);

// ── Step 0: Verify admin_test exists ──────────────────────
const [adminUser] = await db
  .select({ id: schema.users.id })
  .from(schema.users)
  .where(and(eq(schema.users.username, 'admin_test'), isNull(schema.users.deletedAt)));

if (!adminUser) {
  console.error('❌ admin_test not found. Run seed-test-user.ts first.');
  await sqlClient.end();
  process.exit(1);
}
const adminId = adminUser.id;
console.log(`✅ admin_test found (id=${adminId})`);

// ── Step 1: Clear existing data ────────────────────────────
console.log('🗑️  Clearing existing data...');
await db.execute(sql`UPDATE quotations SET converted_to_order_id = NULL`);
await db.execute(sql`UPDATE sales_orders SET quotation_id = NULL`);
await db.execute(sql`
  TRUNCATE TABLE
    audit_logs, anomalies, customer_interactions, processed_operations,
    device_tokens, order_items, quotations, sales_orders,
    inventory_items, products, customers
  RESTART IDENTITY CASCADE
`);
console.log('✅ All tables cleared');

// ── Step 2: Products (20 IoT / electronics items, USD) ────
const insertedProducts = await db.insert(schema.products).values([
  // ── Microcontrollers & SoCs
  { name: 'STM32F103C8T6 Microcontroller',         sku: 'MCU-STM32F103C8',    unitPrice: '4.50',  costPrice: '2.60', minStockLevel: 200 },
  { name: 'ESP32-WROOM-32U WiFi+BT Module',         sku: 'MCU-ESP32-WROOM32U', unitPrice: '5.80',  costPrice: '3.40', minStockLevel: 100 },
  { name: 'nRF52840 BLE 5.0 SoC Module',            sku: 'COMM-NRF52840-MOD',  unitPrice: '9.50',  costPrice: '5.60', minStockLevel: 80  },
  // ── Sensors
  { name: 'BME280 Environmental Sensor (T/H/P)',    sku: 'SENS-BME280-3IN1',   unitPrice: '3.20',  costPrice: '1.90', minStockLevel: 150 },
  { name: 'MPU-6050 6-Axis IMU Sensor',             sku: 'SENS-MPU6050-6AX',   unitPrice: '1.80',  costPrice: '1.05', minStockLevel: 200 },
  // ── Power & Battery
  { name: 'LiPo Battery 3.7V 1800mAh',             sku: 'BATT-LIPO-3V7-1800', unitPrice: '5.20',  costPrice: '3.10', minStockLevel: 80  },
  { name: 'AMS1117-3.3V LDO Regulator SOT-223',    sku: 'PMIC-LDO-AMS1117-33',unitPrice: '0.35',  costPrice: '0.18', minStockLevel: 1000},
  { name: 'LM2596S Buck DC-DC Converter 3A',       sku: 'PMIC-BUCK-LM2596S',  unitPrice: '0.65',  costPrice: '0.38', minStockLevel: 500 },
  // ── Connectors
  { name: 'USB Type-C 16P SMD Receptacle',         sku: 'CONN-USBC-16P-SMD',  unitPrice: '0.48',  costPrice: '0.27', minStockLevel: 1000},
  { name: 'JST-PH 2P 2.0mm Connector Pair',        sku: 'CONN-JST-PH2-2P',    unitPrice: '0.22',  costPrice: '0.12', minStockLevel: 2000},
  // ── Displays
  { name: 'OLED Display 0.96" 128x64 I2C',         sku: 'DISP-OLED-096-I2C',  unitPrice: '3.50',  costPrice: '2.10', minStockLevel: 120 },
  { name: 'TFT LCD 2.4" 240x320 ILI9341 SPI',     sku: 'DISP-TFT-24-ILI9341',unitPrice: '7.80',  costPrice: '4.60', minStockLevel: 60  },
  // ── Passives (reel units)
  { name: 'SMD Resistor 0402 1kΩ ±1% (Reel/5K)',  sku: 'PASS-RES-0402-1K5K',  unitPrice: '3.80',  costPrice: '2.10', minStockLevel: 50  },
  { name: 'MLCC Cap 0402 100nF 10V X7R (Reel/4K)',sku: 'PASS-CAP-0402-100N4K', unitPrice: '4.50',  costPrice: '2.60', minStockLevel: 50  },
  { name: 'WS2812B RGB LED SMD 5050 (Reel/100)',   sku: 'LED-WS2812B-5050R100', unitPrice: '8.50',  costPrice: '5.00', minStockLevel: 30  },
  // ── Other Components
  { name: '5V SPDT Signal Relay SRD-05VDC',        sku: 'RLAY-SRD-05VDC-SPDT', unitPrice: '0.75',  costPrice: '0.42', minStockLevel: 300 },
  { name: '40mm DC Brushless Fan 12V',             sku: 'FAN-40X10-12V-DC',    unitPrice: '3.80',  costPrice: '2.20', minStockLevel: 60  },
  { name: 'ABS Enclosure 200x120x75mm IP54',       sku: 'ENCL-ABS-200X120-IP54',unitPrice: '6.50', costPrice: '3.80', minStockLevel: 40  },
  { name: 'FR-4 PCB 100x100mm 2-Layer',            sku: 'PCB-FR4-2L-100X100',  unitPrice: '2.20',  costPrice: '1.30', minStockLevel: 100 },
  { name: '2.54mm 40P Breakaway Pin Header',       sku: 'CONN-HDR-254-40P',    unitPrice: '0.45',  costPrice: '0.25', minStockLevel: 500 },
]).returning({ id: schema.products.id });

const [p0,p1,p2,p3,p4,p5,p6,p7,p8,p9,p10,p11,p12,p13,p14,p15,p16,p17,p18,p19] =
  insertedProducts.map(r => r.id);
console.log(`✅ Products (20): ${insertedProducts.map(r => r.id).join(', ')}`);

// ── Step 3: Customers (12 B2B companies) ──────────────────
const insertedCustomers = await db.insert(schema.customers).values([
  { name: 'TechNova Devices Inc.',        contact: 'Sarah Chen',    email: 's.chen@technova-devices.com',   taxId: '27-8001001', paymentTermsDays: 30 },
  { name: 'Luminary IoT Systems LLC',     contact: 'Mike Johnson',  email: 'm.johnson@luminaryiot.com',     taxId: '27-8001002', paymentTermsDays: 45 },
  { name: 'PinPoint Electronics Corp.',   contact: 'Amy Park',      email: 'a.park@pinpointelectronics.com',taxId: '27-8001003', paymentTermsDays: 30 },
  { name: 'Horizon Wearables Ltd.',       contact: 'David Liu',     email: 'd.liu@horizonwearables.com',    taxId: '27-8001004', paymentTermsDays: 60 },
  { name: 'Nexus PCB Assembly Co.',       contact: 'Rachel Wang',   email: 'r.wang@nexuspcba.com',          taxId: '27-8001005', paymentTermsDays: 30 },
  { name: 'SkyEdge Robotics Inc.',        contact: 'Tom Bradley',   email: 't.bradley@skyedgerobotics.com', taxId: '27-8001006', paymentTermsDays: 45 },
  { name: 'Greenfield Smart Home Co.',    contact: 'Jessica Tan',   email: 'j.tan@greenfieldsh.com',        taxId: '27-8001007', paymentTermsDays: 30 },
  { name: 'Meridian Test Equipment Ltd.', contact: "Kevin O'Brien", email: 'k.obrien@meridiantest.com',     taxId: '27-8001008', paymentTermsDays: 60 },
  { name: 'CoreSync Industrial LLC',      contact: 'Priya Sharma',  email: 'p.sharma@coresync-ind.com',     taxId: '27-8001009', paymentTermsDays: 30 },
  { name: 'BlueWave Medical Devices',     contact: 'Frank Mueller', email: 'f.mueller@bluewavemd.com',      taxId: '27-8001010', paymentTermsDays: 45 },
  { name: 'Apex Automation Systems',      contact: 'Linda Chang',   email: 'l.chang@apexautomation.com',    taxId: '27-8001011', paymentTermsDays: 30 },
  { name: 'Trident Marine Electronics',   contact: 'Chris Nguyen',  email: 'c.nguyen@tridentmarine.com',    taxId: '27-8001012', paymentTermsDays: 60 },
]).returning({ id: schema.customers.id });

const [c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11] =
  insertedCustomers.map(r => r.id);
console.log(`✅ Customers (12): ${insertedCustomers.map(r => r.id).join(', ')}`);

// ── Step 4: Inventory ──────────────────────────────────────
// p2 (nRF52840): available=50 < min=80  → STOCK_SAFETY anomaly
// p5 (LiPo):     available=34 < min=80  → STOCK_CRITICAL anomaly
await db.insert(schema.inventoryItems).values([
  { productId: p0,  warehouseId: 1, quantityOnHand: 280,   quantityReserved: 30,   minStockLevel: 200,  alertStockLevel: 100, criticalStockLevel: 60  },
  { productId: p1,  warehouseId: 1, quantityOnHand: 620,   quantityReserved: 80,   minStockLevel: 100,  alertStockLevel: 50,  criticalStockLevel: 30  },
  { productId: p2,  warehouseId: 1, quantityOnHand: 65,    quantityReserved: 15,   minStockLevel: 80,   alertStockLevel: 40,  criticalStockLevel: 24  }, // ⚠️ LOW
  { productId: p3,  warehouseId: 1, quantityOnHand: 220,   quantityReserved: 40,   minStockLevel: 150,  alertStockLevel: 75,  criticalStockLevel: 45  },
  { productId: p4,  warehouseId: 1, quantityOnHand: 480,   quantityReserved: 80,   minStockLevel: 200,  alertStockLevel: 100, criticalStockLevel: 60  },
  { productId: p5,  warehouseId: 1, quantityOnHand: 42,    quantityReserved: 8,    minStockLevel: 80,   alertStockLevel: 40,  criticalStockLevel: 24  }, // 🚨 CRITICAL
  { productId: p6,  warehouseId: 1, quantityOnHand: 6500,  quantityReserved: 1000, minStockLevel: 1000, alertStockLevel: 500, criticalStockLevel: 300 },
  { productId: p7,  warehouseId: 1, quantityOnHand: 2800,  quantityReserved: 400,  minStockLevel: 500,  alertStockLevel: 250, criticalStockLevel: 150 },
  { productId: p8,  warehouseId: 1, quantityOnHand: 3200,  quantityReserved: 500,  minStockLevel: 1000, alertStockLevel: 500, criticalStockLevel: 300 },
  { productId: p9,  warehouseId: 1, quantityOnHand: 8500,  quantityReserved: 1200, minStockLevel: 2000, alertStockLevel: 1000,criticalStockLevel: 600 },
  { productId: p10, warehouseId: 1, quantityOnHand: 380,   quantityReserved: 60,   minStockLevel: 120,  alertStockLevel: 60,  criticalStockLevel: 36  },
  { productId: p11, warehouseId: 1, quantityOnHand: 180,   quantityReserved: 30,   minStockLevel: 60,   alertStockLevel: 30,  criticalStockLevel: 18  },
  { productId: p12, warehouseId: 1, quantityOnHand: 120,   quantityReserved: 20,   minStockLevel: 50,   alertStockLevel: 25,  criticalStockLevel: 15  },
  { productId: p13, warehouseId: 1, quantityOnHand: 85,    quantityReserved: 15,   minStockLevel: 50,   alertStockLevel: 25,  criticalStockLevel: 15  },
  { productId: p14, warehouseId: 1, quantityOnHand: 95,    quantityReserved: 15,   minStockLevel: 30,   alertStockLevel: 15,  criticalStockLevel: 9   },
  { productId: p15, warehouseId: 1, quantityOnHand: 850,   quantityReserved: 150,  minStockLevel: 300,  alertStockLevel: 150, criticalStockLevel: 90  },
  { productId: p16, warehouseId: 1, quantityOnHand: 180,   quantityReserved: 30,   minStockLevel: 60,   alertStockLevel: 30,  criticalStockLevel: 18  },
  { productId: p17, warehouseId: 1, quantityOnHand: 120,   quantityReserved: 20,   minStockLevel: 40,   alertStockLevel: 20,  criticalStockLevel: 12  },
  { productId: p18, warehouseId: 1, quantityOnHand: 350,   quantityReserved: 50,   minStockLevel: 100,  alertStockLevel: 50,  criticalStockLevel: 30  },
  { productId: p19, warehouseId: 1, quantityOnHand: 1200,  quantityReserved: 200,  minStockLevel: 500,  alertStockLevel: 250, criticalStockLevel: 150 },
]);
console.log('✅ Inventory (20 items, 2 low-stock: p2 nRF52840, p5 LiPo)');

// ── Step 5: Sales Orders 6 months ─────────────────────────
type OItem = { productId: number; qty: number; price: number };
type OSpec = {
  customerId: number;
  status: 'shipped' | 'confirmed' | 'pending';
  paymentStatus: 'paid' | 'unpaid';
  createdAt: Date;
  confirmedAt?: Date;
  shippedAt?: Date;
  paidAt?: Date;
  items: OItem[];
};

const orderSpecs: OSpec[] = [
  // ════ Nov 2025 — target ~$25,285 ════════════════════════
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,5), confirmedAt: d(2025,11,7), shippedAt: d(2025,11,12), paidAt: d(2025,11,20),
    items: [{ productId: p1, qty: 500, price: 5.80 }, { productId: p3, qty: 300, price: 3.20 }, { productId: p8, qty: 2000, price: 0.48 }],
    // $2900 + $960 + $960 = $4,820
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,8), confirmedAt: d(2025,11,10), shippedAt: d(2025,11,15), paidAt: d(2025,11,25),
    items: [{ productId: p0, qty: 800, price: 4.50 }, { productId: p18, qty: 400, price: 2.20 }, { productId: p19, qty: 1000, price: 0.45 }],
    // $3600 + $880 + $450 = $4,930
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,12), confirmedAt: d(2025,11,14), shippedAt: d(2025,11,19), paidAt: d(2025,11,28),
    items: [{ productId: p2, qty: 200, price: 9.50 }, { productId: p10, qty: 300, price: 3.50 }, { productId: p5, qty: 150, price: 5.20 }],
    // $1900 + $1050 + $780 = $3,730
  },
  {
    customerId: c6, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,16), confirmedAt: d(2025,11,18), shippedAt: d(2025,11,23), paidAt: d(2025,12,2),
    items: [{ productId: p1, qty: 400, price: 5.80 }, { productId: p3, qty: 400, price: 3.20 }, { productId: p15, qty: 800, price: 0.75 }],
    // $2320 + $1280 + $600 = $4,200
  },
  {
    customerId: c8, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,20), confirmedAt: d(2025,11,22), shippedAt: d(2025,11,27), paidAt: d(2025,12,5),
    items: [{ productId: p11, qty: 200, price: 7.80 }, { productId: p17, qty: 150, price: 6.50 }, { productId: p16, qty: 200, price: 3.80 }],
    // $1560 + $975 + $760 = $3,295
  },
  {
    customerId: c10, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,24), confirmedAt: d(2025,11,26), shippedAt: d(2025,11,29), paidAt: d(2025,12,8),
    items: [{ productId: p7, qty: 1000, price: 0.65 }, { productId: p6, qty: 3000, price: 0.35 }, { productId: p12, qty: 50, price: 3.80 }, { productId: p13, qty: 40, price: 4.50 }],
    // $650 + $1050 + $190 + $180 = $2,070
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,11,28), confirmedAt: d(2025,11,29), shippedAt: d(2025,12,3), paidAt: d(2025,12,12),
    items: [{ productId: p4, qty: 500, price: 1.80 }, { productId: p9, qty: 3000, price: 0.22 }, { productId: p14, qty: 80, price: 8.50 }],
    // $900 + $660 + $680 = $2,240
  },
  // Nov total: $25,285

  // ════ Dec 2025 — target ~$42,729 ════════════════════════
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,2), confirmedAt: d(2025,12,4), shippedAt: d(2025,12,10), paidAt: d(2025,12,22),
    items: [{ productId: p2, qty: 300, price: 9.50 }, { productId: p5, qty: 200, price: 5.20 }, { productId: p10, qty: 500, price: 3.50 }],
    // $2850 + $1040 + $1750 = $5,640
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,5), confirmedAt: d(2025,12,7), shippedAt: d(2025,12,12), paidAt: d(2025,12,25),
    items: [{ productId: p0, qty: 1000, price: 4.50 }, { productId: p8, qty: 3000, price: 0.48 }],
    // $4500 + $1440 = $5,940
  },
  {
    customerId: c5, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,8), confirmedAt: d(2025,12,10), shippedAt: d(2025,12,15), paidAt: d(2025,12,28),
    items: [{ productId: p11, qty: 300, price: 7.80 }, { productId: p16, qty: 200, price: 3.80 }, { productId: p17, qty: 100, price: 6.50 }],
    // $2340 + $760 + $650 = $3,750
  },
  {
    customerId: c9, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,11), confirmedAt: d(2025,12,13), shippedAt: d(2025,12,18), paidAt: d(2026,1,3),
    items: [{ productId: p2, qty: 250, price: 9.50 }, { productId: p3, qty: 500, price: 3.20 }, { productId: p4, qty: 800, price: 1.80 }],
    // $2375 + $1600 + $1440 = $5,415
  },
  {
    customerId: c7, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,14), confirmedAt: d(2025,12,16), shippedAt: d(2025,12,20), paidAt: d(2026,1,5),
    items: [{ productId: p0, qty: 600, price: 4.50 }, { productId: p18, qty: 500, price: 2.20 }, { productId: p19, qty: 2000, price: 0.45 }],
    // $2700 + $1100 + $900 = $4,700
  },
  {
    customerId: c11, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,17), confirmedAt: d(2025,12,19), shippedAt: d(2025,12,23), paidAt: d(2026,1,8),
    items: [{ productId: p1, qty: 600, price: 5.80 }, { productId: p7, qty: 2000, price: 0.65 }, { productId: p15, qty: 1000, price: 0.75 }],
    // $3480 + $1300 + $750 = $5,530
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,19), confirmedAt: d(2025,12,21), shippedAt: d(2025,12,24), paidAt: d(2026,1,6),
    items: [{ productId: p12, qty: 80, price: 3.80 }, { productId: p13, qty: 80, price: 4.50 }, { productId: p6, qty: 5000, price: 0.35 }],
    // $304 + $360 + $1750 = $2,414
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,22), confirmedAt: d(2025,12,24), shippedAt: d(2025,12,27), paidAt: d(2026,1,10),
    items: [{ productId: p11, qty: 200, price: 7.80 }, { productId: p17, qty: 150, price: 6.50 }],
    // $1560 + $975 = $2,535
  },
  {
    customerId: c10, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,26), confirmedAt: d(2025,12,27), shippedAt: d(2025,12,30), paidAt: d(2026,1,12),
    items: [{ productId: p14, qty: 150, price: 8.50 }, { productId: p16, qty: 150, price: 3.80 }],
    // $1275 + $570 = $1,845
  },
  {
    customerId: c6, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2025,12,28), confirmedAt: d(2025,12,29), shippedAt: d(2026,1,2), paidAt: d(2026,1,15),
    items: [{ productId: p1, qty: 500, price: 5.80 }, { productId: p8, qty: 2000, price: 0.48 }, { productId: p9, qty: 5000, price: 0.22 }],
    // $2900 + $960 + $1100 = $4,960
  },
  // Dec total: $42,729

  // ════ Jan 2026 — target ~$18,555 ════════════════════════
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,6), confirmedAt: d(2026,1,8), shippedAt: d(2026,1,13), paidAt: d(2026,1,25),
    items: [{ productId: p1, qty: 300, price: 5.80 }, { productId: p3, qty: 200, price: 3.20 }, { productId: p10, qty: 200, price: 3.50 }],
    // $1740 + $640 + $700 = $3,080
  },
  {
    customerId: c5, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,10), confirmedAt: d(2026,1,12), shippedAt: d(2026,1,17), paidAt: d(2026,1,28),
    items: [{ productId: p0, qty: 500, price: 4.50 }, { productId: p4, qty: 1000, price: 1.80 }],
    // $2250 + $1800 = $4,050
  },
  {
    customerId: c8, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,15), confirmedAt: d(2026,1,17), shippedAt: d(2026,1,22), paidAt: d(2026,2,3),
    items: [{ productId: p7, qty: 2000, price: 0.65 }, { productId: p6, qty: 5000, price: 0.35 }, { productId: p15, qty: 800, price: 0.75 }],
    // $1300 + $1750 + $600 = $3,650
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,20), confirmedAt: d(2026,1,22), shippedAt: d(2026,1,27), paidAt: d(2026,2,6),
    items: [{ productId: p5, qty: 150, price: 5.20 }, { productId: p2, qty: 100, price: 9.50 }, { productId: p11, qty: 100, price: 7.80 }],
    // $780 + $950 + $780 = $2,510
  },
  {
    customerId: c11, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,25), confirmedAt: d(2026,1,27), shippedAt: d(2026,1,30), paidAt: d(2026,2,10),
    items: [{ productId: p17, qty: 200, price: 6.50 }, { productId: p16, qty: 200, price: 3.80 }, { productId: p18, qty: 400, price: 2.20 }],
    // $1300 + $760 + $880 = $2,940
  },
  {
    customerId: c9, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,1,28), confirmedAt: d(2026,1,29), shippedAt: d(2026,2,1), paidAt: d(2026,2,12),
    items: [{ productId: p2, qty: 150, price: 9.50 }, { productId: p4, qty: 500, price: 1.80 }],
    // $1425 + $900 = $2,325
  },
  // Jan total: $18,555

  // ════ Feb 2026 — target ~$28,353 ════════════════════════
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,3), confirmedAt: d(2026,2,5), shippedAt: d(2026,2,10), paidAt: d(2026,2,22),
    items: [{ productId: p1, qty: 600, price: 5.80 }, { productId: p8, qty: 3000, price: 0.48 }, { productId: p9, qty: 5000, price: 0.22 }],
    // $3480 + $1440 + $1100 = $6,020
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,8), confirmedAt: d(2026,2,10), shippedAt: d(2026,2,15), paidAt: d(2026,2,26),
    items: [{ productId: p0, qty: 700, price: 4.50 }, { productId: p18, qty: 500, price: 2.20 }],
    // $3150 + $1100 = $4,250
  },
  {
    customerId: c7, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,12), confirmedAt: d(2026,2,14), shippedAt: d(2026,2,19), paidAt: d(2026,3,3),
    items: [{ productId: p11, qty: 250, price: 7.80 }, { productId: p17, qty: 120, price: 6.50 }],
    // $1950 + $780 = $2,730
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,16), confirmedAt: d(2026,2,18), shippedAt: d(2026,2,23), paidAt: d(2026,3,5),
    items: [{ productId: p2, qty: 200, price: 9.50 }, { productId: p10, qty: 300, price: 3.50 }, { productId: p14, qty: 100, price: 8.50 }],
    // $1900 + $1050 + $850 = $3,800
  },
  {
    customerId: c6, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,20), confirmedAt: d(2026,2,22), shippedAt: d(2026,2,26), paidAt: d(2026,3,8),
    items: [{ productId: p3, qty: 600, price: 3.20 }, { productId: p1, qty: 350, price: 5.80 }, { productId: p15, qty: 600, price: 0.75 }],
    // $1920 + $2030 + $450 = $4,400
  },
  {
    customerId: c10, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,25), confirmedAt: d(2026,2,26), shippedAt: d(2026,2,28), paidAt: d(2026,3,10),
    items: [{ productId: p12, qty: 60, price: 3.80 }, { productId: p13, qty: 60, price: 4.50 }, { productId: p6, qty: 5000, price: 0.35 }, { productId: p7, qty: 1500, price: 0.65 }],
    // $228 + $270 + $1750 + $975 = $3,223
  },
  {
    customerId: c5, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,2,27), confirmedAt: d(2026,2,28), shippedAt: d(2026,3,3), paidAt: d(2026,3,14),
    items: [{ productId: p11, qty: 200, price: 7.80 }, { productId: p16, qty: 150, price: 3.80 }, { productId: p0, qty: 400, price: 4.50 }],
    // $1560 + $570 + $1800 = $3,930
  },
  // Feb total: $28,353

  // ════ Mar 2026 — target ~$36,789 ════════════════════════
  {
    customerId: c9, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,3), confirmedAt: d(2026,3,5), shippedAt: d(2026,3,10), paidAt: d(2026,3,22),
    items: [{ productId: p2, qty: 300, price: 9.50 }, { productId: p3, qty: 500, price: 3.20 }, { productId: p4, qty: 500, price: 1.80 }],
    // $2850 + $1600 + $900 = $5,350
  },
  {
    customerId: c3, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,7), confirmedAt: d(2026,3,9), shippedAt: d(2026,3,14), paidAt: d(2026,3,26),
    items: [{ productId: p5, qty: 250, price: 5.20 }, { productId: p10, qty: 400, price: 3.50 }, { productId: p11, qty: 200, price: 7.80 }],
    // $1300 + $1400 + $1560 = $4,260
  },
  {
    customerId: c1, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,10), confirmedAt: d(2026,3,12), shippedAt: d(2026,3,17), paidAt: d(2026,3,28),
    items: [{ productId: p1, qty: 700, price: 5.80 }, { productId: p8, qty: 4000, price: 0.48 }],
    // $4060 + $1920 = $5,980
  },
  {
    customerId: c11, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,14), confirmedAt: d(2026,3,16), shippedAt: d(2026,3,21), paidAt: d(2026,4,2),
    items: [{ productId: p17, qty: 200, price: 6.50 }, { productId: p16, qty: 300, price: 3.80 }, { productId: p15, qty: 1000, price: 0.75 }],
    // $1300 + $1140 + $750 = $3,190
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,18), confirmedAt: d(2026,3,20), shippedAt: d(2026,3,25), paidAt: d(2026,4,5),
    items: [{ productId: p0, qty: 1200, price: 4.50 }, { productId: p7, qty: 2000, price: 0.65 }],
    // $5400 + $1300 = $6,700
  },
  {
    customerId: c8, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,22), confirmedAt: d(2026,3,24), shippedAt: d(2026,3,28), paidAt: d(2026,4,8),
    items: [{ productId: p6, qty: 5000, price: 0.35 }, { productId: p12, qty: 80, price: 3.80 }, { productId: p13, qty: 80, price: 4.50 }, { productId: p19, qty: 2000, price: 0.45 }],
    // $1750 + $304 + $360 + $900 = $3,314
  },
  {
    customerId: c2, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,27), confirmedAt: d(2026,3,29), shippedAt: d(2026,4,1), paidAt: d(2026,4,12),
    items: [{ productId: p18, qty: 600, price: 2.20 }, { productId: p2, qty: 150, price: 9.50 }, { productId: p4, qty: 1000, price: 1.80 }],
    // $1320 + $1425 + $1800 = $4,545
  },
  {
    customerId: c4, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,3,30), confirmedAt: d(2026,4,1), shippedAt: d(2026,4,4), paidAt: d(2026,4,15),
    items: [{ productId: p14, qty: 200, price: 8.50 }, { productId: p10, qty: 500, price: 3.50 }],
    // $1700 + $1750 = $3,450
  },
  // Mar total: $36,789

  // ════ Apr 2026 — 5 shipped + 1 confirmed + 1 pending ════
  {
    customerId: c6, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,3), confirmedAt: d(2026,4,5), shippedAt: d(2026,4,10), paidAt: d(2026,4,20),
    items: [{ productId: p1, qty: 500, price: 5.80 }, { productId: p3, qty: 400, price: 3.20 }, { productId: p9, qty: 5000, price: 0.22 }],
    // $2900 + $1280 + $1100 = $5,280  ← soApr1
  },
  {
    customerId: c7, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,7), confirmedAt: d(2026,4,9), shippedAt: d(2026,4,14), paidAt: d(2026,4,24),
    items: [{ productId: p0, qty: 800, price: 4.50 }, { productId: p18, qty: 500, price: 2.20 }],
    // $3600 + $1100 = $4,700  ← soApr2
  },
  {
    customerId: c5, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,11), confirmedAt: d(2026,4,13), shippedAt: d(2026,4,18), paidAt: d(2026,4,26),
    items: [{ productId: p2, qty: 200, price: 9.50 }, { productId: p5, qty: 150, price: 5.20 }, { productId: p11, qty: 150, price: 7.80 }],
    // $1900 + $780 + $1170 = $3,850  ← soApr3
  },
  {
    customerId: c10, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,15), confirmedAt: d(2026,4,17), shippedAt: d(2026,4,22), paidAt: d(2026,4,28),
    items: [{ productId: p7, qty: 2000, price: 0.65 }, { productId: p6, qty: 5000, price: 0.35 }, { productId: p15, qty: 800, price: 0.75 }],
    // $1300 + $1750 + $600 = $3,650  ← soApr4
  },
  {
    customerId: c0, status: 'shipped', paymentStatus: 'paid',
    createdAt: d(2026,4,20), confirmedAt: d(2026,4,22), shippedAt: d(2026,4,27), paidAt: d(2026,5,2),
    items: [{ productId: p1, qty: 600, price: 5.80 }, { productId: p8, qty: 3000, price: 0.48 }],
    // $3480 + $1440 = $4,920  ← soApr5
  },
  {
    customerId: c3, status: 'confirmed', paymentStatus: 'unpaid',
    createdAt: d(2026,4,24), confirmedAt: d(2026,4,25),
    items: [{ productId: p2, qty: 250, price: 9.50 }, { productId: p10, qty: 400, price: 3.50 }],
    // $2375 + $1400 = $3,775  ← soApr6 (confirmed)
  },
  {
    customerId: c9, status: 'pending', paymentStatus: 'unpaid',
    createdAt: d(2026,4,27),
    items: [{ productId: p4, qty: 800, price: 1.80 }, { productId: p3, qty: 300, price: 3.20 }],
    // $1440 + $960 = $2,400  ← soApr7 (pending)
  },
  // Apr shipped+paid: $22,400 | total: $28,575
];

// Insert orders and collect IDs
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
    spec.items.map(item => ({
      salesOrderId: so.id,
      productId:    item.productId,
      quantity:     item.qty,
      unitPrice:    item.price.toFixed(2),
      subtotal:     (item.qty * item.price).toFixed(2),
    })),
  );
  soIds.push(so.id);
}

// Apr order indices: 38=soApr1, 39=soApr2, 40=soApr3, 41=soApr4, 42=soApr5, 43=soApr6, 44=soApr7
const soApr1 = soIds[38];
const soApr2 = soIds[39];
const soApr3 = soIds[40];
const soApr4 = soIds[41];
const soApr5 = soIds[42];

console.log(`✅ Sales orders (${orderSpecs.length}) + order items inserted`);
console.log(`   Apr IDs: Apr1=${soApr1} Apr2=${soApr2} Apr3=${soApr3} Apr4=${soApr4} Apr5=${soApr5}`);

// ── Step 6: Quotations (12, recent 30 days) ───────────────
// 5 converted + 3 expired + 2 sent + 2 draft → conversion 41.7%
await db.insert(schema.quotations).values([
  // Converted (5) → linked to Apr shipped orders
  {
    customerId: c6, createdBy: adminId,
    totalAmount: '5544.00', taxAmount: '264.00',
    status: 'converted', convertedToOrderId: soApr1,
    createdAt: d(2026,3,28), updatedAt: d(2026,4,3),  // 6 days
  },
  {
    customerId: c7, createdBy: adminId,
    totalAmount: '4935.00', taxAmount: '235.00',
    status: 'converted', convertedToOrderId: soApr2,
    createdAt: d(2026,3,31), updatedAt: d(2026,4,7),  // 7 days
  },
  {
    customerId: c5, createdBy: adminId,
    totalAmount: '4042.50', taxAmount: '192.50',
    status: 'converted', convertedToOrderId: soApr3,
    createdAt: d(2026,4,4), updatedAt: d(2026,4,11),  // 7 days
  },
  {
    customerId: c10, createdBy: adminId,
    totalAmount: '3832.50', taxAmount: '182.50',
    status: 'converted', convertedToOrderId: soApr4,
    createdAt: d(2026,4,9), updatedAt: d(2026,4,15),  // 6 days
  },
  {
    customerId: c0, createdBy: adminId,
    totalAmount: '5166.00', taxAmount: '246.00',
    status: 'converted', convertedToOrderId: soApr5,
    createdAt: d(2026,4,15), updatedAt: d(2026,4,20), // 5 days
  },
  // Expired (3)
  {
    customerId: c1, createdBy: adminId,
    totalAmount: '8200.00', taxAmount: '390.48',
    status: 'expired',
    createdAt: d(2026,4,1), updatedAt: d(2026,4,15),
  },
  {
    customerId: c4, createdBy: adminId,
    totalAmount: '12500.00', taxAmount: '595.24',
    status: 'expired',
    createdAt: d(2026,4,5), updatedAt: d(2026,4,19),
  },
  {
    customerId: c11, createdBy: adminId,
    totalAmount: '6800.00', taxAmount: '323.81',
    status: 'expired',
    createdAt: d(2026,4,9), updatedAt: d(2026,4,23),
  },
  // Sent (2) — awaiting customer response
  {
    customerId: c2, createdBy: adminId,
    totalAmount: '9800.00', taxAmount: '466.67',
    status: 'sent',
    createdAt: d(2026,4,14), updatedAt: d(2026,4,15),
  },
  {
    customerId: c8, createdBy: adminId,
    totalAmount: '7200.00', taxAmount: '342.86',
    status: 'sent',
    createdAt: d(2026,4,18), updatedAt: d(2026,4,19),
  },
  // Draft (2)
  {
    customerId: c9, createdBy: adminId,
    totalAmount: '11200.00', taxAmount: '533.33',
    status: 'draft',
    createdAt: d(2026,4,22), updatedAt: d(2026,4,22),
  },
  {
    customerId: c3, createdBy: adminId,
    totalAmount: '8500.00', taxAmount: '404.76',
    status: 'draft',
    createdAt: d(2026,4,26), updatedAt: d(2026,4,26),
  },
]);
console.log('✅ Quotations (12) inserted — 5 converted, 3 expired, 2 sent, 2 draft');

// ── Step 7: Duplicate-pending order pair (DUPLICATE_ORDER anomaly) ──
// Same customer (c0 TechNova), same items (p1×50 + p3×30), 2 pending orders within 48h
type DuplicatePairRow = { first_order_id: number; second_order_id: number };
const fingerprint = `${p1}:50,${p3}:30`;

const existing = await db.execute(sql`
  WITH candidate_orders AS (
    SELECT
      so.id AS order_id,
      so.created_at,
      STRING_AGG(
        oi.product_id::text || ':' || oi.quantity::text,
        ',' ORDER BY oi.product_id, oi.quantity, oi.id
      ) AS fingerprint
    FROM sales_orders so
    JOIN order_items oi ON oi.sales_order_id = so.id
    WHERE so.customer_id = ${c0}
      AND so.status = 'pending'
      AND so.deleted_at IS NULL
    GROUP BY so.id, so.created_at
  )
  SELECT older.order_id AS first_order_id, newer.order_id AS second_order_id
  FROM candidate_orders older
  JOIN candidate_orders newer
    ON newer.fingerprint = older.fingerprint
   AND newer.created_at > older.created_at
   AND newer.created_at <= older.created_at + INTERVAL '48 hours'
  WHERE older.fingerprint = ${fingerprint}
  LIMIT 1
`);

if ((existing as unknown as DuplicatePairRow[]).length === 0) {
  for (const createdAt of [hoursAgo(6), hoursAgo(2)]) {
    const [order] = await db.insert(schema.salesOrders).values({
      customerId: c0, createdBy: adminId,
      status: 'pending', paymentStatus: 'unpaid',
      createdAt, updatedAt: createdAt,
    }).returning({ id: schema.salesOrders.id });

    await db.insert(schema.orderItems).values([
      { salesOrderId: order.id, productId: p1, quantity: 50,  unitPrice: '5.80',  subtotal: '290.00' },
      { salesOrderId: order.id, productId: p3, quantity: 30,  unitPrice: '3.20',  subtotal: '96.00'  },
    ]);
  }
  console.log('✅ Duplicate pending order pair inserted (DUPLICATE_ORDER anomaly demo)');
}

// ── Step 8: Anomaly scanner ────────────────────────────────
await runAnomalyScanner(db);
console.log('✅ Anomaly scanner executed');

// ── Summary ────────────────────────────────────────────────
console.log(`
╔══════════════════════════════════════════════════════════════╗
║          Production English Dataset — Seed Complete          ║
╠══════════════════════════════════════════════════════════════╣
║  Products  : 20 (IoT electronics, USD pricing)               ║
║  Customers : 12 (B2B companies)                              ║
║  Inventory : 20 items (⚠️  nRF52840 low, 🚨 LiPo critical)  ║
║  Sales Orders: ${orderSpecs.length} orders + 2 duplicate-pending          ║
║    ├ shipped+paid : 43                                        ║
║    ├ confirmed    :  1  (Apr-6)                               ║
║    └ pending      :  3  (Apr-7 + 2 anomaly)                  ║
║  Monthly Revenue (shipped):                                   ║
║    Nov 2025 : ~$  25,285                                      ║
║    Dec 2025 : ~$  42,729  ← year-end peak                    ║
║    Jan 2026 : ~$  18,555  ← post-holiday dip                 ║
║    Feb 2026 : ~$  28,353                                      ║
║    Mar 2026 : ~$  36,789                                      ║
║    Apr 2026 : ~$  22,400  (+ $6,175 in progress)             ║
║  Quotations: 12 (5 converted 41.7%, avg 6.2 days)            ║
║    Active pipeline: sent×2 + draft×2 = ~$36,700              ║
╚══════════════════════════════════════════════════════════════╝
`);

await sqlClient.end();
