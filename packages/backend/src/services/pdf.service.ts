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

// ── 內部型別 ──────────────────────────────────────────────

type LineItem = {
  productName: string;
  sku:         string;
  quantity:    number;
  unitPrice:   string | number;
  subtotal:    string | number;
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

// ── 通用組件：Section 1 — 文件抬頭區 ───────────────────────

function drawDocHeader(
  doc: PDFKit.PDFDocument,
  titleZh: string,
  titleEn: string,
  docNum: string,
  date: Date,
  extraLines: [string, string][] = [], // 例如 [['有效至 Valid', '2024/05/20']]
): number {
  const L = 40, R = 555;
  const COL_R = 330; // right column start x
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
    .text(titleZh, COL_R, 40, { width: COL_W, align: 'right', lineBreak: false });
  doc.fontSize(10).fillColor(G.mid)
    .text(titleEn, COL_R, 66, { width: COL_W, align: 'right', lineBreak: false });
  
  let ry = 82;
  doc.fontSize(8).fillColor(G.mid)
    .text(`單號 No.：${docNum}`, COL_R, ry, { width: COL_W, align: 'right', lineBreak: false });
  ry += 12;
  doc.text(`日期 Date：${date.toLocaleDateString('zh-TW')}`, COL_R, ry, { width: COL_W, align: 'right', lineBreak: false });
  ry += 12;

  for (const [label, val] of extraLines) {
    doc.text(`${label}：${val}`, COL_R, ry, { width: COL_W, align: 'right', lineBreak: false });
    ry += 12;
  }

  const y = Math.max(leftY, ry) + 10;
  doc.moveTo(L, y).lineTo(R, y).lineWidth(0.5).stroke(G.border);
  return y + 12;
}

// ── 通用組件：Section 2 — 核心資訊區 ───────────────────────

interface DocCustomer {
  name: string;
  contact: string | null;
  email: string | null;
  taxId: string | null;
}

function drawDocInfoBox(
  doc: PDFKit.PDFDocument,
  customer: DocCustomer,
  rightRows: [string, string][],
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

// ── 通用組件：Section 3 — 明細表格 ─────────────────────────

function drawDocItemsTable(
  doc: PDFKit.PDFDocument,
  items: LineItem[],
  startY: number,
  options: { showHeader?: boolean, stripeOffset?: number } = {},
): number {
  const { showHeader = true, stripeOffset = 0 } = options;
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

  let y = startY;

  // Header bar
  if (showHeader) {
    doc.rect(L, y, W, HEADER_H).fill(G.dark);
    const hy = y + 6;
    doc.font(FONT_NAME).fontSize(8).fillColor(G.white);
    doc.text('No.',          C.no,    hy, { width: 20,  lineBreak: false });
    doc.text('品名 / Item',  C.name,  hy, { width: 187, lineBreak: false });
    doc.text('SKU',          C.sku,   hy, { width: 96,  lineBreak: false });
    doc.text('數量 / Qty',   C.qty,   hy, { width: 46,  align: 'right', lineBreak: false });
    doc.text('單價 / Price', C.price, hy, { width: 82,  align: 'right', lineBreak: false });
    doc.text('小計 / Sub',   C.sub,   hy, { width: 65,  align: 'right', lineBreak: false });
    y += HEADER_H;
  }

  items.forEach((item, idx) => {
    // 檢查分頁
    if (y > 750) {
      doc.addPage();
      y = 40;
      // 分頁後重繪表頭（可選）
      if (showHeader) {
         doc.rect(L, y, W, HEADER_H).fill(G.dark);
         doc.font(FONT_NAME).fontSize(8).fillColor(G.white);
         doc.text('No.', C.no, y + 6);
         doc.text('品名 / Item', C.name, y + 6);
         y += HEADER_H;
      }
    }

    const bg = (idx + stripeOffset) % 2 === 1 ? G.stripe : G.white;
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

// ── 通用組件：Section 4 — 金額合計 ─────────────────────────

function drawDocTotals(
  doc: PDFKit.PDFDocument,
  totalAmount: string,
  taxAmount: string,
  startY: number,
  options: { labelPrefix?: string } = {},
): number {
  const { labelPrefix = '' } = options;
  const R = 555;
  const pretax   = parseFloat(totalAmount) - parseFloat(taxAmount);
  const BLOCK_W  = 235;
  const BLOCK_X  = R - BLOCK_W;
  const LABEL_W  = 135;
  const VAL_X    = BLOCK_X + LABEL_W;
  const VAL_W    = BLOCK_W - LABEL_W;
  const LINE_H   = 17;

  let y = startY;
  const isTaxed = parseFloat(taxAmount) > 0;

  const rows: [string, string][] = [
    [
      isTaxed ? `${labelPrefix}未稅小計 / Subtotal` : `${labelPrefix}小計 (未稅) / Subtotal (excl. tax)`,
      fmtMoney(pretax.toFixed(2)),
    ],
    [
      isTaxed ? `${labelPrefix}稅額 5% / Tax` : `${labelPrefix}稅額 Tax`,
      isTaxed ? fmtMoney(taxAmount) : '—',
    ],
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
  const totalLabel = isTaxed ? `${labelPrefix}含稅合計 / Total` : `${labelPrefix}合計 (未稅) / Total (excl. tax)`;
  doc.font(FONT_NAME).fontSize(9).fillColor(G.mid)
    .text(totalLabel, BLOCK_X - 8, y + 7,
      { width: LABEL_W, align: 'right', lineBreak: false });
  doc.fontSize(11).fillColor(G.black)
    .text(fmtMoney(totalAmount), VAL_X, y + 5,
      { width: VAL_W, align: 'right', lineBreak: false });

  return y + 32;
}

// ── 通用組件：Section 5 — 備註與簽核 ───────────────────────

function drawDocNotesSig(
  doc: PDFKit.PDFDocument, 
  startY: number,
  options: { showSig?: boolean } = { showSig: true },
): void {
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

  if (options.showSig) {
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

  const customer: DocCustomer = {
    name:    row.customer.name,
    contact: row.customer.contact ?? null,
    email:   (row.customer as any).email ?? null,
    taxId:   row.customer.taxId ?? null,
  };

  let y = drawDocHeader(doc, '報價單', 'Quotation', docNum, row.createdAt, [
    ['有效至 Valid', expiry.toLocaleDateString('zh-TW')],
  ]);
  
  y = drawDocInfoBox(doc, customer, [
    ['報價單號 / No.', docNum],
    ['報價日期 / Date', row.createdAt.toLocaleDateString('zh-TW')],
    ['有效期限 / Expiry', expiry.toLocaleDateString('zh-TW')],
  ], y);

  y = drawDocItemsTable(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })), y);

  y = drawDocTotals(doc, row.totalAmount, row.taxAmount, y);
  drawDocNotesSig(doc, y);

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
  const docNum = `SO-${String(row.id).padStart(6, '0')}`;
  
  const customer: DocCustomer = {
    name:    row.customer.name,
    contact: row.customer.contact ?? null,
    email:   (row.customer as any).email ?? null,
    taxId:   row.customer.taxId ?? null,
  };

  let y = drawDocHeader(doc, '銷售訂單', 'Sales Order', docNum, row.createdAt);
  
  y = drawDocInfoBox(doc, customer, [
    ['訂單單號 / No.', docNum],
    ['下單日期 / Date', row.createdAt.toLocaleDateString('zh-TW')],
    ['訂單狀態 / Status', statusLabel[row.status] ?? row.status],
  ], y);

  y = drawDocItemsTable(doc, row.orderItems.map(i => ({
    productName: i.product.name,
    sku:         i.product.sku,
    quantity:    i.quantity,
    unitPrice:   i.unitPrice,
    subtotal:    i.subtotal,
  })), y);

  y = drawDocTotals(doc, totalAmount.toFixed(2), taxAmount.toFixed(2), y);
  drawDocNotesSig(doc, y, { showSig: true });

  return docToBuffer(doc);
}

export async function generateStatementPdf(
  db: DrizzleDb,
  customerId: number,
  year: number,
  month: number,
): Promise<Buffer> {
  const customerRecord = await db.query.customers.findFirst({
    where: and(eq(customers.id, customerId), isNull(customers.deletedAt)),
  });
  if (!customerRecord) throw Object.assign(new Error('NOT_FOUND'), { statusCode: 404 });

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
  const docNum = `ST-${customerId}-${year}${String(month).padStart(2, '0')}`;
  const periodLabel = `${year}/${String(month).padStart(2, '0')}`;

  const customer: DocCustomer = {
    name:    customerRecord.name,
    contact: customerRecord.contact ?? null,
    email:   (customerRecord as any).email ?? null,
    taxId:   customerRecord.taxId ?? null,
  };

  let y = drawDocHeader(doc, '月結對帳單', 'Monthly Statement', docNum, new Date());

  y = drawDocInfoBox(doc, customer, [
    ['對帳單號 / No.', docNum],
    ['對帳期間 / Period', periodLabel],
    ['訂單數量 / Count', String(orders.length)],
  ], y);

  if (orders.length === 0) {
    doc.font(FONT_NAME).fontSize(10).fillColor(G.mid)
      .text(`${periodLabel} 無訂單記錄 / No orders found in this period.`, 40, y);
  } else {
    let grandTotal = 0;
    let grandTax   = 0;

    orders.forEach((order, idx) => {
      const orderTotal = order.orderItems.reduce((s, i) => s + parseFloat(i.subtotal), 0);
      const orderTax   = orderTotal * 0.05;
      grandTotal += orderTotal;
      grandTax   += orderTax;

      // 每個訂單的小標題
      doc.font(FONT_NAME).fontSize(9).fillColor(G.dark)
        .text(`訂單 Order SO-${String(order.id).padStart(6, '0')} (${order.createdAt.toLocaleDateString('zh-TW')})`, 40, y);
      y += 14;

      y = drawDocItemsTable(doc, order.orderItems.map(i => ({
        productName: i.product.name,
        sku:         i.product.sku,
        quantity:    i.quantity,
        unitPrice:   i.unitPrice,
        subtotal:    i.subtotal,
      })), y, { showHeader: idx === 0 }); // 僅第一筆顯示表頭以節省空間

      y = drawDocTotals(doc, (orderTotal + orderTax).toFixed(2), orderTax.toFixed(2), y, { labelPrefix: '訂單' });
      y += 10;
    });

    // 最後的月結總計
    doc.moveTo(40, y).lineTo(555, y).lineWidth(1).stroke(G.black);
    y += 10;
    y = drawDocTotals(doc, (grandTotal + grandTax).toFixed(2), grandTax.toFixed(2), y, { labelPrefix: '月結' });
  }

  drawDocNotesSig(doc, y, { showSig: false });

  return docToBuffer(doc);
}
