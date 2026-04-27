/**
 * Anomalies REST API — Phase 2 P2-ALT
 *
 * GET   /anomalies            → 拉取未解決異常清單（依嚴重度排序）
 * POST  /anomalies/scan       → 手動觸發掃描（測試用）
 * PATCH /anomalies/:id/resolve → 標記已解決（任何有權限的角色）
 *
 * 不走 sync 協定：anomalies 由後端 scanner 產生，
 * 所有裝置拉同一份 backend 資料，自然達到跨裝置一致。
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { sql, eq, and } from 'drizzle-orm';
import { anomalies } from '@/schemas/anomalies.schema.js';
import { runAnomalyScanner } from '@/services/anomaly_scanner.service.js';

const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

// 嚴重度排序：critical > high > medium > low
const SEVERITY_ORDER = `
  CASE severity
    WHEN 'critical' THEN 1
    WHEN 'high'     THEN 2
    WHEN 'medium'   THEN 3
    ELSE 4
  END
`;

export default async function anomaliesRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /anomalies ─────────────────────────────────────
  // 回傳所有未解決異常，依嚴重度 → 建立時間排序。
  // 支援 ?resolved=true 查看已解決記錄（供稽核）。
  app.get('/', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const { resolved } = request.query as { resolved?: string };
    const showResolved = resolved === 'true';

    const rows = await db.execute(sql`
      SELECT
        id, alert_type, severity, entity_type, entity_id,
        message, detail, is_resolved, resolved_at,
        created_at, updated_at
      FROM anomalies
      WHERE is_resolved = ${showResolved}
      ORDER BY ${sql.raw(SEVERITY_ORDER)}, created_at DESC
      LIMIT 200
    `);

    return reply.send({ data: rows });
  });

  // ── POST /anomalies/scan ───────────────────────────────
  // 手動立即觸發一次完整掃描，回傳 { ok: true }。
  // 僅供開發 / 測試使用；生產環境由排程自動執行。
  app.post('/scan', {
    preHandler: [app.verifyJwt],
  }, async (_request, reply) => {
    await runAnomalyScanner(db);
    return reply.send({ ok: true });
  });

  // ── PATCH /anomalies/:id/resolve ───────────────────────
  // 將指定異常標記為已解決。
  app.patch('/:id/resolve', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parse = IdParam.safeParse(request.params);
    if (!parse.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: parse.error.message });
    }
    const { id } = parse.data;

    const result = await db
      .update(anomalies)
      .set({
        isResolved: true,
        resolvedAt: new Date(),
        updatedAt:  new Date(),
      })
      .where(and(eq(anomalies.id, id), eq(anomalies.isResolved, false)))
      .returning({ id: anomalies.id });

    if (result.length === 0) {
      return reply.status(404).send({
        code: 'NOT_FOUND',
        message: '找不到該異常記錄，或已經是已解決狀態。',
      });
    }

    return reply.send({ success: true, id });
  });
}
