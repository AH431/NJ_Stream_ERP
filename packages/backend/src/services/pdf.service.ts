/**
 * PDF 產生服務（中英雙語格式）
 *
 * 報價單：四區塊灰階設計
 *   1. 文件抬頭區  — 公司資訊 + 文件名稱
 *   2. 核心資訊區  — 客戶資料 + 報價單號 / 日期 / 有效期
 *   3. 報價明細區  — 品項表格 + 金額合計
 *   4. 備註與簽核區 — 備註欄 + 雙欄簽名框
 *
 * 銷售訂單 / 對帳單：維持既有雙欄排版
 *
 * 字型優先順序：
 *   1. assets/fonts/NotoSansTC-VariableFont_wght.ttf
 *   2. Windows 系統字型 Microsoft JhengHei（開發機備援）
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
const CANDIDATE_FONTS = [
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-VariableFont_wght.ttf'),
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-Regular.ttf'),
  'C:\\Windows\\Fonts\\msjhbd.ttf',
  'C:\\Windows\\Fonts\\msjh.ttf',
];
const CJK_FONT_PATH = CANDIDATE_FONTS.find(p => existsSync(p)) ?? null;
const FONT_NAME = CJK_FONT_PATH ? 'CJK' : 'Helvetica';

// ── 公司資訊（環境變數，報價單抬頭用） ────────────────────
const CO = {
  name:    process.env.COMPANY_NAME    ?? 'NJ Stream',
  address: process.env.COMPANY_ADDRESS ?? '',
  phone:   process.env.COMPANY_PHONE   ?? '',
  email:   process.env.COMPANY_EMAIL   ?? '',
  taxId:   process.env.COMPANY_TAX_ID  ?? '',
};

// ── 灰階色盤 ─────────────────────────────────────────────
const G = {
  black:  '#111111',
  dark:   '#2d2d2d',
  mid:    '#666666',
  stripe: '#f4f4f4',
  border: '#cccccc',
  white:  '#ffffff',
};

// ── 基礎工具 ──────────────────────────────────────────────

function makeDoc(): PDFKit.PDFDocument {
  const doc = new PDFDocument({ margin: 40, size: 'A4' });
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

function fmtMoney(value: string | number): string {
  const n = typeof value === 'number' ? value : parseFloat(value);
  return 'NT$ ' + n.toLocaleString('zh-TW', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
}

// ── 報價單：Section 1 — 文件抬頭區 ───────────────────────

function quotDrawHeader(
  doc: PDFKit.PDFDocument,
  docNum: string,
  date: Date,
  expiry: Date,
): number {
  const L = 40, R = 555;
  const COL_R = 355; // right column start x
  const COL_W = R - COL_R;

  let leftY = 40;

  // Left: company name
  doc.font(FONT_NAME).fontSize(15).fillColor(G.black)
    .text(CO.name, L, leftY, { width: 300, lineBreak: false });
  leftY += 20;

  // Left: company contact lines
  doc.fontSize(8).fillColor(G.mid);
  const coLines = [CO.address, CO.phone, CO.email,
    CO.taxId ? `統編 Tax ID：${CO.taxId}` : ''].filter(s => s.length > 0);
  for (const line of coLines) {
    doc.text(line, L, leftY, { width: 300, lineBreak: false });
    leftY += 12;
  }

  // Right: document title block
  doc.font(FONT_NAME).fontSize(22).fillColor(G.black)
    .text('報價單', COL_R, 40, { width: COL_W, align: 'right', lineBreak: false });
  doc.fontSize(10).fillColor(G.mid)
    .text('Quotation', COL_R, 66, { width: COL_W, align: 'right', lineBreak: false });
  doc.fontSize(8).fillColor(G.mid)
    .text(`單號 No.：${docNum}`, COL_R, 82, { width: COL_W, align: 'right', lineBreak: false })
    .text(`日期 Date：${date.toLocaleDateString('zh-TW')}`, COL_R, 94, { width: COL_W, align: 'right', lineBreak: false })
    .text(`有效至 Valid：${expiry.toLocaleDateString('zh-TW')}`, COL_R, 106, { width: COL_W, align: 'right', lineBreak: false });

  const y = Math.max(leftY, 120) + 10;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(0.5).stroke(G.border);
  return y + 12;
}

// ── 報價單：Section 2 — 核心資訊區 ───────────────────────

interface QuotCustomer {
  name: string;
  contact: string | null;
  email: string | null;
  taxId: string | null;
}

function quotDrawInfoBox(
  doc: PDFKit.PDFDocument,
  customer: QuotCustomer,
  docNum: string,
  date: Date,
  expiry: Date,
  startY: number,
): number {
  const L = 40, W = 515;
  const MID = L + 257;
  const PAD = 10;
  const LINE_H = 18;
  const LABEL_W = 92;

  const leftRows: [string, string][] = [
    ['客戶 / Customer', customer.name],
    ...(customer.contact ? [['聯絡人 / Contact', customer.contact] as [string, string]] : []),
    ...(customer.email   ? [['Email',             customer.email]   as [string, string]] : []),
    ...(customer.taxId   ? [['統編 / Tax ID',      customer.taxId]   as [string, string]] : []),
  ];

  const rightRows: [string, string][] = [
    ['報價單號 / No.',    docNum],
    ['報價日期 / Date',  date.toLocaleDateString('zh-TW')],
    ['有效期限 / Expiry', expiry.toLocaleDateString('zh-TW')],
  ];

  const boxRows = Math.max(leftRows.length, rightRows.length);
  const boxH    = boxRows * LINE_H + PAD * 2;

  // Box outline + vertical divider
  doc.rect(L, startY, W, boxH).lineWidth(0.5).stroke(G.border);
  doc.moveTo(MID, startY).lineTo(MID, startY + boxH).lineWidth(0.5).stroke(G.border);

  // Left column
  let ly = startY + PAD;
  for (const [label, val] of leftRows) {
    doc.font(FONT_NAME).fontSize(8).fillColor(G.mid)
      .text(label, L + PAD, ly, { width: LABEL_W, lineBreak: false });
    doc.fillColor(G.black)
      .text(val, L + PAD + LABEL_W + 2, ly,
        { width: MID - L - PAD * 2 - LABEL_W - 4, lineBreak: false });
    ly += LINE_H;
  }

  // Right column
  let ry = startY + PAD;
  for (const [label, val] of rightRows) {
    doc.font(FONT_NAME).fontSize(8).fillColor(G.mid)
      .text(label, MID + PAD, ry, { width: LABEL_W, lineBreak: false });
    doc.fillColor(G.black)
      .text(val, MID + PAD + LABEL_W + 2, ry,
        { width: W / 2 - PAD * 2 - LABEL_W - 4, lineBreak: false });
    ry += LINE_H;
  }

  return startY + boxH + 16;
}

// ── 報價單：Section 3 — 報價明細區 ───────────────────────

interface LineItem {
  productName: string;
  sku: string;
  quantity: number;
  unitPrice: string;
  subtotal: string;
}

function quotDrawItemsTable(
  doc: PDFKit.PDFDocument,
  items: LineItem[],
  startY: number,
): number {
  const L = 40, R = 555, W = 515;
  const C = {
    no:    L,
    name:  L + 24,
    sku:   L + 215,
    qty:   L + 315,
    price: L + 365,
    sub:   L + 450,
  };
  const HEADER_H = 20;
  const ROW_H    = 22;

  // Header bar
  doc.rect(L, startY, W, HEADER_H).fill(G.dark);
  const hy = startY + 6;
  doc.font(FONT_NAME).fontSize(8).fillColor(G.white);
  doc.text('No.',          C.no,    hy, { width: 20,  lineBreak: false });
  doc.text('品名 / Item',  C.name,  hy, { width: 187, lineBreak: false });
  doc.text('SKU',          C.sku,   hy, { width: 96,  lineBreak: false });
  doc.text('數量 / Qty',   C.qty,   hy, { width: 46,  align: 'right', lineBreak: false });
  doc.text('單價 / Price', C.price, hy, { width: 82,  align: 'right', lineBreak: false });
  doc.text('小計 / Sub',   C.sub,   hy, { width: 65,  align: 'right', lineBreak: false });

  let y = startY + HEADER_H;
  items.forEach((item, idx) => {
    const bg = idx % 2 === 1 ? G.stripe : G.white;
    doc.rect(L, y, W, ROW_H).fill(bg);
    const ry = y + 6;
    doc.font(FONT_NAME).fontSize(8.5).fillColor(G.black);
    doc.text(String(idx + 1),         C.no,    ry, { width: 20,  lineBreak: false });
    doc.text(item.productName,         C.name,  ry, { width: 187, lineBreak: false });
    doc.text(item.sku,                 C.sku,   ry, { width: 96,  lineBreak: false });
    doc.text(String(item.quantity),    C.qty,   ry, { width: 46,  align: 'right', lineBreak: false });
    doc.text(fmtMoney(item.unitPrice), C.price, ry, { width: 82,  align: 'right', lineBreak: false });
    doc.text(fmtMoney(item.subtotal),  C.sub,   ry, { width: 65,  align: 'right', lineBreak: false });
    y += ROW_H;
  });

  doc.moveTo(L, y).lineTo(R, y).lineWidth(0.5).stroke(G.border);
  return y + 12;
}

function quotDrawTotals(
  doc: PDFKit.PDFDocument,
  totalAmount: string,
  taxAmount: string,
  startY: number,
): number {
  const R = 555;
  const pretax   = parseFloat(totalAmount) - parseFloat(taxAmount);
  const BLOCK_W  = 235;
  const BLOCK_X  = R - BLOCK_W;
  const LABEL_W  = 135;
  const VAL_X    = BLOCK_X + LABEL_W;
  const VAL_W    = BLOCK_W - LABEL_W;
  const LINE_H   = 17;

  let y = startY;

  const rows: [string, string][] = [
    ['未稅小計 / Subtotal', fmtMoney(pretax.toFixed(2))],
    ['稅額 5% / Tax',       fmtMoney(taxAmount)],
  ];
  for (const [label, val] of rows) {
    doc.font(FONT_NAME).fontSize(9).fillColor(G.mid)
      .text(label, BLOCK_X, y, { width: LABEL_W, align: 'right', lineBreak: false });
    doc.fillColor(G.black)
      .text(val, VAL_X, y, { width: VAL_W, align: 'right', lineBreak: false });
    y += LINE_H;
  }

  // Total highlight
  y += 4;
  doc.rect(BLOCK_X - 8, y, BLOCK_W + 8, 24).fill(G.stripe);
  doc.font(FONT_NAME).fontSize(9).fillColor(G.mid)
    .text('含稅合計 / Total', BLOCK_X - 8, y + 7,
      { width: LABEL_W, align: 'right', lineBreak: false });
  doc.fontSize(11).fillColor(G.black)
    .text(fmtMoney(totalAmount), VAL_X, y + 5,
      { width: VAL_W, align: 'right', lineBreak: false });

  return y + 32;
}

// ── 報價單：Section 4 — 備註與簽核區 ─────────────────────

function quotDrawNotesSig(doc: PDFKit.PDFDocument, startY: number): void {
  const L = 40, R = 555, W = 515;
  const HEADER_H = 18;
  let y = startY + 10;

  // Notes box
  const NOTES_BODY_H = 54;
  doc.rect(L, y, W, HEADER_H + NOTES_BODY_H).lineWidth(0.5).stroke(G.border);
  doc.rect(L, y, W, HEADER_H).fill(G.dark);
  doc.font(FONT_NAME).fontSize(8).fillColor(G.white)
    .text('備註 / Notes', L + 8, y + 5, { width: 200, lineBreak: false });
  for (let i = 0; i < 3; i++) {
    const lY = y + HEADER_H + 10 + i * 15;
    doc.moveTo(L + 8, lY).lineTo(R - 8, lY).lineWidth(0.3).stroke(G.border);
  }
  y += HEADER_H + NOTES_BODY_H + 14;

  // Signature boxes (two columns)
  const SIG_H  = 70;
  const HALF   = Math.floor((W - 8) / 2);

  doc.rect(L, y, HALF, SIG_H).lineWidth(0.5).stroke(G.border);
  doc.rect(L, y, HALF, HEADER_H).fill(G.dark);
  doc.font(FONT_NAME).fontSize(8).fillColor(G.white)
    .text('公司簽名蓋章 / Company Signature', L + 8, y + 5,
      { width: HALF - 12, lineBreak: false });

  const SIG_RX = L + HALF + 8;
  doc.rect(SIG_RX, y, HALF, SIG_H).lineWidth(0.5).stroke(G.border);
  doc.rect(SIG_RX, y, HALF, HEADER_H).fill(G.dark);
  doc.font(FONT_NAME).fontSize(8).fillColor(G.white)
    .text('客戶簽名蓋章 / Customer Signature', SIG_RX + 8, y + 5,
      { width: HALF - 12, lineBreak: false });
}

// ── 銷售訂單 / 對帳單：舊版共用元件 ──────────────────────

function drawPageHeader(
  doc: PDFKit.PDFDocument,
  titleZh: string,
  titleEn: string,
  docNumber: string,
  date: Date,
) {
  doc.font(FONT_NAME).fontSize(18).text('NJ Stream ERP', 50, 50);
  doc.fontSize(14).text(`${titleZh} / ${titleEn}`, { align: 'right' });
  doc.moveDown(0.3);
  doc.fontSize(10)
    .text(`單號 No.：${docNumber}`, { align: 'right' })
    .text(`日期 Date：${date.toLocaleDateString('zh-TW')}`, { align: 'right' });
  doc.moveTo(50, doc.y + 8).lineTo(545, doc.y + 8).stroke();
  doc.moveDown(1);
}

function drawCustomerSection(
  doc: PDFKit.PDFDocument,
  customer: { name: string; contact: string | null; taxId: string | null },
) {
  doc.font(FONT_NAME).fontSize(10);
  doc.text(`客戶 / Customer：${customer.name}`);
  if (customer.contact) doc.text(`聯絡人 / Contact：${customer.contact}`);
  if (customer.taxId)   doc.text(`統編 / Tax ID：${customer.taxId}`);
  doc.moveDown(1);
}

function drawItemsTableLegacy(doc: PDFKit.PDFDocument, items: LineItem[]) {
  const cols = { no: 50, name: 80, sku: 240, qty: 330, price: 380, sub: 465 };

  doc.font(FONT_NAME).fontSize(8).fillColor('#444444');
  doc.text('No.',              cols.no,    doc.y, { width: 25 });
  doc.text('品名 / Item',      cols.name,  doc.y - 9, { width: 155 });
  doc.text('SKU',              cols.sku,   doc.y - 9, { width: 85 });
  doc.text('數量 / Qty',       cols.qty,   doc.y - 9, { width: 45, align: 'right' });
  doc.text('單價 / Price',     cols.price, doc.y - 9, { width: 80, align: 'right' });
  doc.text('小計 / Sub',       cols.sub,   doc.y - 9, { width: 80, align: 'right' });
  const headerBottom = doc.y + 4;
  doc.moveTo(50, headerBottom).lineTo(545, headerBottom).stroke('#aaaaaa');
  doc.moveDown(0.4);

  doc.fontSize(9).fillColor('#000000');
  items.forEach((item, idx) => {
    const y = doc.y;
    doc.text(String(idx + 1),         cols.no,    y, { width: 25 });
    doc.text(item.productName,         cols.name,  y, { width: 155 });
    doc.text(item.sku,                 cols.sku,   y, { width: 85 });
    doc.text(String(item.quantity),    cols.qty,   y, { width: 45, align: 'right' });
    doc.text(fmtMoney(item.unitPrice), cols.price, y, { width: 80, align: 'right' });
    doc.text(fmtMoney(item.subtotal),  cols.sub,   y, { width: 80, align: 'right' });
    doc.moveDown(0.6);
  });

  const tableBottom = doc.y + 2;
  doc.moveTo(50, tableBottom).lineTo(545, tableBottom).stroke('#aaaaaa');
  doc.moveDown(0.8);
}

function drawTotalsLegacy(doc: PDFKit.PDFDocument, totalAmount: string, taxAmount: string) {
  const subtotal = parseFloat(totalAmount) - parseFloat(taxAmount);
  doc.font(FONT_NAME).fontSize(10);
  doc.text(`小計 / Subtotal：${fmtMoney(String(subtotal.toFixed(2)))}`, { align: 'right' });
  doc.text(`稅額 Tax (5%)：${fmtMoney(taxAmount)}`,                     { align: 'right' });
  doc.fontSize(11).font(FONT_NAME)
    .text(`含稅合計 / Total：${fmtMoney(totalAmount)}`, { align: 'right' });
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

  const doc    = makeDoc();
  const docNum = `Q-${String(row.id).padStart(6, '0')}`;
  const expiry = new Date(row.createdAt);
  expiry.setDate(expiry.getDate() + 30);

  const customer: QuotCustomer = {
    name:    row.customer.name,
    contact: row.customer.contact ?? null,
    email:   (row.customer as { email?: string | null }).email ?? null,
    taxId:   row.customer.taxId ?? null,
  };

  let y = quotDrawHeader(doc, docNum, row.createdAt, expiry);
  y = quotDrawInfoBox(doc, customer, docNum, row.createdAt, expiry, y);
  y = quotDrawItemsTable(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })), y);
  y = quotDrawTotals(doc, row.totalAmount, row.taxAmount, y);
  quotDrawNotesSig(doc, y);

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

  const statusLabel: Record<string, string> = {
    pending:   '待確認 / Pending',
    confirmed: '已確認 / Confirmed',
    shipped:   '已出貨 / Shipped',
    cancelled: '已取消 / Cancelled',
  };

  const doc = makeDoc();
  drawPageHeader(doc, '銷售訂單', 'Sales Order', `SO-${String(row.id).padStart(6, '0')}`, row.createdAt);
  drawCustomerSection(doc, row.customer);
  doc.fontSize(10)
    .text(`狀態 Status：${statusLabel[row.status] ?? row.status}`)
    .moveDown(0.5);
  drawItemsTableLegacy(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })));
  drawTotalsLegacy(doc, totalAmount.toFixed(2), taxAmount.toFixed(2));
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
  const monthLabel = `${year}/${String(month).padStart(2, '0')}`;
  drawPageHeader(
    doc,
    '對帳單',
    'Statement',
    `ST-${customerId}-${year}${String(month).padStart(2, '0')}`,
    new Date(),
  );
  doc.font(FONT_NAME).fontSize(10).text(`期間 Period：${monthLabel}`).moveDown(0.5);
  drawCustomerSection(doc, customer);

  if (orders.length === 0) {
    doc.fontSize(10).text(`${monthLabel} 無訂單記錄 / No orders.`);
  } else {
    let grandTotal = 0;

    orders.forEach(order => {
      const orderTotal = order.orderItems.reduce((s, i) => s + parseFloat(i.subtotal), 0);
      grandTotal += orderTotal;
      const orderTax = orderTotal * 0.05;

      doc.font(FONT_NAME).fontSize(10)
        .text(
          `訂單 Order SO-${String(order.id).padStart(6, '0')}  ${order.createdAt.toLocaleDateString('zh-TW')}` +
          `  (${orderTotal > 0 ? fmtMoney(orderTotal.toFixed(2)) : '--'})`,
        )
        .moveDown(0.3);

      drawItemsTableLegacy(doc, order.orderItems.map(i => ({
        productName: i.product.name,
        sku:         i.product.sku,
        quantity:    i.quantity,
        unitPrice:   i.unitPrice,
        subtotal:    i.subtotal,
      })));
      drawTotalsLegacy(doc, orderTotal.toFixed(2), orderTax.toFixed(2));
      doc.moveDown(1);
    });

    // 月結總計
    doc.moveTo(50, doc.y).lineTo(545, doc.y).stroke();
    doc.moveDown(0.5);
    const grandTax = grandTotal * 0.05;
    doc.font(FONT_NAME).fontSize(12)
      .text(
        `${monthLabel} 月結合計 / Monthly Total：${fmtMoney((grandTotal + grandTax).toFixed(2))}`,
        { align: 'right' },
      );
  }

  return docToBuffer(doc);
}
