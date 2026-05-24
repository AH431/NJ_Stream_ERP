/**
 * ForecastScheduler — Phase 4 PR-4
 *
 * Runs in-process (setInterval) and enqueues a forecast job for each configured
 * tenant by calling the ai_service POST /forecast/generate endpoint.
 *
 * Concurrency guard: ai_service uses pg_advisory_xact_lock(tenant_id) so a
 * second concurrent request for the same tenant will receive HTTP 409 and be
 * silently skipped.  No duplicate running jobs can exist.
 *
 * Configuration (env vars):
 *   FORECAST_TENANT_IDS          — comma-separated tenant IDs, default "1"
 *   FORECAST_SCHEDULE_INTERVAL_MS — polling interval ms, default 21600000 (6 h)
 *   FORECAST_WEEKS_AHEAD          — weeks to forecast, default 12
 *   AI_SERVICE_URL                — base URL of ai_service
 *   AI_SERVICE_INTERNAL_TOKEN     — shared bearer token
 */

import type { FastifyBaseLogger } from 'fastify';
import type { DrizzleDb } from '@/plugins/db.js';
import { sql } from 'drizzle-orm';

// ── Config ──────────────────────────────────────────────────────────────────

export interface SchedulerConfig {
  intervalMs:         number;
  tenantsToSchedule:  number[];
  weeksAhead:         number;
}

function _loadConfig(): SchedulerConfig {
  const rawIds   = process.env.FORECAST_TENANT_IDS ?? '1';
  const tenants  = rawIds.split(',').map((s) => parseInt(s.trim(), 10)).filter((n) => !isNaN(n));
  const interval = parseInt(process.env.FORECAST_SCHEDULE_INTERVAL_MS ?? '21600000', 10);
  const weeks    = parseInt(process.env.FORECAST_WEEKS_AHEAD ?? '12', 10);
  return {
    intervalMs:        isNaN(interval) ? 21_600_000 : interval,
    tenantsToSchedule: tenants.length ? tenants : [1],
    weeksAhead:        isNaN(weeks) ? 12 : weeks,
  };
}

// ── Logger helper (mirrors anomaly_scanner pattern) ─────────────────────────

type _JobLog = { info(obj: object, msg?: string): void; error(obj: object, msg?: string): void };

function _makeLog(log: FastifyBaseLogger | undefined): _JobLog {
  const prefix = { job: 'ForecastScheduler' };
  if (log) {
    const child = log.child(prefix);
    return { info: (o, m) => child.info(o, m), error: (o, m) => child.error(o, m) };
  }
  return {
    info:  (o) => console.log(JSON.stringify({ level: 'info',  ...prefix, ...o })),
    error: (o) => console.error(JSON.stringify({ level: 'error', ...prefix, ...o })),
  };
}

// ── Active-lease check (advisory lock) ──────────────────────────────────────

export async function _hasActiveLease(db: DrizzleDb, tenantId: number): Promise<boolean> {
  const rows = await db.execute(sql`
    SELECT 1 FROM forecast_jobs
    WHERE tenant_id = ${tenantId}
      AND status = 'running'
      AND lease_expires_at > NOW()
    LIMIT 1
  `);
  return rows.length > 0;
}

// ── Trigger one forecast run via ai_service ──────────────────────────────────

export async function _triggerForecast(
  tenantId:   number,
  weeksAhead: number,
  log:        _JobLog,
): Promise<void> {
  const baseUrl = process.env.AI_SERVICE_URL ?? 'http://localhost:8000';
  const token   = process.env.AI_SERVICE_INTERNAL_TOKEN ?? '';

  const url = `${baseUrl}/forecast/generate`;
  const body = JSON.stringify({
    tenantId,
    weeksAhead,
    triggerType: 'scheduler',
  });

  const res = await fetch(url, {
    method:  'POST',
    headers: {
      'Content-Type':    'application/json',
      'x-internal-token': token,
    },
    body,
    signal: AbortSignal.timeout(120_000),
  });

  if (res.status === 409) {
    log.info({ tenantId }, 'scheduler.skip.already_running');
    return;
  }
  if (!res.ok) {
    const text = await res.text().catch(() => '');
    throw new Error(`ai_service returned ${res.status}: ${text.slice(0, 200)}`);
  }
  const data = await res.json() as { runId?: string; generated?: number };
  log.info({ tenantId, runId: data.runId, generated: data.generated }, 'scheduler.trigger.ok');
}

// ── Main entry ───────────────────────────────────────────────────────────────

export async function runForecastScheduler(
  db:  DrizzleDb,
  log?: FastifyBaseLogger,
): Promise<void> {
  const cfg = _loadConfig();
  const jl  = _makeLog(log);

  jl.info({ tenants: cfg.tenantsToSchedule, weeksAhead: cfg.weeksAhead }, 'scheduler.tick.start');

  for (const tenantId of cfg.tenantsToSchedule) {
    try {
      const active = await _hasActiveLease(db, tenantId);
      if (active) {
        jl.info({ tenantId }, 'scheduler.skip.lease_active');
        continue;
      }
      await _triggerForecast(tenantId, cfg.weeksAhead, jl);
    } catch (err) {
      jl.error({
        tenantId,
        error: err instanceof Error ? err.message : String(err),
      }, 'scheduler.tick.error');
    }
  }

  jl.info({ tenants: cfg.tenantsToSchedule }, 'scheduler.tick.done');
}
