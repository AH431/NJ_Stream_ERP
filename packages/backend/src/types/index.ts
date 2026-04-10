import type { EntityType, SyncErrorCode } from '@/constants/index.js';
import type {
  CustomerPayload, ProductPayload, QuotationPayload,
  SalesOrderPayload, InventoryItemPayload,
} from './payloads.js';

// ── Re-export constants types ────────────────────────────
export type { EntityType, SyncErrorCode };
export type { DeltaType, OperationType, UserRole } from '@/constants/index.js';

// ── Sync Push 請求結構（對應 API Contract v1.6）────────────
export interface SyncOperation {
  id: string;
  entityType: EntityType;
  operationType: string;
  deltaType?: string | null;
  createdAt: string;
  payload: Record<string, unknown>;
}

// ── Sync Push 回應結構 ────────────────────────────────────
export interface FailedOperation {
  operationId: string;
  code: SyncErrorCode;
  message: string;
  server_state: ServerState | null;
}

export interface SyncPushResponse {
  succeeded: string[];
  failed: FailedOperation[];
}

// ── ServerState discriminated union（對應 discriminator）──
export type ServerState =
  | CustomerPayload
  | ProductPayload
  | QuotationPayload
  | SalesOrderPayload
  | InventoryItemPayload;
