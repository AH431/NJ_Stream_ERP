/**
 * PR-6 M6.5 — Tenant Isolation Tests
 *
 * Verifies that every authenticated route scopes its DB queries to the tenant
 * stored in the JWT, and that INSERT operations stamp the correct tenantId.
 *
 * Strategy:
 *   • vi.mock tenant.service so tenantFilter / requireTenantId are spies.
 *   • FakeDb uses a Proxy-based chainable that resolves to [].
 *   • INSERT calls are captured in FakeDb.insertedRows for assertion.
 *   • Relational findFirst returns null → routes return 404 (isolation).
 *
 * API categories covered (spec: 5+):
 *   1. Customers  — GET list
 *   2. Customers  — POST create
 *   3. Products   — GET list
 *   4. Products   — POST create
 *   5. Inventory  — GET by productId
 *   6. Sales Orders — GET /:id (cross-tenant 404)
 */

import { beforeEach, describe, expect, it, vi } from 'vitest';
import Fastify from 'fastify';
import fp from 'fastify-plugin';
import type { DrizzleDb } from '@/plugins/db.js';
import type { JwtPayload } from '@/types/auth.js';

// ── Spy on tenant.service ─────────────────────────────────────────────────────
// vi.mock is hoisted; factory runs lazily so vi.fn() instances are created once.
vi.mock('@/services/tenant.service.js', () => ({
  requireTenantId: vi.fn((req: any): number => req.user.tenantId),
  // Returns undefined → Drizzle's and() filters it out; FakeDb never executes SQL.
  tenantFilter: vi.fn((_col: any, _tenantId: number): undefined => undefined),
}));

import * as tenantService from '@/services/tenant.service.js';
import customersRoutes   from '@/routes/customers.route.js';
import productsRoutes    from '@/routes/products.route.js';
import inventoryRoutes   from '@/routes/inventory.route.js';
import salesOrdersRoutes from '@/routes/sales_orders.route.js';

// ── FakeDb ────────────────────────────────────────────────────────────────────

type AnyRow = Record<string, unknown>;

/**
 * A Proxy-based Drizzle stub.
 * Every method call returns a new chainable Proxy that resolves to `rows` when awaited.
 * INSERT calls push the row into `insertedRows` for assertion.
 */
function makeChainable(rows: AnyRow[] = []): any {
  return new Proxy(
    {},
    {
      get(_t, prop) {
        if (prop === 'then') {
          return (resolve: (v: AnyRow[]) => void) => resolve(rows);
        }
        if (prop === 'catch') return () => Promise.resolve(rows);
        return () => makeChainable(rows);
      },
    },
  );
}

class FakeDb {
  insertedRows: AnyRow[] = [];

  select(_cols?: unknown) {
    return makeChainable();
  }

  query = {
    salesOrders:   { findFirst: async (_opts?: unknown) => null },
    quotations:    { findFirst: async (_opts?: unknown) => null },
    customers:     { findFirst: async (_opts?: unknown) => null },
    products:      { findFirst: async (_opts?: unknown) => null },
    inventoryItems:{ findFirst: async (_opts?: unknown) => null },
  };

  insert(_table: unknown) {
    return {
      values: (row: AnyRow) => {
        this.insertedRows.push(row);
        return { returning: async (_sel?: unknown) => [{ id: 999, ...row }] };
      },
    };
  }

  update(_table: unknown) {
    return {
      set: (_v: unknown) => ({ where: async () => {} }),
    };
  }

  execute(_sql: unknown) {
    return Promise.resolve([]);
  }
}

// ── App builder ───────────────────────────────────────────────────────────────

function buildApp(routePlugin: any, fakeUser: JwtPayload | null) {
  const fake = new FakeDb();
  const app  = Fastify({ logger: false });

  app.decorate('db', fake as unknown as DrizzleDb);

  app.register(fp(async (instance) => {
    instance.decorateRequest('user', null as any);
    instance.decorate('verifyJwt', async (req: any, rep: any) => {
      if (!fakeUser) {
        return rep.status(401).send({ code: 'UNAUTHORIZED', message: 'token required' });
      }
      req.user = fakeUser;
    });
    instance.decorate('requireRole', () => async () => {});
  }, { name: 'auth' }));

  app.register(routePlugin);
  return { app, fake };
}

// ── Shared JWT payloads ───────────────────────────────────────────────────────

const T1_USER: JwtPayload = { userId: 1, tenantId: 1, role: 'admin' };
const T2_USER: JwtPayload = { userId: 2, tenantId: 2, role: 'admin' };

// ── Tests ─────────────────────────────────────────────────────────────────────

beforeEach(() => {
  vi.mocked(tenantService.tenantFilter).mockClear();
  vi.mocked(tenantService.requireTenantId).mockClear();
});

// ── 1 & 2. Customers ─────────────────────────────────────────────────────────

