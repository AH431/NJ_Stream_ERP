import Fastify from 'fastify';
import jwt from 'jsonwebtoken';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import authPlugin from './auth.plugin.js';
import type { DrizzleDb } from '@/plugins/db.js';

const SECRET = 'test-secret-for-auth-plugin';

function makeDb(isActive: boolean): DrizzleDb {
  return {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        where: vi.fn().mockReturnValue({
          limit: vi.fn().mockResolvedValue([{ isActive }]),
        }),
      }),
    }),
  } as unknown as DrizzleDb;
}

async function buildApp(isActive: boolean) {
  const app = Fastify({ logger: false });
  app.decorate('db', makeDb(isActive));

  await app.register(authPlugin);

  app.get('/protected', { preHandler: [app.verifyJwt] }, async () => ({ ok: true }));

  await app.ready();
  return app;
}

function makeToken(userId: number, role = 'sales', expiresIn: jwt.SignOptions['expiresIn'] = '1h') {
  return jwt.sign({ userId, role, tenantId: 1 }, SECRET, { expiresIn });
}

beforeEach(() => {
  process.env.JWT_SECRET = SECRET;
});

afterEach(async () => {
  vi.clearAllMocks();
  delete process.env.JWT_SECRET;
});

describe('verifyJwt — isActive check (#8)', () => {
  it('allows requests when account is active', async () => {
    const app = await buildApp(true);
    const token = makeToken(1);

    const res = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(200);
    await app.close();
  });

  it('rejects with 401 ACCOUNT_DISABLED when account is inactive', async () => {
    const app = await buildApp(false);
    const token = makeToken(2);

    const res = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: `Bearer ${token}` },
    });

    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'ACCOUNT_DISABLED' });
    await app.close();
  });

  it('rejects with 401 UNAUTHORIZED when token is missing', async () => {
    const app = await buildApp(true);

    const res = await app.inject({ method: 'GET', url: '/protected' });

    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'UNAUTHORIZED' });
    await app.close();
  });

  it('rejects with 401 UNAUTHORIZED when token is expired', async () => {
    const app = await buildApp(true);
    const expiredToken = jwt.sign({ userId: 3, role: 'sales' }, SECRET, { expiresIn: -1 });

    const res = await app.inject({
      method: 'GET',
      url: '/protected',
      headers: { authorization: `Bearer ${expiredToken}` },
    });

    expect(res.statusCode).toBe(401);
    expect(res.json()).toMatchObject({ code: 'UNAUTHORIZED' });
    await app.close();
  });
});
