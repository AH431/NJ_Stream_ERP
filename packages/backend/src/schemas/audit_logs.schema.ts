import {
  pgTable, serial, integer, text, timestamp, jsonb, index,
} from 'drizzle-orm/pg-core';

export type AuditAction = 'ai.chat' | 'ai.tool_call' | 'ai.blocked' | 'admin.import';
export type AuditStatus = 'pending' | 'success' | 'denied' | 'blocked' | 'error';

export const auditLogs = pgTable('audit_logs', {
  id:           serial('id').primaryKey(),
  /** 一次 ai.chat 請求全程共用同一個 UUID，用於關聯 tool_call 事件 */
  requestId:    text('request_id').notNull(),
  userId:       integer('user_id').notNull(),
  userRole:     text('user_role').notNull(),
  action:       text('action').notNull().$type<AuditAction>(),
  resourceType: text('resource_type'),
  resourceId:   text('resource_id'),
  /** SHA-256(question)，去識別化統計用，不儲存明文問句 */
  questionHash: text('question_hash'),
  toolName:     text('tool_name'),
  status:       text('status').notNull().$type<AuditStatus>(),
  errorMessage: text('error_message'),
  meta:         jsonb('meta'),
  createdAt:    timestamp('created_at', { withTimezone: true, mode: 'date' }).notNull().defaultNow(),
  finishedAt:   timestamp('finished_at', { withTimezone: true, mode: 'date' }),
}, (table) => [
  index('idx_audit_logs_request_id').on(table.requestId),
  index('idx_audit_logs_user_id').on(table.userId),
  index('idx_audit_logs_created_at').on(table.createdAt),
]);

export type AuditLog    = typeof auditLogs.$inferSelect;
export type NewAuditLog = typeof auditLogs.$inferInsert;
