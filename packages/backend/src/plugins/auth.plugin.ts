/**
 * Auth Plugin — JWT 驗證 + 角色授權
 *
 * 使用 fastify-plugin（fp）包裝，確保 decorate 結果冒泡到父 scope，
 * 讓所有路由插件都能存取 app.verifyJwt 和 request.user。
 *
 * 使用方式（路由層）：
 *   // 只驗證 JWT（任何已登入角色皆可）
 *   { preHandler: [app.verifyJwt] }
 *
 *   // 驗證 JWT + 限定角色
 *   { preHandler: [app.verifyJwt, app.requireRole('admin', 'sales')] }
 */

import fp from 'fastify-plugin';
import jwt from 'jsonwebtoken';
import type { FastifyRequest, FastifyReply } from 'fastify';
import type { JwtPayload } from '@/types/auth.js';

// ── Fastify 型別擴充 ───────────────────────────────────────
// 讓 TypeScript 知道 app.verifyJwt、app.requireRole、request.user 的型別，
// 避免在路由層出現 "Property does not exist" 錯誤。
declare module 'fastify' {
  interface FastifyInstance {
    /**
     * preHandler：驗證 Authorization: Bearer <token>
     * 通過後將解碼的 payload（userId, role）寫入 request.user
     */
    verifyJwt: (request: FastifyRequest, reply: FastifyReply) => Promise<void>;

    /**
     * preHandler 工廠：只允許指定角色的已登入使用者通過
     * 必須在 verifyJwt 之後呼叫（依賴 request.user 已存在）
     *
     * @param roles 允許通行的角色清單，e.g. 'admin', 'sales'
     */
    requireRole: (...roles: string[]) => (request: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }

  interface FastifyRequest {
    /**
     * 由 verifyJwt preHandler 注入。
     * ⚠️ 只有在 verifyJwt 執行後的路由中才有效；
     *    未受保護的路由（如 /auth/login）不應存取此屬性。
     */
    user: JwtPayload;
  }
}

export default fp(async (app) => {
  // Fastify 規定：在 route handler 使用 request.xxx 之前必須先 decorateRequest
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  app.decorateRequest('user', null as any);

  // ── verifyJwt ──────────────────────────────────────────
  app.decorate('verifyJwt', async (request: FastifyRequest, reply: FastifyReply) => {
    const authHeader = request.headers.authorization;

    // 1. 檢查 header 格式
    if (!authHeader?.startsWith('Bearer ')) {
      return reply.status(401).send({
        code: 'UNAUTHORIZED',
        message: '需要 Authorization: Bearer <accessToken>。',
      });
    }

    // 2. 驗證 JWT 簽章與有效期
    try {
      const payload = jwt.verify(
        authHeader.slice(7),           // 去掉 "Bearer " 前綴
        process.env.JWT_SECRET!,
      ) as JwtPayload;

      request.user = payload;          // 注入給後續 handler 使用
    } catch {
      // jwt.verify 若過期或簽章不符均會 throw
      return reply.status(401).send({
        code: 'UNAUTHORIZED',
        message: 'Access Token 無效或已過期，請重新登入或執行 Token 刷新。',
      });
    }
  });

  // ── requireRole ────────────────────────────────────────
  app.decorate('requireRole', (...roles: string[]) => {
    return async (request: FastifyRequest, reply: FastifyReply) => {
      // request.user 由前一個 preHandler（verifyJwt）設定
      if (!roles.includes(request.user.role)) {
        return reply.status(403).send({
          code: 'PERMISSION_DENIED',
          message: `此操作需要 ${roles.join(' 或 ')} 角色，目前角色為 ${request.user.role}。`,
        });
      }
    };
  });
}, { name: 'auth' }); // name 確保此 plugin 全域只註冊一次（idempotent guard）
