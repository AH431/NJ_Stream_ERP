/**
 * Permanent English demo seed for phone testing and Dashboard analytics.
 *
 * Why this file exists:
 *   - `seed-demo-data.ts` was originally introduced during the 2026-04-26
 *     Phase 2 validation session.
 *   - Phone testing later hit an avoidable failure mode: backend switched to a
 *     fresh / different DB session, test users still existed, but analytics
 *     demo data was empty, so the Dashboard looked broken on the phone.
 *   - This file is the stable, long-lived entrypoint we should reference in
 *     guides whenever we need the canonical English demo dataset again.
 *
 * Behavior:
 *   - Reuses the proven 2026-04-26 dataset and logic from `seed-demo-data.ts`
 *   - Idempotent: if SKU `TUBE-A001` already exists, it exits safely
 *
 * Usage:
 *   node node_modules/tsx/dist/cli.mjs scripts/seed-phone-demo-en.ts
 *   npm run seed:phone-demo
 *
 * Required pre-step:
 *   Run `seed-test-user.ts` first if `admin_test` does not exist.
 */

import './seed-demo-data.ts';
