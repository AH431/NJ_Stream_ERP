import {
  pgTable, serial, varchar, jsonb, timestamp, unique, index,
} from 'drizzle-orm/pg-core';
import {
  ENTITY_TYPES, OPERATION_TYPES, DELTA_TYPES, PROCESSED_OP_STATUSES,
  SYNC,
} from '@/constants/index.js';

/**
 * 已處理操作記錄表
 *
 * 職責：
 *   1. 冪等去重：以 operation_id UNIQUE 確保相同 UUID 只處理一次
 *   2. 審計追蹤：保留原始 payload 快照供事後查驗
 *   3. 定期清理：排程任務每週刪除 processedAt 超過 SYNC.CLEANUP_DAYS（30 天）的記錄
 *
 * 索引設計：
 *   - idx_processed_at：支援清理排程的範圍查詢（WHERE processed_at < NOW() - INTERVAL '30 days'）
 *   - idx_entity_type ：支援按 entity 類型統計與查詢
 */
export const processedOperations = pgTable('processed_operations', {
  id:            serial('id').primaryKey(),
  /** 前端產生的 UUID v4，UNIQUE 確保冪等性。長度 36 = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" */
  operationId:   varchar('operation_id', { length: 36 }).notNull(),
  entityType:    varchar('entity_type', { length: 50 })
                   .notNull()
                   .$type<typeof ENTITY_TYPES[keyof typeof ENTITY_TYPES]>(),
  operationType: varchar('operation_type', { length: 20 })
                   .notNull()
                   .$type<typeof OPERATION_TYPES[keyof typeof OPERATION_TYPES]>(),
  deltaType:     varchar('delta_type', { length: 20 })
                   .$type<typeof DELTA_TYPES[keyof typeof DELTA_TYPES]>(),
  /** 原始 operation payload 快照 */
  payload:       jsonb('payload').notNull(),
  status:        varchar('status', { length: 20 })
                   .notNull()
                   .$type<typeof PROCESSED_OP_STATUSES[keyof typeof PROCESSED_OP_STATUSES]>()
                   .default('success'),
  errorMessage:  varchar('error_message', { length: 1000 }),
  createdAt:     timestamp('created_at',   { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  /** 清理排程依此欄位進行範圍刪除（保留 SYNC.CLEANUP_DAYS = ${SYNC.CLEANUP_DAYS} 天）*/
  processedAt:   timestamp('processed_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  deletedAt:     timestamp('deleted_at',   { withTimezone: true, mode: 'date' }),
}, (table) => [
  unique('uq_operation_id').on(table.operationId),
  index('idx_processed_at').on(table.processedAt),
  index('idx_entity_type').on(table.entityType),
]);

export type ProcessedOperation    = typeof processedOperations.$inferSelect;
export type NewProcessedOperation = typeof processedOperations.$inferInsert;
