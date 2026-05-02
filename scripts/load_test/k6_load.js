/**
 * k6 sustained load test — health + authenticated sync/pull
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:3000 \
 *          --env USERNAME=sales_test \
 *          --env PASSWORD=P@ssw0rd! \
 *          scripts/load_test/k6_load.js
 */
import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 10 },
    { duration: '1m',  target: 10 },
    { duration: '30s', target: 0  },
  ],
  thresholds: {
    http_req_failed:   ['rate<0.01'],
    http_req_duration: ['p(95)<500', 'p(99)<1000'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000';
const USERNAME = __ENV.USERNAME || 'sales_test';
const PASSWORD = __ENV.PASSWORD || 'P@ssw0rd!';

// One token per VU, obtained once at setup and reused.
export function setup() {
  const res = http.post(
    `${BASE_URL}/api/v1/auth/login`,
    JSON.stringify({ username: USERNAME, password: PASSWORD }),
    { headers: { 'Content-Type': 'application/json' } },
  );
  if (res.status !== 200) {
    throw new Error(`Login failed during setup: ${res.status} ${res.body}`);
  }
  return { token: res.json('accessToken') };
}

export default function ({ token }) {
  // Health check
  const healthRes = http.get(`${BASE_URL}/health`);
  check(healthRes, { 'health 200': (r) => r.status === 200 });

  // Authenticated sync pull
  const syncRes = http.get(
    `${BASE_URL}/api/v1/sync/pull`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  check(syncRes, {
    'sync/pull 200': (r) => r.status === 200,
    'sync/pull has collections': (r) => {
      try {
        const body = r.json();
        return body.customers !== undefined || body.products !== undefined;
      } catch { return false; }
    },
  });

  sleep(1);
}
