/**
 * AnomalyScanner — INSERT 並發安全測試（M1.3 #9）
 *
 * 驗證：所有 INSERT 語句都帶 `ON CONFLICT DO NOTHING`，
 * 使得並發或重跑時即使觸發 partial unique index 衝突也不會 throw，
 * 否則整個 scan loop 會中斷後續 rule。
 */

import { describe, expect, it } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const SOURCE = readFileSync(join(__dirname, 'anomaly_scanner.service.ts'), 'utf8');

describe('AnomalyScanner — ON CONFLICT DO NOTHING guard (M1.3 #9)', () => {
  it('every INSERT INTO anomalies is paired with ON CONFLICT DO NOTHING', () => {
    const insertCount  = (SOURCE.match(/INSERT INTO anomalies/g)            ?? []).length;
    const guardedCount = (SOURCE.match(/ON CONFLICT DO NOTHING/g)           ?? []).length;

    // 兩者數量必須相同，且至少有一條規則
    expect(insertCount).toBeGreaterThan(0);
    expect(guardedCount).toBe(insertCount);
  });
});
