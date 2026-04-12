import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import dbPlugin from '@/plugins/db.js';
import authPlugin from '@/plugins/auth.plugin.js';
import authRoutes from '@/routes/auth.route.js';
import customersRoutes from '@/routes/customers.route.js';
import productsRoutes from '@/routes/products.route.js';
import syncRoutes from '@/routes/sync.route.js';

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

  // ── Auth 插件（JWT verifyJwt + requireRole）────────────
  // 必須在路由之前註冊，讓 app.verifyJwt 裝飾在路由 preHandler 時已存在
  app.register(authPlugin);

  // ── 健康檢查 ────────────────────────────────────────────
  app.get('/health', async () => ({ status: 'ok', timestamp: new Date().toISOString() }));

  // ── 路由 ────────────────────────────────────────────────
  app.register(authRoutes,      { prefix: '/api/v1/auth' });
  app.register(customersRoutes, { prefix: '/api/v1/customers' });
  app.register(productsRoutes,  { prefix: '/api/v1/products' });
  app.register(syncRoutes,      { prefix: '/api/v1/sync' });

  return app;
}
