import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { and, eq, isNull } from 'drizzle-orm';
import { USER_ROLES } from '@/constants/index.js';
import { salesOrders } from '@/schemas/sales_orders.schema.js';
import { requireTenantId, tenantFilter } from '@/services/tenant.service.js';

const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

export default async function salesOrdersRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/:id', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const tenantId = requireTenantId(request);
    const row = await db.query.salesOrders.findFirst({
      where: and(
        eq(salesOrders.id, parsed.data.id),
        isNull(salesOrders.deletedAt),
        tenantFilter(salesOrders.tenantId, tenantId),
      ),
      with: {
        customer: true,
        orderItems: { with: { product: true } },
      },
    });

    if (!row) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此訂單。' });
    }

    const isWarehouse = request.user.role === USER_ROLES.WAREHOUSE;
    const pretaxTotal = row.orderItems.reduce((sum, item) => sum + Number(item.subtotal), 0);
    const taxAmount = pretaxTotal * 0.05;
    const totalAmount = pretaxTotal + taxAmount;

    return reply.status(200).send({
      id: row.id,
      quotationId: row.quotationId,
      customerId: row.customerId,
      customerName: row.customer.name,
      createdBy: row.createdBy,
      status: row.status,
      paymentStatus: isWarehouse ? null : row.paymentStatus,
      confirmedAt: row.confirmedAt,
      shippedAt: row.shippedAt,
      paidAt: row.paidAt,
      dueDate: row.dueDate,
      totalAmount: isWarehouse ? null : totalAmount.toFixed(2),
      taxAmount: isWarehouse ? null : taxAmount.toFixed(2),
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      items: row.orderItems.map((item) => ({
        productId: item.productId,
        productName: item.product.name,
        sku: item.product.sku,
        quantity: item.quantity,
        unitPrice: isWarehouse ? null : item.unitPrice,
        subtotal: isWarehouse ? null : item.subtotal,
      })),
    });
  });
}
