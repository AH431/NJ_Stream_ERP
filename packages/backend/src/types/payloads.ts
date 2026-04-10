/**
 * Payload 型別定義（對應 API Contract v1.6 components/schemas）
 * 供後端 service 層在回傳 server_state 時使用，確保欄位與 YAML 一致。
 */

export interface CustomerPayload {
  entityType: 'customer';
  id: number;
  name: string;
  contact: string | null;
  taxId: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface ProductPayload {
  entityType: 'product';
  id: number;
  name: string;
  sku: string;
  unitPrice: string;
  minStockLevel: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface QuotationItem {
  productId: number;
  quantity: number;
  unitPrice: string;
  subtotal: string;
}

export interface QuotationPayload {
  entityType: 'quotation';
  id: number;
  customerId: number;
  createdBy: number;
  items: QuotationItem[];
  totalAmount: string;
  taxAmount: string;
  status: 'draft' | 'sent' | 'converted' | 'expired';
  convertedToOrderId: number | null;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface SalesOrderPayload {
  entityType: 'sales_order';
  id: number;
  quotationId: number | null;
  customerId: number;
  createdBy: number;
  status: 'pending' | 'confirmed' | 'shipped' | 'cancelled';
  confirmedAt: string | null;
  shippedAt: string | null;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}

export interface InventoryItemPayload {
  entityType: 'inventory_delta';
  id: number;
  productId: number;
  warehouseId: number;
  quantityOnHand: number;
  quantityReserved: number;
  minStockLevel: number;
  createdAt: string;
  updatedAt: string;
  deletedAt: string | null;
}
