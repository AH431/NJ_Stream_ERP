import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

// ── mock firebase-admin ────────────────────────────────────
// 必須在 import fcm.service 之前宣告，確保 mock 生效
vi.mock('firebase-admin', () => {
  const sendEachForMulticast = vi.fn();
  return {
    default: {
      initializeApp: vi.fn(),
      credential: { cert: vi.fn(() => ({})) },
      messaging: () => ({ sendEachForMulticast }),
    },
  };
});

import admin from 'firebase-admin';
import { sendAnomalyNotifications, initFcm } from './fcm.service.js';
import type { NewAnomalyForFcm } from './fcm.service.js';
import type { DrizzleDb } from '@/plugins/db.js';

function makeDb(tokens: string[]): DrizzleDb {
  return {
    execute: vi.fn().mockResolvedValue(tokens.map((t) => ({ token: t }))),
  } as unknown as DrizzleDb;
}

const mockMessaging = admin.messaging() as unknown as { sendEachForMulticast: ReturnType<typeof vi.fn> };

const baseAnomaly: NewAnomalyForFcm = {
  severity: 'critical',
  message: 'test',
  entityType: 'inventory_item',
  alertType: 'STOCK_CRITICAL',
};

beforeEach(() => {
  // 強制重置 _initialized，讓每個 test 可以重新初始化
  vi.resetModules();
  mockMessaging.sendEachForMulticast.mockResolvedValue({
    successCount: 1,
    failureCount: 0,
    responses: [{ success: true }],
  });
});

afterEach(() => {
  vi.clearAllMocks();
});

describe('sendAnomalyNotifications — FCM chunk logic', () => {
  it('calls sendEachForMulticast once when tokens <= 500', async () => {
    // force _initialized = true via FIREBASE_SERVICE_ACCOUNT env + initFcm
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ type: 'service_account' });
    initFcm();

    const tokens = Array.from({ length: 300 }, (_, i) => `token-${i}`);
    // DB returns 300 tokens
    mockMessaging.sendEachForMulticast.mockResolvedValue({
      successCount: 300,
      failureCount: 0,
      responses: tokens.map(() => ({ success: true })),
    });

    const db = makeDb(tokens);
    await sendAnomalyNotifications(db, [baseAnomaly]);

    expect(mockMessaging.sendEachForMulticast).toHaveBeenCalledTimes(1);
    const call = mockMessaging.sendEachForMulticast.mock.calls[0][0];
    expect(call.tokens).toHaveLength(300);
  });

  it('splits into multiple chunks when tokens > 500', async () => {
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ type: 'service_account' });
    initFcm();

    const tokens = Array.from({ length: 1100 }, (_, i) => `token-${i}`);
    mockMessaging.sendEachForMulticast.mockResolvedValue({
      successCount: 500,
      failureCount: 0,
      responses: Array(500).fill({ success: true }),
    });

    const db = makeDb(tokens);
    await sendAnomalyNotifications(db, [baseAnomaly]);

    // 1100 tokens → ceil(1100/500) = 3 chunks (500, 500, 100)
    expect(mockMessaging.sendEachForMulticast).toHaveBeenCalledTimes(3);
    const chunkSizes = mockMessaging.sendEachForMulticast.mock.calls.map(
      (call) => (call[0] as { tokens: string[] }).tokens.length,
    );
    expect(chunkSizes).toEqual([500, 500, 100]);
  });

  it('does not throw when sendEachForMulticast rejects (error is caught and logged)', async () => {
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ type: 'service_account' });
    initFcm();

    mockMessaging.sendEachForMulticast.mockRejectedValue(new Error('Firebase quota exceeded'));

    const db = makeDb(['token-0']);
    const consoleSpy = vi.spyOn(console, 'error').mockImplementation(() => {});

    // Must not throw even though the FCM call fails
    await expect(sendAnomalyNotifications(db, [baseAnomaly])).resolves.toBeUndefined();

    // The error should have been logged as structured JSON
    expect(consoleSpy).toHaveBeenCalledOnce();
    const logged = JSON.parse(consoleSpy.mock.calls[0][0] as string);
    expect(logged).toMatchObject({ level: 'error', job: 'FCM', msg: 'chunk.failed' });
    expect(logged.errorSummary).toContain('Firebase quota exceeded');

    consoleSpy.mockRestore();
    delete process.env.FIREBASE_SERVICE_ACCOUNT;
  });

  it('removes invalid tokens collected across all chunks', async () => {
    process.env.FIREBASE_SERVICE_ACCOUNT = JSON.stringify({ type: 'service_account' });
    initFcm();

    const tokens = Array.from({ length: 600 }, (_, i) => `token-${i}`);
    // chunk 1 (500 tokens): token-0 is invalid
    // chunk 2 (100 tokens): token-500 is invalid
    mockMessaging.sendEachForMulticast
      .mockResolvedValueOnce({
        successCount: 499,
        failureCount: 1,
        responses: Array(500).fill({ success: true }).map((r, i) =>
          i === 0
            ? { success: false, error: { code: 'messaging/registration-token-not-registered' } }
            : r,
        ),
      })
      .mockResolvedValueOnce({
        successCount: 99,
        failureCount: 1,
        responses: Array(100).fill({ success: true }).map((r, i) =>
          i === 0
            ? { success: false, error: { code: 'messaging/invalid-registration-token' } }
            : r,
        ),
      });

    const dbExecute = vi.fn()
      .mockResolvedValueOnce(tokens.map((t) => ({ token: t }))) // token query
      .mockResolvedValueOnce([]); // DELETE query

    const db = { execute: dbExecute } as unknown as DrizzleDb;
    await sendAnomalyNotifications(db, [baseAnomaly]);

    // DELETE should have been called with 2 invalid tokens
    expect(dbExecute).toHaveBeenCalledTimes(2);
    const deleteCall = dbExecute.mock.calls[1][0];
    // The DELETE sql template is called with the invalidTokens array
    expect(deleteCall).toBeDefined();
  });
});
