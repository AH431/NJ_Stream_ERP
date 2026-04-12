/**
 * Sync Route — POST /api/v1/sync/push
 *
 * 職責（薄路由層）：
 *   1. 請求驗證（JWT + Zod）
 *   2. 批次上限 50 筆（同步協定 v1.6 § 5）
 *   3. 順序驗證：operations 須依 created_at 升序（v1.6 § 5）
 *   4. 冪等去重：已在 processed_operations 的 operationId → 直接歸入 succeeded
 *   5. 逐筆開啟 Transaction，呼叫 sync.service 處理業務邏輯
 *   6. 無論成功或失敗都寫入 processed_operations（審計記錄）
 *   7. 回傳 { succeeded: string[], failed: FailedOperation[] }
 *
 * 同步協定 v1.6 § 6 錯誤碼處理由 sync.service 負責；
 * 此路由僅做輸入驗證與結果彙整。
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, gt } from 'drizzle-orm';
import { customers } from '@/schemas/customers.schema.js';
import { products } from '@/schemas/products.schema.js';
import { quotations } from '@/schemas/quotations.schema.js';
import { salesOrders } from '@/schemas/sales_orders.schema.js';
import { processedOperations } from '@/schemas/processed_operations.schema.js';
import { processOperation } from '@/services/sync.service.js';
import { SYNC } from '@/constants/index.js';
import type { FailedOperation } from '@/types/index.js';

// ── 請求 Body Schema ───────────────────────────────────────

/**
 * SyncOperation Zod Schema
 * 對應 types/index.ts 的 SyncOperation interface（雙重保護：TS 型別 + 執行期驗證）
 */
const SyncOperationSchema = z.object({
  /** 前端產生的 UUID v4，用於冪等去重 */
  id:            z.string().uuid('operationId 必須是 UUID v4 格式'),
  entityType:    z.enum(['customer', 'product', 'quotation', 'sales_order', 'inventory_delta']),
  operationType: z.enum(['create', 'update', 'delete', 'delta_update']),
  /** 僅 inventory_delta 使用 */
  deltaType:     z.enum(['reserve', 'cancel', 'out', 'in']).nullable().optional(),
  /** 嚴格升序依據（同步協定 v1.6 § 5）*/
  createdAt:     z.string().datetime(),
  /** 完整 entity 快照（各 entityType 的詳細格式由 sync.service 內的 Zod schema 驗證）*/
  payload:       z.record(z.unknown()),
});

const SyncPushBody = z.object({
  operations: z.array(SyncOperationSchema),
});

// ── 路由 ──────────────────────────────────────────────────

