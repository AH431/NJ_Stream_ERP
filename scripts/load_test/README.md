# k6 Load Tests

Three k6 scripts for performance and rate-limit validation of the NJ Stream ERP backend.

## Prerequisites

Install k6: https://k6.io/docs/getting-started/installation/

```powershell
# Windows (winget)
winget install k6 --source winget
```

## Environment Variables

| Variable   | Default               | Description                     |
|------------|-----------------------|---------------------------------|
| `BASE_URL` | `http://localhost:3000` | Backend base URL (no trailing slash) |
| `USERNAME` | `sales_test`          | Test user username              |
| `PASSWORD` | `P@ssw0rd!`           | Test user password              |

Seed test users first if needed:
```powershell
cd packages/backend
$env:DATABASE_URL = 'postgresql://postgres:<password>@localhost:5432/nj_erp'
npx tsx scripts/seed-test-user.ts
```

## Scripts

### k6_smoke.js — Happy-path smoke test

1 VU, 1 iteration. Login → sync/pull. Use this to verify the stack is alive before heavier tests.

```powershell
k6 run --env BASE_URL=http://localhost:3000 scripts/load_test/k6_smoke.js
```

Thresholds: `p(95) < 500ms`, `error rate < 1%`

---

### k6_load.js — Sustained normal load

Ramps up to 10 VUs over 30 s, holds for 60 s, ramps down. Validates the backend under realistic concurrent usage.

```powershell
k6 run --env BASE_URL=http://localhost:3000 `
       --env USERNAME=sales_test `
       --env PASSWORD=P@ssw0rd! `
       scripts/load_test/k6_load.js
```

Thresholds: `p(95) < 500ms`, `p(99) < 1000ms`, `error rate < 1%`

---

### k6_spike.js — Spike / rate-limit test

Ramps to 50 VUs quickly. Hammers `/health` and mixes in bad login attempts. A custom `rate_limited_429` counter tracks how many requests hit the rate limiter.

```powershell
k6 run --env BASE_URL=http://localhost:3000 scripts/load_test/k6_spike.js
```

Expected: many 429 responses with `code: RATE_LIMIT_EXCEEDED`. The threshold allows up to 60 % failure rate during the spike.

---

## Saving Results

```powershell
# Save summary JSON
k6 run --out json=results.json scripts/load_test/k6_smoke.js

# Save full time-series to InfluxDB (optional)
k6 run --out influxdb=http://localhost:8086/k6 scripts/load_test/k6_load.js
```

## Interpreting Results

- **`http_req_duration`** — latency distribution. Check `p(95)` and `p(99)`.
- **`http_req_failed`** — requests that returned an error or unexpected status code.
- **`rate_limited_429`** — (spike test only) count of intentional 429 responses.
- A threshold marked `✗` in the summary means the test **failed** that SLO.

## CI / GitHub Actions

Use the manual workflow at `.github/workflows/load-test.yml`:

1. Go to **Actions → Load Test** in GitHub.
2. Click **Run workflow**.
3. Select `test_type` (`smoke`, `load`, or `spike`) and supply `base_url`.
4. The workflow uploads `results.json` as an artifact when done.
