/**
 * FCM Service — Firebase Admin SDK 包裝
 *
 * 負責：
 *   1. 初始化 Firebase Admin（從 FIREBASE_SERVICE_ACCOUNT 環境變數讀取 JSON）
 *   2. 依 severity + entityType 決定通知目標角色
 *   3. 以 sendEachForMulticast 批次發送，自動清理失效 token
 *
 * 通知規則：
 *   critical → admin + warehouse + sales（全員）
 *   high（庫存類 entity_type=inventory_item） → admin + warehouse
 *   high（其他）→ admin + sales
 *   medium → 不發 push（避免雜訊）
 */

import admin from 'firebase-admin';
import { sql } from 'drizzle-orm';
import type { DrizzleDb } from '@/plugins/db.js';

// ── 初始化（只執行一次）────────────────────────────────────

let _initialized = false;

export function initFcm(): void {
  if (_initialized) return;

  const raw = process.env.FIREBASE_SERVICE_ACCOUNT;
  if (!raw) {
    console.warn(JSON.stringify({ level: 'warn', job: 'FCM', msg: 'init.skipped', reason: 'FIREBASE_SERVICE_ACCOUNT not set' }));
    return;
  }

  try {
    admin.initializeApp({
      credential: admin.credential.cert(JSON.parse(raw) as admin.ServiceAccount),
    });
    _initialized = true;
    console.log(JSON.stringify({ level: 'info', job: 'FCM', msg: 'init.ok' }));
  } catch (err) {
    const errorSummary = err instanceof Error ? err.message : String(err);
    console.error(JSON.stringify({ level: 'error', job: 'FCM', msg: 'init.failed', errorSummary }));
  }
}

export function isFcmEnabled(): boolean {
  return _initialized;
}

// ── 新異常資料型別（供 AnomalyScanner 使用）───────────────

export type NewAnomalyForFcm = {
  severity: string;
  message: string;
  entityType: string;
  alertType: string;
};

// ── 主函式：依新異常送出 push 通知 ────────────────────────

export async function sendAnomalyNotifications(
  db: DrizzleDb,
  newAnomalies: NewAnomalyForFcm[],
  jobId?: string
): Promise<void> {
  if (!_initialized || newAnomalies.length === 0) return;

  // 過濾出需要 push 的異常（只發 critical + high）
  const pushable = newAnomalies.filter(
    (a) => a.severity === 'critical' || a.severity === 'high'
  );
  if (pushable.length === 0) return;

  // 依目標角色分組，減少 DB 查詢次數
  const byRoleKey = new Map<string, NewAnomalyForFcm[]>();
  for (const anomaly of pushable) {
    const roles = _targetRoles(anomaly.severity, anomaly.entityType);
    if (roles.length === 0) continue;
    const key = roles.join(',');
    if (!byRoleKey.has(key)) byRoleKey.set(key, []);
    byRoleKey.get(key)!.push(anomaly);
  }

  for (const [rolesKey, anomalies] of byRoleKey) {
    const roles = rolesKey.split(',');
    await _sendToRoles(db, roles, anomalies, jobId);
  }
}

// ── 角色決策 ──────────────────────────────────────────────

function _targetRoles(severity: string, entityType: string): string[] {
  if (severity === 'critical') return ['admin', 'warehouse', 'sales'];
  if (severity === 'high') {
    if (entityType === 'inventory_item') return ['admin', 'warehouse'];
    return ['admin', 'sales'];
  }
  return [];
}

// ── 查 token + 發送 ───────────────────────────────────────

/** FCM sendEachForMulticast 單批上限 */
const FCM_CHUNK_SIZE = 500;

async function _sendToRoles(
  db: DrizzleDb,
  roles: string[],
  anomalies: NewAnomalyForFcm[],
  jobId?: string
): Promise<void> {
  // 查詢目標角色的 device token
  const tokenRows = await db.execute(sql`
    SELECT dt.token
    FROM device_tokens dt
    JOIN users u ON u.id = dt.user_id
    WHERE u.role = ANY(${roles}::text[])
      AND u.is_active = TRUE
      AND u.deleted_at IS NULL
  `);

  const tokens = (tokenRows as unknown as Array<{ token: string }>).map((r) => r.token);
  if (tokens.length === 0) return;

  // 組裝通知標題 / 內容
  const title =
    anomalies.length === 1
      ? `⚠ ${_alertLabel(anomalies[0].alertType)}`
      : `⚠ ${anomalies.length} 筆新異常`;
  const body =
    anomalies.length === 1
      ? anomalies[0].message
      : anomalies.map((a) => a.message).join('；').slice(0, 200);

  const msgPayload = {
    notification: { title, body },
    android: {
      priority: 'high' as const,
      notification: { channelId: 'anomaly_alerts', sound: 'default' },
    },
    data: {
      alertType: anomalies[0].alertType,
      screen: 'notifications',
    },
  };

  // FCM 每批最多 500 個 token，超過需分批送出
  const invalidTokens: string[] = [];
  let successCount = 0;
  let failureCount = 0;

  for (let i = 0; i < tokens.length; i += FCM_CHUNK_SIZE) {
    const chunk = tokens.slice(i, i + FCM_CHUNK_SIZE);
    try {
      const response = await admin.messaging().sendEachForMulticast({
        tokens: chunk,
        ...msgPayload,
      });

      successCount += response.successCount;
      failureCount += response.failureCount;

      // 收集失效 token（裝置解除安裝或 token 已輪換）
      response.responses.forEach((resp, idx) => {
        const code = resp.error?.code ?? '';
        if (
          !resp.success &&
          (code === 'messaging/registration-token-not-registered' ||
            code === 'messaging/invalid-registration-token')
        ) {
          invalidTokens.push(chunk[idx]);
        }
      });
    } catch (err) {
      const chunkIdx = i / FCM_CHUNK_SIZE + 1;
      const errorSummary = err instanceof Error ? err.message : String(err);
      console.error(JSON.stringify({ level: 'error', job: 'FCM', jobId, msg: 'chunk.failed', chunkIdx, errorSummary }));
    }
  }

  if (invalidTokens.length > 0) {
    await db.execute(sql`
      DELETE FROM device_tokens WHERE token = ANY(${invalidTokens}::text[])
    `);
    console.log(JSON.stringify({ level: 'info', job: 'FCM', jobId, msg: 'tokens.removed', removedCount: invalidTokens.length }));
  }

  console.log(JSON.stringify({
    level: 'info', job: 'FCM', jobId,
    msg: 'job.done',
    anomalyCount: anomalies.length,
    deviceCount: tokens.length,
    successCount,
    failureCount,
  }));
}

// ── Alert type 中文標籤（對應前端 NotificationScreen）─────

function _alertLabel(alertType: string): string {
  const labels: Record<string, string> = {
    LONG_PENDING_ORDER: '訂單停滯',
    NEGATIVE_AVAILABLE: '庫存異常',
    STOCKOUT_PROLONGED: '長期缺貨',
    STOCK_CRITICAL: '緊急缺貨',
    STOCK_ALERT: '庫存警急',
    STOCK_SAFETY: '庫存預警',
    DUPLICATE_ORDER: '重複訂單',
    ORDER_QUANTITY_SPIKE: '數量異常',
    CUSTOMER_INACTIVE: '客戶沉默',
    OVERDUE_PAYMENT: '逾期未收',
    HIGH_VALUE_CUSTOMER_CHURN_RISK: '高價值客戶流失風險',
    FREQUENT_CANCELLATION: '頻繁取消',
  };
  return labels[alertType] ?? alertType;
}
