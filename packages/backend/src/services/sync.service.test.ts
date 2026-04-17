import { describe, expect, it } from 'vitest';
import { processOperation } from './sync.service.js';
import { orderItems, quotations, salesOrders, inventoryItems } from '@/schemas/index.js';
import type { SyncOperation } from '@/types/index.js';

type FakeRow = Record<string, unknown>;

class FakeTx {
  quotationRows: FakeRow[];
  quotationItemRows: FakeRow[];
  inventoryRows: FakeRow[];
  nextSalesOrderId: number;
  insertedOrderItems: FakeRow[] = [];
  updatedQuotations: FakeRow[] = [];
  updatedInventory: FakeRow[] = [];

  constructor({
    quotationRows = [],
    quotationItemRows = [],
    inventoryRows = [],
    nextSalesOrderId = 9001,
  }: {
    quotationRows?: FakeRow[];
    quotationItemRows?: FakeRow[];
    inventoryRows?: FakeRow[];
    nextSalesOrderId?: number;
  }) {
    this.quotationRows = quotationRows;
    this.quotationItemRows = quotationItemRows;
    this.inventoryRows = inventoryRows;
    this.nextSalesOrderId = nextSalesOrderId;
  }

  select() {
    return {
      from: (table: unknown) => ({
        where: async () => {
          if (table === quotations) return this.quotationRows;
          if (table === orderItems) return this.quotationItemRows;
          if (table === inventoryItems) return this.inventoryRows;
          return [];
        },
      }),
    };
  }

  insert(table: unknown) {
    return {
      values: (values: FakeRow | FakeRow[]) => {
        if (table === salesOrders) {
          const id = this.nextSalesOrderId++;
          return {
            returning: async () => [{ id }],
          };
        }

        if (table === orderItems) {
          this.insertedOrderItems.push(...(Array.isArray(values) ? values : [values]));
        }

        return {
          returning: async () => [],
        };
      },
    };
  }

  update(table: unknown) {
    return {
      set: (values: FakeRow) => ({
        where: async () => {
          if (table === quotations) {
            this.updatedQuotations.push(values);
          }
          if (table === inventoryItems) {
            this.updatedInventory.push(values);
          }
          return [];
        },
      }),
    };
  }
}

describe('processOperation', () => {
  it('copies quotation items into sales order items when converting quotation', async () => {
    const tx = new FakeTx({
      quotationRows: [{
        id: 11,
        customerId: 7,
        createdBy: 3,
        totalAmount: '210.00',
        taxAmount: '10.00',
        status: 'draft',
        convertedToOrderId: null,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
      quotationItemRows: [
        {
          id: 1,
          quotationId: 11,
          salesOrderId: null,
          productId: 101,
          quantity: 2,
          unitPrice: '100.00',
          subtotal: '200.00',
        },
        {
          id: 2,
          quotationId: 11,
          salesOrderId: null,
          productId: 102,
          quantity: 1,
          unitPrice: '10.00',
          subtotal: '10.00',
        },
      ],
    });

    const op: SyncOperation = {
      id: '550e8400-e29b-41d4-a716-446655440000',
      entityType: 'sales_order',
      operationType: 'create',
      createdAt: '2026-04-17T10:00:00.000Z',
      payload: {
        quotationId: 11,
        customerId: 7,
        createdBy: 3,
        status: 'pending',
        createdAt: '2026-04-17T10:00:00.000Z',
        updatedAt: '2026-04-17T10:00:00.000Z',
      },
    };

    const result = await processOperation(tx as never, op, 3, 'sales');

    expect(result).toEqual({ ok: true, serverId: 9001 });
    expect(tx.insertedOrderItems).toEqual([
      {
        quotationId: null,
        salesOrderId: 9001,
        productId: 101,
        quantity: 2,
        unitPrice: '100.00',
        subtotal: '200.00',
      },
      {
        quotationId: null,
        salesOrderId: 9001,
        productId: 102,
        quantity: 1,
        unitPrice: '10.00',
        subtotal: '10.00',
      },
    ]);
    expect(tx.updatedQuotations).toHaveLength(1);
  });

  it('rejects quotation conversion when source quotation has no items', async () => {
    const tx = new FakeTx({
      quotationRows: [{
        id: 12,
        customerId: 8,
        createdBy: 4,
        totalAmount: '0.00',
        taxAmount: '0.00',
        status: 'draft',
        convertedToOrderId: null,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
      quotationItemRows: [],
    });

    const op: SyncOperation = {
      id: '650e8400-e29b-41d4-a716-446655440000',
      entityType: 'sales_order',
      operationType: 'create',
      createdAt: '2026-04-17T10:00:00.000Z',
      payload: {
        quotationId: 12,
        customerId: 8,
        createdBy: 4,
        status: 'pending',
        createdAt: '2026-04-17T10:00:00.000Z',
        updatedAt: '2026-04-17T10:00:00.000Z',
      },
    };

    const result = await processOperation(tx as never, op, 4, 'sales');

    expect(result).toEqual({
      ok: false,
      failure: {
        operationId: op.id,
        code: 'DATA_CONFLICT',
        message: 'quotationId=12 缺少可轉換的明細資料。',
        server_state: null,
      },
    });
  });

  it('returns INSUFFICIENT_STOCK when inventory delta would break constraints', async () => {
    const tx = new FakeTx({
      inventoryRows: [{
        id: 33,
        productId: 101,
        warehouseId: 1,
        quantityOnHand: 5,
        quantityReserved: 5,
        minStockLevel: 0,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
    });

    const op: SyncOperation = {
      id: '750e8400-e29b-41d4-a716-446655440000',
      entityType: 'inventory_delta',
      operationType: 'delta_update',
      deltaType: 'reserve',
      createdAt: '2026-04-17T10:00:00.000Z',
      payload: {
        productId: 101,
        amount: 1,
      },
    };

    const result = await processOperation(tx as never, op, 1, 'sales');

    expect(result).toEqual({
      ok: false,
      failure: {
        operationId: op.id,
        code: 'INSUFFICIENT_STOCK',
        message: '庫存不足：onHand=5, reserved=5, delta=reserve(1)。',
        server_state: {
          entityType: 'inventory_item',
          id: 33,
          productId: 101,
          warehouseId: 1,
          quantityOnHand: 5,
          quantityReserved: 5,
          minStockLevel: 0,
          createdAt: '2026-04-01T00:00:00.000Z',
          updatedAt: '2026-04-01T00:00:00.000Z',
          deletedAt: null,
        },
      },
    });
    expect(tx.updatedInventory).toHaveLength(0);
  });
});
