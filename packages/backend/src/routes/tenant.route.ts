/**
 * Tenant REST API — M7.1
 *
 * 權限矩陣：
 *   GET  /tenant           → 所有已登入角色（查看自己所屬租戶）
 *   PATCH /tenant          → admin（更新租戶名稱、聯絡信箱、時區）
 *   POST /tenant/provision → 公開端點（建立新租戶 + 初始 admin 帳號）
 *
 * 不可由 PATCH 修改的欄位：slug（URL 識別碼）、plan（由後台控管）
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq } from 'drizzle-orm';
import bcrypt from 'bcryptjs';
import { tenants } from '@/schemas/tenants.schema.js';
import { users } from '@/schemas/users.schema.js';
import { USER_ROLES } from '@/constants/index.js';
import { requireTenantId } from '@/services/tenant.service.js';

// ── Zod Schema ─────────────────────────────────────────────

const PatchTenantBody = z.object({
  name:             z.string().min(1).max(100).optional(),
  contactEmail:     z.string().email().max(255).nullable().optional(),
  timezone:         z.string().min(1).max(50).optional(),
  markAsOnboarded:  z.boolean().optional(),
}).refine(
  (data) => Object.keys(data).length > 0,
  { message: '至少需要提供一個要更新的欄位。' },
);

const ProvisionBody = z.object({
  name:          z.string().min(1).max(100),
  slug:          z.string().min(2).max(50).regex(
    /^[a-z0-9-]+$/,
    'slug 只能包含小寫字母、數字和連字號。',
  ),
  plan:          z.enum(['basic', 'pro', 'enterprise']).default('basic'),
  contactEmail:  z.string().email().max(255).optional(),
  timezone:      z.string().min(1).max(50).default('UTC'),
  adminUsername: z.string().min(3).max(100),
  adminPassword: z.string().min(8).max(255),
});

// ── 路由 ──────────────────────────────────────────────────

export default async function tenantRoutes(app: FastifyInstance) {
  const { db } = app;

  // GET /tenant — 取得目前登入者所屬租戶資訊
  app.get('/', {
    preHandler: [app.verifyJwt],
  }, async (request, reply) => {
    const tenantId = requireTenantId(request);
    const [tenant] = await db
      .select()
      .from(tenants)
      .where(eq(tenants.id, tenantId));

    if (!tenant) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此租戶。' });
    }

    return reply.status(200).send(tenant);
  });

  // PATCH /tenant — 更新租戶基本資料（admin 限定）
  app.patch('/', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    const parsed = PatchTenantBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const tenantId = requireTenantId(request);
    const updates: Record<string, unknown> = {};
    const { name, contactEmail, timezone, markAsOnboarded } = parsed.data;
    if (name             !== undefined) updates.name         = name;
    if (contactEmail     !== undefined) updates.contactEmail = contactEmail;
    if (timezone         !== undefined) updates.timezone     = timezone;
    if (markAsOnboarded === true)       updates.onboardedAt  = new Date();

    const [updated] = await db
      .update(tenants)
      .set(updates)
      .where(eq(tenants.id, tenantId))
      .returning();

    if (!updated) {
      return reply.status(404).send({ code: 'NOT_FOUND', message: '找不到此租戶。' });
    }

    return reply.status(200).send(updated);
  });

  // POST /tenant/provision — 建立新租戶 + 初始 admin 帳號（公開端點）
  app.post('/provision', async (request, reply) => {
    const parsed = ProvisionBody.safeParse(request.body);
    if (!parsed.success) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: parsed.error.issues[0]?.message ?? '請求格式錯誤。',
      });
    }

    const { name, slug, plan, contactEmail, timezone, adminUsername, adminPassword } = parsed.data;

    // slug 唯一性預檢（搶在 transaction 前快速回應 409）
    const [existing] = await db
      .select({ id: tenants.id })
      .from(tenants)
      .where(eq(tenants.slug, slug));

    if (existing) {
      return reply.status(409).send({
        code: 'SLUG_CONFLICT',
        message: '此 slug 已被使用，請選擇其他名稱。',
      });
    }

    const passwordHash = await bcrypt.hash(adminPassword, 10);

    const result = await db.transaction(async (tx) => {
      const [tenant] = await tx
        .insert(tenants)
        .values({
          name,
          slug,
          plan,
          contactEmail: contactEmail ?? null,
          timezone,
          isActive: true,
        })
        .returning();

      const adminEmail = contactEmail ?? `${adminUsername}@${slug}.local`;

      const [adminUser] = await tx
        .insert(users)
        .values({
          tenantId: tenant.id,
          username: adminUsername,
          email:    adminEmail,
          password: passwordHash,
          role:     USER_ROLES.ADMIN,
          isActive: true,
        })
        .returning({
          id:       users.id,
          username: users.username,
          email:    users.email,
          role:     users.role,
        });

      return { tenant, adminUserId: adminUser.id, adminUsername: adminUser.username };
    });

    return reply.status(201).send(result);
  });
}
