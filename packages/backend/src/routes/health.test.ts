import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import { afterEach, describe, expect, it } from 'vitest';

function buildHealthTestApp() {
  const app = Fastify({ logger: false });

  app.register(helmet);
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

  // Must use app.after() so that the rate-limit plugin's onRoute hook is already
  // registered before the /health route is added. Registering the route directly
  // at root level would fire onRoute before the plugin loads (avvio queues plugins
  // asynchronously but route registration is synchronous).
  app.after(() => {
    app.get('/health', {
      config: { rateLimit: { max: 10, timeWindow: '1 minute' } },
    }, async () => ({ status: 'ok' }));
  });

  return app;
}

let app = buildHealthTestApp();

afterEach(async () => {
  await app.close();
  app = buildHealthTestApp();
});

describe('GET /health', () => {
  it('returns 200 with the expected body and security headers', async () => {
    await app.ready();

    const res = await app.inject({
      method: 'GET',
      url: '/health',
    });

    expect(res.statusCode).toBe(200);
    expect(res.json()).toEqual({ status: 'ok' });
    expect(res.headers['x-content-type-options']).toBeDefined();
    expect(res.headers['x-frame-options']).toBeDefined();
    expect(res.headers['x-dns-prefetch-control']).toBeDefined();
  });

  it('includes rate-limit headers on a normal response', async () => {
    await app.ready();

    const res = await app.inject({
      method: 'GET',
      url: '/health',
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['x-ratelimit-limit']).toBeDefined();
    expect(res.headers['x-ratelimit-remaining']).toBeDefined();
    expect(res.headers['x-ratelimit-reset']).toBeDefined();
  });

  it('returns the custom 429 body after 11 rapid requests', async () => {
    await app.ready();

    for (let i = 0; i < 10; i++) {
      const okRes = await app.inject({
        method: 'GET',
        url: '/health',
      });
      expect(okRes.statusCode).toBe(200);
    }

    const limitedRes = await app.inject({
      method: 'GET',
      url: '/health',
    });

    expect(limitedRes.statusCode).toBe(429);
    expect(limitedRes.json()).toMatchObject({
      statusCode: 429,
      code: 'RATE_LIMIT_EXCEEDED',
    });
    expect(limitedRes.json().message).toMatch(/^請求過於頻繁，請 \d+ 秒後重試。$/);
  });
});
