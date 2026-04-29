import { afterEach, describe, expect, it, vi } from 'vitest';
import Fastify from 'fastify';
import fp from 'fastify-plugin';
import aiRoutes from './ai.route.js';
import type { DrizzleDb } from '@/plugins/db.js';
import type { JwtPayload } from '@/types/auth.js';

// ── Fake DB ────────────────────────────────────────────────────────────────────

type AnyRow = Record<string, unknown>;

class FakeDb {
  insertedRows: AnyRow[] = [];
  updatedSets:  AnyRow[] = [];
  private nextId = 1;

  insert(_table: unknown) {
    return {
      values: (row: AnyRow) => {
        this.insertedRows.push(row);
        const id = this.nextId++;
        return { returning: async (_sel?: unknown) => [{ id }] };
      },
    };
  }

  update(_table: unknown) {
    return {
      set: (values: AnyRow) => {
        this.updatedSets.push(values);
        return { where: async (_cond?: unknown) => {} };
      },
    };
  }
}

// ── Build minimal test app ─────────────────────────────────────────────────────

function buildTestApp(fakeUser: JwtPayload | null) {
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

  app.register(aiRoutes);

  return { app, fake };
}

// ── Helpers ────────────────────────────────────────────────────────────────────

function makeFakeUpstreamOk(chunks: string[]): Response {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      for (const chunk of chunks) {
        controller.enqueue(new TextEncoder().encode(chunk));
      }
      controller.close();
    },
  });
  return new Response(stream, {
    status:  200,
    headers: { 'Content-Type': 'text/event-stream' },
  });
}

const VALID_SSE_CHUNKS = [
  'data: {"type":"token","content":"測試"}\n\n',
  'data: {"type":"done"}\n\n',
];

// ── Tests ──────────────────────────────────────────────────────────────────────

afterEach(() => vi.unstubAllGlobals());

describe('POST /chat — auth & validation', () => {
  it('returns 401 when unauthenticated', async () => {
    const { app } = buildTestApp(null);
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: { 'content-type': 'application/json' },
      body:    JSON.stringify({ question: '測試問題' }),
    });

    expect(res.statusCode).toBe(401);
    expect(res.json().code).toBe('UNAUTHORIZED');
  });

  it('returns 400 when question is missing', async () => {
    const { app } = buildTestApp({ userId: 1, role: 'admin' });
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: { 'content-type': 'application/json' },
      body:    JSON.stringify({}),
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('VALIDATION_ERROR');
  });

  it('returns 400 when question is empty string', async () => {
    const { app } = buildTestApp({ userId: 1, role: 'warehouse' });
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: { 'content-type': 'application/json' },
      body:    JSON.stringify({ question: '' }),
    });

    expect(res.statusCode).toBe(400);
    expect(res.json().code).toBe('VALIDATION_ERROR');
  });

  it('does not write audit log when body is invalid', async () => {
    const { app, fake } = buildTestApp({ userId: 1, role: 'admin' });
    await app.ready();

    await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: { 'content-type': 'application/json' },
      body:    JSON.stringify({ question: '' }),
    });

    expect(fake.insertedRows).toHaveLength(0);
  });
});

describe('POST /chat — SSE proxy', () => {
  it('proxies SSE stream and updates audit to success', async () => {
    vi.stubGlobal('fetch', async () => makeFakeUpstreamOk(VALID_SSE_CHUNKS));

    const user: JwtPayload = { userId: 7, role: 'sales' };
    const { app, fake } = buildTestApp(user);
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: {
        'content-type':  'application/json',
        'authorization': 'Bearer fake.jwt.token',
      },
      body: JSON.stringify({ question: 'IC-8800 庫存？' }),
    });

    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain('text/event-stream');
    expect(res.body).toContain('data:');

    // Audit created with pending status
    const inserted = fake.insertedRows[0]!;
    expect(inserted.action).toBe('ai.chat');
    expect(inserted.status).toBe('pending');
    expect(inserted.userId).toBe(7);
    expect(inserted.userRole).toBe('sales');
    expect(typeof inserted.questionHash).toBe('string');
    expect((inserted.questionHash as string).length).toBe(64);

    // Audit finalized to success
    const updated = fake.updatedSets[0]!;
    expect(updated.status).toBe('success');
    expect(updated.finishedAt).toBeInstanceOf(Date);
  });

  it('forwards X-Internal-Token and body to ai_service', async () => {
    let capturedInput: RequestInit | undefined;
    vi.stubGlobal('fetch', async (_url: string, init: RequestInit) => {
      capturedInput = init;
      return makeFakeUpstreamOk(VALID_SSE_CHUNKS);
    });

    const { app } = buildTestApp({ userId: 3, role: 'admin' });
    await app.ready();

    await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: {
        'content-type':  'application/json',
        'authorization': 'Bearer my.test.jwt',
      },
      body: JSON.stringify({ question: '測試轉發' }),
    });

    const headers = capturedInput?.headers as Record<string, string>;
    expect(headers['Content-Type']).toBe('application/json');
    expect(typeof headers['X-Internal-Token']).toBe('string');

    const body = JSON.parse(capturedInput?.body as string);
    expect(body.question).toBe('測試轉發');
    expect(body.userJwt).toBe('my.test.jwt');
    expect(body.role).toBe('admin');
    expect(body.userId).toBe(3);
    expect(typeof body.requestId).toBe('string');
  });

  it('returns 503 and updates audit to error when ai_service is unreachable', async () => {
    vi.stubGlobal('fetch', async () => { throw new Error('ECONNREFUSED'); });

    const { app, fake } = buildTestApp({ userId: 7, role: 'sales' });
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: {
        'content-type':  'application/json',
        'authorization': 'Bearer fake.jwt.token',
      },
      body: JSON.stringify({ question: 'IC-8800 庫存？' }),
    });

    expect(res.statusCode).toBe(503);
    expect(res.json().code).toBe('AI_SERVICE_UNAVAILABLE');

    const updated = fake.updatedSets[0]!;
    expect(updated.status).toBe('error');
    expect(updated.finishedAt).toBeInstanceOf(Date);
  });

  it('returns 503 and updates audit to error when ai_service returns non-ok status', async () => {
    vi.stubGlobal('fetch', async () => new Response('{"detail":"forbidden"}', {
      status:  403,
      headers: { 'Content-Type': 'application/json' },
    }));

    const { app, fake } = buildTestApp({ userId: 7, role: 'sales' });
    await app.ready();

    const res = await app.inject({
      method:  'POST',
      url:     '/chat',
      headers: {
        'content-type':  'application/json',
        'authorization': 'Bearer fake.jwt.token',
      },
      body: JSON.stringify({ question: 'IC-8800 庫存？' }),
    });

    expect(res.statusCode).toBe(503);
    expect(res.json().code).toBe('AI_SERVICE_ERROR');

    const updated = fake.updatedSets[0]!;
    expect(updated.status).toBe('error');
    expect((updated.errorMessage as string)).toBe('upstream_403');
  });
});
