/**
 * Sync Service — POST /api/v1/sync/push 核心邏輯
 *
 * 職責：
 *   接收一筆 SyncOperation，依 entityType + operationType 路由到對應的處理函式，
 *   回傳 ProcessResult（成功 or 失敗 + FailedOperation 詳情）。
 *
 * 設計原則：
 *   - 每個 processor 都在呼叫端提供的 transaction（tx）內執行，確保
 *     「業務 DB 寫入」與「processed_operations 記錄」原子提交。
 *   - 應用層先做約束檢查（庫存、LWW），避免依賴 DB CHECK 錯誤訊息。
 *   - 所有 processor 都是 pure function（無全域狀態），方便單元測試。
 */

import { z } from 'zod';
import { eq, isNull, and } from 'drizzle-orm';
import type { PgTransaction } from 'drizzle-orm/pg-core';
import type { PostgresJsQueryResultHKT } from 'drizzle-orm/postgres-js';
import type { ExtractTablesWithRelations } from 'drizzle-orm';
import { customers }  from '@/schemas/customers.schema.js';
import { products }   from '@/schemas/products.schema.js';
import { quotations } from '@/schemas/quotations.schema.js';
import { salesOrders }     from '@/schemas/sales_orders.schema.js';
import { orderItems }      from '@/schemas/order_items.schema.js';
import { inventoryItems }  from '@/schemas/inventory_items.schema.js';
import { USER_ROLES, DELTA_TYPES } from '@/constants/index.js';
import type * as schema from '@/schemas/index.js';
import type { SyncOperation, FailedOperation, ServerState } from '@/types/index.js';
import type {
  CustomerPayload, ProductPayload, QuotationPayload,
  SalesOrderPayload, InventoryItemPayload,
} from '@/types/payloads.js';

/**
 * Transaction 內的 Drizzle client 型別。
 * db.transaction(async (tx) => {...}) 的 tx 是 PgTransaction，
 * 沒有 $client 屬性，與 PostgresJsDatabase 不相容，需要獨立宣告。
 */
type SyncTx = PgTransaction<
  PostgresJsQueryResultHKT,
  typeof schema,
  ExtractTablesWithRelations<typeof schema>
>;

// ==============================================================================
// 型別
// ==============================================================================

export type ProcessResult =
  | { ok: true; serverId?: number }
  | { ok: false; failure: FailedOperation };

// ==============================================================================
// 常數
// ==============================================================================

/** 金額字串格式 regex（對應後端 numeric precision:12 scale:2）*/
const PRICE_REGEX = /^\d+(\.\d{1,2})?$/;

/**
 * 權限矩陣
 * key: `${entityType}:${operationType}[:${deltaType}]`
 * value: 允許通行的角色清單
 *
 * 對應 PRD §3 角色權限矩陣。
 * delta_update 的 reserve/cancel 由業務角色觸發（確認/取消訂單）；
 * in/out 由倉管角色觸發（入出庫操作）。
 */
