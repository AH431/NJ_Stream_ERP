/**
 * k6 smoke test — happy-path login → sync/pull
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:3000 \
 *          --env USERNAME=sales_test \
 *          --env PASSWORD=P@ssw0rd! \
 *          scripts/load_test/k6_smoke.js
 */
import http from 'k6/http';
import { check } from 'k6';

export const options = {
  vus: 1,
  iterations: 1,
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<500'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const USERNAME = __ENV.USERNAME || 'sales_test';
const PASSWORD = __ENV.PASSWORD || 'P@ssw0rd!';

export default function () {
  // 1. Login
  const loginRes = http.post(
    `${BASE_URL}/api/v1/auth/login`,
    JSON.stringify({ username: USERNAME, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  check(loginRes, {
    'login status 200': (r) => r.status === 200,
    'login returns accessToken': (r) => {
      try { return !!r.json('accessToken'); } catch { return false; }
    },
  });

  const token = loginRes.json('accessToken');
  if (!token) return;

  // 2. Sync pull
  const syncRes = http.get(
    `${BASE_URL}/api/v1/sync/pull`,
    { headers: { Authorization: `Bearer ${token}` } },
  );

  check(syncRes, {
    'sync/pull status 200': (r) => r.status === 200,
    'sync/pull has bucketed collections': (r) => {
      try {
        const body = r.json();
        return (
          body.customers !== undefined ||
          body.products  !== undefined ||
          body.quotations !== undefined
        );
      } catch { return false; }
    },
  });
}