describe('Customers — tenant isolation', () => {
  it('GET /: scopes list query to the tenantId in the JWT', async () => {
    const { app } = buildApp(customersRoutes, T2_USER);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/' });

    expect(res.statusCode).toBe(200);
    expect(vi.mocked(tenantService.tenantFilter))
      .toHaveBeenCalledWith(expect.anything(), T2_USER.tenantId);
  });

  it('GET /: tenant 2 query uses tenantId 2, not tenant 1', async () => {
    const { app: app1 } = buildApp(customersRoutes, T1_USER);
    const { app: app2 } = buildApp(customersRoutes, T2_USER);
    await Promise.all([app1.ready(), app2.ready()]);

    await app1.inject({ method: 'GET', url: '/' });
    const t1Call = vi.mocked(tenantService.tenantFilter).mock.calls.at(-1)?.[1];

    vi.mocked(tenantService.tenantFilter).mockClear();

    await app2.inject({ method: 'GET', url: '/' });
    const t2Call = vi.mocked(tenantService.tenantFilter).mock.calls.at(-1)?.[1];

    expect(t1Call).toBe(1);
    expect(t2Call).toBe(2);
    expect(t1Call).not.toBe(t2Call);
  });

  it('POST /: stamps tenantId from JWT on the created row', async () => {
    const { app, fake } = buildApp(customersRoutes, T2_USER);
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/',
      headers: { 'content-type': 'application/json' },
      payload: JSON.stringify({ name: 'Tenant 2 Corp' }),
    });

    expect(res.statusCode).toBe(201);
    expect(fake.insertedRows).toHaveLength(1);
    expect(fake.insertedRows[0]).toMatchObject({ tenantId: T2_USER.tenantId });
    expect(fake.insertedRows[0].tenantId).not.toBe(T1_USER.tenantId);
  });
});

// ── 3 & 4. Products ──────────────────────────────────────────────────────────

describe('Products — tenant isolation', () => {
  it('GET /: scopes list query to the tenantId in the JWT', async () => {
    const { app } = buildApp(productsRoutes, T2_USER);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/' });

    expect(res.statusCode).toBe(200);
    expect(vi.mocked(tenantService.tenantFilter))
      .toHaveBeenCalledWith(expect.anything(), T2_USER.tenantId);
  });

  it('POST /: stamps tenantId from JWT on the created row', async () => {
    const { app, fake } = buildApp(productsRoutes, T2_USER);
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/',
      headers: { 'content-type': 'application/json' },
      payload: JSON.stringify({ name: 'T2 Widget', sku: 'T2-WGT-001', unitPrice: '99.00' }),
    });

    expect(res.statusCode).toBe(201);
    expect(fake.insertedRows).toHaveLength(1);
    expect(fake.insertedRows[0]).toMatchObject({ tenantId: T2_USER.tenantId });
  });
});

// ── 5. Inventory ──────────────────────────────────────────────────────────────

describe('Inventory — tenant isolation', () => {
  it('GET /?productId=1: scopes inventory query to tenantId in JWT', async () => {
    const { app } = buildApp(inventoryRoutes, T2_USER);
    await app.ready();

    // FakeDb returns [] → row is undefined → 404 (expected, no data seeded)
    const res = await app.inject({ method: 'GET', url: '/?productId=1' });

    expect(res.statusCode).toBe(404);
    expect(vi.mocked(tenantService.tenantFilter))
      .toHaveBeenCalledWith(expect.anything(), T2_USER.tenantId);
  });
});

// ── 6. Sales Orders — cross-tenant 404 ────────────────────────────────────────

describe('Sales Orders — cross-tenant isolation', () => {
  it('GET /:id: returns 404 — order not visible to requesting tenant', async () => {
    // FakeDb.query.salesOrders.findFirst always returns null,
    // simulating "no matching row for this tenant's filter".
    const { app } = buildApp(salesOrdersRoutes, T2_USER);
    await app.ready();

    const res = await app.inject({ method: 'GET', url: '/1' });

    expect(res.statusCode).toBe(404);
    expect(JSON.parse(res.body)).toMatchObject({ code: 'NOT_FOUND' });
    // tenantFilter must have been called to scope the query to tenant 2
    expect(vi.mocked(tenantService.tenantFilter))
      .toHaveBeenCalledWith(expect.anything(), T2_USER.tenantId);
  });
});

// ── 7. Auth Guard ─────────────────────────────────────────────────────────────

describe('Auth Guard — unauthenticated requests are rejected', () => {
  const authCases = [
    { name: 'GET /customers',         plugin: customersRoutes, method: 'GET', url: '/' },
    { name: 'GET /products',          plugin: productsRoutes,  method: 'GET', url: '/' },
    { name: 'GET /inventory?productId', plugin: inventoryRoutes, method: 'GET', url: '/?productId=1' },
  ];

  it.each(authCases)('$name returns 401', async ({ plugin, method, url }) => {
    const { app } = buildApp(plugin, null);
    await app.ready();
    const res = await app.inject({ method: method as any, url });
    expect(res.statusCode).toBe(401);
  });
});