const PERMISSIONS: Record<string, string[]> = {
  'customer:create':             [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'customer:update':             [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'customer:delete':             [USER_ROLES.ADMIN],
  'product:create':              [USER_ROLES.ADMIN],
  'product:update':              [USER_ROLES.ADMIN],
  'product:delete':              [USER_ROLES.ADMIN],
  'quotation:create':            [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'quotation:update':            [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'quotation:delete':            [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'sales_order:create':          [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'sales_order:update':          [USER_ROLES.SALES, USER_ROLES.WAREHOUSE, USER_ROLES.ADMIN],
  'sales_order:delete':          [USER_ROLES.ADMIN],
  // inventory_delta 的 deltaType 決定誰可以操作
  'inventory_delta:delta_update:reserve': [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'inventory_delta:delta_update:cancel':  [USER_ROLES.SALES, USER_ROLES.ADMIN],
  'inventory_delta:delta_update:out':     [USER_ROLES.WAREHOUSE, USER_ROLES.ADMIN],
  'inventory_delta:delta_update:in':      [USER_ROLES.WAREHOUSE, USER_ROLES.ADMIN],
};

// ==============================================================================
// 小工具
// ==============================================================================

/** Date | null → ISO string | null（用於組裝 ServerState）*/
function toIso(d: Date | null | undefined): string | null {
  return d ? d.toISOString() : null;
}

/** 建立統一格式的 FailedOperation */
function makeFailure(
  operationId: string,
  code: FailedOperation['code'],
  message: string,
  serverState: ServerState | null = null,
): ProcessResult {
  return {
    ok: false,
    failure: { operationId, code, message, server_state: serverState },
  };
}

/**
 * 權限檢查
 * @returns true = 有權限，false = 無權限
 */
function hasPermission(role: string, entityType: string, operationType: string, deltaType?: string | null): boolean {
  // inventory_delta 的 key 包含 deltaType
  const key = deltaType
    ? `${entityType}:${operationType}:${deltaType}`
    : `${entityType}:${operationType}`;
  const allowed = PERMISSIONS[key];
  return allowed ? allowed.includes(role) : false;
}

// ==============================================================================
// ServerState 轉換器（DB row → API payload 格式）
// 前端收到 server_state 後直接覆蓋本地記錄（Force Overwrite），
// 因此格式必須與前端 Drift schema 完全對應。
// ==============================================================================

function customerToState(row: typeof customers.$inferSelect): CustomerPayload {
  return {
    entityType: 'customer',
    id: row.id,
    name: row.name,
    contact: row.contact ?? null,
    taxId: row.taxId ?? null,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: toIso(row.deletedAt),
  };
}

function productToState(row: typeof products.$inferSelect): ProductPayload {
  return {
    entityType: 'product',
    id: row.id,
    name: row.name,
    sku: row.sku,
    unitPrice: row.unitPrice,           // Drizzle numeric → string，直接對齊前端 DecimalConverter
    minStockLevel: row.minStockLevel,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: toIso(row.deletedAt),
  };
}

function inventoryToState(row: typeof inventoryItems.$inferSelect): InventoryItemPayload {
  return {
    entityType: 'inventory_item',
    id: row.id,
    productId: row.productId,
    warehouseId: row.warehouseId,
    quantityOnHand: row.quantityOnHand,
    quantityReserved: row.quantityReserved,
    minStockLevel: row.minStockLevel,
    createdAt: row.createdAt.toISOString(),
    updatedAt: row.updatedAt.toISOString(),
    deletedAt: null,
  };
}

// ==============================================================================
// Zod Payload Schema（各 entityType 的 payload 結構驗證）
// ==============================================================================

const CustomerCreateSchema = z.object({
  customerId: z.number().optional(), // 建立時忽略，後端配發
  name:    z.string().min(1).max(255),
  contact: z.string().max(255).nullable().optional(),
  taxId:   z.string().max(20).nullable().optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

const CustomerMutateSchema = z.object({
  id:      z.number().int().positive(),
  name:    z.string().min(1).max(255).optional(),
  contact: z.string().max(255).nullable().optional(),
  taxId:   z.string().max(20).nullable().optional(),
  updatedAt: z.string().datetime(),
});

const ProductCreateSchema = z.object({
  name:          z.string().min(1).max(255),
  sku:           z.string().min(1).max(100),
  unitPrice:     z.string().regex(PRICE_REGEX, 'unitPrice 格式錯誤'),
  minStockLevel: z.number().int().min(0).default(0),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

const ProductMutateSchema = z.object({
  id:            z.number().int().positive(),
  name:          z.string().min(1).max(255).optional(),
  sku:           z.string().min(1).max(100).optional(),
  unitPrice:     z.string().regex(PRICE_REGEX).optional(),
  minStockLevel: z.number().int().min(0).optional(),
  updatedAt: z.string().datetime(),
});

const QuotationItemSchema = z.object({
  productId: z.number().int().positive(),
  quantity:  z.number().int().positive(),
  unitPrice: z.string().regex(PRICE_REGEX, 'unitPrice 格式錯誤'),
  subtotal:  z.string().regex(PRICE_REGEX, 'subtotal 格式錯誤'),
});

const QuotationCreateSchema = z.object({
  customerId:   z.number().int().positive(),
  createdBy:    z.number().int().positive(),
  items:        z.array(QuotationItemSchema).min(1),
  totalAmount:  z.string().regex(PRICE_REGEX),
  taxAmount:    z.string().regex(PRICE_REGEX),
  status:       z.enum(['draft', 'sent', 'converted', 'expired']).default('draft'),
  convertedToOrderId: z.number().int().positive().nullable().optional(),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

const QuotationMutateSchema = z.object({
  id:           z.number().int().positive(),
  items:        z.array(QuotationItemSchema).optional(),
  totalAmount:  z.string().regex(PRICE_REGEX).optional(),
  taxAmount:    z.string().regex(PRICE_REGEX).optional(),
  status:       z.enum(['draft', 'sent', 'converted', 'expired']).optional(),
  updatedAt: z.string().datetime(),
});

const SalesOrderCreateSchema = z.object({
  quotationId: z.number().int().positive().nullable().optional(),
  customerId:  z.number().int().positive(),
  createdBy:   z.number().int().positive(),
  status:      z.enum(['pending', 'confirmed', 'shipped', 'cancelled']).default('pending'),
  createdAt: z.string().datetime(),
  updatedAt: z.string().datetime(),
});

const SalesOrderMutateSchema = z.object({
  id:          z.number().int().positive(),
  status:      z.enum(['pending', 'confirmed', 'shipped', 'cancelled']).optional(),
  confirmedAt: z.string().datetime().nullable().optional(),
  shippedAt:   z.string().datetime().nullable().optional(),
  updatedAt: z.string().datetime(),
});

const InventoryDeltaSchema = z.object({
  productId:       z.number().int().positive(),
  inventoryItemId: z.number().int().positive().optional(),
  amount:          z.number().int().positive(),
});

// ==============================================================================
// Operation Processors
// ==============================================================================

// ── Customer ──────────────────────────────────────────────

async function processCustomer(
  tx: SyncTx,
  op: SyncOperation,
  _userId: number,
  role: string,
): Promise<ProcessResult> {
  // 權限檢查
  if (!hasPermission(role, 'customer', op.operationType)) {
    return makeFailure(op.id, 'PERMISSION_DENIED',
      `角色 ${role} 無權執行 customer:${op.operationType}。`);
  }

  if (op.operationType === 'create') {
    const parsed = CustomerCreateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { name, contact, taxId } = parsed.data;
    const [inserted] = await tx.insert(customers).values({
      name,
      contact: contact ?? null,
      taxId: taxId ?? null,
    }).returning({ id: customers.id });
    return { ok: true, serverId: inserted.id };
  }

  if (op.operationType === 'update') {
    const parsed = CustomerMutateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { id, updatedAt: payloadUpdatedAt, ...fields } = parsed.data;

    const [current] = await tx.select().from(customers)
      .where(and(eq(customers.id, id), isNull(customers.deletedAt)));
    if (!current) {
      return makeFailure(op.id, 'DATA_CONFLICT', `找不到 customer id=${id}。`);
    }
    // LWW：伺服器資料較新時，不接受客戶端更新
    if (current.updatedAt > new Date(payloadUpdatedAt)) {
      return makeFailure(op.id, 'FORBIDDEN_OPERATION',
        'LWW：伺服器資料較新，執行 Force Overwrite。',
        customerToState(current));
    }
    await tx.update(customers)
      .set({ ...fields, updatedAt: new Date() })
      .where(eq(customers.id, id));
    return { ok: true };
  }

  if (op.operationType === 'delete') {
    const parsed = z.object({ id: z.number().int().positive() }).safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR', 'payload 需包含 id。');
    }
    await tx.update(customers)
      .set({ deletedAt: new Date() })
      .where(and(eq(customers.id, parsed.data.id), isNull(customers.deletedAt)));
    return { ok: true };
  }

  return makeFailure(op.id, 'VALIDATION_ERROR',
    `不支援的 customer operationType: ${op.operationType}。`);
}

// ── Product ───────────────────────────────────────────────

async function processProduct(
  tx: SyncTx,
  op: SyncOperation,
  _userId: number,
  role: string,
): Promise<ProcessResult> {
  if (!hasPermission(role, 'product', op.operationType)) {
    return makeFailure(op.id, 'PERMISSION_DENIED',
      `角色 ${role} 無權執行 product:${op.operationType}。`);
  }

  if (op.operationType === 'create') {
    const parsed = ProductCreateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { name, sku, unitPrice, minStockLevel } = parsed.data;
    try {
      await tx.insert(products).values({ name, sku, unitPrice, minStockLevel });
    } catch (err: unknown) {
      const e = err as { code?: string };
      if (e.code === '23505') { // unique_violation（SKU 重複）
        return makeFailure(op.id, 'DATA_CONFLICT', `SKU "${sku}" 已存在。`);
      }
      throw err;
    }
    return { ok: true };
  }

  if (op.operationType === 'update') {
    const parsed = ProductMutateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { id, updatedAt: payloadUpdatedAt, ...fields } = parsed.data;

    const [current] = await tx.select().from(products)
      .where(and(eq(products.id, id), isNull(products.deletedAt)));
    if (!current) {
      return makeFailure(op.id, 'DATA_CONFLICT', `找不到 product id=${id}。`);
    }
    if (current.updatedAt > new Date(payloadUpdatedAt)) {
      return makeFailure(op.id, 'FORBIDDEN_OPERATION',
        'LWW：伺服器資料較新，執行 Force Overwrite。',
        productToState(current));
    }
    try {
      await tx.update(products)
        .set({ ...fields, updatedAt: new Date() })
        .where(eq(products.id, id));
    } catch (err: unknown) {
      const e = err as { code?: string };
      if (e.code === '23505') {
        return makeFailure(op.id, 'DATA_CONFLICT', 'SKU 已被其他產品使用。');
      }
      throw err;
    }
    return { ok: true };
  }

  if (op.operationType === 'delete') {
    const parsed = z.object({ id: z.number().int().positive() }).safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR', 'payload 需包含 id。');
    }
    await tx.update(products)
      .set({ deletedAt: new Date() })
      .where(and(eq(products.id, parsed.data.id), isNull(products.deletedAt)));
    return { ok: true };
  }

  return makeFailure(op.id, 'VALIDATION_ERROR',
    `不支援的 product operationType: ${op.operationType}。`);
}

// ── Quotation ─────────────────────────────────────────────

async function processQuotation(
  tx: SyncTx,
  op: SyncOperation,
  _userId: number,
  role: string,
): Promise<ProcessResult> {
  if (!hasPermission(role, 'quotation', op.operationType)) {
    return makeFailure(op.id, 'PERMISSION_DENIED',
      `角色 ${role} 無權執行 quotation:${op.operationType}。`);
  }

  if (op.operationType === 'create') {
    const parsed = QuotationCreateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { customerId, createdBy, items, totalAmount, taxAmount, status } = parsed.data;

    // 1. 建立報價單主表
    const [created] = await tx.insert(quotations)
      .values({ customerId, createdBy, totalAmount, taxAmount, status })
      .returning({ id: quotations.id });

    // 2. 正規化：前端 JSON items → 後端 order_items 逐筆插入
    //    subtotal 由前端計算並傳入（DecimalConverter 精確計算）
    if (items.length > 0) {
      await tx.insert(orderItems).values(
        items.map((item) => ({
          quotationId: created.id,
          salesOrderId: null,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          subtotal: item.subtotal,
        })),
      );
    }
    return { ok: true, serverId: created.id };
  }

  if (op.operationType === 'update') {
    const parsed = QuotationMutateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { id, items, updatedAt: payloadUpdatedAt, ...fields } = parsed.data;

    const [current] = await tx.select().from(quotations)
      .where(and(eq(quotations.id, id), isNull(quotations.deletedAt)));
    if (!current) {
      return makeFailure(op.id, 'DATA_CONFLICT', `找不到 quotation id=${id}。`);
    }
    // 已轉成訂單的報價不可再更新（First-to-Sync wins 的邏輯由後端守護）
    if (current.convertedToOrderId != null) {
      return makeFailure(op.id, 'FORBIDDEN_OPERATION',
        '此報價已轉成訂單，不可再修改。');
    }
    if (current.updatedAt > new Date(payloadUpdatedAt)) {
      // 回傳 server_state 供前端 Force Overwrite（不含 items，items 下次 Pull 取得）
      const quotationState: QuotationPayload = {
        entityType: 'quotation',
        id: current.id,
        customerId: current.customerId,
        createdBy: current.createdBy,
        items: [],         // items 不在 LWW 回應內，前端需靠 Pull 取得
        totalAmount: current.totalAmount,
        taxAmount: current.taxAmount,
        status: current.status as QuotationPayload['status'],
        convertedToOrderId: current.convertedToOrderId ?? null,
        createdAt: current.createdAt.toISOString(),
        updatedAt: current.updatedAt.toISOString(),
        deletedAt: toIso(current.deletedAt),
      };
      return makeFailure(op.id, 'FORBIDDEN_OPERATION',
        'LWW：伺服器資料較新，執行 Force Overwrite。', quotationState);
    }

    // 更新主表
    if (Object.keys(fields).length > 0) {
      await tx.update(quotations)
        .set({ ...fields, updatedAt: new Date() })
        .where(eq(quotations.id, id));
    }
    // 若 items 有傳入 → 刪除舊明細並重新插入（整單替換）
    if (items && items.length > 0) {
      await tx.delete(orderItems).where(eq(orderItems.quotationId, id));
      await tx.insert(orderItems).values(
        items.map((item) => ({
          quotationId: id,
          salesOrderId: null,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          subtotal: item.subtotal,
        })),
      );
    }
    return { ok: true };
  }

  if (op.operationType === 'delete') {
    const parsed = z.object({ id: z.number().int().positive() }).safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR', 'payload 需包含 id。');
    }
    await tx.update(quotations)
      .set({ deletedAt: new Date() })
      .where(and(eq(quotations.id, parsed.data.id), isNull(quotations.deletedAt)));
    return { ok: true };
  }

  return makeFailure(op.id, 'VALIDATION_ERROR',
    `不支援的 quotation operationType: ${op.operationType}。`);
}

// ── SalesOrder ────────────────────────────────────────────

async function processSalesOrder(
  tx: SyncTx,
  op: SyncOperation,
  _userId: number,
  role: string,
): Promise<ProcessResult> {
  if (!hasPermission(role, 'sales_order', op.operationType)) {
    return makeFailure(op.id, 'PERMISSION_DENIED',
      `角色 ${role} 無權執行 sales_order:${op.operationType}。`);
  }

  if (op.operationType === 'create') {
    const parsed = SalesOrderCreateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { quotationId, customerId, createdBy, status } = parsed.data;
    let sourceQuotationItems: typeof orderItems.$inferSelect[] = [];

    // First-to-Sync wins：若從報價轉單，確認報價尚未被其他裝置轉換
    if (quotationId != null) {
      const [quot] = await tx.select().from(quotations)
        .where(and(eq(quotations.id, quotationId), isNull(quotations.deletedAt)));
      if (!quot) {
        return makeFailure(op.id, 'DATA_CONFLICT',
          `找不到 quotationId=${quotationId} 的報價。`);
      }
      if (quot.convertedToOrderId != null) {
        // 先到者已轉換，回傳最新報價狀態供前端 Force Overwrite（items 靠 Pull 取得）
        const quotState: QuotationPayload = {
          entityType: 'quotation',
          id: quot.id,
          customerId: quot.customerId,
          createdBy: quot.createdBy,
          items: [],
          totalAmount: quot.totalAmount,
          taxAmount: quot.taxAmount,
          status: quot.status as QuotationPayload['status'],
          convertedToOrderId: quot.convertedToOrderId,
          createdAt: quot.createdAt.toISOString(),
          updatedAt: quot.updatedAt.toISOString(),
          deletedAt: toIso(quot.deletedAt),
        };
        return makeFailure(op.id, 'FORBIDDEN_OPERATION',
          'First-to-Sync wins：此報價已被轉換為訂單，本次操作已取消。', quotState);
      }

      sourceQuotationItems = await tx.select().from(orderItems)
        .where(and(eq(orderItems.quotationId, quotationId), isNull(orderItems.salesOrderId)));

      if (sourceQuotationItems.length === 0) {
        return makeFailure(op.id, 'DATA_CONFLICT',
          `quotationId=${quotationId} 缺少可轉換的明細資料。`);
      }
    }

    // 建立訂單，若從報價轉入則同 transaction 更新報價狀態
    const [newOrder] = await tx.insert(salesOrders)
      .values({ quotationId: quotationId ?? null, customerId, createdBy, status })
      .returning({ id: salesOrders.id });

    if (quotationId != null) {
      await tx.insert(orderItems).values(
        sourceQuotationItems.map((item) => ({
          quotationId: null,
          salesOrderId: newOrder.id,
          productId: item.productId,
          quantity: item.quantity,
          unitPrice: item.unitPrice,
          subtotal: item.subtotal,
        })),
      );

      await tx.update(quotations)
        .set({ convertedToOrderId: newOrder.id, status: 'converted', updatedAt: new Date() })
        .where(eq(quotations.id, quotationId));
    }

    return { ok: true, serverId: newOrder.id };
  }

  if (op.operationType === 'update') {
    const parsed = SalesOrderMutateSchema.safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR',
        parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
    }
    const { id, updatedAt: payloadUpdatedAt, ...fields } = parsed.data;

    const [current] = await tx.select().from(salesOrders)
      .where(and(eq(salesOrders.id, id), isNull(salesOrders.deletedAt)));
    if (!current) {
      return makeFailure(op.id, 'DATA_CONFLICT', `找不到 sales_order id=${id}。`);
    }
    if (current.updatedAt > new Date(payloadUpdatedAt)) {
      const state: SalesOrderPayload = {
        entityType: 'sales_order',
        id: current.id,
        quotationId: current.quotationId ?? null,
        customerId: current.customerId,
        createdBy: current.createdBy,
        status: current.status as SalesOrderPayload['status'],
        confirmedAt: toIso(current.confirmedAt),
        shippedAt: toIso(current.shippedAt),
        createdAt: current.createdAt.toISOString(),
        updatedAt: current.updatedAt.toISOString(),
        deletedAt: toIso(current.deletedAt),
      };
      return makeFailure(op.id, 'FORBIDDEN_OPERATION',
        'LWW：伺服器資料較新，執行 Force Overwrite。', state);
    }
    // 將 nullable datetime 欄位轉回 Date | null
    const updateFields: Record<string, unknown> = { updatedAt: new Date() };
    if (fields.status !== undefined)      updateFields.status = fields.status;
    if (fields.confirmedAt !== undefined) updateFields.confirmedAt = fields.confirmedAt ? new Date(fields.confirmedAt) : null;
    if (fields.shippedAt !== undefined)   updateFields.shippedAt   = fields.shippedAt   ? new Date(fields.shippedAt)   : null;

    await tx.update(salesOrders).set(updateFields).where(eq(salesOrders.id, id));
    return { ok: true };
  }

  if (op.operationType === 'delete') {
    const parsed = z.object({ id: z.number().int().positive() }).safeParse(op.payload);
    if (!parsed.success) {
      return makeFailure(op.id, 'VALIDATION_ERROR', 'payload 需包含 id。');
    }
    await tx.update(salesOrders)
      .set({ deletedAt: new Date() })
      .where(and(eq(salesOrders.id, parsed.data.id), isNull(salesOrders.deletedAt)));
    return { ok: true };
  }

  return makeFailure(op.id, 'VALIDATION_ERROR',
    `不支援的 sales_order operationType: ${op.operationType}。`);
}

// ── InventoryDelta ────────────────────────────────────────

async function processInventoryDelta(
  tx: SyncTx,
  op: SyncOperation,
  _userId: number,
  role: string,
): Promise<ProcessResult> {
  const deltaType = op.deltaType;
  if (!deltaType) {
    return makeFailure(op.id, 'VALIDATION_ERROR',
      'inventory_delta 操作需要提供 deltaType。');
  }

  // 權限：reserve/cancel = sales+admin；in/out = warehouse+admin
  if (!hasPermission(role, 'inventory_delta', op.operationType, deltaType)) {
    return makeFailure(op.id, 'PERMISSION_DENIED',
      `角色 ${role} 無權執行 inventory_delta:${deltaType}。`);
  }

  const parsed = InventoryDeltaSchema.safeParse(op.payload);
  if (!parsed.success) {
    return makeFailure(op.id, 'VALIDATION_ERROR',
      parsed.error.issues[0]?.message ?? 'payload 格式錯誤。');
  }
  const { productId, amount } = parsed.data;

  // 查詢目前庫存（SELECT FOR UPDATE 語意由 Drizzle transaction 保證）
  const [item] = await tx.select().from(inventoryItems)
    .where(eq(inventoryItems.productId, productId));
  if (!item) {
    return makeFailure(op.id, 'DATA_CONFLICT',
      `找不到 productId=${productId} 的庫存記錄。`);
  }

  // 計算更新後的數量（應用層先算，避免觸發 DB CHECK 錯誤）
  let newOnHand    = item.quantityOnHand;
  let newReserved  = item.quantityReserved;

  switch (deltaType) {
    case DELTA_TYPES.IN:
      newOnHand += amount;
      break;
    case DELTA_TYPES.RESERVE:
      newReserved += amount;
      break;
    case DELTA_TYPES.CANCEL:
      newReserved -= amount;
      break;
    case DELTA_TYPES.OUT:
      newOnHand   -= amount;
      newReserved -= amount;
      break;
    default:
      return makeFailure(op.id, 'VALIDATION_ERROR',
        `不支援的 deltaType: ${deltaType}。`);
  }

  // 約束檢查（同步協定 v1.6 § 4）
  if (newOnHand < 0 || newReserved < 0 || newReserved > newOnHand) {
    return makeFailure(op.id, 'INSUFFICIENT_STOCK',
      `庫存不足：onHand=${item.quantityOnHand}, reserved=${item.quantityReserved}, delta=${deltaType}(${amount})。`,
      inventoryToState(item));
  }

  await tx.update(inventoryItems)
    .set({ quantityOnHand: newOnHand, quantityReserved: newReserved, updatedAt: new Date() })
    .where(eq(inventoryItems.id, item.id));

  return { ok: true };
}

// ==============================================================================
// 主分派器
// ==============================================================================

/**
 * 根據 operation.entityType 路由到對應的 processor。
 *
 * @param tx    Drizzle transaction（呼叫端負責開啟）
 * @param op    待處理的 SyncOperation
 * @param userId 呼叫者的 userId（從 JWT 取得）
 * @param role   呼叫者的 role（從 JWT 取得）
 */
export async function processOperation(
  tx: SyncTx,
  op: SyncOperation,
  userId: number,
  role: string,
): Promise<ProcessResult> {
  switch (op.entityType) {
    case 'customer':
      return processCustomer(tx, op, userId, role);
    case 'product':
      return processProduct(tx, op, userId, role);
    case 'quotation':
      return processQuotation(tx, op, userId, role);
    case 'sales_order':
      return processSalesOrder(tx, op, userId, role);
    case 'inventory_delta':
      return processInventoryDelta(tx, op, userId, role);
    default:
      return makeFailure(op.id, 'VALIDATION_ERROR',
        `不支援的 entityType: ${op.entityType}。`);
  }
}
