import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { eq } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';
import { users } from '@/schemas/index.js';
import type { TokenResponse, JwtPayload } from '@/types/auth.js';

const ACCESS_EXPIRES_IN  = Number(process.env.JWT_ACCESS_EXPIRES_IN  ?? 3600);
const REFRESH_EXPIRES_IN = Number(process.env.JWT_REFRESH_EXPIRES_IN ?? 2592000);

// 預先計算的 dummy bcrypt hash，用於帳號不存在時消耗對等的 CPU 時間，
// 防止攻擊者透過 login 回應時間差列舉有效帳號（timing attack）。
// 雜湊內容是隨機字串，永遠不會匹配任何合法密碼。
const DUMMY_HASH = bcrypt.hashSync('dummy-password-not-a-real-credential', 10);

function getSecret(): string {
  const secret = process.env.JWT_SECRET;
  if (!secret) throw new Error('JWT_SECRET is not set');
  return secret;
}

function signAccessToken(payload: JwtPayload): string {
  return jwt.sign(payload, getSecret(), { expiresIn: ACCESS_EXPIRES_IN });
}

function signRefreshToken(payload: JwtPayload): string {
  return jwt.sign(payload, getSecret(), { expiresIn: REFRESH_EXPIRES_IN });
}

// ── Login ──────────────────────────────────────────────────────────────────

export async function login(
  db: DrizzleDb,
  username: string,
  password: string,
): Promise<TokenResponse> {
  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.username, username))
    .limit(1);

  if (!user) {
    // 故意 hash 一次以模擬密碼比對成本，讓「帳號不存在」與「密碼錯誤」耗時相當。
    await bcrypt.compare(password, DUMMY_HASH);
    throw Object.assign(new Error('帳號或密碼錯誤。'), { code: 'INVALID_CREDENTIALS', status: 401 });
  }

  const passwordMatch = await bcrypt.compare(password, user.password);
  if (!passwordMatch) {
    throw Object.assign(new Error('帳號或密碼錯誤。'), { code: 'INVALID_CREDENTIALS', status: 401 });
  }

  if (!user.isActive) {
    throw Object.assign(new Error('此帳號已停用，請聯絡管理員。'), { code: 'ACCOUNT_DISABLED', status: 403 });
  }

  const jwtPayload: JwtPayload = { userId: user.id, role: user.role };
  const accessToken  = signAccessToken(jwtPayload);
  const refreshToken = signRefreshToken(jwtPayload);

  await db
    .update(users)
    .set({ refreshToken })
    .where(eq(users.id, user.id));

  return { accessToken, refreshToken, expiresIn: ACCESS_EXPIRES_IN, role: user.role, userId: user.id };
}

// ── Refresh ────────────────────────────────────────────────────────────────

export async function refresh(
  db: DrizzleDb,
  refreshToken: string,
): Promise<{ accessToken: string; refreshToken: string; expiresIn: number }> {
  let payload: JwtPayload;
  try {
    payload = jwt.verify(refreshToken, getSecret()) as JwtPayload;
  } catch {
    throw Object.assign(new Error('Refresh Token 已過期，請重新登入。'), { code: 'REFRESH_TOKEN_EXPIRED', status: 401 });
  }

  const [user] = await db
    .select()
    .from(users)
    .where(eq(users.id, payload.userId))
    .limit(1);

  if (!user || user.refreshToken !== refreshToken) {
    throw Object.assign(new Error('Refresh Token 已過期，請重新登入。'), { code: 'REFRESH_TOKEN_EXPIRED', status: 401 });
  }

  if (!user.isActive) {
    throw Object.assign(new Error('此帳號已停用，請聯絡管理員。'), { code: 'ACCOUNT_DISABLED', status: 403 });
  }

  // Refresh token rotation：每次刷新都同步換發新的 refresh token，
  // 並覆寫 DB 中存的值，使舊 refresh token 立即失效。
  // 攻擊者若竊取 refresh token，使用過一次後合法使用者下次刷新就會失敗，
  // 讓使用者可察覺帳號被盜用並重新登入。
  const jwtPayload: JwtPayload = { userId: user.id, role: user.role };
  const accessToken = signAccessToken(jwtPayload);
  const newRefreshToken = signRefreshToken(jwtPayload);

  await db
    .update(users)
    .set({ refreshToken: newRefreshToken })
    .where(eq(users.id, user.id));

  return { accessToken, refreshToken: newRefreshToken, expiresIn: ACCESS_EXPIRES_IN };
}

// ── Logout ─────────────────────────────────────────────────────────────────

export async function logout(
  db: DrizzleDb,
  userId: number,
  refreshToken: string,
): Promise<void> {
  const [user] = await db
    .select({ refreshToken: users.refreshToken })
    .from(users)
    .where(eq(users.id, userId))
    .limit(1);

  if (!user || user.refreshToken !== refreshToken) return;

  await db
    .update(users)
    .set({ refreshToken: null })
    .where(eq(users.id, userId));
}
