/**
 * Customer Interactions API — Phase 2 P2-CRM C3
 *
 * 互動記錄（append-only 備忘，不支援 update）：
 *   GET    /customer-interactions?customerId=N  → 列出客戶的互動記錄（活躍）
 *   POST   /customer-interactions               → 新增
 *   DELETE /customer-interactions/:id           → 軟刪除
 *
 * 權限：sales / admin（倉管無 CRM 權限）
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq, isNull, and, desc } from 'drizzle-orm';
import { customerInteractions } from '@/schemas/customer_interactions.schema.js';
import { customers }             from '@/schemas/customers.schema.js';
import { USER_ROLES }            from '@/constants/index.js';

const ListQuery = z.object({
  customerId: z.coerce.number().int().positive(),
});

const CreateBody = z.object({
  customerId: z.number().int().positive(),
  note:       z.string().min(1).max(2000),
});

const IdParam = z.object({
  id: z.coerce.number().int().positive(),
});

export default async function customerInteractionsRoutes(app: FastifyInstance) {
  const { db } = app;

  // ── GET /customer-interactions?customerId=N ────────────
  app.get('/', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = ListQuery.safeParse(request.query);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'customerId 必須為正整數。' });
    }

    const rows = await db
      .select()
      .from(customerInteractions)
      .where(and(
        eq(customerInteractions.customerId, parsed.data.customerId),
        isNull(customerInteractions.deletedAt),
      ))
      .orderBy(desc(customerInteractions.createdAt));

    return reply.status(200).send(rows);
  });

  // ── POST /customer-interactions ────────────────────────
  app.post('/', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = CreateBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    // 確認客戶存在
    const [customer] = await db
      .select({ id: customers.id })
      .from(customers)
      .where(and(eq(customers.id, parsed.data.customerId), isNull(customers.deletedAt)));

    if (!customer) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此客戶。' });
    }

    const [created] = await db
      .insert(customerInteractions)
      .values({
        customerId: parsed.data.customerId,
        note:       parsed.data.note,
        createdBy:  request.user.userId,
      })
      .returning();

    return reply.status(201).send(created);
  });

  // ── DELETE /customer-interactions/:id ─────────────────
  app.delete('/:id', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.SALES, USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = IdParam.safeParse(request.params);
    if (!parsed.success) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'id 必須為正整數。' });
    }

    const [deleted] = await db
      .update(customerInteractions)
      .set({ deletedAt: new Date() })
      .where(and(
        eq(customerInteractions.id, parsed.data.id),
        isNull(customerInteractions.deletedAt),
      ))
      .returning();

    if (!deleted) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此記錄或已被刪除。' });
    }

    return reply.status(204).send();
  });
}