export default async function syncRoutes(app: FastifyInstance) {
  const { db } = app;

  /**
   * POST /api/v1/sync/push
   *
   * 接收離線期間累積的操作佇列，逐筆處理並回傳結果。
   * 部分失敗不影響其他操作（partial success 設計）。
   */
  app.post('/push', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    // ── 1. 請求格式驗證 ──────────────────────────────────
    const parsed = SyncPushBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const { operations } = parsed.data;

    // ── 2. 批次上限（同步協定 v1.6 § 5）────────────────
    if (operations.length > SYNC.BATCH_LIMIT) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: `單批次 operations 上限為 ${SYNC.BATCH_LIMIT} 筆，收到 ${operations.length} 筆。`,
      });
    }

    // ── 3. 順序驗證：必須依 created_at 升序排列 ─────────
    for (let i = 1; i < operations.length; i++) {
      if (operations[i].createdAt <= operations[i - 1].createdAt) {
        return reply.status(400).send({
          code: 'VALIDATION_ERROR',
          message: `operations[${i}].createdAt 未依升序排列（違反同步協定 v1.6 § 5）。`,
        });
      }
    }

    // ── 4–6. 逐筆處理 ────────────────────────────────────
    const succeeded: string[] = [];
    const failed: FailedOperation[] = [];
    const { userId, role } = request.user;

    for (const op of operations) {
      // ── 4. 冪等去重：已處理過的 operationId 直接視為成功 ─
      const [existing] = await db.select({ id: processedOperations.id })
        .from(processedOperations)
        .where(eq(processedOperations.operationId, op.id));

      if (existing) {
        succeeded.push(op.id);
        continue;
      }

      // ── 5. 在 Transaction 內執行業務邏輯 + 寫 processed_operations ──
      //    Transaction 確保「業務寫入」和「記錄已處理」原子提交；
      //    若 DB 異常，兩者一起 rollback，下次推送可重試。
      try {
        type TxResult = { ok: true } | { ok: false; failure: FailedOperation };

        const result = await db.transaction(async (tx): Promise<TxResult> => {
          const opResult = await processOperation(tx, op, userId, role);

          // 無論成功或失敗都寫入 processed_operations（審計記錄）
          await tx.insert(processedOperations).values({
            operationId:   op.id,
            entityType:    op.entityType,
            operationType: op.operationType,
            deltaType:     op.deltaType ?? null,
            payload:       op.payload,
            status:        opResult.ok ? 'success' : 'failed',
            errorMessage:  opResult.ok ? null : opResult.failure.message,
          });

          return opResult;
        });

        // ── 6. 彙整結果 ──────────────────────────────────
        if (result.ok) {
          succeeded.push(op.id);
        } else {
          failed.push(result.failure);
        }
      } catch (err: unknown) {
        // 未預期的 DB 錯誤（如連線中斷、schema 不符等）
        // processed_operations 未寫入 → 下次推送可重試（非永久失敗）
        app.log.error({ err, operationId: op.id }, 'sync push unexpected error');
        failed.push({
          operationId: op.id,
          code: 'DATA_CONFLICT',
          message: '伺服器處理時發生未預期的錯誤，請稍後重試。',
          server_state: null,
        });
      }
    }

    // ── 7. 回傳結果 ──────────────────────────────────────
    // HTTP 200 即使有 failed operations — 部分成功是正常狀態，非 HTTP 錯誤
    return reply.status(200).send({ succeeded, failed });
  });

  /**
   * GET /api/v1/sync/pull
   * 下拉伺服器最新狀態（Fail-to-Pull 與增量同步）
   */
  app.get('/pull', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const querySchema = z.object({
      since: z.string().datetime().optional(),
      entityTypes: z.string().optional(),
    });

    const parsed = querySchema.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: 'Invalid query parameters.',
      });
    }

    const { since, entityTypes } = parsed.data;
    const sinceDate = since ? new Date(since) : new Date(0);
    const types = entityTypes ? entityTypes.split(',') : ['customer', 'product', 'quotation', 'sales_order', 'inventory_delta'];

    const result: Record<string, unknown[]> = {
      customers: [],
      products: [],
      quotations: [],
      salesOrders: [],
      inventoryDeltas: [],
    };

    if (types.includes('customer')) {
      const rows = await db.select().from(customers)
        .where(gt(customers.updatedAt, sinceDate));
      result.customers = rows.map(r => ({
        entityType: 'customer',
        id: r.id,
        name: r.name,
        contact: r.contact ?? null,
        taxId: r.taxId ?? null,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
        deletedAt: r.deletedAt ? r.deletedAt.toISOString() : null,
      }));
    }

    if (types.includes('product')) {
      const rows = await db.select().from(products)
        .where(gt(products.updatedAt, sinceDate));
      result.products = rows.map(r => ({
        entityType: 'product',
        id: r.id,
        name: r.name,
        sku: r.sku,
        unitPrice: r.unitPrice,
        minStockLevel: r.minStockLevel,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
        deletedAt: r.deletedAt ? r.deletedAt.toISOString() : null,
      }));
    }

    if (types.includes('quotation')) {
      const rows = await db.select().from(quotations)
        .where(gt(quotations.updatedAt, sinceDate));
      result.quotations = rows.map(r => ({
        entityType: 'quotation',
        id: r.id,
        customerId: r.customerId,
        createdBy: r.createdBy,
        items: [],          // items 需靠 order_items join，W5 Issue #10 補完
        totalAmount: r.totalAmount,
        taxAmount: r.taxAmount,
        status: r.status,
        convertedToOrderId: r.convertedToOrderId ?? null,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
        deletedAt: r.deletedAt ? r.deletedAt.toISOString() : null,
      }));
    }

    if (types.includes('sales_order')) {
      const rows = await db.select().from(salesOrders)
        .where(gt(salesOrders.updatedAt, sinceDate));
      result.salesOrders = rows.map(r => ({
        entityType: 'sales_order',
        id: r.id,
        quotationId: r.quotationId ?? null,
        customerId: r.customerId,
        createdBy: r.createdBy,
        status: r.status,
        confirmedAt: r.confirmedAt ? r.confirmedAt.toISOString() : null,
        shippedAt: r.shippedAt ? r.shippedAt.toISOString() : null,
        createdAt: r.createdAt.toISOString(),
        updatedAt: r.updatedAt.toISOString(),
        deletedAt: r.deletedAt ? r.deletedAt.toISOString() : null,
      }));
    }

    return reply.status(200).send(result);
  });
}
