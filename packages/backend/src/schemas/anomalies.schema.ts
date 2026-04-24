import {
  pgTable, serial, varchar, integer, boolean, text, jsonb, timestamp, index,
} from 'drizzle-orm/pg-core';

/**
 * P2-DB-01：異常事件記錄表
 *
 * 由後端 AnomalyScanner（cron job）寫入，不透過 sync push 流程。
 * 前端透過專用端點拉取未解決的異常清單。
 *
 * 嚴重度（severity）：
 *   critical — 直接影響營運（缺貨、資料異常）
 *   high     — 高風險預警（客戶流失、逾期付款）
 *   medium   — 一般異常（積壓庫存、重複下單）
 */
export const anomalies = pgTable('anomalies', {
  id:         serial('id').primaryKey(),
  alertType:  varchar('alert_type',  { length: 64  }).notNull(),
  severity:   varchar('severity',    { length: 16  }).notNull(),
  entityType: varchar('entity_type', { length: 32  }).notNull(),
  entityId:   integer('entity_id').notNull(),
  /** 人類可讀說明（中文），前端直接顯示 */
  message:    text('message').notNull(),
  /** 觸發當下的數值快照（JSON），供前端顯示細節 */
  detail:     jsonb('detail'),
  isResolved: boolean('is_resolved').notNull().default(false),
  resolvedAt: timestamp('resolved_at', { withTimezone: true, mode: 'date' }),
  createdAt:  timestamp('created_at',  { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  updatedAt:  timestamp('updated_at',  { withTimezone: true, mode: 'date' }).notNull().defaultNow().$onUpdate(() => new Date()),
}, (table) => [
  index('idx_anomalies_unresolved').on(table.isResolved, table.severity),
  index('idx_anomalies_entity').on(table.entityType, table.entityId),
]);

export type Anomaly    = typeof anomalies.$inferSelect;
export type NewAnomaly = typeof anomalies.$inferInsert;
