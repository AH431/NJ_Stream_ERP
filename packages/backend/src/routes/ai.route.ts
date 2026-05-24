import type { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify';
import { z } from 'zod';
import {
  createAuditLog,
  finishAuditLog,
  hashText,
  logAuditEvent,
} from '@/services/audit.service.js';

const ChatBody = z.object({
  question: z.string().min(1).max(2000),
});

const UPSTREAM_TIMEOUT_MS = 60_000;

// Per-user rate limit: 10 req/min.
// Runs as preHandler AFTER verifyJwt so request.user.userId is available.
// IP-based global limit (50/min in app.ts) continues to apply on top of this.
const _aiWindows = new Map<number, { count: number; resetAt: number }>();

async function aiRateLimit(request: FastifyRequest, reply: FastifyReply): Promise<void> {
  const userId = request.user.userId;
  const now = Date.now();
  let entry = _aiWindows.get(userId);
  if (!entry || now >= entry.resetAt) {
    entry = { count: 0, resetAt: now + 60_000 };
    _aiWindows.set(userId, entry);
  }
  entry.count++;
  if (entry.count > 10) {
    const retryAfter = Math.ceil((entry.resetAt - now) / 1000);
    reply.header('Retry-After', String(retryAfter));
    await reply.status(429).send({
      statusCode: 429,
      code:       'RATE_LIMIT_EXCEEDED',
      message:    `請求過於頻繁，請 ${retryAfter} 秒後重試。`,
    });
  }
}

export default async function aiRoutes(app: FastifyInstance) {
  const { db } = app;

  // POST /api/v1/ai/chat
  // JWT required, rate-limited. Proxies SSE stream from ai_service.
  // Writes pending audit on entry; updates to success/error on exit.
  app.post('/chat', {
    preHandler: [app.verifyJwt, aiRateLimit],
  }, async (request, reply) => {
    const parsed = ChatBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const { question } = parsed.data;
    const { userId, role } = request.user;
    const requestId = request.id;  // UUID (genReqId in app.ts); same value appears in access log
    const authHeader = request.headers.authorization ?? '';
    const userJwt = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : '';

    const auditId = await createAuditLog(db, {
      requestId,
      userId,
      userRole: role,
      action:      'ai.chat',
      questionHash: hashText(question),
      status:      'pending',
    });

    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), UPSTREAM_TIMEOUT_MS);

    // ── 連線 ai_service ───────────────────────────────────
    let upstreamRes: Response;
    try {
      upstreamRes = await fetch(
        `${process.env.AI_SERVICE_URL ?? 'http://localhost:8000'}/chat`,
        {
          method: 'POST',
          headers: {
            'Content-Type':    'application/json',
            'X-Internal-Token': process.env.AI_SERVICE_INTERNAL_TOKEN ?? '',
          },
          body:   JSON.stringify({ question, userJwt, role, userId, requestId }),
          signal: ac.signal,
        },
      );
    } catch (err: any) {
      clearTimeout(timer);
      await finishAuditLog(db, auditId, {
        status:       'error',
        errorMessage: err?.message ?? 'upstream_unavailable',
      });
      return reply.status(503).send({
        code:    'AI_SERVICE_UNAVAILABLE',
        message: 'AI 服務暫時無法連線，請稍後再試。',
      });
    }

    if (!upstreamRes.ok) {
      clearTimeout(timer);
      await finishAuditLog(db, auditId, {
        status:       'error',
        errorMessage: `upstream_${upstreamRes.status}`,
      });
      return reply.status(503).send({
        code:    'AI_SERVICE_ERROR',
        message: 'AI 服務回應錯誤，請稍後再試。',
      });
    }

    // ── SSE proxy ─────────────────────────────────────────
    reply.hijack();
    reply.raw.setHeader('Content-Type', 'text/event-stream');
    reply.raw.setHeader('Cache-Control', 'no-cache');
    reply.raw.setHeader('X-Accel-Buffering', 'no');
    reply.raw.setHeader('Connection', 'keep-alive');
    reply.raw.writeHead(200);

    // Client disconnect → abort upstream fetch body read
    request.raw.on('close', () => ac.abort());

    let seenBlocked = false;

    try {
      const reader  = upstreamRes.body!.getReader();
      const decoder = new TextDecoder();
      let sseBuffer = '';

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        if (reply.raw.destroyed) break;

        sseBuffer += decoder.decode(value, { stream: true });
        const events = sseBuffer.split('\n\n');
        sseBuffer = events.pop() ?? '';

        for (const raw of events) {
          if (!raw.startsWith('data: ')) {
            reply.raw.write(raw + '\n\n');
            continue;
          }

          let payload: any;
          try {
            payload = JSON.parse(raw.slice(6));
          } catch {
            reply.raw.write(raw + '\n\n');
            continue;
          }

          if (payload.type === 'blocked') {
            seenBlocked = true;
            reply.raw.write(raw + '\n\n');
            continue;
          }

          if (payload.type === 'tool_call') {
            void logAuditEvent(db, {
              requestId,
              userId,
              userRole: role,
              action: 'ai.tool_call',
              toolName: payload.tool,
              resourceType: payload.resourceType,
              resourceId: payload.resourceId != null ? String(payload.resourceId) : undefined,
              status: 'success',
            }).catch(() => {});
            continue;
          }

          reply.raw.write(raw + '\n\n');
        }
      }

      if (sseBuffer && !reply.raw.destroyed) {
        reply.raw.write(sseBuffer);
      }

      clearTimeout(timer);
      await finishAuditLog(db, auditId, { status: seenBlocked ? 'blocked' : 'success' });
    } catch (err: any) {
      clearTimeout(timer);
      await finishAuditLog(db, auditId, {
        status:       'error',
        errorMessage: err?.name === 'AbortError' ? 'client_abort' : (err?.message ?? 'stream_error'),
      });
    } finally {
      if (!reply.raw.destroyed) reply.raw.end();
    }
  });
}
