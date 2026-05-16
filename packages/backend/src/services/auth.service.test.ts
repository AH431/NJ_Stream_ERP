import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import * as authService from './auth.service.js';
import type { DrizzleDb } from '@/plugins/db.js';

type AnyRow = Record<string, unknown>;

// ── Fake DB ────────────────────────────────────────────────────────────────
// 模擬 Drizzle 的 select/update/where chain；只要支援 auth.service 用到的方法即可。

class FakeDb {
  userRows: AnyRow[] = [];
  updates: AnyRow[] = [];
  updateConditions: unknown[] = [];

  insert(_table: unknown) {
    throw new Error('FakeDb.insert not used by auth.service');
  }

  select(_columns?: unknown) {
    return {
      from: (_table: unknown) => ({
        where: (_cond?: unknown) => ({
          limit: async (_n: number) => this.userRows,
        }),
      }),
    };
  }

  update(_table: unknown) {
    return {
      set: (values: AnyRow) => ({
        where: async (cond?: unknown) => {
          this.updates.push(values);
          this.updateConditions.push(cond);
          return [];
        },
      }),
    };
  }
}

function makeDb(): { db: DrizzleDb; fake: FakeDb } {
  const fake = new FakeDb();
  return { db: fake as unknown as DrizzleDb, fake };
}

const SECRET = 'test-secret-not-for-production';

beforeEach(() => {
  process.env.JWT_SECRET = SECRET;
  // 縮短測試用 expiry 以加速 token 比較
  process.env.JWT_ACCESS_EXPIRES_IN  = '3600';
  process.env.JWT_REFRESH_EXPIRES_IN = '2592000';
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ── login: timing-safe path for non-existent accounts ──────────────────────

describe('login', () => {
  it('returns INVALID_CREDENTIALS and consumes a bcrypt compare cycle when account does not exist', async () => {
    const { db, fake } = makeDb();
    fake.userRows = []; // 帳號不存在

    // spy bcrypt.compare 以驗證即使帳號不存在也會走過比對流程（避免 timing oracle）
    const compareSpy = vi.spyOn(bcrypt, 'compare');

    await expect(
      authService.login(db, 'no-such-user', 'somepassword'),
    ).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS', status: 401 });

    // 即使帳號不存在，也必須做一次 bcrypt.compare（消除 timing diff）
    expect(compareSpy).toHaveBeenCalledTimes(1);
    // 比對對象必須是合法的 bcrypt hash（$2 開頭），證明真的有跑 hash 比對
    const targetHash = String(compareSpy.mock.calls[0]?.[1] ?? '');
    expect(targetHash).toMatch(/^\$2[aby]\$/);
  });

  it('returns INVALID_CREDENTIALS when password does not match', async () => {
    const { db, fake } = makeDb();
    const hash = await bcrypt.hash('correct-password', 10);
    fake.userRows = [{
      id: 1, username: 'alice', password: hash, role: 'sales', isActive: true,
    }];

    await expect(
      authService.login(db, 'alice', 'wrong-password'),
    ).rejects.toMatchObject({ code: 'INVALID_CREDENTIALS', status: 401 });
  });

  it('returns tokens on successful login and persists refreshToken', async () => {
    const { db, fake } = makeDb();
    const hash = await bcrypt.hash('correct-password', 10);
    fake.userRows = [{
      id: 7, username: 'alice', password: hash, role: 'sales', isActive: true,
    }];

    const tokens = await authService.login(db, 'alice', 'correct-password');

    expect(tokens.accessToken).toBeTruthy();
    expect(tokens.refreshToken).toBeTruthy();
    expect(tokens.userId).toBe(7);
    expect(tokens.role).toBe('sales');
    // refreshToken 應該被寫入 DB
    expect(fake.updates).toHaveLength(1);
    expect(fake.updates[0].refreshToken).toBe(tokens.refreshToken);
  });

  it('rejects login when account is disabled', async () => {
    const { db, fake } = makeDb();
    const hash = await bcrypt.hash('correct-password', 10);
    fake.userRows = [{
      id: 1, username: 'alice', password: hash, role: 'sales', isActive: false,
    }];

    await expect(
      authService.login(db, 'alice', 'correct-password'),
    ).rejects.toMatchObject({ code: 'ACCOUNT_DISABLED', status: 403 });
  });
});

// ── refresh: token rotation ────────────────────────────────────────────────

describe('refresh', () => {
  it('rotates the refresh token: returns a new one and overwrites it in DB', async () => {
    const { db, fake } = makeDb();
    // 用 60 秒前的 iat 簽舊 token，確保旋轉後 iat 不同 → 簽出來的 token 必不同
    const pastIat = Math.floor(Date.now() / 1000) - 60;
    const oldRefresh = jwt.sign(
      { userId: 5, role: 'sales', iat: pastIat },
      SECRET,
      { expiresIn: '30d' },
    );
    fake.userRows = [{
      id: 5, username: 'bob', role: 'sales', isActive: true, refreshToken: oldRefresh,
    }];

    const result = await authService.refresh(db, oldRefresh);

    expect(result.accessToken).toBeTruthy();
    expect(result.refreshToken).toBeTruthy();
    expect(result.refreshToken).not.toBe(oldRefresh);
    expect(result.expiresIn).toBe(3600);

    // DB 中存的 refresh token 必須被換成新值（舊的立即失效）
    expect(fake.updates).toHaveLength(1);
    expect(fake.updates[0].refreshToken).toBe(result.refreshToken);
  });

  it('rejects a stale refresh token that was already rotated', async () => {
    const { db, fake } = makeDb();
    const nowSec = Math.floor(Date.now() / 1000);
    // 兩個 token 用不同 iat 確保 JWT 簽出來不同（避免 1 秒粒度衝突）
    const staleRefresh   = jwt.sign({ userId: 5, role: 'sales', iat: nowSec - 120 }, SECRET, { expiresIn: '30d' });
    const currentRefresh = jwt.sign({ userId: 5, role: 'sales', iat: nowSec - 60  }, SECRET, { expiresIn: '30d' });

    // DB 已紀錄較新的 currentRefresh
    fake.userRows = [{
      id: 5, username: 'bob', role: 'sales', isActive: true, refreshToken: currentRefresh,
    }];

    // 攻擊者拿著舊的 staleRefresh 來換 → 應被拒絕
    await expect(
      authService.refresh(db, staleRefresh),
    ).rejects.toMatchObject({ code: 'REFRESH_TOKEN_EXPIRED', status: 401 });
    // 沒有任何 DB 更新（不能因為攻擊者請求而換發合法使用者的 token）
    expect(fake.updates).toHaveLength(0);
  });

  it('rejects an invalid (malformed/expired) refresh token', async () => {
    const { db } = makeDb();
    await expect(
      authService.refresh(db, 'not-a-real-jwt'),
    ).rejects.toMatchObject({ code: 'REFRESH_TOKEN_EXPIRED', status: 401 });
  });

  it('rejects refresh when account is disabled', async () => {
    const { db, fake } = makeDb();
    const refreshToken = jwt.sign({ userId: 5, role: 'sales' }, SECRET, { expiresIn: '30d' });
    fake.userRows = [{
      id: 5, username: 'bob', role: 'sales', isActive: false, refreshToken,
    }];

    await expect(
      authService.refresh(db, refreshToken),
    ).rejects.toMatchObject({ code: 'ACCOUNT_DISABLED', status: 403 });
  });
});
