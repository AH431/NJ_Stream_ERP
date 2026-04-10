import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import dbPlugin from '@/plugins/db.js';

export function buildApp() {
  const app = Fastify({
    logger: {
      transport: process.env.NODE_ENV === 'development'
        ? { target: 'pino-pretty', options: { colorize: true } }
        : undefined,
    },
  });

  // ── 安全性插件 ──────────────────────────────────────────
  app.register(helmet);
  app.register(cors, {
    origin: process.env.NODE_ENV === 'development' ? true : false,
  });

  // ── 資料庫插件 ──────────────────────────────────────────
  app.register(dbPlugin);

  // ── 健康檢查 ────────────────────────────────────────────
  app.get('/health', async () => ({ status: 'ok', timestamp: new Date().toISOString() }));

  // ── 路由（W1–W2 以後逐步掛載）───────────────────────────
  // app.register(syncRoutes, { prefix: '/api/v1/sync' });
  // app.register(authRoutes, { prefix: '/api/v1/auth' });

  return app;
}
