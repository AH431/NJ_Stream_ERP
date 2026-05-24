import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { DrizzleDb } from '@/plugins/db.js';

// ── helpers ──────────────────────────────────────────────────────────────────

function makeDb(leaseRows: unknown[] = []): DrizzleDb {
  return {
    execute: vi.fn().mockResolvedValue(leaseRows),
  } as unknown as DrizzleDb;
}

function makeFetch(status: number, body: unknown = {}): typeof fetch {
  return vi.fn().mockResolvedValue({
    ok:     status >= 200 && status < 300,
    status,
    json:   () => Promise.resolve(body),
    text:   () => Promise.resolve(JSON.stringify(body)),
  } as Response);
}

// ── tests ─────────────────────────────────────────────────────────────────────

describe('_hasActiveLease', () => {
  it('returns true when DB returns a row', async () => {
    const { _hasActiveLease } = await import('./forecast_scheduler.service.js');
    const db = makeDb([{ '?column?': 1 }]);
    expect(await _hasActiveLease(db, 1)).toBe(true);
  });

  it('returns false when DB returns no rows', async () => {
    const { _hasActiveLease } = await import('./forecast_scheduler.service.js');
    const db = makeDb([]);
    expect(await _hasActiveLease(db, 1)).toBe(false);
  });
});

describe('_triggerForecast', () => {
  beforeEach(() => {
    process.env.AI_SERVICE_URL            = 'http://ai-test:8000';
    process.env.AI_SERVICE_INTERNAL_TOKEN = 'test-token';
  });
  afterEach(() => vi.restoreAllMocks());

  it('resolves on HTTP 200 and logs runId', async () => {
    const { _triggerForecast } = await import('./forecast_scheduler.service.js');
    const mockFetch = makeFetch(200, { runId: 'uuid-1', generated: 5 });
    vi.stubGlobal('fetch', mockFetch);

    const log = { info: vi.fn(), error: vi.fn() };
    await expect(_triggerForecast(1, 12, log)).resolves.toBeUndefined();
    expect(log.info).toHaveBeenCalledWith(
      expect.objectContaining({ tenantId: 1, runId: 'uuid-1', generated: 5 }),
      'scheduler.trigger.ok',
    );
  });

  it('silently returns (no throw) on HTTP 409 already-running', async () => {
    const { _triggerForecast } = await import('./forecast_scheduler.service.js');
    vi.stubGlobal('fetch', makeFetch(409, { detail: 'forecast_job_already_running' }));

    const log = { info: vi.fn(), error: vi.fn() };
    await expect(_triggerForecast(1, 12, log)).resolves.toBeUndefined();
    expect(log.info).toHaveBeenCalledWith(
      expect.objectContaining({ tenantId: 1 }),
      'scheduler.skip.already_running',
    );
  });

  it('throws on HTTP 500', async () => {
    const { _triggerForecast } = await import('./forecast_scheduler.service.js');
    vi.stubGlobal('fetch', makeFetch(500, 'internal error'));

    const log = { info: vi.fn(), error: vi.fn() };
    await expect(_triggerForecast(1, 12, log)).rejects.toThrow('500');
  });
});

describe('runForecastScheduler', () => {
  beforeEach(() => {
    process.env.FORECAST_TENANT_IDS           = '1,2';
    process.env.FORECAST_WEEKS_AHEAD          = '12';
    process.env.AI_SERVICE_URL                = 'http://ai-test:8000';
    process.env.AI_SERVICE_INTERNAL_TOKEN     = 'test-token';
  });
  afterEach(() => vi.restoreAllMocks());

  it('skips tenant when active lease is present', async () => {
    const { runForecastScheduler } = await import('./forecast_scheduler.service.js');
    const mockFetch = vi.fn();
    vi.stubGlobal('fetch', mockFetch);

    // Both tenants have active leases
    const db = makeDb([{ '?column?': 1 }]);
    await runForecastScheduler(db);

    expect(mockFetch).not.toHaveBeenCalled();
  });

  it('calls ai_service for tenants without active lease', async () => {
    const { runForecastScheduler } = await import('./forecast_scheduler.service.js');
    const mockFetch = makeFetch(200, { runId: 'uuid-2', generated: 3 });
    vi.stubGlobal('fetch', mockFetch);

    // No active lease
    const db = makeDb([]);
    await runForecastScheduler(db);

    // Two tenants (1 and 2), each should trigger once
    expect(mockFetch).toHaveBeenCalledTimes(2);
    const firstCall = (mockFetch as ReturnType<typeof vi.fn>).mock.calls[0];
    const body = JSON.parse(firstCall[1].body as string);
    expect(body.triggerType).toBe('scheduler');
  });

  it('catches per-tenant errors and continues to next tenant', async () => {
    const { runForecastScheduler } = await import('./forecast_scheduler.service.js');
    vi.stubGlobal('fetch', makeFetch(500, 'error'));

    const db = makeDb([]);
    // Should not throw even though fetch fails
    await expect(runForecastScheduler(db)).resolves.toBeUndefined();
  });
});
