/**
 * Notifications Route — FCM device token 管理
 *
 * POST   /api/v1/notifications/token   — 登入後註冊 / 更新 FCM token（UPSERT）
 * DELETE /api/v1/notifications/token   — 登出後移除 FCM token
 *
 * 任何已登入角色均可呼叫（verifyJwt）。
 */

import type { FastifyPluginAsync } from 'fastify';
import { sql } from 'drizzle-orm';
import { z } from 'zod';

const RegisterTokenBody = z.object({
  token:    z.string().min(1).max(4096),
  platform: z.enum(['android', 'ios']).default('android'),
});

const notificationsRoutes: FastifyPluginAsync = async (app) => {
  // POST /token — 登入後 App 呼叫，UPSERT FCM token
  app.post('/token', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = RegisterTokenBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'INVALID_BODY', message: parsed.error.message });
    }

    const { token, platform } = parsed.data;
    const userId = (request.user as { userId: number }).userId;

    // UPSERT：同一 token 已存在時只更新 userId + updatedAt（裝置換帳號情境）
    await app.db.execute(sql`
      INSERT INTO device_tokens (user_id, token, platform, updated_at)
      VALUES (${userId}, ${token}, ${platform}, NOW())
      ON CONFLICT (token) DO UPDATE
        SET user_id = EXCLUDED.user_id,
            platform = EXCLUDED.platform,
            updated_at = NOW()
    `);

    return reply.status(204).send();
  });

  // DELETE /token — 登出時 App 呼叫，移除該裝置的 FCM token
  app.delete('/token', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = z.object({ token: z.string().min(1) }).safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'INVALID_BODY', message: parsed.error.message });
    }

    const userId = (request.user as { userId: number }).userId;

    await app.db.execute(sql`
      DELETE FROM device_tokens
      WHERE token = ${parsed.data.token}
        AND user_id = ${userId}
    `);

    return reply.status(204).send();
  });
};

export default notificationsRoutes;
