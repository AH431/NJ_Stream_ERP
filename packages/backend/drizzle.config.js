import { defineConfig } from 'drizzle-kit';
import 'dotenv/config';

export default defineConfig({
  dialect: 'postgresql',
  // Use a generated JS schema mirror so local Drizzle commands avoid TS/esbuild startup on Windows.
  schema: './.drizzle-schema/index.js',
  out: './drizzle',
  dbCredentials: {
    url: process.env.DATABASE_URL,
  },
  verbose: true,
  strict: true,
});
