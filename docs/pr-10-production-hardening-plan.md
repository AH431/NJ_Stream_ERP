# PR-10: Production Hardening Plan

**Date**: 2026-04-30  
**Scope**: docker prod 驗證、WAF 驗證、restore drill、壓測  
**Status**: revised implementation plan aligned to current repo state

---

## 1. Goal

PR-10 hardens the Phase 3 stack for production readiness across four areas:

- Verify the `docker-compose.prod.yml` stack can build, migrate, boot, and pass a smoke test
- Verify Cloudflare WAF rules are actually enforced against the real backend surface
- Automate the restore drill so backup recovery can be tested repeatedly with low operator effort
- Add k6 load tests and a manual workflow for repeatable performance checks before go-live

---

## 2. Current Repo Reality

This revised plan is based on the current implementation, not only the original PRD intent.

- Production compose already exists in [docker-compose.prod.yml](/abs/path/c:/Projects/NJ_Stream_ERP/docker-compose.prod.yml:1)
- The prod stack includes a dedicated `migrate` service and it must be part of validation
- Health check route exists at [packages/backend/src/app.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/src/app.ts:68)
- Global rate limit and custom 429 body are defined in [packages/backend/src/app.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/src/app.ts:45)
- Admin routes are mounted under `/api/v1/admin`, not `/admin`, in [packages/backend/src/app.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/src/app.ts:77)
- `GET /api/v1/sync/pull` returns bucketed objects such as `customers`, `products`, `quotations`, not an `operations` array, in [packages/backend/src/routes/sync.route.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/src/routes/sync.route.ts:224)
- Existing restore docs still contain stale validation steps and must be corrected in [docs/phase3-restore-runbook.md](/abs/path/c:/Projects/NJ_Stream_ERP/docs/phase3-restore-runbook.md:118)
- Existing backend test users can be seeded via [packages/backend/scripts/seed-test-user.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/scripts/seed-test-user.ts:1)

---

## 3. Key Corrections From The Earlier Draft

The earlier draft had several mismatches with the repo. This plan corrects them.

- Docker validation must include `migrate`; a green `/health` alone is not enough
- WAF verification must target `/api/v1/admin` instead of `/admin`
- Load tests must validate the real `sync/pull` response shape
- Restore runbook updates must fix incorrect existing steps, not only append a new section
- Load-test workflow should reuse the repo seed script instead of handwritten SQL when possible

---

## 4. Deliverables

### 4.1 Docker Prod Validation

**A. `scripts/smoke_test_prod.ps1`**  
New local smoke-test script for production compose.

Required behavior:

- Create ephemeral `.env.test-prod` with safe dummy values
- Run `docker compose -f docker-compose.prod.yml --env-file .env.test-prod build`
- Start `postgres`
- Wait for `postgres` health check to pass
- Run `docker compose -f docker-compose.prod.yml --env-file .env.test-prod --profile migrate run --rm migrate`
- Start `backend`
- Poll `http://127.0.0.1:3000/health` for up to 120 seconds
- Assert response body contains `{"status":"ok"}`
- Assert `x-content-type-options` and `x-frame-options` headers exist
- Always tear down with `down -v --remove-orphans`
- Optional `-KeepRunning` switch for manual inspection

**B. `.github/workflows/ci.yml`**  
Modify existing CI workflow.

Required changes:

- Add `npm test` to the backend job after `Build`
- Add a new `docker-prod-validate` job
- New job must:
  - write `.env.test-prod`
  - build prod compose
  - start `postgres`
  - run `migrate`
  - start `backend`
  - poll `/health`
  - check security headers
  - always tear down containers

**C. `.gitignore`**  
Add `.env.test-prod`.

---

### 4.2 Backend Health / Security Test

**`packages/backend/src/routes/health.test.ts`**  
New Vitest file using a minimal Fastify app.

Test coverage:

- `/health` returns 200 with `{ status: 'ok' }`
- `x-content-type-options` header exists
- `x-frame-options` header exists
- `x-dns-prefetch-control` header exists
- normal response includes rate-limit headers
- after 11 rapid requests, the last response is 429
- 429 body matches the custom `RATE_LIMIT_EXCEEDED` format from `app.ts`

Implementation note:

- Mirror the real app configuration closely enough to validate headers and rate limiting
- Do not couple this test to the DB plugin

---

### 4.3 WAF Verification

**`scripts/verify_waf.ps1`**  
New manual verification script for Cloudflare WAF after dashboard rules are applied.

Parameters:

- `-BaseUrl https://api.yourdomain.com`

Checks:

- `GET /health` returns 200
- requests to real admin paths under `/api/v1/admin` are blocked as expected
- malicious user agents such as `sqlmap`, `nikto`, `nmap`, and empty `User-Agent` are blocked
- HSTS header is present
- a short burst against `/health` reports whether 429 appears

Notes:

- This script verifies enforcement, not rule provisioning
- Admin-path checks must use the actual backend prefix, not `/admin`

---

### 4.4 Restore Drill Automation

**A. `scripts/drill_restore.ps1`**  
New automated drill script that reuses the existing backup and restore scripts.

Required behavior:

