/**
 * 測試用 seed script — 建立 Issue #23 驗收測試所需帳號
 * 執行: npx tsx scripts/seed-test-user.ts
 * 完成後可刪除此檔案
 */
import 'dotenv/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import bcrypt from 'bcryptjs';
import * as schema from '../src/schemas/index.js';

const sql = postgres(process.env.DATABASE_URL!);
const db = drizzle(sql, { schema });

const HASH_ROUNDS = 10;

await db.insert(schema.users).values([
  {
    username: 'sales_test',
    email: 'sales@test.local',
    password: await bcrypt.hash('P@ssw0rd!', HASH_ROUNDS),
    role: 'sales',
    isActive: true,
  },
  {
    username: 'disabled_user',
    email: 'disabled@test.local',
    password: await bcrypt.hash('P@ssw0rd!', HASH_ROUNDS),
    role: 'sales',
    isActive: false,
  },
]).onConflictDoNothing();

console.log('✅ Test users seeded');
await sql.end();
