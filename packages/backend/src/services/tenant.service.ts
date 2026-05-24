import { eq } from 'drizzle-orm';
import type { FastifyRequest } from 'fastify';

/**
 * Extracts tenantId from the authenticated request context.
 * Safe to call only after verifyJwt has run (tenantId is guaranteed non-null by auth.plugin.ts).
 */
export function requireTenantId(request: FastifyRequest): number {
  return request.user.tenantId;
}

/**
 * Returns a Drizzle eq() condition scoped to the given tenant.
 * Usage: tenantFilter(table.tenantId, tenantId)
 */
// eslint-disable-next-line @typescript-eslint/no-explicit-any
export function tenantFilter(column: any, tenantId: number) {
  return eq(column, tenantId);
}
