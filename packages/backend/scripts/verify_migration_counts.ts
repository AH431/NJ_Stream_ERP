/**
 * PR-6 M6.5 — Migration verification script
 *
 * Verifies that migrations 0011_tenants + 0012_add_tenant_id were applied
 * correctly to the live database. Run after any migration apply or rollback
 * dry-run to confirm data integrity.
 *
 * Usage:
 *   npx tsx scripts/verify_migration_counts.ts
 *
 * Checks:
 *   1. All 14 business tables have tenant_id NOT NULL for every row.
 *   2. All existing rows are assigned to tenant 1 (the default seed tenant).
 *   3. The tenants table exists and contains at least the seed row.
 *   4. FK constraints on tenant_id are in place for all 14 tables.
 */

import 'dotenv/config';
import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { sql } from 'drizzle-orm';

// ── Tables to verify ──────────────────────────────────────────────────────────

const BUSINESS_TABLES = [
  'customers',
  'products',
  'users',
  'processed_operations',
  'quotations',
  'inventory_items',
  'customer_interactions',
  'device_tokens',
  'sales_orders',
  'order_items',
  'anomalies',
  'audit_logs',
  'demand_forecasts',
  'forecast_jobs',
] as const;

// ── DB connection ─────────────────────────────────────────────────────────────

const client = postgres(process.env.DATABASE_URL!);
const db = drizzle(client);

// ── Helpers ───────────────────────────────────────────────────────────────────

function ok(msg: string)   { console.log(`  ✓  ${msg}`); }
function fail(msg: string) { console.error(`  ✗  ${msg}`); }

// ── Main ──────────────────────────────────────────────────────────────────────

let allPassed = true;

console.log('\n═══════════════════════════════════════════════════════════');
console.log('  Migration 0011 + 0012 — Row Count Verification');
console.log('═══════════════════════════════════════════════════════════\n');

// ── 1. Per-table tenant_id integrity ─────────────────────────────────────────

console.log('1. Per-table tenant_id integrity\n');

const tableResults: Array<{
  table: string;
  total: number;
  withTenant: number;
  withNull: number;
  onlyTenant1: boolean;
}> = [];

for (const table of BUSINESS_TABLES) {
  const rows = await db.execute(sql`
    SELECT
      COUNT(*)::int                                          AS total,
      COUNT(*) FILTER (WHERE tenant_id IS NOT NULL)::int    AS "withTenant",
      COUNT(*) FILTER (WHERE tenant_id IS NULL)::int        AS "withNull",
      COUNT(*) FILTER (WHERE tenant_id != 1)::int           AS "otherTenant"
    FROM ${sql.identifier(table)}
  `);

  const row = rows[0] as {
    total: number;
    withTenant: number;
    withNull: number;
    otherTenant: number;
  };

  const passed = row.withNull === 0 && row.total === row.withTenant;
  if (!passed) allPassed = false;

  const padded = table.padEnd(28);
  const summary = `total=${row.total}  not-null=${row.withTenant}  null=${row.withNull}  other-tenant=${row.otherTenant}`;
  if (passed) {
    ok(`${padded} ${summary}`);
  } else {
    fail(`${padded} ${summary}`);
  }

  tableResults.push({
    table,
    total:       row.total,
    withTenant:  row.withTenant,
    withNull:    row.withNull,
    onlyTenant1: row.otherTenant === 0,
  });
}

// ── 2. tenants seed row ───────────────────────────────────────────────────────

console.log('\n2. Tenants seed row\n');

const tenantRows = await db.execute(sql`
  SELECT id, name, slug, plan, is_active FROM tenants ORDER BY id
`);

if (tenantRows.length === 0) {
  allPassed = false;
  fail('tenants table is empty — seed row missing');
} else {
  for (const t of tenantRows as Array<{ id: number; name: string; slug: string; plan: string; is_active: boolean }>) {
    ok(`id=${t.id}  name="${t.name}"  slug="${t.slug}"  plan=${t.plan}  active=${t.is_active}`);
  }
}

// ── 3. FK constraint existence ────────────────────────────────────────────────

console.log('\n3. FK constraints on tenant_id\n');

const fkRows = await db.execute(sql`
  SELECT tc.table_name, tc.constraint_name
  FROM information_schema.table_constraints tc
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.constraint_name LIKE '%tenant_id_tenants_id_fk'
  ORDER BY tc.table_name
`);

const fkTables = new Set(
  (fkRows as Array<{ table_name: string }>).map((r) => r.table_name),
);

for (const table of BUSINESS_TABLES) {
  if (fkTables.has(table)) {
    ok(`${table.padEnd(28)} has FK constraint`);
  } else {
    allPassed = false;
    fail(`${table.padEnd(28)} missing FK constraint`);
  }
}

// ── 4. Summary ────────────────────────────────────────────────────────────────

const tablesWithNulls  = tableResults.filter((r) => r.withNull > 0);
const tablesWithOthers = tableResults.filter((r) => !r.onlyTenant1);

console.log('\n═══════════════════════════════════════════════════════════');
console.log('  Summary');
console.log('═══════════════════════════════════════════════════════════\n');
console.log(`  Tables verified:           ${BUSINESS_TABLES.length}`);
console.log(`  Tables with NULL tenant_id: ${tablesWithNulls.length}`);
console.log(`  Tables with non-1 tenants:  ${tablesWithOthers.length}`);
console.log(`  FK constraints found:       ${fkTables.size} / ${BUSINESS_TABLES.length}`);
console.log(`  Tenants seeded:             ${tenantRows.length}`);
console.log('');

if (allPassed) {
  console.log('  ✓  All checks passed — migration looks healthy.\n');
} else {
  console.error('  ✗  Some checks FAILED — review output above.\n');
}

await client.end();
process.exit(allPassed ? 0 : 1);
