/**
 * Import Route — POST /api/v1/admin/import
 *
 * 職責：
 *   接收 CSV 檔案，逐行解析並批次匯入初始資料。
 *   用於專案上線前的種子資料匯入（產品、客戶、庫存初始化）。
 *
 * 權限：僅 admin 可執行。
 * 觸發：人工（DevSettingsScreen → ImportScreen）。
 *
 * 支援類型（query param ?type=）：
 *   - product   : name,sku,unitPrice,minStockLevel
 *   - customer  : name,contact,taxId
 *   - inventory : sku,quantity
 *     （以 SKU 查 productId；warehouseId 固定 DEFAULT_WAREHOUSE_ID）
 *
 * 回傳：
 *   { type, succeeded, failed: [{ row, reason }] }
 */

import type { FastifyInstance } from 'fastify';
import { z } from 'zod';
import { eq } from 'drizzle-orm';
import { products }       from '@/schemas/products.schema.js';
import { customers }      from '@/schemas/customers.schema.js';
import { inventoryItems } from '@/schemas/inventory_items.schema.js';
import { USER_ROLES, DEFAULT_WAREHOUSE_ID } from '@/constants/index.js';

// ── Zod Row Schemas ───────────────────────────────────────────────────────────

const ProductRow = z.object({
  name:          z.string().min(1),
  sku:           z.string().min(1),
  unitPrice:     z.string().regex(/^\d+(\.\d{1,2})?$/, '必須為數字（最多 2 位小數）'),
  minStockLevel: z.string().regex(/^\d+$/, '必須為非負整數').transform(Number),
});

const CustomerRow = z.object({
  name:    z.string().min(1),
  contact: z.string().optional(),
  taxId:   z.string().optional(),
});

const InventoryRow = z.object({
  sku:      z.string().min(1),
  quantity: z.string().regex(/^\d+$/, '必須為非負整數').transform(Number),
});

// ── CSV 解析工具 ──────────────────────────────────────────────────────────────

/**
 * 簡易 CSV 解析器（不處理引號內換行，MVP 足夠用）
 * 回傳 header 與 rows（已 trim，跳過空行）
 */
function parseCsv(text: string): { headers: string[]; rows: Record<string, string>[] } {
  const lines = text.split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  if (lines.length < 2) return { headers: [], rows: [] };

  const headers = lines[0].split(',').map((h) => h.trim());
  const rows = lines.slice(1).map((line) => {
    const values = line.split(',').map((v) => v.trim());
    return Object.fromEntries(headers.map((h, i) => [h, values[i] ?? '']));
  });

  return { headers, rows };
}

// ── Route ─────────────────────────────────────────────────────────────────────

export default async function importRoutes(app: FastifyInstance) {
  const { db } = app;

  /**
   * POST /api/v1/admin/import?type=product|customer|inventory
   *
   * Body: multipart/form-data，欄位名稱 "file"，Content-Type text/csv
   */
  app.post('/import', {
    preHandler: [app.verifyJwt, app.requireRole(USER_ROLES.ADMIN)],
  }, async (request, reply) => {
    // 1. 驗證 query param
    const typeParam = (request.query as Record<string, string>)['type'];
    if (!['product', 'customer', 'inventory'].includes(typeParam)) {
      return reply.status(400).send({
        code: 'VALIDATION_ERROR',
        message: 'query param type 必須為 product | customer | inventory',
      });
    }
    const importType = typeParam as 'product' | 'customer' | 'inventory';

    // 2. 讀取 multipart file
    const data = await request.file();
    if (!data) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: '請上傳 CSV 檔案' });
    }

    const chunks: Buffer[] = [];
    for await (const chunk of data.file) {
      chunks.push(chunk);
    }
    const csvText = Buffer.concat(chunks).toString('utf-8');

    // 3. 解析 CSV
    const { rows } = parseCsv(csvText);
    if (rows.length === 0) {
      return reply.status(400).send({ code: 'VALIDATION_ERROR', message: 'CSV 無有效資料行' });
    }

    // 4. 逐行驗證並匯入
    const failed: { row: number; reason: string }[] = [];
    let succeeded = 0;

    for (let i = 0; i < rows.length; i++) {
      const rowNum = i + 2; // row 1 是 header
      const raw = rows[i];

      try {
        if (importType === 'product') {
          const parsed = ProductRow.parse(raw);
          await db.insert(products).values({
            name:          parsed.name,
            sku:           parsed.sku,
            unitPrice:     parsed.unitPrice,
            minStockLevel: parsed.minStockLevel,
          }).onConflictDoUpdate({
            target: products.sku,
            set: {
              name:          parsed.name,
              unitPrice:     parsed.unitPrice,
              minStockLevel: parsed.minStockLevel,
              updatedAt:     new Date(),
            },
          });
          succeeded++;

        } else if (importType === 'customer') {
          const parsed = CustomerRow.parse(raw);
          await db.insert(customers).values({
            name:    parsed.name,
            contact: parsed.contact ?? null,
            taxId:   parsed.taxId   ?? null,
          });
          succeeded++;

        } else {
          // inventory
          const parsed = InventoryRow.parse(raw);

          // 以 SKU 查 productId
          const [product] = await db
            .select({ id: products.id })
            .from(products)
            .where(eq(products.sku, parsed.sku))
            .limit(1);

          if (!product) {
            failed.push({ row: rowNum, reason: `SKU "${parsed.sku}" 不存在` });
            continue;
          }

          await db.insert(inventoryItems).values({
            productId:        product.id,
            warehouseId:      DEFAULT_WAREHOUSE_ID,
            quantityOnHand:   parsed.quantity,
            quantityReserved: 0,
            minStockLevel:    0,
          }).onConflictDoUpdate({
            target: inventoryItems.productId,
            set: {
              quantityOnHand: parsed.quantity,
              updatedAt:      new Date(),
            },
          });
          succeeded++;
        }
      } catch (err) {
        const reason = err instanceof z.ZodError
          ? err.errors.map((e) => `${e.path.join('.')}: ${e.message}`).join('; ')
          : String(err);
        failed.push({ row: rowNum, reason });
      }
    }

    app.log.info({ importType, succeeded, failedCount: failed.length }, 'Admin import completed');

    return reply.status(200).send({ type: importType, succeeded, failed });
  });
}
