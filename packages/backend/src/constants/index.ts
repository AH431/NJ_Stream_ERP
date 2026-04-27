/**
 * NJ_Stream_ERP 同步協定常數
 * 對應《同步協定規格 v1.6》（工程憲法）
 * 禁止在未更新同步協定文件前修改此檔案的值
 */

// ── 同步協定核心常數（命名空間結構）─────────────────────────
export const SYNC = {
  /** 單次 sync/push 可接受的最大 operations 數量（同步協定 v1.6 § 5） */
  BATCH_LIMIT: 50,
  /** processed_operations 保留天數，超過可清除（同步協定 v1.6 Addendum） */
  CLEANUP_DAYS: 30,
} as const;

// ── DELTA_UPDATE 類型 ─────────────────────────────────────
export const DELTA_TYPES = {
  /** 採購入庫：quantity_on_hand + amount */
  IN: 'in',
  /** 確認訂單鎖定：quantity_reserved + amount */
  RESERVE: 'reserve',
  /** 取消訂單釋放：quantity_reserved - amount */
  CANCEL: 'cancel',
  /** 實際出貨：quantity_on_hand - amount，quantity_reserved - amount */
  OUT: 'out',
} as const;

export type DeltaType = typeof DELTA_TYPES[keyof typeof DELTA_TYPES];

// ── Operation 類型 ────────────────────────────────────────
export const OPERATION_TYPES = {
  CREATE: 'create',
  UPDATE: 'update',
  DELETE: 'delete',
  DELTA_UPDATE: 'delta_update',
} as const;

export type OperationType = typeof OPERATION_TYPES[keyof typeof OPERATION_TYPES];

// ── Entity 類型 ───────────────────────────────────────────
export const ENTITY_TYPES = {
  CUSTOMER:             'customer',
  PRODUCT:              'product',
  QUOTATION:            'quotation',
  SALES_ORDER:          'sales_order',
  INVENTORY_DELTA:      'inventory_delta',
  CUSTOMER_INTERACTION: 'customer_interaction',
} as const;

export type EntityType = typeof ENTITY_TYPES[keyof typeof ENTITY_TYPES];

// ── 錯誤碼（對應 API Contract v1.6）────────────────────────
export const SYNC_ERROR_CODES = {
  /** 庫存不足 → 前端強制 Pull */
  INSUFFICIENT_STOCK: 'INSUFFICIENT_STOCK',
  /** 業務規則禁止（如報價已轉換）→ Force Overwrite */
  FORBIDDEN_OPERATION: 'FORBIDDEN_OPERATION',
  /** 角色無此操作權限 → Force Overwrite */
  PERMISSION_DENIED: 'PERMISSION_DENIED',
  /** payload 欄位驗證失敗 → Force Overwrite */
  VALIDATION_ERROR: 'VALIDATION_ERROR',
  /** 嚴重衝突，無法自動解決 → 人工介入 */
  DATA_CONFLICT: 'DATA_CONFLICT',
} as const;

export type SyncErrorCode = typeof SYNC_ERROR_CODES[keyof typeof SYNC_ERROR_CODES];

// ── 角色 ──────────────────────────────────────────────────
export const USER_ROLES = {
  SALES: 'sales',
  WAREHOUSE: 'warehouse',
  ADMIN: 'admin',
} as const;

export type UserRole = typeof USER_ROLES[keyof typeof USER_ROLES];

// ── 報價狀態 ──────────────────────────────────────────────
export const QUOTATION_STATUSES = {
  DRAFT: 'draft',
  SENT: 'sent',
  CONVERTED: 'converted',
  EXPIRED: 'expired',
} as const;

// ── 訂單狀態 ──────────────────────────────────────────────
export const SALES_ORDER_STATUSES = {
  PENDING: 'pending',
  CONFIRMED: 'confirmed',
  SHIPPED: 'shipped',
  CANCELLED: 'cancelled',
} as const;

// ── 付款狀態 ──────────────────────────────────────────────
export const PAYMENT_STATUSES = {
  UNPAID:       'unpaid',
  PAID:         'paid',
  WRITTEN_OFF:  'written_off',
} as const;

export type PaymentStatus = typeof PAYMENT_STATUSES[keyof typeof PAYMENT_STATUSES];

// ── processed_operations 狀態 ─────────────────────────────
export const PROCESSED_OP_STATUSES = {
  SUCCESS: 'success',
  FAILED: 'failed',
  SKIPPED: 'skipped',
} as const;

// ── MVP 預設倉庫 ──────────────────────────────────────────
/** MVP 階段單一預設倉庫 ID（欄位保留，UI 暫時隱藏）*/
export const DEFAULT_WAREHOUSE_ID = 1;

/** 軟刪除記錄保留天數 */
export const SOFT_DELETE_RETENTION_DAYS = 30;
