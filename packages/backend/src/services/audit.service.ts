import { createHash } from 'node:crypto';
import { eq } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';
import { auditLogs } from '@/schemas/index.js';
import type { AuditAction, AuditStatus } from '@/schemas/audit_logs.schema.js';

// ── Pure helpers ───────────────────────────────────────────────────────────

export function hashText(text: string): string {
  return createHash('sha256').update(text).digest('hex');
}

const EMAIL_RE = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/g;
const PHONE_TW = /(?:\+886|0)9\d{2}[-\s]?\d{3}[-\s]?\d{3}/g;
const ID_TW    = /\b[A-Z]\d{9}\b/g;

export function redactText(text: string): string {
  return text
    .replace(EMAIL_RE, '[EMAIL]')
    .replace(PHONE_TW, '[PHONE]')
    .replace(ID_TW, '[ID]');
}

// ── createAuditLog ─────────────────────────────────────────────────────────

export interface CreateAuditParams {
  requestId:    string;
  userId:       number;
  userRole:     string;
  action:       AuditAction;
  status?:      AuditStatus;
  questionHash?: string;
  resourceType?: string;
  resourceId?:  string;
  toolName?:    string;
  meta?:        Record<string, unknown>;
}

export async function createAuditLog(
  db: DrizzleDb,
  params: CreateAuditParams,
): Promise<number> {
  const [row] = await db
    .insert(auditLogs)
    .values({
      requestId:    params.requestId,
      userId:       params.userId,
      userRole:     params.userRole,
      action:       params.action,
      status:       params.status ?? 'pending',
      questionHash: params.questionHash,
      resourceType: params.resourceType,
      resourceId:   params.resourceId,
      toolName:     params.toolName,
      meta:         params.meta ?? null,
    })
    .returning({ id: auditLogs.id });
  return row.id;
}

// ── finishAuditLog ─────────────────────────────────────────────────────────

export interface FinishAuditParams {
  status:        AuditStatus;
  errorMessage?: string;
  finishedAt?:   Date;
}

export async function finishAuditLog(
  db: DrizzleDb,
  id: number,
  params: FinishAuditParams,
): Promise<void> {
  await db
    .update(auditLogs)
    .set({
      status:       params.status,
      errorMessage: params.errorMessage,
      finishedAt:   params.finishedAt ?? new Date(),
    })
    .where(eq(auditLogs.id, id));
}

// ── logAuditEvent ──────────────────────────────────────────────────────────

export interface LogAuditEventParams {
  requestId:    string;
  userId:       number;
  userRole:     string;
  action:       AuditAction;
  toolName?:    string;
  resourceType?: string;
  resourceId?:  string;
  status:       AuditStatus;
  errorMessage?: string;
  meta?:        Record<string, unknown>;
}

export async function logAuditEvent(
  db: DrizzleDb,
  params: LogAuditEventParams,
): Promise<number> {
  const [row] = await db
    .insert(auditLogs)
    .values({
      requestId:    params.requestId,
      userId:       params.userId,
      userRole:     params.userRole,
      action:       params.action,
      toolName:     params.toolName,
      resourceType: params.resourceType,
      resourceId:   params.resourceId,
      status:       params.status,
      errorMessage: params.errorMessage,
      meta:         params.meta ?? null,
    })
    .returning({ id: auditLogs.id });
  return row.id;
}
