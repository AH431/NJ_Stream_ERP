import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { and, eq, isNull } from 'drizzle-orm';
import { USER_ROLES } from '@/constants/index.js';
import { quotations } from '@/schemas/quotations.schema.js';
import { requireTenantId, tenantFilter } from '@/services/tenant.service.js';

const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

export default async function quotationsRoutes(app: FastifyInstance) {
  const { db } = app;

  app.get('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const tenantId = requireTenantId(request);
    const row = await db.query.quotations.findFirst({
      where: and(
        eq(quotations.id, parsed.data.id),
        isNull(quotations.deletedAt),
        tenantFilter(quotations.tenantId, tenantId),
      ),
      with: {
        customer: true,
        orderItems: { with: { product: true } },
      },
    });

    if (!row) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此報價單。' });
    }

    return reply.status(200).send({
      id: row.id,
      customerId: row.customerId,
      customerName: row.customer.name,
      createdBy: row.createdBy,
      totalAmount: row.totalAmount,
      taxAmount: row.taxAmount,
      status: row.status,
      convertedToOrderId: row.convertedToOrderId,
      createdAt: row.createdAt,
      updatedAt: row.updatedAt,
      items: row.orderItems.map((item) => ({
        productId: item.productId,
        productName: item.product.name,
        sku: item.product.sku,
        quantity: item.quantity,
        unitPrice: item.unitPrice,
        subtotal: item.subtotal,
      })),
    });
  });
}
