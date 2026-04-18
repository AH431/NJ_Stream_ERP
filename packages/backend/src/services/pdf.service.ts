/**
 * PDF 產生服務
 *
 * 字型優先順序：
 *   1. assets/fonts/NotoSansTC-Regular.ttf（跨平台，需手動放置）
 *   2. Windows 系統字型 Microsoft JhengHei（開發機備援）
 *
 * 若兩者皆不存在，pdfkit 使用內建 Helvetica（中文會顯示方塊）。
 */

import PDFDocument from 'pdfkit';
import { eq, and, gte, lt, isNull } from 'drizzle-orm';
import { existsSync } from 'fs';
import { join } from 'path';
import type { DrizzleDb } from '@/plugins/db.js';
import {
  quotations, salesOrders, customers,
} from '@/schemas/index.js';

// ── 字型設定 ──────────────────────────────────────────────
// 只接受 .ttf（pdfkit 不支援 .ttc collection 格式）
const CANDIDATE_FONTS = [
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-VariableFont_wght.ttf'),
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-Regular.ttf'),
  'C:\\Windows\\Fonts\\msjhbd.ttf',
  'C:\\Windows\\Fonts\\msjh.ttf',
];
const CJK_FONT_PATH = CANDIDATE_FONTS.find(p => existsSync(p)) ?? null;
const FONT_NAME = CJK_FONT_PATH ? 'CJK' : 'Helvetica';

function makeDoc(): PDFKit.PDFDocument {
  const doc = new PDFDocument({ margin: 50, size: 'A4' });
  if (CJK_FONT_PATH) doc.registerFont('CJK', CJK_FONT_PATH);
  return doc;
}

function docToBuffer(doc: PDFKit.PDFDocument): Promise<Buffer> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
    doc.end();
  });
}

// ── 共用排版元件 ──────────────────────────────────────────

function drawPageHeader(doc: PDFKit.PDFDocument, title: string, docNumber: string, date: Date) {
  doc.font(FONT_NAME).fontSize(18).text('NJ Stream ERP', 50, 50);
  doc.fontSize(14).text(title, { align: 'right' });
  doc.moveDown(0.3);
  doc.fontSize(10)
    .text(`單號：${docNumber}`, { align: 'right' })
    .text(`日期：${date.toLocaleDateString('zh-TW')}`, { align: 'right' });
  doc.moveTo(50, doc.y + 8).lineTo(545, doc.y + 8).stroke();
  doc.moveDown(1);
}

function drawCustomerSection(
  doc: PDFKit.PDFDocument,
  customer: { name: string; contact: string | null; taxId: string | null },
) {
  doc.font(FONT_NAME).fontSize(10);
  doc.text(`客戶：${customer.name}`);
  if (customer.contact) doc.text(`聯絡人：${customer.contact}`);
  if (customer.taxId)   doc.text(`統一編號：${customer.taxId}`);
  doc.moveDown(1);
}

interface LineItem {
  productName: string;
  sku: string;
  quantity: number;
  unitPrice: string;
  subtotal: string;
}

function drawItemsTable(doc: PDFKit.PDFDocument, items: LineItem[]) {
  const cols = { no: 50, name: 80, sku: 250, qty: 340, price: 390, sub: 470 };

  // 表頭
  doc.font(FONT_NAME).fontSize(9).fillColor('#444444');
  doc.text('No.',        cols.no,   doc.y, { width: 25 });
  doc.text('品名',       cols.name, doc.y - 9, { width: 165 });
  doc.text('SKU',        cols.sku,  doc.y - 9, { width: 85 });
  doc.text('數量',       cols.qty,  doc.y - 9, { width: 45, align: 'right' });
  doc.text('單價',       cols.price, doc.y - 9, { width: 75, align: 'right' });
  doc.text('小計',       cols.sub,  doc.y - 9, { width: 75, align: 'right' });
  const headerBottom = doc.y + 4;
  doc.moveTo(50, headerBottom).lineTo(545, headerBottom).stroke('#aaaaaa');
  doc.moveDown(0.4);

  // 明細列
  doc.fillColor('#000000');
  items.forEach((item, idx) => {
    const y = doc.y;
    doc.text(String(idx + 1),       cols.no,   y, { width: 25 });
    doc.text(item.productName,       cols.name, y, { width: 165 });
    doc.text(item.sku,               cols.sku,  y, { width: 85 });
    doc.text(String(item.quantity),  cols.qty,  y, { width: 45, align: 'right' });
    doc.text(fmtMoney(item.unitPrice), cols.price, y, { width: 75, align: 'right' });
    doc.text(fmtMoney(item.subtotal),  cols.sub,   y, { width: 75, align: 'right' });
    doc.moveDown(0.6);
  });

  const tableBottom = doc.y + 2;
  doc.moveTo(50, tableBottom).lineTo(545, tableBottom).stroke('#aaaaaa');
  doc.moveDown(0.8);
}

