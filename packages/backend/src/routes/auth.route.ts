import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import jwt from 'jsonwebtoken';
import * as authService from '@/services/auth.service.js';
import type { JwtPayload, AuthErrorResponse } from '@/types/auth.js';

const LoginBody = z.object({
  username: z.string().min(1).max(100),
  password: z.string().min(8),
});

const RefreshBody = z.object({
  refreshToken: z.string().min(1),
});

function getSecret(): string {
  return process.env.JWT_SECRET!;
}


export default async function authRoutes(app: FastifyInstance) {
  // ── POST /api/v1/auth/login ──────────────────────────────
  // 嚴格速率限制：每 IP 每分鐘最多 10 次，防止暴力破解密碼
  app.post('/login', {
    config: {
      rateLimit: {
        max: 10,
        timeWindow: '1 minute',
      },
    },
  }, async (request, reply) => {
    const parsed = LoginBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      } satisfies AuthErrorResponse);
    }

    const { username, password } = parsed.data;
    try {
      const tokens = await authService.login(app.db, username, password);
      return reply.status(200).send(tokens);
    } catch (err: unknown) {
      const e = err as { code?: string; message?: string; status?: number };
      return reply.status(e.status ?? 500).send({
        code: e.code ?? 'INTERNAL_ERROR',
        message: e.message ?? '伺服器錯誤。',
      } satisfies AuthErrorResponse);
    }
  });

  // ── POST /api/v1/auth/refresh ────────────────────────────
  app.post('/refresh', async (request, reply) => {
    const parsed = RefreshBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: '請提供 refreshToken。',
      } satisfies AuthErrorResponse);
    }

    try {
      const result = await authService.refresh(app.db, parsed.data.refreshToken);
      return reply.status(200).send(result);
    } catch (err: unknown) {
      const e = err as { code?: string; message?: string; status?: number };
      return reply.status(e.status ?? 500).send({
        code: e.code ?? 'INTERNAL_ERROR',
        message: e.message ?? '伺服器錯誤。',
      } satisfies AuthErrorResponse);
    }
  });

  // ── POST /api/v1/auth/logout ─────────────────────────────
  app.post('/logout', async (request, reply) => {
    const authHeader = request.headers.authorization;
    if (!authHeader?.startsWith('Bearer ')) {
      return reply.status(401).send({
        code: 'UNAUTHORIZED',
        message: '需要 Bearer Token。',
      } satisfies AuthErrorResponse);
    }

    let payload: JwtPayload;
    try {
      payload = jwt.verify(authHeader.slice(7), getSecret()) as JwtPayload;
    } catch {
      return reply.status(401).send({
        code: 'UNAUTHORIZED',
        message: 'Access Token 無效或已過期。',
      } satisfies AuthErrorResponse);
    }

    const parsed = RefreshBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: '請提供 refreshToken。',
      } satisfies AuthErrorResponse);
    }

    await authService.logout(app.db, payload.userId, parsed.data.refreshToken);
    return reply.status(204).send();
  });
}
