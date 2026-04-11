import jwt from 'jsonwebtoken';
import bcrypt from 'bcryptjs';
import { eq } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';
import { users } from '@/schemas/index.js';
import type { TokenResponse, JwtPayload } from '@/types/auth.js';

const ACCESS_EXPIRES_IN  = Number(process.env.JWT_ACCESS_EXPIRES_IN  ?? 3600);
const REFRESH_EXPIRES_IN = Number(process.env.JWT_REFRESH_EXPIRES_IN ?? 2592000);

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
): Promise<{ accessToken: string; expiresIn: number }> {
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

  const accessToken = signAccessToken({ userId: user.id, role: user.role });
  return { accessToken, expiresIn: ACCESS_EXPIRES_IN };
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