- Validate required env vars:
  - `POSTGRES_USER`
  - `POSTGRES_DB`
  - `POSTGRES_PASSWORD`
  - `BACKUP_PASSPHRASE`
  - `BACKUP_DIR`
- Unless `-SkipBackup`, call `.\scripts\backup_pg.ps1`
- Find the most recent `.pgdump.gpg` in `BACKUP_DIR`
- Start an isolated drill container such as `nj-erp-postgres-drill`
- Wait for `pg_isready`
- Set `POSTGRES_CONTAINER` to the drill container
- Call `.\scripts\restore_pg.ps1 -BackupFile ... -DropAndRecreate -Force`
- Run SQL smoke checks:
  - `SELECT COUNT(*) FROM customers`
  - `SELECT COUNT(*) FROM users WHERE is_active = true`
  - confirm existence of core tables:
    - `users`
    - `customers`
    - `products`
    - `quotations`
    - `sales_orders`
    - `inventory_items`
    - `processed_operations`
    - `audit_logs`
- Tear down the drill container
- Report duration, backup file used, and final PASS or FAIL

**B. `scripts/setup_backup_task.ps1`**  
Optional helper to register a Windows scheduled task for daily backup.

Required behavior:

- Create a local env bootstrap file with instructions
- Register `NJ_ERP_Daily_Backup`
- Run daily at 02:00
- Use `StartWhenAvailable`
- Apply a 30-minute execution limit

**C. `docs/phase3-restore-runbook.md`**  
Modify the existing runbook.

Required changes:

- Add a new automated-drill section
- Correct stale validation steps in the existing document
- Replace incorrect `POST /api/v1/sync/pull` references with `GET /api/v1/sync/pull`
- Replace `operations` wording with the actual bucketed response shape
- Add a drill log table for recurring exercise records

---

### 4.5 k6 Load Testing

**A. `scripts/load_test/k6_smoke.js`**  
Happy-path smoke test.

Flow:

- `POST /api/v1/auth/login`
- extract `accessToken`
- `GET /api/v1/sync/pull`

Checks:

- login returns 200 and `accessToken`
- sync pull returns 200
- response contains expected top-level collections such as `customers`, `products`, or other known buckets

Thresholds:

- `p(95) < 500`
- `http_req_failed rate < 0.01`

**B. `scripts/load_test/k6_load.js`**  
Sustained normal-load test.

Suggested flow:

- `GET /health`
- authenticated `GET /api/v1/sync/pull`
- optionally add one more stable read endpoint after verifying suitability

Thresholds:

- `p(95) < 500`
- `p(99) < 1000`
- `http_req_failed rate < 0.01`

**C. `scripts/load_test/k6_spike.js`**  
Spike / rate-limit test.

Suggested flow:

- hammer `GET /health`
- mix in failed `POST /api/v1/auth/login` attempts
- count 429 responses with a custom metric

Checks:

- 429 body matches `RATE_LIMIT_EXCEEDED`
- expected auth failures remain bounded to 401 or 429

**D. `scripts/load_test/README.md`**  
Document installation, env vars, run commands, and result interpretation.

---

### 4.6 Manual GitHub Actions Load-Test Workflow

**`.github/workflows/load-test.yml`**  
New manually triggered workflow.

Requirements:

- `workflow_dispatch` with `test_type` and `base_url`
- write `.env.test-prod`
- build prod compose
- start `postgres`
- run `migrate`
- start `backend`
- seed test users
- run the selected k6 script
- upload `results.json`
- always tear down

Implementation preference:

- Reuse [packages/backend/scripts/seed-test-user.ts](/abs/path/c:/Projects/NJ_Stream_ERP/packages/backend/scripts/seed-test-user.ts:1) instead of embedding handwritten SQL, unless workflow constraints force a simpler fallback

---

## 5. Recommended Implementation Order

1. Update `.gitignore`
2. Add `scripts/smoke_test_prod.ps1`
3. Update `.github/workflows/ci.yml`
4. Add `packages/backend/src/routes/health.test.ts`
5. Add `scripts/verify_waf.ps1`
6. Add `scripts/drill_restore.ps1`
7. Add `scripts/setup_backup_task.ps1`
8. Update `docs/phase3-restore-runbook.md`
9. Add k6 scripts and `README.md`
10. Add `.github/workflows/load-test.yml`

---

## 6. Verification Matrix

| Area | Verification |
|---|---|
| Local docker prod validation | `.\scripts\smoke_test_prod.ps1` exits 0 and reports PASS |
| CI docker prod validation | `docker-prod-validate` job is green |
| Backend tests | `cd packages/backend && npm test` passes including `health.test.ts` |
| WAF verification | `.\scripts\verify_waf.ps1 -BaseUrl ...` reports no FAIL checks |
| Restore drill | `.\scripts\drill_restore.ps1` reports PASS and timing |
| k6 smoke | smoke thresholds pass against local or CI target |
| k6 load/spike | workflow artifact uploaded and thresholds evaluated |

---

## 7. Non-Goals

PR-10 does not change core application behavior or add new business features. It focuses on validation, operational automation, and production-readiness checks around the existing stack.
