import { describe, expect, it } from 'vitest';
import {
  hashText,
  redactText,
  createAuditLog,
  finishAuditLog,
  logAuditEvent,
} from './audit.service.js';
import { auditLogs } from '@/schemas/index.js';
import type { DrizzleDb } from '@/plugins/db.js';

// ── Fake DB ────────────────────────────────────────────────────────────────

type AnyRow = Record<string, unknown>;

class FakeDb {
  insertedRows: AnyRow[] = [];
  updatedSets: AnyRow[] = [];
  private nextId = 1;

  insert(_table: unknown) {
    return {
      values: (row: AnyRow) => {
        this.insertedRows.push(row);
        const id = this.nextId++;
        return {
          returning: async (_sel?: unknown) => [{ id }],
        };
      },
    };
  }

  update(_table: unknown) {
    return {
      set: (values: AnyRow) => {
        this.updatedSets.push(values);
        return {
          where: async (_cond?: unknown) => {},
        };
      },
    };
  }
}

function makeDb(): { db: DrizzleDb; fake: FakeDb } {
  const fake = new FakeDb();
  return { db: fake as unknown as DrizzleDb, fake };
}

// ── hashText ───────────────────────────────────────────────────────────────

describe('hashText', () => {
  it('returns a 64-char hex string', () => {
    expect(hashText('hello')).toMatch(/^[0-9a-f]{64}$/);
  });

  it('is deterministic for the same input', () => {
    expect(hashText('IC-8800 現在庫存多少')).toBe(hashText('IC-8800 現在庫存多少'));
  });

  it('differs for different inputs', () => {
    expect(hashText('question A')).not.toBe(hashText('question B'));
  });

  it('handles empty string', () => {
    expect(hashText('')).toHaveLength(64);
  });
});

// ── redactText ─────────────────────────────────────────────────────────────

describe('redactText', () => {
  it('redacts email addresses', () => {
    expect(redactText('請聯絡 sales@example.com 取得報價')).toBe('請聯絡 [EMAIL] 取得報價');
  });

  it('redacts multiple emails in one string', () => {
    const result = redactText('a@a.com 和 b@b.com');
    expect(result).toBe('[EMAIL] 和 [EMAIL]');
  });

  it('redacts TW mobile without separators', () => {
    expect(redactText('電話：0912345678')).toBe('電話：[PHONE]');
  });

  it('redacts TW mobile with hyphens', () => {
    expect(redactText('聯絡：0912-345-678')).toBe('聯絡：[PHONE]');
  });

  it('redacts TW mobile with spaces', () => {
    expect(redactText('0987 654 321')).toBe('[PHONE]');
  });

  it('redacts international TW format', () => {
    expect(redactText('+886912345678')).toBe('[PHONE]');
  });

  it('redacts TW national ID', () => {
    expect(redactText('身分證：A123456789')).toBe('身分證：[ID]');
  });

  it('does not redact unrelated 10-digit numbers', () => {
    const result = redactText('訂單編號：1234567890');
    expect(result).toBe('訂單編號：1234567890');
  });

  it('leaves clean text unchanged', () => {
    expect(redactText('IC-8800 的庫存是多少？')).toBe('IC-8800 的庫存是多少？');
  });

  it('handles combined PII in one string', () => {
    const result = redactText('客戶 John A123456789 電話 0912-345-678 信箱 j@j.com');
    expect(result).toBe('客戶 John [ID] 電話 [PHONE] 信箱 [EMAIL]');
  });
});

// ── createAuditLog ─────────────────────────────────────────────────────────

describe('createAuditLog', () => {
  it('returns the inserted id', async () => {
    const { db } = makeDb();
    const id = await createAuditLog(db, {
      requestId: 'req-001',
      userId:    1,
      userRole:  'sales',
      action:    'ai.chat',
    });
    expect(id).toBe(1);
  });

  it('defaults status to pending', async () => {
    const { db, fake } = makeDb();
    await createAuditLog(db, {
      requestId: 'req-002',
      userId:    2,
      userRole:  'warehouse',
      action:    'ai.chat',
    });
    expect(fake.insertedRows[0]?.status).toBe('pending');
  });

  it('passes questionHash and toolName when provided', async () => {
    const { db, fake } = makeDb();
    await createAuditLog(db, {
      requestId:    'req-003',
      userId:       3,
      userRole:     'admin',
      action:       'ai.tool_call',
      questionHash: hashText('test question'),
      toolName:     'get_inventory',
    });
    const row = fake.insertedRows[0]!;
    expect(row.toolName).toBe('get_inventory');
    expect(typeof row.questionHash).toBe('string');
  });

  it('assigns null to meta when not provided', async () => {
    const { db, fake } = makeDb();
    await createAuditLog(db, {
      requestId: 'req-004',
      userId:    1,
      userRole:  'sales',
      action:    'ai.chat',
    });
    expect(fake.insertedRows[0]?.meta).toBeNull();
  });
});

// ── finishAuditLog ─────────────────────────────────────────────────────────

describe('finishAuditLog', () => {
  it('updates to success with a finishedAt timestamp', async () => {
    const { db, fake } = makeDb();
    await finishAuditLog(db, 1, { status: 'success' });
    const updated = fake.updatedSets[0]!;
    expect(updated.status).toBe('success');
    expect(updated.finishedAt).toBeInstanceOf(Date);
  });

  it('updates to error and stores errorMessage', async () => {
    const { db, fake } = makeDb();
    await finishAuditLog(db, 2, { status: 'error', errorMessage: 'upstream timeout' });
    const updated = fake.updatedSets[0]!;
    expect(updated.status).toBe('error');
    expect(updated.errorMessage).toBe('upstream timeout');
  });

  it('uses provided finishedAt if given', async () => {
    const { db, fake } = makeDb();
    const ts = new Date('2026-01-01T00:00:00Z');
    await finishAuditLog(db, 3, { status: 'blocked', finishedAt: ts });
    expect(fake.updatedSets[0]?.finishedAt).toBe(ts);
  });
});

// ── logAuditEvent ──────────────────────────────────────────────────────────

describe('logAuditEvent', () => {
  it('returns a new id for the leaf event', async () => {
    const { db } = makeDb();
    const id = await logAuditEvent(db, {
      requestId:    'req-010',
      userId:       1,
      userRole:     'sales',
      action:       'ai.tool_call',
      toolName:     'get_inventory',
      resourceType: 'inventory',
      resourceId:   '42',
      status:       'success',
    });
    expect(id).toBe(1);
  });

  it('stores denied status for role restriction events', async () => {
    const { db, fake } = makeDb();
    await logAuditEvent(db, {
      requestId: 'req-011',
      userId:    5,
      userRole:  'warehouse',
      action:    'ai.tool_call',
      toolName:  'get_quotation',
      status:    'denied',
    });
    expect(fake.insertedRows[0]?.status).toBe('denied');
    expect(fake.insertedRows[0]?.userRole).toBe('warehouse');
  });

  it('stores blocked status for blocked queries', async () => {
    const { db, fake } = makeDb();
    await logAuditEvent(db, {
      requestId: 'req-012',
      userId:    3,
      userRole:  'admin',
      action:    'ai.blocked',
      status:    'blocked',
    });
    expect(fake.insertedRows[0]?.action).toBe('ai.blocked');
    expect(fake.insertedRows[0]?.status).toBe('blocked');
  });
});
