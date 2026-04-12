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
import { eq } from 'drizzle-orm';
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
}
