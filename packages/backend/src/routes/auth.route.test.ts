import Fastify from 'fastify';
import jwt from 'jsonwebtoken';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authRoutes from './auth.route.js';
import type { DrizzleDb } from '@/plugins/db.js';

const SECRET = 'test-secret-for-auth-route';

// Minimal stub: logout only calls authService.logout
vi.mock('@/services/auth.service.js', () => ({
  login: vi.fn(),
  refresh: vi.fn(),
  logout: vi.fn().mockResolvedValue(undefined),
}));

function buildApp(db: DrizzleDb) {
  const app = Fastify({ logger: false });
  app.decorate('db', db);
  app.register(authRoutes, { prefix: '/api/v1/auth' });
  return app;
}

function makeDb(): DrizzleDb {
  return {} as unknown as DrizzleDb;
}

function makeExpiredToken(userId: number, role = 'sales') {
  // expiresIn: -1 → token was already expired 1 second ago
  return jwt.sign({ userId, role }, SECRET, { expiresIn: -1 });
}

function makeValidToken(userId: number, role = 'sales') {
  return jwt.sign({ userId, role }, SECRET, { expiresIn: '1h' });
}

beforeEach(() => {
  process.env.JWT_SECRET = SECRET;
});

afterEach(() => {
  vi.clearAllMocks();
  delete process.env.JWT_SECRET;
});

describe('POST /api/v1/auth/logout — #11: jwt.decode accepts expired tokens', () => {
  it('accepts an already-expired access token and returns 204', async () => {
    const app = buildApp(makeDb());
    await app.ready();

    const expiredToken = makeExpiredToken(10);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      headers: { authorization: `Bearer ${expiredToken}` },
      payload: { refreshToken: 'some-refresh-token' },
    });

    // Should succeed even though access token is expired
    expect(res.statusCode).toBe(204);
    await app.close();
  });

  it('accepts a still-valid access token and returns 204', async () => {
    const app = buildApp(makeDb());
    await app.ready();

    const validToken = makeValidToken(11);

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      headers: { authorization: `Bearer ${validToken}` },
      payload: { refreshToken: 'some-refresh-token' },
    });

    expect(res.statusCode).toBe(204);
    await app.close();
  });

  it('returns 401 when token is completely malformed (not a JWT)', async () => {
    const app = buildApp(makeDb());
    await app.ready();

    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      headers: { authorization: 'Bearer not-a-jwt-at-all' },
      payload: { refreshToken: 'some-refresh-token' },
    });

    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'UNAUTHORIZED' });
    await app.close();
  });
});

describe('POST /api/v1/auth/logout — #12: getSecret null guard', () => {
  it('handles missing JWT_SECRET gracefully (should not crash the route)', async () => {
    delete process.env.JWT_SECRET;
    const app = buildApp(makeDb());
    await app.ready();

    // Without JWT_SECRET, getSecret() is not called on this route
    // (logout uses jwt.decode which doesn't need the secret).
    // The key assertion: malformed token → 401, not an unhandled 500.
    const res = await app.inject({
      method: 'POST',
      url: '/api/v1/auth/logout',
      headers: { authorization: 'Bearer bad-token' },
      payload: { refreshToken: 'r' },
    });

    expect(res.statusCode).toBe(401);
    await app.close();
  });
});
