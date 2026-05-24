/**
 * PR-7 M7.3 Acceptance — Tenant Route Tests
 *
 * Coverage:
 *   POST /tenant/provision  — 建立新租戶 + admin 帳號
 *   GET  /tenant            — 查詢自己所屬租戶
 *   PATCH /tenant           — 更新租戶資料 + 完成入駐（markAsOnboarded）
 *
 * M7.3 Acceptance sequence (final test):
 *   provision → GET（確認尚未入駐）→ PATCH markAsOnboarded → GET（確認入駐完成）
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import Fastify from 'fastify';
import fp from 'fastify-plugin';
import type { DrizzleDb } from '@/plugins/db.js';
import type { JwtPayload } from '@/types/auth.js';
import tenantRoutes from './tenant.route.js';

// ── Fake auth plugin ──────────────────────────────────────────────────────────

function stubAuth(fakeUser: JwtPayload | null) {
  return fp(async (app) => {
    app.decorateRequest('user', null as any);

    app.decorate('verifyJwt', async (req: any, rep: any) => {
      if (!fakeUser) {
        return rep.status(401).send({ code: 'UNAUTHORIZED', message: 'token required' });
      }
      req.user = fakeUser;
    });

    app.decorate('requireRole', (...roles: string[]) => async (req: any, rep: any) => {
      if (!roles.includes(req.user?.role)) {
        return rep.status(403).send({ code: 'PERMISSION_DENIED', message: 'forbidden' });
      }
    });
  }, { name: 'auth' });
}

// ── Fixture data ──────────────────────────────────────────────────────────────

const TENANT_2 = {
  id: 2,
  name: 'Acme Corp',
  slug: 'acme',
  plan: 'basic' as const,
  isActive: true,
  timezone: 'Asia/Taipei',
  contactEmail: 'admin@acme.local' as string | null,
  onboardedAt: null as Date | null,
  createdAt: new Date('2026-05-23T00:00:00Z'),
};

const USER_3 = {
  id: 3,
  username: 'acme-admin',
  email: 'acme-admin@acme.local',
  role: 'admin',
};

// ── DB factories ──────────────────────────────────────────────────────────────

/**
 * DB mock for POST /provision.
 * - select: slug uniqueness check → returns [] (no conflict) or [{ id }] (conflict)
 * - transaction: first insert = tenant, second insert = user
 */
function makeProvisionDb(slugConflict = false): DrizzleDb {
  const tx = {
    insert: vi.fn()
      .mockImplementationOnce(() => ({
        values: vi.fn().mockReturnValue({
          returning: vi.fn().mockResolvedValue([TENANT_2]),
        }),
      }))
      .mockImplementationOnce(() => ({
        values: vi.fn().mockReturnValue({
          returning: vi.fn().mockResolvedValue([USER_3]),
        }),
      })),
  };

  return {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        where: vi.fn().mockResolvedValue(slugConflict ? [{ id: 1 }] : []),
      }),
    }),
    transaction: vi.fn().mockImplementation((cb: (tx: any) => any) => cb(tx)),
  } as unknown as DrizzleDb;
}

/**
 * Stateful DB mock for GET/PATCH /tenant.
 * select.from.where reads the current `state`.
 * update.set mutates `state` and returning() reflects the change.
 * This allows testing that a PATCH is visible to a subsequent GET.
 */
function makeTenantDb(initial: typeof TENANT_2 = TENANT_2): DrizzleDb {
  let state = { ...initial };

  return {
    select: vi.fn().mockReturnValue({
      from: vi.fn().mockReturnValue({
        where: vi.fn().mockImplementation(() => Promise.resolve([state])),
      }),
    }),
    update: vi.fn().mockReturnValue({
      set: vi.fn().mockImplementation((updates: Record<string, unknown>) => {
        state = { ...state, ...updates };
        return {
          where: vi.fn().mockReturnValue({
            returning: vi.fn().mockImplementation(() => Promise.resolve([state])),
          }),
        };
      }),
    }),
  } as unknown as DrizzleDb;
}

