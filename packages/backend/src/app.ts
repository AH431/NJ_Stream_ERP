import { randomUUID } from 'node:crypto';
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
import documentsRoutes from '@/routes/documents.route.js';
import analyticsRoutes from '@/routes/analytics.route.js';
import anomaliesRoutes from '@/routes/anomalies.route.js';
import customerInteractionsRoutes from '@/routes/customer_interactions.route.js';
import arRoutes from '@/routes/ar.route.js';
import { runAnomalyScanner } from '@/services/anomaly_scanner.service.js';
import { runForecastScheduler } from '@/services/forecast_scheduler.service.js';
import type { JwtPayload } from '@/types/auth.js';
import notificationsRoutes from '@/routes/notifications.route.js';
import aiRoutes from '@/routes/ai.route.js';
import inventoryRoutes from '@/routes/inventory.route.js';
import quotationsRoutes from '@/routes/quotations.route.js';
import salesOrdersRoutes from '@/routes/sales_orders.route.js';
import tenantRoutes from '@/routes/tenant.route.js';
import { initFcm } from '@/services/fcm.service.js';

export function buildApp() {
  const app = Fastify({
    logger: {
      transport: process.env.NODE_ENV === 'development'
        ? { target: 'pino-pretty', options: { colorize: true } }
        : undefined,
    },
    // Suppress Fastify's default req/res log lines; replaced by our onResponse hook below
    disableRequestLogging: true,
    // Use UUID so req.id can be forwarded to ai_service for cross-service log correlation
    genReqId: () => randomUUID(),
  });

  // ── Structured access log（每次請求完成後各一行）──────────
  app.addHook('onResponse', async (req, reply) => {
    req.log.info({
      requestId: req.id,
      userId: (req.user as JwtPayload | null)?.userId ?? null,
      tenantId: null,  // Phase 4C M6.3 將從 JWT 帶入
      // Fastify 5 已將 routerPath 移至 routeOptions.url；未命中任何 route 時 fallback 到 url
      route:      req.routeOptions?.url ?? req.url,
      statusCode: reply.statusCode,
      durationMs: Math.round(reply.elapsedTime),
    }, 'http');
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
  // Must use app.after() so the rate-limit plugin's onRoute hook is registered
  // before this route is added (plugin registration is async via avvio).
  app.after(() => {
    app.get('/health', {
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    }, async () => ({ status: 'ok' }));
  });

  // ── 路由 ────────────────────────────────────────────────
  app.register(authRoutes,      { prefix: '/api/v1/auth' });
  app.register(customersRoutes, { prefix: '/api/v1/customers' });
  app.register(productsRoutes,  { prefix: '/api/v1/products' });
  app.register(syncRoutes,      { prefix: '/api/v1/sync' });
  app.register(adminRoutes,     { prefix: '/api/v1/admin' });
  app.register(importRoutes,     { prefix: '/api/v1/admin' });
  app.register(documentsRoutes,  { prefix: '/api/v1' });
  app.register(analyticsRoutes,  { prefix: '/api/v1/analytics' });
  app.register(anomaliesRoutes,              { prefix: '/api/v1/anomalies' });
  app.register(customerInteractionsRoutes,  { prefix: '/api/v1/customer-interactions' });
  app.register(arRoutes,                    { prefix: '/api/v1/ar' });
  app.register(notificationsRoutes,         { prefix: '/api/v1/notifications' });
  app.register(aiRoutes,                    { prefix: '/api/v1/ai' });
  app.register(inventoryRoutes,             { prefix: '/api/v1/inventory' });
  app.register(quotationsRoutes,            { prefix: '/api/v1/quotations' });
  app.register(salesOrdersRoutes,           { prefix: '/api/v1/sales-orders' });
  app.register(tenantRoutes,               { prefix: '/api/v1/tenant' });

  // ── Firebase Admin SDK 初始化（FIREBASE_SERVICE_ACCOUNT 不存在時靜默跳過）──
  initFcm();

  // ── AnomalyScanner 排程（每小時執行一次）─────────────────
  // onReady：確保 DB plugin 已完成初始化後才啟動排程
  app.addHook('onReady', async () => {
    const SCAN_INTERVAL_MS = 60 * 60 * 1000; // 1 hour
    // 啟動後 10 秒延遲首次掃描（等 DB 連線穩定）
    setTimeout(async () => {
      await runAnomalyScanner(app.db, app.log);
      setInterval(() => runAnomalyScanner(app.db, app.log), SCAN_INTERVAL_MS);
    }, 10_000);

    // ── ForecastScheduler 排程（每 6h；預設 FORECAST_SCHEDULE_INTERVAL_MS）──
    const FORECAST_INTERVAL_MS = parseInt(
      process.env.FORECAST_SCHEDULE_INTERVAL_MS ?? '21600000', 10,
    );
    // 啟動後 30 秒延遲首次觸發（等 AnomalyScanner 先完成首次掃描）
    setTimeout(async () => {
      await runForecastScheduler(app.db, app.log);
      setInterval(() => runForecastScheduler(app.db, app.log), FORECAST_INTERVAL_MS);
    }, 30_000);
  });

  return app;
}
