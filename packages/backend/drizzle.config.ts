import { defineConfig } from 'drizzle-kit';
import 'dotenv/config';

export default defineConfig({
  dialect: 'postgresql',
  // glob 直接指向各 schema 檔案，避免 drizzle-kit CJS 無法解析 ESM .js 擴充名
  schema: './src/schemas/*.schema.ts',
  out: './drizzle',
  dbCredentials: {
    url: process.env.DATABASE_URL!,
  },
  verbose: true,
  strict: true,
});