// ── App builder ───────────────────────────────────────────────────────────────

function buildApp(db: DrizzleDb, user: JwtPayload | null) {
  const app = Fastify({ logger: false });
  app.decorate('db', db);
  app.register(stubAuth(user));
  app.register(tenantRoutes, { prefix: '/tenant' });
  return app;
}

// ── Shared JWT payloads ───────────────────────────────────────────────────────

const ADMIN_JWT: JwtPayload = { userId: 3, tenantId: 2, role: 'admin' };
const SALES_JWT: JwtPayload = { userId: 4, tenantId: 2, role: 'sales' };

// ── POST /tenant/provision ────────────────────────────────────────────────────

describe('POST /tenant/provision', () => {
  it('creates new tenant + admin user and returns 201', async () => {
    const app = buildApp(makeProvisionDb(), null);
    await app.ready();

    const res = await app.inject({
      method: 'POST',
      url: '/tenant/provision',
      payload: {
        name: 'Acme Corp',
        slug: 'acme',
        adminUsername: 'acme-admin',
        adminPassword: 'password123',
        timezone: 'Asia/Taipei',
        contactEmail: 'admin@acme.local',
      },
    });

    expect(res.statusCode).toBe(201);
    const body = res.json();
    expect(body.tenant.slug).toBe('acme');
    expect(body.adminUsername).toBe('acme-admin');
    expect(body.adminUserId).toBe(3);

    await app.close();
  });

  it('returns 409 when slug already exists', async () => {
    const app = buildApp(makeProvisionDb(true), null);
    await app.ready();

    const res = await app.inject({
      method: 'POST',
      url: '/tenant/provision',
      payload: {
        name: 'Acme Corp',
        slug: 'acme',
        adminUsername: 'acme-admin',
        adminPassword: 'password123',
      },
    });

    expect(res.statusCode).toBe(409);
    expect(res.json().code).toBe('SLUG_CONFLICT');

    await app.close();
  });

  it('returns 400 when slug contains uppercase or spaces', async () => {
    const app = buildApp(makeProvisionDb(), null);
    await app.ready();

    const res = await app.inject({
      method: 'POST',
      url: '/tenant/provision',
      payload: {
        name: 'Bad Slug Co',
        slug: 'BAD SLUG!',
        adminUsername: 'admin',
        adminPassword: 'password123',
      },
    });

    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('returns 400 when adminPassword is shorter than 8 characters', async () => {
    const app = buildApp(makeProvisionDb(), null);
    await app.ready();

    const res = await app.inject({
      method: 'POST',
      url: '/tenant/provision',
      payload: {
        name: 'Acme Corp',
        slug: 'acme',
        adminUsername: 'acme-admin',
        adminPassword: 'short',
      },
    });

    expect(res.statusCode).toBe(400);
    await app.close();
  });
});

// ── GET /tenant ───────────────────────────────────────────────────────────────

describe('GET /tenant', () => {
  it('returns tenant info for authenticated user', async () => {
    const app = buildApp(makeTenantDb(), ADMIN_JWT);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/tenant' });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.slug).toBe('acme');
    expect(body.onboardedAt).toBeNull();

    await app.close();
  });

  it('returns 401 without JWT', async () => {
    const app = buildApp(makeTenantDb(), null);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/tenant' });

    expect(res.statusCode).toBe(401);
    await app.close();
  });

  it('non-admin role can also GET (all roles allowed)', async () => {
    const app = buildApp(makeTenantDb(), SALES_JWT);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/tenant' });

    expect(res.statusCode).toBe(200);
    await app.close();
  });
});

// ── PATCH /tenant ─────────────────────────────────────────────────────────────

describe('PATCH /tenant', () => {
  it('admin can update name and timezone', async () => {
    const app = buildApp(makeTenantDb(), ADMIN_JWT);
    await app.ready();

    const res = await app.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: { name: 'Acme Corp Ltd', timezone: 'Asia/Tokyo' },
    });

    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.name).toBe('Acme Corp Ltd');
    expect(body.timezone).toBe('Asia/Tokyo');

    await app.close();
  });

  it('markAsOnboarded=true sets onboardedAt to a non-null value', async () => {
    const app = buildApp(makeTenantDb(), ADMIN_JWT);
    await app.ready();

    const res = await app.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: { markAsOnboarded: true },
    });

    expect(res.statusCode).toBe(200);
    expect(res.json().onboardedAt).not.toBeNull();

    await app.close();
  });

  it('returns 403 for non-admin role', async () => {
    const app = buildApp(makeTenantDb(), SALES_JWT);
    await app.ready();

    const res = await app.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: { name: 'Hacker' },
    });

    expect(res.statusCode).toBe(403);
    await app.close();
  });

  it('returns 400 when body is empty (no fields provided)', async () => {
    const app = buildApp(makeTenantDb(), ADMIN_JWT);
    await app.ready();

    const res = await app.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: {},
    });

    expect(res.statusCode).toBe(400);
    await app.close();
  });

  it('returns 401 without JWT', async () => {
    const app = buildApp(makeTenantDb(), null);
    await app.ready();

    const res = await app.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: { name: 'Test' },
    });

    expect(res.statusCode).toBe(401);
    await app.close();
  });
});

