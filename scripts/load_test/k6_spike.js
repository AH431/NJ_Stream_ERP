/**
 * k6 spike / rate-limit test
 *
 * Hammers /health and mixes in failed login attempts.
 * Counts 429 responses with a custom metric to verify rate limiting fires.
 *
 * Usage:
 *   k6 run --env BASE_URL=http://localhost:3000 \
 *          scripts/load_test/k6_spike.js
 */
import http from 'k6/http';
import { check } from 'k6';
import { Counter } from 'k6/metrics';

export const options = {
  stages: [
    { duration: '10s', target: 50 },
    { duration: '20s', target: 50 },
    { duration: '10s', target: 0  },
  ],
  thresholds: {
    // Allow up to 60 % failure during a spike — we expect 429s
    http_req_failed: ['rate<0.60'],
  },
};

const BASE_URL    = __ENV.BASE_URL || 'http://localhost:3000';
const rateLimited = new Counter('rate_limited_429');

export default function () {
  // Burst health checks
  const healthRes = http.get(`${BASE_URL}/health`);
  if (healthRes.status === 429) {
    rateLimited.add(1);
    check(healthRes, {
      '429 body matches RATE_LIMIT_EXCEEDED': (r) => {
        try { return r.json('code') === 'RATE_LIMIT_EXCEEDED'; } catch { return false; }
      },
    });
  }

  // Intentionally bad login — expect 401 or 429, never 500
  const badLogin = http.post(
    `${BASE_URL}/api/v1/auth/login`,
    JSON.stringify({ username: 'nouser', password: 'badpass' }),
    { headers: { 'Content-Type': 'application/json' } },
  );

  if (badLogin.status === 429) {
    rateLimited.add(1);
  }

  check(badLogin, {
    'bad login is 401 or 429': (r) => r.status === 401 || r.status === 429,
  });
}
