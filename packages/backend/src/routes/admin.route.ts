/**
 * Admin Route — POST /api/v1/admin/cleanup
 *
 * 職責：
 *   定期清理超過保留期限的舊記錄，釋放 DB 空間。
 *   依同步協定 v1.6 Addendum，processed_operations 保留 30 天。
 *   軟刪除（soft-delete）記錄另保留 30 天後可清除。
 *
 * 權限：僅 admin 可執行。
 * 觸發：人工（DevSettingsScreen）或定期 script，無自動排程。
 */

import type { FastifyInstance } from 'fastify';
import { lt, and, isNotNull } from 'drizzle-orm';
import { processedOperations } from '@/schemas/processed_operations.schema.js';
import { customers }    from '@/schemas/customers.schema.js';
import { products }     from '@/schemas/products.schema.js';
import { quotations }   from '@/schemas/quotations.schema.js';
import { salesOrders }  from '@/schemas/sales_orders.schema.js';
import { SYNC, SOFT_DELETE_RETENTION_DAYS, USER_ROLES } from '@/constants/index.js';

export default async function adminRoutes(app: FastifyInstance) {
  const { db } = app;

  /**
   * POST /api/v1/admin/cleanup
   *
   * 清理兩類舊記錄：
   *   1. processed_operations：processedAt 超過 SYNC.CLEANUP_DAYS（30 天）
   *   2. 軟刪除記錄（customers / products / quotations / salesOrders）：
   *      deletedAt 超過 SOFT_DELETE_RETENTION_DAYS（30 天）
   *
   * 回傳各類型刪除筆數，供前端顯示結果。
   */
  app.post('/cleanup', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (_request, reply) => {
    const cutoffProcessed = new Date(
      Date.now() - SYNC.CLEANUP_DAYS * 24 * 60 * 60 * 1000,
    );
    const cutoffSoftDelete = new Date(
      Date.now() - SOFT_DELETE_RETENTION_DAYS * 24 * 60 * 60 * 1000,
    );

    // 1. processed_operations：超過 30 天的審計記錄
    const deletedProcessed = await db
      .delete(processedOperations)
      .where(lt(processedOperations.processedAt, cutoffProcessed))
      .returning({ id: processedOperations.id });

    // 2. 軟刪除記錄：各 entity 類型超過 30 天的已刪除記錄
    const deletedCustomers = await db
      .delete(customers)
      .where(and(isNotNull(customers.deletedAt), lt(customers.deletedAt, cutoffSoftDelete)))
      .returning({ id: customers.id });

    const deletedProducts = await db
      .delete(products)
      .where(and(isNotNull(products.deletedAt), lt(products.deletedAt, cutoffSoftDelete)))
      .returning({ id: products.id });

    const deletedQuotations = await db
      .delete(quotations)
      .where(and(isNotNull(quotations.deletedAt), lt(quotations.deletedAt, cutoffSoftDelete)))
      .returning({ id: quotations.id });

    const deletedSalesOrders = await db
      .delete(salesOrders)
      .where(and(isNotNull(salesOrders.deletedAt), lt(salesOrders.deletedAt, cutoffSoftDelete)))
      .returning({ id: salesOrders.id });

    app.log.info({
      deletedProcessedOps: deletedProcessed.length,
      deletedSoftDeleted: {
        customers:   deletedCustomers.length,
        products:    deletedProducts.length,
        quotations:  deletedQuotations.length,
        salesOrders: deletedSalesOrders.length,
      },
    }, 'Admin cleanup completed');

    return reply.status(200).send({
      deletedProcessedOps: deletedProcessed.length,
      deletedSoftDeleted: {
        customers:   deletedCustomers.length,
        products:    deletedProducts.length,
        quotations:  deletedQuotations.length,
        salesOrders: deletedSalesOrders.length,
      },
      cutoffProcessed:   cutoffProcessed.toISOString(),
      cutoffSoftDelete: cutoffSoftDelete.toISOString(),
    });
  });
}
