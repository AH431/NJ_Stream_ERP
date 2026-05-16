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
  nextQuotationId: number;
  insertedOrderItems: FakeRow[] = [];
  insertedQuotations: FakeRow[] = [];
  insertedSalesOrders: FakeRow[] = [];
  updatedQuotations: FakeRow[] = [];
  updatedInventory: FakeRow[] = [];
  /** 紀錄每張查詢是否套用 SELECT ... FOR UPDATE 鎖 */
  forUpdateCalls: { table: string; strength: string }[] = [];

  constructor({
    quotationRows = [],
    quotationItemRows = [],
    inventoryRows = [],
    nextSalesOrderId = 9001,
    nextQuotationId = 5001,
  }: {
    quotationRows?: FakeRow[];
    quotationItemRows?: FakeRow[];
    inventoryRows?: FakeRow[];
    nextSalesOrderId?: number;
    nextQuotationId?: number;
  }) {
    this.quotationRows = quotationRows;
    this.quotationItemRows = quotationItemRows;
    this.inventoryRows = inventoryRows;
    this.nextSalesOrderId = nextSalesOrderId;
    this.nextQuotationId = nextQuotationId;
  }

  private rowsFor(table: unknown): FakeRow[] {
    if (table === quotations) return this.quotationRows;
    if (table === orderItems) return this.quotationItemRows;
    if (table === inventoryItems) return this.inventoryRows;
    return [];
  }

  private tableName(table: unknown): string {
    if (table === quotations) return 'quotations';
    if (table === orderItems) return 'order_items';
    if (table === inventoryItems) return 'inventory_items';
    if (table === salesOrders) return 'sales_orders';
    return 'unknown';
  }

  select() {
    return {
      from: (table: unknown) => {
        // 回傳一個 thenable，同時支援 `.for('update')` 鏈式呼叫，
        // 對應 drizzle 真實 query builder 的 `await ...where(...).for('update')`。
        const buildResult = (locked: boolean) => {
          const rows = async () => this.rowsFor(table);
          return {
            for: (strength: string) => {
              this.forUpdateCalls.push({ table: this.tableName(table), strength });
              return buildResult(true);
            },
            then: <T,>(
              onFulfilled: (value: FakeRow[]) => T,
              onRejected?: (reason: unknown) => T,
            ) => rows().then(onFulfilled, onRejected),
            // 標記避免 lint「未使用變數」
            _locked: locked,
          };
        };
        return {
          where: (_cond?: unknown) => buildResult(false),
        };
      },
    };
  }

  insert(table: unknown) {
    return {
      values: (values: FakeRow | FakeRow[]) => {
        if (table === salesOrders) {
          const row = Array.isArray(values) ? values[0] : values;
          const id = this.nextSalesOrderId++;
          this.insertedSalesOrders.push({ id, ...row });
          return {
            returning: async () => [{ id }],
          };
        }

        if (table === quotations) {
          const row = Array.isArray(values) ? values[0] : values;
          const id = this.nextQuotationId++;
          this.insertedQuotations.push({ id, ...row });
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

  // ── 安全修正：庫存 RESERVE 必須使用 SELECT ... FOR UPDATE ───────
  it('locks the inventory row with SELECT FOR UPDATE before applying reserve delta', async () => {
    const tx = new FakeTx({
      inventoryRows: [{
        id: 50,
        productId: 200,
        warehouseId: 1,
        quantityOnHand: 100,
        quantityReserved: 0,
        minStockLevel: 0,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
    });

    const op: SyncOperation = {
      id: '11111111-1111-4111-8111-111111111111',
      entityType: 'inventory_delta',
      operationType: 'delta_update',
      deltaType: 'reserve',
      createdAt: '2026-05-16T10:00:00.000Z',
      payload: { productId: 200, amount: 10 },
    };

    const result = await processOperation(tx as never, op, 1, 'sales');

    expect(result).toEqual({ ok: true });
    // SELECT FOR UPDATE 必須執行於 inventory_items 表，避免兩筆 RESERVE 並發超賣
    expect(tx.forUpdateCalls).toContainEqual({ table: 'inventory_items', strength: 'update' });
    expect(tx.updatedInventory).toEqual([
      expect.objectContaining({ quantityOnHand: 100, quantityReserved: 10 }),
    ]);
  });

  it('locks the inventory row with SELECT FOR UPDATE before applying out delta', async () => {
    const tx = new FakeTx({
      inventoryRows: [{
        id: 51,
        productId: 201,
        warehouseId: 1,
        quantityOnHand: 20,
        quantityReserved: 10,
        minStockLevel: 0,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
    });

    const op: SyncOperation = {
      id: '22222222-2222-4222-8222-222222222222',
      entityType: 'inventory_delta',
      operationType: 'delta_update',
      deltaType: 'out',
      createdAt: '2026-05-16T10:00:00.000Z',
      payload: { productId: 201, amount: 5 },
    };

    const result = await processOperation(tx as never, op, 1, 'warehouse');

    expect(result).toEqual({ ok: true });
    expect(tx.forUpdateCalls).toContainEqual({ table: 'inventory_items', strength: 'update' });
  });

  // ── 安全修正：createdBy 由 JWT 注入，client 提供值會被忽略（BOLA 防護）─
  it('uses JWT userId for quotation.createdBy and ignores client-supplied createdBy', async () => {
    const tx = new FakeTx({});

    const op: SyncOperation = {
      id: '33333333-3333-4333-8333-333333333333',
      entityType: 'quotation',
      operationType: 'create',
      createdAt: '2026-05-16T10:00:00.000Z',
      payload: {
        customerId: 7,
        // 惡意 client 偽造其他使用者的 ID
        createdBy: 999,
        items: [{ productId: 101, quantity: 2, unitPrice: '100.00', subtotal: '200.00' }],
        totalAmount: '200.00',
        taxAmount: '10.00',
        status: 'draft',
        createdAt: '2026-05-16T10:00:00.000Z',
        updatedAt: '2026-05-16T10:00:00.000Z',
      },
    };

    // 真實呼叫者（JWT）userId = 42
    const result = await processOperation(tx as never, op, 42, 'sales');

    expect(result).toEqual({ ok: true, serverId: 5001 });
    expect(tx.insertedQuotations).toHaveLength(1);
    expect(tx.insertedQuotations[0]).toMatchObject({ customerId: 7, createdBy: 42 });
    // 確保 client 偽造的 999 沒被採用
    expect(tx.insertedQuotations[0].createdBy).not.toBe(999);
  });

  it('uses JWT userId for sales_order.createdBy on standalone create (no quotation)', async () => {
    const tx = new FakeTx({});

    const op: SyncOperation = {
      id: '44444444-4444-4444-8444-444444444444',
      entityType: 'sales_order',
      operationType: 'create',
      createdAt: '2026-05-16T10:00:00.000Z',
      payload: {
        customerId: 8,
        // 惡意 client 偽造
        createdBy: 999,
        status: 'pending',
        createdAt: '2026-05-16T10:00:00.000Z',
        updatedAt: '2026-05-16T10:00:00.000Z',
      },
    };

    const result = await processOperation(tx as never, op, 17, 'sales');

    expect(result).toEqual({ ok: true, serverId: 9001 });
    expect(tx.insertedSalesOrders).toHaveLength(1);
    expect(tx.insertedSalesOrders[0]).toMatchObject({ customerId: 8, createdBy: 17 });
    expect(tx.insertedSalesOrders[0].createdBy).not.toBe(999);
  });

  it('uses JWT userId for sales_order.createdBy when converting from quotation', async () => {
    const tx = new FakeTx({
      quotationRows: [{
        id: 22,
        customerId: 9,
        createdBy: 3, // 原報價建立者
        totalAmount: '100.00',
        taxAmount: '5.00',
        status: 'draft',
        convertedToOrderId: null,
        createdAt: new Date('2026-04-01T00:00:00.000Z'),
        updatedAt: new Date('2026-04-01T00:00:00.000Z'),
        deletedAt: null,
      }],
      quotationItemRows: [{
        id: 9,
        quotationId: 22,
        salesOrderId: null,
        productId: 101,
        quantity: 1,
        unitPrice: '100.00',
        subtotal: '100.00',
      }],
    });

    const op: SyncOperation = {
      id: '55555555-5555-4555-8555-555555555555',
      entityType: 'sales_order',
      operationType: 'create',
      createdAt: '2026-05-16T10:00:00.000Z',
      payload: {
        quotationId: 22,
        customerId: 9,
        // client 嘗試以原報價建立者身份建單
        createdBy: 3,
        status: 'pending',
        createdAt: '2026-05-16T10:00:00.000Z',
        updatedAt: '2026-05-16T10:00:00.000Z',
      },
    };

    // 真實轉單者 userId = 88（不同於報價建立者）
    const result = await processOperation(tx as never, op, 88, 'sales');

    expect(result).toEqual({ ok: true, serverId: 9001 });
    // 轉單後 sales_order.createdBy 應記錄「目前操作者」，而非原報價建立者
    expect(tx.insertedSalesOrders[0]).toMatchObject({ createdBy: 88 });
  });
});
