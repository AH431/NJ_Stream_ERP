import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, isNull, and } from 'drizzle-orm';
import { inventoryItems } from '@/schemas/inventory_items.schema.js';
import { products } from '@/schemas/products.schema.js';

const InventoryQuery = z.union([
  z.object({ productId: z.coerce.number().int().positive(), sku: z.string().optional() }),
  z.object({ productId: z.coerce.number().optional(), sku: z.string().min(1).max(100) }),
]).refine(
  (data) => data.productId !== undefined || (data.sku !== undefined && data.sku.length > 0),
  { message: '必須提供 productId 或 sku 其中之一。' },
);

export default async function inventoryRoutes(app: FastifyInstance) {
  const { db } = app;

  // GET /inventory?productId=<id>  OR  ?sku=<sku>
  // availableQuantity = quantityOnHand - quantityReserved, computed server-side.
  app.get('/', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = InventoryQuery.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '必須提供 productId 或 sku 其中之一。',
      });
    }

    const { productId, sku } = parsed.data as { productId?: number; sku?: string };

    let resolvedProductId = productId;

    if (!resolvedProductId && sku) {
      const [product] = await db
        .select({ id: products.id })
        .from(products)
        .where(and(eq(products.sku, sku), isNull(products.deletedAt)));

      if (!product) {
        return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此 SKU 的產品。' });
      }
      resolvedProductId = product.id;
    }

    const [row] = await db
      .select({
        id:                 inventoryItems.id,
        productId:          inventoryItems.productId,
        warehouseId:        inventoryItems.warehouseId,
        quantityOnHand:     inventoryItems.quantityOnHand,
        quantityReserved:   inventoryItems.quantityReserved,
        minStockLevel:      inventoryItems.minStockLevel,
        alertStockLevel:    inventoryItems.alertStockLevel,
        criticalStockLevel: inventoryItems.criticalStockLevel,
        productName:        products.name,
        sku:                products.sku,
        unitPrice:          products.unitPrice,
      })
      .from(inventoryItems)
      .innerJoin(products, eq(inventoryItems.productId, products.id))
      .where(and(
        eq(inventoryItems.productId, resolvedProductId!),
        isNull(products.deletedAt),
      ));

    if (!row) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此產品的庫存資料。' });
    }

    return reply.status(200).send({
      ...row,
      availableQuantity: row.quantityOnHand - row.quantityReserved,
    });
  });
}
