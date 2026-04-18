/**
 * Documents API — PDF 下載 & Email 寄送
 *
 * 權限（對應 PRD §3）：
 *   Sales / Admin 可執行所有路由；Warehouse 無此功能。
 *
 * Email 路由依賴 customers.email 欄位（migration 0002）及 .env SMTP 設定。
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, and, isNull } from 'drizzle-orm';
import { USER_ROLES } from '@/constants/index.js';
import { customers, quotations, salesOrders } from '@/schemas/index.js';
import {
  generateQuotationPdf,
  generateSalesOrderPdf,
  generateStatementPdf,
} from '@/services/pdf.service.js';
import { sendDocumentEmail } from '@/services/email.service.js';

const IdParam   = z.object({ id: z.coerce.number().int().positive() });
const StmtParam = z.object({
  id:    z.coerce.number().int().positive(),
  year:  z.coerce.number().int().min(2000).max(2100),
  month: z.coerce.number().int().min(1).max(12),
});

export default async function documentsRoutes(app: FastifyInstance) {
  const { db } = app;
  const salesAdmin = [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)];

  // ── GET /quotations/:id/pdf ────────────────────────────
  app.get('/quotations/:id/pdf', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id } = IdParam.parse(request.params);
    const buf = await generateQuotationPdf(db, id);
    return reply
      .header('Content-Type', 'application/pdf')
      .header('Content-Disposition', `attachment; filename="quotation-${id}.pdf"`)
      .send(buf);
  });

  // ── GET /sales-orders/:id/pdf ─────────────────────────
  app.get('/sales-orders/:id/pdf', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id } = IdParam.parse(request.params);
    const buf = await generateSalesOrderPdf(db, id);
    return reply
      .header('Content-Type', 'application/pdf')
      .header('Content-Disposition', `attachment; filename="order-${id}.pdf"`)
      .send(buf);
  });

  // ── GET /customers/:id/statement ──────────────────────
  // Query params: ?year=2026&month=4
  app.get('/customers/:id/statement', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id, year, month } = StmtParam.parse({
      ...(request.params as object),
      ...(request.query as object),
    });
    const buf = await generateStatementPdf(db, id, year, month);
    const monthStr = `${year}${String(month).padStart(2, '0')}`;
    return reply
      .header('Content-Type', 'application/pdf')
      .header('Content-Disposition', `attachment; filename="statement-${id}-${monthStr}.pdf"`)
      .send(buf);
  });

  // ── POST /quotations/:id/send-email ───────────────────
  app.post('/quotations/:id/send-email', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id } = IdParam.parse(request.params);

    const row = await db.query.quotations.findFirst({
      where: and(eq(quotations.id, id), isNull(quotations.deletedAt)),
      with: { customer: true },
    });
    if (!row) return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此報價單。' });
    if (!row.customer.email) {
      return reply.status(422).send({ code: 'MISSING_EMAIL', message: '此客戶尚未設定 email，請先至客戶資料填寫。' });
    }

    const buf = await generateQuotationPdf(db, id);
    const { previewUrl } = await sendDocumentEmail({
      to:                 row.customer.email,
      subject:            `【報價單】${row.customer.name} — Q-${String(id).padStart(6, '0')}`,
      text:               `您好，\n\n請見附件報價單 Q-${String(id).padStart(6, '0')}。\n\n如有任何問題，歡迎與我們聯絡。\n\nNJ Stream ERP`,
      attachmentFilename: `quotation-${id}.pdf`,
      pdfBuffer:          buf,
    });

    return reply.status(200).send({ message: `報價單已寄送至 ${row.customer.email}。`, previewUrl: previewUrl || null });
  });

  // ── POST /sales-orders/:id/send-email ─────────────────
  app.post('/sales-orders/:id/send-email', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id } = IdParam.parse(request.params);

    const row = await db.query.salesOrders.findFirst({
      where: and(eq(salesOrders.id, id), isNull(salesOrders.deletedAt)),
      with: { customer: true },
    });
    if (!row) return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此訂單。' });
    if (!row.customer.email) {
      return reply.status(422).send({ code: 'MISSING_EMAIL', message: '此客戶尚未設定 email，請先至客戶資料填寫。' });
    }

    const buf = await generateSalesOrderPdf(db, id);
    const { previewUrl } = await sendDocumentEmail({
      to:                 row.customer.email,
      subject:            `【訂單確認】${row.customer.name} — SO-${String(id).padStart(6, '0')}`,
      text:               `您好，\n\n請見附件訂單 SO-${String(id).padStart(6, '0')} 確認書。\n\n如有任何問題，歡迎與我們聯絡。\n\nNJ Stream ERP`,
      attachmentFilename: `order-${id}.pdf`,
      pdfBuffer:          buf,
    });

    return reply.status(200).send({ message: `訂單已寄送至 ${row.customer.email}。`, previewUrl: previewUrl || null });
  });

  // ── POST /customers/:id/send-statement ────────────────
  // Body: { year: number, month: number }
  app.post('/customers/:id/send-statement', {
    preHandler: salesAdmin,
  }, async (request, reply) => {
    const { id } = IdParam.parse(request.params);
    const { year, month } = z.object({
      year:  z.number().int().min(2000).max(2100),
      month: z.number().int().min(1).max(12),
    }).parse(request.body);

    const customer = await db.query.customers.findFirst({
      where: and(eq(customers.id, id), isNull(customers.deletedAt)),
    });
    if (!customer) return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此客戶。' });
    if (!customer.email) {
      return reply.status(422).send({ code: 'MISSING_EMAIL', message: '此客戶尚未設定 email，請先至客戶資料填寫。' });
    }

    const buf = await generateStatementPdf(db, id, year, month);
    const monthLabel = `${year}年${String(month).padStart(2, '0')}月`;
    const { previewUrl } = await sendDocumentEmail({
      to:                 customer.email,
      subject:            `【對帳單】${customer.name} — ${monthLabel}`,
      text:               `您好，\n\n請見附件 ${monthLabel} 對帳單。\n\n如有任何問題，歡迎與我們聯絡。\n\nNJ Stream ERP`,
      attachmentFilename: `statement-${id}-${year}${String(month).padStart(2, '0')}.pdf`,
      pdfBuffer:          buf,
    });

    return reply.status(200).send({ message: `對帳單已寄送至 ${customer.email}。`, previewUrl: previewUrl || null });
  });
}