// ── M7.3 Acceptance ───────────────────────────────────────────────────────────

describe('M7.3 Acceptance — provision → authenticate → onboard sequence', () => {
  it('full onboarding flow: provision → GET unboarded → PATCH onboard → GET confirms', async () => {
    // Step 1: Provision a brand-new tenant (no auth required)
    const provisionApp = buildApp(makeProvisionDb(), null);
    await provisionApp.ready();

    const provisionRes = await provisionApp.inject({
      method: 'POST',
      url: '/tenant/provision',
      payload: {
        name: 'New Customer Inc',
        slug: 'acme',              // fixture slug
        adminUsername: 'acme-admin',
        adminPassword: 'securepass1',
        timezone: 'Asia/Taipei',
        contactEmail: 'admin@newcustomer.com',
      },
    });

    expect(provisionRes.statusCode).toBe(201);
    const { tenant, adminUserId } = provisionRes.json();
    expect(typeof adminUserId).toBe('number');
    await provisionApp.close();

    // Step 2: Admin logs in — simulate by issuing a JWT for the new tenant
    const adminJwt: JwtPayload = { userId: adminUserId, tenantId: tenant.id, role: 'admin' };
    const db = makeTenantDb({ ...TENANT_2, id: tenant.id, onboardedAt: null });
    const mainApp = buildApp(db, adminJwt);
    await mainApp.ready();

    // Step 3: GET confirms onboardedAt is null (not yet onboarded)
    const getRes1 = await mainApp.inject({ method: 'GET', url: '/tenant' });
    expect(getRes1.statusCode).toBe(200);
    expect(getRes1.json().onboardedAt).toBeNull();

    // Step 4: Admin completes onboarding via 3-step flow → PATCH with markAsOnboarded
    const patchRes = await mainApp.inject({
      method: 'PATCH',
      url: '/tenant',
      payload: {
        name: 'New Customer Inc',
        timezone: 'Asia/Taipei',
        contactEmail: 'admin@newcustomer.com',
        markAsOnboarded: true,
      },
    });
    expect(patchRes.statusCode).toBe(200);
    expect(patchRes.json().onboardedAt).not.toBeNull();

    // Step 5: GET now shows onboardedAt is set (banner will hide in Flutter)
    const getRes2 = await mainApp.inject({ method: 'GET', url: '/tenant' });
    expect(getRes2.statusCode).toBe(200);
    expect(getRes2.json().onboardedAt).not.toBeNull();

    await mainApp.close();
  });
});