function drawTotals(doc: PDFKit.PDFDocument, totalAmount: string, taxAmount: string) {
  const subtotal = parseFloat(totalAmount) - parseFloat(taxAmount);
  doc.font(FONT_NAME).fontSize(10);
  doc.text(`未稅金額：${fmtMoney(String(subtotal.toFixed(2)))}`, { align: 'right' });
  doc.text(`稅額（5%）：${fmtMoney(taxAmount)}`,                 { align: 'right' });
  doc.fontSize(11).font(FONT_NAME)
    .text(`含稅總計：${fmtMoney(totalAmount)}`, { align: 'right' });
}

function fmtMoney(value: string): string {
  const n = parseFloat(value);
  return 'NT$ ' + n.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

// ── 公開 API ──────────────────────────────────────────────

export async function generateQuotationPdf(db: DrizzleDb, quotationId: number): Promise<Buffer> {
  const row = await db.query.quotations.findFirst({
    where: and(eq(quotations.id, quotationId), isNull(quotations.deletedAt)),
    with: {
      customer:   true,
      orderItems: { with: { product: true } },
    },
  });
  if (!row) throw Object.assign(new Error('NOT_FOUND'), { statusCode: 404 });

  const doc = makeDoc();
  drawPageHeader(doc, '報價單', `Q-${String(row.id).padStart(6, '0')}`, row.createdAt);
  drawCustomerSection(doc, row.customer);
  drawItemsTable(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })));
  drawTotals(doc, row.totalAmount, row.taxAmount);
  return docToBuffer(doc);
}

export async function generateSalesOrderPdf(db: DrizzleDb, orderId: number): Promise<Buffer> {
  const row = await db.query.salesOrders.findFirst({
    where: and(eq(salesOrders.id, orderId), isNull(salesOrders.deletedAt)),
    with: {
      customer:   true,
      orderItems: { with: { product: true } },
    },
  });
  if (!row) throw Object.assign(new Error('NOT_FOUND'), { statusCode: 404 });

  const totalAmount = row.orderItems.reduce((s, i) => s + parseFloat(i.subtotal), 0);
  const taxAmount   = totalAmount * 0.05;

  const doc = makeDoc();
  drawPageHeader(doc, '銷售訂單', `SO-${String(row.id).padStart(6, '0')}`, row.createdAt);
  drawCustomerSection(doc, row.customer);

  // 訂單狀態
  const statusLabel: Record<string, string> = {
    pending: '待確認', confirmed: '已確認', shipped: '已出貨', cancelled: '已取消',
  };
  doc.fontSize(10).text(`狀態：${statusLabel[row.status] ?? row.status}`).moveDown(0.5);

  drawItemsTable(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })));
  drawTotals(doc, totalAmount.toFixed(2), taxAmount.toFixed(2));
  return docToBuffer(doc);
}

export async function generateStatementPdf(
  db: DrizzleDb,
  customerId: number,
  year: number,
  month: number,
): Promise<Buffer> {
  const customer = await db.query.customers.findFirst({
    where: and(eq(customers.id, customerId), isNull(customers.deletedAt)),
  });
  if (!customer) throw Object.assign(new Error('NOT_FOUND'), { statusCode: 404 });

  const from = new Date(year, month - 1, 1);
  const to   = new Date(year, month, 1);

  const orders = await db.query.salesOrders.findMany({
    where: and(
      eq(salesOrders.customerId, customerId),
      isNull(salesOrders.deletedAt),
      gte(salesOrders.createdAt, from),
      lt(salesOrders.createdAt, to),
    ),
    with: { orderItems: { with: { product: true } } },
    orderBy: (t, { asc }) => asc(t.createdAt),
  });

  const doc = makeDoc();
  const monthLabel = `${year}年${String(month).padStart(2, '0')}月`;
  drawPageHeader(doc, `對帳單 ${monthLabel}`, `ST-${customerId}-${year}${String(month).padStart(2, '0')}`, new Date());
  drawCustomerSection(doc, customer);

  if (orders.length === 0) {
    doc.fontSize(10).text(`${monthLabel} 無訂單記錄。`);
  } else {
    let grandTotal = 0;

    orders.forEach(order => {
      const orderTotal = order.orderItems.reduce((s, i) => s + parseFloat(i.subtotal), 0);
      grandTotal += orderTotal;
      const orderTax = orderTotal * 0.05;

      doc.font(FONT_NAME).fontSize(10)
        .text(`訂單 SO-${String(order.id).padStart(6, '0')}  ${order.createdAt.toLocaleDateString('zh-TW')}  （${orderTotal > 0 ? fmtMoney(orderTotal.toFixed(2)) : '--'}）`)
        .moveDown(0.3);

      drawItemsTable(doc, order.orderItems.map(i => ({
        productName: i.product.name,
        sku:         i.product.sku,
        quantity:    i.quantity,
        unitPrice:   i.unitPrice,
        subtotal:    i.subtotal,
      })));
      drawTotals(doc, orderTotal.toFixed(2), orderTax.toFixed(2));
      doc.moveDown(1);
    });

    // 月結總計
    doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
    doc.moveDown(0.5);
    const grandTax = grandTotal * 0.05;
    doc.font(FONT_NAME).fontSize(12)
      .text(`${monthLabel} 月結總計：${fmtMoney((grandTotal + grandTax).toFixed(2))}`, { align: 'right' });
  }

  return docToBuffer(doc);
}
