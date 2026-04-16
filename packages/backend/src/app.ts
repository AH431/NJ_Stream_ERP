import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import dbPlugin from '@/plugins/db.js';
import authPlugin from '@/plugins/auth.plugin.js';
import authRoutes from '@/routes/auth.route.js';
import customersRoutes from '@/routes/customers.route.js';
import productsRoutes from '@/routes/products.route.js';
import syncRoutes  from '@/routes/sync.route.js';
import adminRoutes from '@/routes/admin.route.js';
import importRoutes from '@/routes/import.route.js';

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

  // 全域速率限制：每 IP 每分鐘最多 50 次（一般 API 使用）
  // /auth/login 另設更嚴格的限制（見 auth.route.ts）
  app.register(rateLimit, {
    global: true,
    max: 50,
    timeWindow: '1 minute',
    errorResponseBuilder: (_request, context) => ({
      statusCode: 429,
      code: 'RATE_LIMIT_EXCEEDED',
      message: `請求過於頻繁，請 ${Math.ceil(context.ttl / 1000)} 秒後重試。`,
    }),
  });

  // ── 檔案上傳（CSV Import）────────────────────────────────
  // 限制單檔 5 MB，防止超大 CSV 耗盡記憶體
  app.register(multipart, { limits: { fileSize: 5 * 1024 * 1024 } });

  // ── 資料庫插件 ──────────────────────────────────────────
  app.register(dbPlugin);

  // ── Auth 插件（JWT verifyJwt + requireRole）────────────
  // 必須在路由之前註冊，讓 app.verifyJwt 裝飾在路由 preHandler 時已存在
  app.register(authPlugin);

  // ── 健康檢查 ────────────────────────────────────────────
  // rate limit 獨立設定，防止自動化工具用 /health 探測服務狀態
  app.get('/health', {
    config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
  }, async () => ({ status: 'ok' }));

  // ── 路由 ────────────────────────────────────────────────
  app.register(authRoutes,      { prefix: '/api/v1/auth' });
  app.register(customersRoutes, { prefix: '/api/v1/customers' });
  app.register(productsRoutes,  { prefix: '/api/v1/products' });
  app.register(syncRoutes,      { prefix: '/api/v1/sync' });
  app.register(adminRoutes,     { prefix: '/api/v1/admin' });
  app.register(importRoutes,    { prefix: '/api/v1/admin' });

  return app;
}
