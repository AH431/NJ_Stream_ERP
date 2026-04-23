/**
 * NJ Stream ERP — 產品說明書 PDF 產生腳本
 *
 * 執行：npx tsx scripts/generate-brochure.ts
 * 輸出：../../NJ_Stream_ERP_Brochure.pdf（專案根目錄）
 *
 * 5 頁內容：
 *   P1 封面      P2 目標用戶 & 市場痛點
 *   P3 核心流程  P4 ESG 永續整合   P5 快速使用指南
 */

import PDFDocument from 'pdfkit';
import { existsSync, writeFileSync, mkdirSync } from 'fs';
import { join, dirname } from 'path';

// ── 字型 ─────────────────────────────────────────────────
const CJK_PATH = [
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-VariableFont_wght.ttf'),
  join(process.cwd(), 'assets', 'fonts', 'NotoSansTC-Regular.ttf'),
  'C:\\Windows\\Fonts\\msjhbd.ttf',
  'C:\\Windows\\Fonts\\msjh.ttf',
].find(p => existsSync(p)) ?? null;
const F = CJK_PATH ? 'CJK' : 'Helvetica';

// ── 色盤 ─────────────────────────────────────────────────
const C = {
  darkGreen:  '#1b4332',
  midGreen:   '#2d6a4f',
  accent:     '#52b788',
  lightGreen: '#d8f3dc',
  eColor:     '#1b4332',   // Environment
  sColor:     '#1a3c5e',   // Social
  gColor:     '#4a1a72',   // Governance
  dark:       '#212529',
  mid:        '#6c757d',
  lightGray:  '#f2f4f6',
  white:      '#ffffff',
  red:        '#c0392b',
  redLight:   '#fdecea',
  greenLight: '#eafaf1',
  orange:     '#d35400',
};

// ── PDFDocument 工廠 ──────────────────────────────────────
function makeDoc(): PDFKit.PDFDocument {
  const doc = new PDFDocument({ margin: 0, size: 'A4' });
  if (CJK_PATH) doc.registerFont('CJK', CJK_PATH);
  return doc;
}

// ─────────────────────────────────────────────────────────
// 共用繪圖元件
// ─────────────────────────────────────────────────────────

/** 水平箭頭（(x1,y1) → (x2,y2)，y1==y2 時為純水平）*/
function hArrow(doc: PDFKit.PDFDocument, x1: number, y1: number, x2: number, y2: number, color = C.accent) {
  const y = (y1 + y2) / 2;
  doc.moveTo(x1, y).lineTo(x2 - 6, y).lineWidth(1.5).stroke(color);
  doc.moveTo(x2, y).lineTo(x2 - 8, y - 4).lineWidth(1.5).stroke(color);
  doc.moveTo(x2, y).lineTo(x2 - 8, y + 4).lineWidth(1.5).stroke(color);
}

/** 雙向水平箭頭（左右各一箭頭）*/
function biArrow(doc: PDFKit.PDFDocument, x1: number, x2: number, y: number, color = C.accent) {
  const yU = y - 5, yD = y + 5;
  // Upper: x1 → x2
  doc.moveTo(x1, yU).lineTo(x2, yU).lineWidth(1.2).stroke(color);
  doc.moveTo(x2, yU).lineTo(x2 - 7, yU - 3).lineWidth(1.2).stroke(color);
  doc.moveTo(x2, yU).lineTo(x2 - 7, yU + 3).lineWidth(1.2).stroke(color);
  // Lower: x2 → x1
  doc.moveTo(x2, yD).lineTo(x1, yD).lineWidth(1.2).stroke(C.midGreen);
  doc.moveTo(x1, yD).lineTo(x1 + 7, yD - 3).lineWidth(1.2).stroke(C.midGreen);
  doc.moveTo(x1, yD).lineTo(x1 + 7, yD + 3).lineWidth(1.2).stroke(C.midGreen);
}

/** 區塊標題（左側色條 + 中文 + 英文）→ 回傳下一個 y */
function sectionTitle(doc: PDFKit.PDFDocument, x: number, y: number, zh: string, en: string): number {
  doc.rect(x, y, 5, 28).fill(C.accent);
  doc.font(F).fontSize(15).fillColor(C.darkGreen)
    .text(zh, x + 14, y, { lineBreak: false });
  doc.fontSize(8.5).fillColor(C.mid)
    .text(en, x + 14, y + 19, { lineBreak: false });
  return y + 40;
}

/** 全頁頁尾條 */
function footer(doc: PDFKit.PDFDocument, text: string, dark = false) {
  const bg = dark ? C.darkGreen : C.lightGray;
  const fg = dark ? C.accent    : C.mid;
  const fg2 = dark ? C.lightGreen : C.mid;
  doc.rect(0, 790, 595, 52).fill(bg);
  doc.rect(0, 790, 595, 1).fill(C.accent);
  doc.font(F).fontSize(7.5).fillColor(fg)
    .text(`NJ Stream ERP  ·  ${text}`, 30, 810, { lineBreak: false });
  doc.fontSize(7).fillColor(fg2)
    .text('為中小企業而生的智慧輕量 ERP  ·  Built for SMEs', 30, 824, { lineBreak: false });
}

// ─────────────────────────────────────────────────────────
// Page 1 — 封面（Teal/Blue Tech Theme）
// ─────────────────────────────────────────────────────────
function page1(doc: PDFKit.PDFDocument) {
  const T = {
    dark:   '#052e44',
    main:   '#0a5470',
    mid:    '#0d7a9e',
    bright: '#0ea5e9',
    light:  '#bae6fd',
    pale:   '#e0f7ff',
  };

  // ── Gradient header: dark teal → mid teal (30 strips) ────
  const headerH = 238;
  const steps = 30;
  const fromRGB = [5, 46, 68];    // #052e44
  const toRGB   = [13, 122, 158]; // #0d7a9e
  for (let i = 0; i < steps; i++) {
    const t = i / (steps - 1);
    const r = Math.round(fromRGB[0] + (toRGB[0] - fromRGB[0]) * t);
    const g = Math.round(fromRGB[1] + (toRGB[1] - fromRGB[1]) * t);
    const b = Math.round(fromRGB[2] + (toRGB[2] - fromRGB[2]) * t);
    const hex = `#${r.toString(16).padStart(2,'0')}${g.toString(16).padStart(2,'0')}${b.toString(16).padStart(2,'0')}`;
    const sy = Math.floor(i * headerH / steps);
    const sh = Math.ceil(headerH / steps) + 1;
    doc.rect(0, sy, 595, sh).fill(hex);
  }
  doc.rect(0, headerH, 595, 4).fill(T.bright);

  // ── Circular tech emblem (right side of header) ──────────
  const emCX = 478, emCY = 112, emR = 52;
  doc.circle(emCX, emCY, emR + 10).fill('#0a4060');
  doc.circle(emCX, emCY, emR).fill(T.main);
  for (let ly = emCY - emR + 8; ly < emCY + emR - 4; ly += 11) {
    const hw = Math.sqrt(Math.max(0, emR * emR - (ly - emCY) * (ly - emCY)));
    if (hw > 4) {
      doc.moveTo(emCX - hw, ly).lineTo(emCX + hw, ly)
        .lineWidth(0.5).stroke('#1190b8');
    }
  }
  doc.circle(emCX, emCY, emR).lineWidth(2).stroke(T.bright);
  // Crosshair tick marks at 3 o'clock and 9 o'clock
  doc.moveTo(emCX - emR + 4, emCY).lineTo(emCX - emR + 14, emCY)
    .lineWidth(1.2).stroke(T.bright);
  doc.moveTo(emCX + emR - 14, emCY).lineTo(emCX + emR - 4, emCY)
    .lineWidth(1.2).stroke(T.bright);
  doc.font(F).fontSize(30).fillColor(T.pale)
    .text('NJ', emCX - 20, emCY - 21, { lineBreak: false });
  doc.rect(emCX - 20, emCY + 13, 40, 2).fill(T.bright);
  doc.fontSize(9).fillColor(T.light)
    .text('ERP', emCX - 11, emCY + 20, { lineBreak: false });

  // ── Brand text (left of header) ──────────────────────────
  doc.font(F).fontSize(34).fillColor(T.pale)
    .text('NJ Stream ERP', 36, 50, { lineBreak: false });
  doc.rect(36, 93, 260, 2).fill(T.bright);
  doc.fontSize(14).fillColor(T.light)
    .text('AI 智慧供應鏈管理系統', 36, 103, { lineBreak: false });
  doc.fontSize(9.5).fillColor('#90c8e0')
    .text('AI-Driven Supply Chain Intelligence', 36, 124, { lineBreak: false });
  doc.fontSize(8.5).fillColor('#6aaecc')
    .text('Smart ERP for Small & Medium Enterprises', 36, 142, { lineBreak: false });

  // ── Tagline box ──────────────────────────────────────────
  doc.rect(36, 256, 523, 58).fill(T.pale);
  doc.rect(36, 256, 5, 58).fill(T.bright);
  doc.font(F).fontSize(13).fillColor(T.main)
    .text('讓中小製造商用上企業級工具，同時落實 ESG 永續目標', 50, 267, { lineBreak: false });
  doc.fontSize(9).fillColor(T.mid)
    .text('Empowering SMEs with enterprise-grade tools while achieving ESG sustainability goals',
      50, 289, { width: 505, lineBreak: false });

  // ── Feature pills — fixed 100 pt each, 5 pills × 7 pt gap ──
  // Total width: 5×100 + 4×7 = 528 pt; right edge = 36+528 = 564 < 595 ✓
  const pillDefs = [
    { zh: '行動優先', en: 'Mobile First' },
    { zh: '離線同步', en: 'Offline Sync' },
    { zh: '無紙化',   en: 'Paperless' },
    { zh: '多角色',   en: 'Multi-Role' },
    { zh: '雙語介面', en: 'Bilingual' },
  ];
  const pillW = 100, pillH = 32, pillGap = 7, pillY = 330;
  pillDefs.forEach((pill, i) => {
    const px = 36 + i * (pillW + pillGap);
    doc.rect(px, pillY, pillW, pillH).fill(T.main);
    doc.rect(px, pillY, pillW, 3).fill(T.bright);
    doc.font(F).fontSize(9.5).fillColor(T.pale)
      .text(pill.zh, px, pillY + 4, { width: pillW, align: 'center', lineBreak: false });
    doc.fontSize(7.5).fillColor(T.light)
      .text(pill.en, px, pillY + 18, { width: pillW, align: 'center', lineBreak: false });
  });

  // ── KPI cards ────────────────────────────────────────────
  const kpis = [
    { num: '5', desc: '核心模組\nCore Modules' },
    { num: '3', desc: '使用角色\nUser Roles' },
    { num: '100%', desc: '離線可用\nOffline Ready' },
    { num: '2語', desc: '中文 / English\nBilingual' },
  ];
  const kpiW = 122, kpiH = 84;
  kpis.forEach(({ num, desc }, i) => {
    const bx = 36 + i * (kpiW + 10);
    const by = 378;
    doc.rect(bx, by, kpiW, kpiH).fill(T.pale);
    doc.rect(bx, by, kpiW, 4).fill(T.bright);
    doc.font(F).fontSize(26).fillColor(T.main)
      .text(num, bx, by + 14, { width: kpiW, align: 'center', lineBreak: false });
    doc.fontSize(8.5).fillColor(T.mid)
      .text(desc, bx, by + 52, { width: kpiW, align: 'center', lineBreak: true });
  });

  // ── Applicability & tech stack ───────────────────────────
  const infoY = 480;
  doc.rect(36, infoY, 523, 1).fill(T.light);
  doc.font(F).fontSize(8.5).fillColor(C.mid)
    .text('適用場景：製造業  ·  批發業  ·  貿易商  ·  中小企業（50–300 人）', 36, infoY + 10, { lineBreak: false });
  doc.fontSize(8).fillColor(C.mid)
    .text('Tech Stack：Flutter  ·  Node.js  ·  Fastify  ·  PostgreSQL  ·  Drift  ·  PDFKit  ·  Cloudflare Tunnel',
      36, infoY + 26, { lineBreak: false });

  // ── Flow preview bar ─────────────────────────────────────
  const previewY = 528;
  doc.rect(36, previewY, 523, 34).fill(T.main);
  const flowLabels = ['客戶  Client', '報價  Quote', '訂單  Order', '庫存  Stock', '出貨  Ship', '通知  Notify'];
  const fw = 523 / flowLabels.length;
  flowLabels.forEach((label, idx) => {
    if (idx > 0) {
      const lx = 36 + idx * fw;
      doc.moveTo(lx - 8, previewY + 8).lineTo(lx, previewY + 8)
        .lineWidth(1).stroke(T.bright);
    }
    doc.font(F).fontSize(8.5).fillColor(idx === 0 ? T.light : T.pale)
      .text(label, 36 + idx * fw, previewY + 11, { width: fw, align: 'center', lineBreak: false });
  });

  // ── ESG legend ───────────────────────────────────────────
  const legendY = 580;
  [
    { x: 36,  color: C.eColor, label: '● E  環境永續  Environmental' },
    { x: 210, color: C.sColor, label: '● S  社會包容  Social' },
    { x: 350, color: C.gColor, label: '● G  公司治理  Governance' },
  ].forEach(({ x, color, label }) => {
    doc.font(F).fontSize(8).fillColor(color)
      .text('■', x, legendY, { lineBreak: false });
    doc.fillColor(C.mid).text(label.slice(1), x + 14, legendY, { lineBreak: false });
  });

  // ── Footer ───────────────────────────────────────────────
  doc.rect(0, 742, 595, 48).fill(T.dark);
  doc.rect(0, 742, 595, 2).fill(T.bright);
  doc.font(F).fontSize(8).fillColor(T.bright)
    .text('NJ Stream ERP  ·  產品說明書  ·  版本 v1.0  ·  2026', 36, 758, { lineBreak: false });
  doc.fontSize(7.5).fillColor(T.light)
    .text('© 2026 NJ Stream. All rights reserved.  本文件僅供參考，規格以實際系統為準。', 36, 773, { lineBreak: false });
}

// ─────────────────────────────────────────────────────────
// Page 2 — 目標用戶 & 市場痛點
// ─────────────────────────────────────────────────────────
function page2(doc: PDFKit.PDFDocument) {
  doc.rect(0, 0, 595, 6).fill(C.accent);

  let y = sectionTitle(doc, 30, 20, '目標用戶 TA', 'Target Audience');

  // ── 三個角色卡 ────────────────────────────────────────
  const roles = [
    {
      title: '企業主 / 管理者', en: 'Business Owner / Admin', color: C.eColor,
      badge: 'A',
      features: ['完整系統管理權限', '使用者帳號設定', '查看所有報表', 'CSV 資料匯入 / 匯出', '所有模組完整存取'],
    },
    {
      title: '業務 / 銷售人員', en: 'Sales Representative', color: C.sColor,
      badge: 'S',
      features: ['外出建立報價單', '客戶資料管理', '轉換訂單操作', 'PDF / Email 寄送', '庫存唯讀查詢'],
    },
    {
      title: '倉管 / 出貨人員', en: 'Warehouse / Shipping', color: C.gColor,
      badge: 'W',
      features: ['即時庫存快照', '確認預留數量', '執行出貨動作', '低庫存警示通知', '訂單唯讀查詢'],
    },
  ];

  const cardW = 164, cardH = 164;
  roles.forEach((role, i) => {
    const cx = 30 + i * (cardW + 12);
    // Card base
    doc.rect(cx, y, cardW, cardH).fill(C.lightGray);
    // Header
    doc.rect(cx, y, cardW, 44).fill(role.color);
    // Badge circle
    doc.circle(cx + 22, y + 22, 16).fill(C.white);
    doc.font(F).fontSize(14).fillColor(role.color)
      .text(role.badge, cx + 22 - 5, y + 14, { lineBreak: false });
    // Role names
    doc.font(F).fontSize(9.5).fillColor(C.white)
      .text(role.title, cx + 44, y + 8, { width: cardW - 50, lineBreak: false });
    doc.fontSize(7.5).fillColor('rgba(200,230,220,1)')
      .text(role.en, cx + 44, y + 24, { width: cardW - 50, lineBreak: false });
    // Feature list
    role.features.forEach((feat, fi) => {
      const fy = y + 52 + fi * 22;
      doc.rect(cx + 10, fy + 3, 5, 5).fill(role.color);
      doc.font(F).fontSize(8.5).fillColor(C.dark)
        .text(feat, cx + 22, fy, { width: cardW - 28, lineBreak: false });
    });
  });

  y += cardH + 28;

  // ── 市場痛點與解法 ──────────────────────────────────────
  doc.rect(30, y - 4, 535, 1).fill(C.lightGreen);
  y = sectionTitle(doc, 30, y + 8, '市場痛點與解法', 'Pain Points & Solutions');

  const pains: [string, string][] = [
    [
      '手動 Excel 製作報價單\n容易出錯，難以版本追蹤',
      '系統自動生成中英雙語 PDF\nEmail 一鍵寄送客戶',
    ],
    [
      '業務外出無網路，無法\n即時查詢或建立訂單',
      '離線模式：SQLite 本地存儲\n返回後自動推送同步',
    ],
    [
      '庫存靠電話確認，資訊延遲\n導致超賣或庫存衝突',
      '即時庫存快照 + 自動預留\n防止庫存超賣衝突',
    ],
    [
      '紙本文件難數位追蹤\n稽核耗時耗力',
      '全程數位化，Email 確認鏈\n完整操作記錄可查',
    ],
    [
      '外籍客戶需另外準備英文文件\n人力重複作業',
      '雙語 UI + 雙語 PDF\n一份文件自動涵蓋中英',
    ],
  ];

  const HW = 253;
  pains.forEach(([pain, sol], i) => {
    const ry = y + i * 52;

    // Left: pain
    doc.rect(30, ry, HW, 44).fill(C.redLight);
    doc.rect(30, ry, 4, 44).fill(C.red);
    // X mark
    doc.moveTo(44, ry + 14).lineTo(52, ry + 22).lineWidth(1.8).stroke(C.red);
    doc.moveTo(52, ry + 14).lineTo(44, ry + 22).lineWidth(1.8).stroke(C.red);
    doc.font(F).fontSize(8.5).fillColor(C.dark)
      .text(pain, 60, ry + 8, { width: HW - 36, lineBreak: true });

    // Arrow
    hArrow(doc, 30 + HW + 2, ry + 22, 30 + HW + 26, ry + 22, C.accent);

    // Right: solution
    const rx = 30 + HW + 28;
    doc.rect(rx, ry, HW, 44).fill(C.greenLight);
    doc.rect(rx, ry, 4, 44).fill(C.accent);
    // Check mark
    doc.moveTo(rx + 12, ry + 20).lineTo(rx + 18, ry + 26)
      .lineTo(rx + 30, ry + 14).lineWidth(2).stroke(C.accent);
    doc.font(F).fontSize(8.5).fillColor(C.dark)
      .text(sol, rx + 36, ry + 8, { width: HW - 42, lineBreak: true });
  });

  footer(doc, '目標用戶 & 市場痛點  ·  Page 2');
}

// ─────────────────────────────────────────────────────────
// Page 3 — 核心業務流程 & 架構
// ─────────────────────────────────────────────────────────
function page3(doc: PDFKit.PDFDocument) {
  doc.rect(0, 0, 595, 6).fill(C.accent);

  let y = sectionTitle(doc, 30, 20, '核心業務流程', 'Core Business Document Flow');

  // ── 六步驟流程圖 ─────────────────────────────────────
  const steps = [
    { zh: '客戶資料', en: 'Customer',   color: '#1b5e20' },
    { zh: '報  價  單',  en: 'Quotation',  color: C.sColor  },
    { zh: '銷售訂單', en: 'Sales Order', color: C.gColor  },
    { zh: '庫存預留', en: 'Reserve',     color: '#7b341e' },
    { zh: '出貨確認', en: 'Shipment',    color: '#1b4332' },
    { zh: 'Email通知', en: 'Notify',     color: '#0d3349' },
  ];
  const bW = 76, bH = 56;
  steps.forEach((s, i) => {
    const bx = 30 + i * (bW + 10);
    doc.rect(bx, y, bW, bH).fill(s.color);
    doc.font(F).fontSize(9).fillColor(C.white)
      .text(s.zh, bx, y + 10, { width: bW, align: 'center', lineBreak: false });
    doc.fontSize(7).fillColor('rgba(200,230,220,1)')
      .text(s.en, bx, y + 30, { width: bW, align: 'center', lineBreak: false });
    if (i < steps.length - 1) {
      hArrow(doc, bx + bW + 1, y + bH / 2, bx + bW + 9, y + bH / 2, C.accent);
    }
  });

  y += bH + 10;

  // 轉換標記
  doc.font(F).fontSize(7.5).fillColor(C.mid)
    .text('報價單可一鍵轉換為銷售訂單（First-to-Sync Wins 機制防止重複轉單）', 30, y, { lineBreak: false });

  y += 24;
  doc.rect(30, y, 535, 1).fill(C.lightGreen);
  y = sectionTitle(doc, 30, y + 8, '離線優先同步架構', 'Offline-First Sync Architecture');

  // ── 同步架構三元件圖 ──────────────────────────────────
  const cW = 138, cH = 90;
  const components = [
    { zh: '手機 App', en: 'Flutter + Drift\nSQLite 本地儲存', cx: 52 },
    { zh: '雲端 API', en: 'Node.js + Fastify\nCloudflare Tunnel', cx: 228 },
    { zh: '資 料 庫',  en: 'PostgreSQL\nDocker 容器化',   cx: 404 },
  ];
  components.forEach(({ zh, en, cx }) => {
    doc.rect(cx, y, cW, cH).fill(C.lightGray);
    doc.rect(cx, y, cW, 28).fill(C.midGreen);
    doc.font(F).fontSize(10.5).fillColor(C.white)
      .text(zh, cx, y + 8, { width: cW, align: 'center', lineBreak: false });
    doc.fontSize(8).fillColor(C.dark)
      .text(en, cx, y + 38, { width: cW, align: 'center', lineBreak: true });
  });

  // 雙向箭頭（手機 ↔ 雲端）
  biArrow(doc, 52 + cW + 4, 228 - 4, y + cH / 2, C.accent);
  // 單向箭頭（雲端 → 資料庫）
  hArrow(doc, 228 + cW + 4, y + cH / 2, 404 - 4, y + cH / 2, C.accent);

  // 箭頭標籤
  doc.font(F).fontSize(7).fillColor(C.accent)
    .text('Push 同步', 52 + cW + 14, y + cH / 2 - 18, { lineBreak: false });
  doc.fillColor(C.midGreen)
    .text('Pull 更新', 52 + cW + 14, y + cH / 2 + 10, { lineBreak: false });
  doc.fillColor(C.accent)
    .text('CRUD', 408 - 36, y + cH / 2 - 14, { lineBreak: false });

  // LWW 說明條
  const lwwY = y + cH + 10;
  doc.rect(30, lwwY, 535, 22).fill(C.lightGreen);
  doc.font(F).fontSize(8).fillColor(C.midGreen)
    .text('衝突解決策略  Last-Write-Wins (LWW)：以 updatedAt 時間戳決定最終版本，離線編輯不遺失', 44, lwwY + 7, { lineBreak: false });

  y = lwwY + 34;
  doc.rect(30, y - 4, 535, 1).fill(C.lightGreen);
  y = sectionTitle(doc, 30, y + 4, '角色權限矩陣', 'Role-Based Access Control (RBAC)');

  // ── 權限表格 ──────────────────────────────────────────
  const cols = ['角色', '客戶', '產品', '報價單', '訂單', '庫存', '設定'];
  const cws  = [140, 57, 57, 57, 57, 57, 57];
  const rows = [
    { name: 'Admin  管理員',  perms: ['全', '全', '全', '全', '全', '全'] },
    { name: 'Sales  業務員',  perms: ['全', '讀', '全', '全', '讀', '✕'] },
    { name: 'Viewer 檢視者',  perms: ['讀', '讀', '讀', '讀', '讀', '✕'] },
  ];
  const rowH = 28;

  // Header row
  let tx = 30;
  cols.forEach((h, i) => {
    doc.rect(tx, y, cws[i], rowH).fill(C.darkGreen);
    doc.font(F).fontSize(8.5).fillColor(C.white)
      .text(h, tx, y + 9, { width: cws[i], align: 'center', lineBreak: false });
    tx += cws[i];
  });
  y += rowH;

  rows.forEach((row, ri) => {
    tx = 30;
    const bg = ri % 2 === 0 ? C.lightGray : C.white;
    cws.forEach((w, ci) => {
      doc.rect(tx, y, w, rowH).fill(bg);
      if (ci === 0) {
        doc.font(F).fontSize(8.5).fillColor(C.dark)
          .text(row.name, tx + 6, y + 9, { width: w - 8, lineBreak: false });
      } else {
        const p = row.perms[ci - 1];
        const clr = p === '全' ? C.midGreen : p === '讀' ? C.orange : C.red;
        doc.font(F).fontSize(9).fillColor(clr)
          .text(p, tx, y + 9, { width: w, align: 'center', lineBreak: false });
      }
      tx += w;
    });
    y += rowH;
  });

  // 圖例
  doc.font(F).fontSize(7.5).fillColor(C.midGreen).text('全 = 完整存取', 30, y + 8, { lineBreak: false });
  doc.fillColor(C.orange).text('讀 = 唯讀', 130, y + 8, { lineBreak: false });
  doc.fillColor(C.red).text('✕ = 無權限', 195, y + 8, { lineBreak: false });

  footer(doc, '核心業務流程 & 架構  ·  Page 3');
}

// ─────────────────────────────────────────────────────────
// Page 4 — ESG 永續整合
// ─────────────────────────────────────────────────────────
function page4(doc: PDFKit.PDFDocument) {
  doc.rect(0, 0, 595, 6).fill(C.accent);

  let y = sectionTitle(doc, 30, 20, 'ESG 永續整合', 'ESG Sustainability Integration');

  doc.font(F).fontSize(9).fillColor(C.mid)
    .text('NJ Stream ERP 在系統設計初期即將 ESG 三大面向融入功能規劃，協助企業在數位轉型的同時實踐永續目標。', 30, y, { width: 535, lineBreak: true });
  y += 30;

  // ── 三欄 ESG 卡片 ─────────────────────────────────────
  const colW = 167, colH = 348, gap = 7;
  const esg = [
    {
      letter: 'E',
      zh: '環境',
      en: 'Environmental',
      color: C.eColor,
      light: '#e8f5e9',
      items: [
        ['PDF 無紙化流程', '報價單、訂單、對帳單全程數位化，PDF 電子寄送取代實體文件印刷'],
        ['Email 電子簽收', '寄送確認信取代傳統郵件，減少實體信件碳排放'],
        ['雲端集中部署', '單一伺服器服務多使用者，避免多台機器重複耗電'],
        ['行動辦公減少通勤', '離線 App 支援遠端作業，降低不必要的出差與通勤排碳'],
      ],
      metric: '每月估計節省\n≈ 300 張 A4 紙\n≈ 1.2 kg CO₂e 減排',
    },
    {
      letter: 'S',
      zh: '社會',
      en: 'Social',
      color: C.sColor,
      light: '#e3f2fd',
      items: [
        ['降低 SME 門檻', '中小製造商免建置成本即可使用企業級 ERP 功能'],
        ['中英雙語包容設計', '支援不同語言背景員工，促進職場多元融合'],
        ['行動辦公彈性', 'Android App 支援業務外出、倉管現場等彈性工作模式'],
        ['直覺化 UI', '縮短人員培訓週期，降低人力培訓成本'],
      ],
      metric: '適用 50–300 人規模\n中小企業快速導入\n無需 IT 部門維護',
    },
    {
      letter: 'G',
      zh: '治理',
      en: 'Governance',
      color: C.gColor,
      light: '#f3e5f5',
      items: [
        ['RBAC 角色型權限', '最小權限原則，不同角色僅存取必要功能，防止越權操作'],
        ['完整稽核軌跡', '所有訂單操作、庫存異動皆有記錄，支援事後稽核'],
        ['JWT + HTTPS 傳輸', '認證加密傳輸，防止中間人攻擊與資料洩漏'],
        ['庫存異動追蹤', '預留 / 出貨全程追蹤，庫存衝突自動偵測防止舞弊'],
      ],
      metric: '符合數位治理\n最佳實踐規範\nISO 27001 概念對齊',
    },
  ];

  esg.forEach(({ letter, zh, en, color, light, items, metric }, i) => {
    const cx = 30 + i * (colW + gap);

    // Card background
    doc.rect(cx, y, colW, colH).fill(light);

    // Header bar
    doc.rect(cx, y, colW, 52).fill(color);

    // Large background letter
    doc.font(F).fontSize(52).fillColor('rgba(255,255,255,0.1)')
      .text(letter, cx + colW - 42, y + 2, { lineBreak: false });

    // Letter badge circle
    doc.circle(cx + 26, y + 26, 18).fill(C.white);
    doc.font(F).fontSize(18).fillColor(color)
      .text(letter, cx + 26 - 6, y + 16, { lineBreak: false });

    // zh / en title
    doc.font(F).fontSize(14).fillColor(C.white)
      .text(zh, cx + 52, y + 10, { lineBreak: false });
    doc.fontSize(8.5).fillColor('rgba(210,240,225,1)')
      .text(en, cx + 52, y + 28, { lineBreak: false });

    // Item rows
    let iy = y + 62;
    items.forEach(([title, desc]) => {
      // Item title
      doc.rect(cx + 8, iy, 4, 14).fill(color);
      doc.font(F).fontSize(9).fillColor(color)
        .text(title, cx + 18, iy, { lineBreak: false });
      iy += 18;
      // Item description
      doc.fontSize(7.5).fillColor(C.mid)
        .text(desc, cx + 18, iy, { width: colW - 26, lineBreak: true });
      iy += 44;
    });

    // Metric box at bottom
    const metY = y + colH - 64;
    doc.rect(cx, metY, colW, 64).fill(color);
    doc.font(F).fontSize(8.5).fillColor(C.white)
      .text(metric, cx, metY + 10, { width: colW, align: 'center', lineBreak: true });
  });

  y += colH + 18;

  // ── SDGs 對應框 ─────────────────────────────────────────
  doc.rect(30, y, 535, 48).fill(C.lightGray);
  doc.rect(30, y, 5, 48).fill(C.accent);
  doc.font(F).fontSize(9).fillColor(C.darkGreen)
    .text('聯合國永續發展目標（SDGs）對應', 44, y + 6, { lineBreak: false });

  const sdgs = [
    { num: 'SDG 8', desc: '體面工作與\n經濟成長',   color: '#c0392b' },
    { num: 'SDG 9', desc: '工業創新與\n基礎設施',   color: '#e67e22' },
    { num: 'SDG 12', desc: '負責任的\n消費與生產',  color: '#f39c12' },
    { num: 'SDG 16', desc: '和平正義與\n強大制度',  color: '#2980b9' },
  ];
  sdgs.forEach(({ num, desc, color }, i) => {
    const sx = 44 + i * 122;
    doc.rect(sx, y + 22, 110, 18).fill(color);
    doc.font(F).fontSize(7.5).fillColor(C.white)
      .text(`${num}  ${desc.replace('\n', ' ')}`, sx, y + 26, { width: 110, align: 'center', lineBreak: false });
  });

  footer(doc, 'ESG 永續整合  ·  Page 4');
}

// ─────────────────────────────────────────────────────────
// Page 5 — 快速使用指南
// ─────────────────────────────────────────────────────────
function page5(doc: PDFKit.PDFDocument) {
  doc.rect(0, 0, 595, 6).fill(C.accent);

  let y = sectionTitle(doc, 30, 20, '快速使用指南', 'Quick User Guide');

  // ── 五步驟流程 ───────────────────────────────────────
  const steps = [
    {
      num: '1', title: '系統初始化', en: 'Setup',
      desc: '管理員建立帳號\n匯入產品主檔（CSV）\n設定庫存初始值',
      color: C.eColor,
    },
    {
      num: '2', title: '客戶 & 報價', en: 'Quote',
      desc: '業務員新增客戶資料\n選品項 / 數量 / 單價\n系統自動計算含稅合計',
      color: C.sColor,
    },
    {
      num: '3', title: '轉換訂單', en: 'Convert',
      desc: '確認報價後一鍵轉換\n狀態自動更新同步\nFirst-Sync-Wins 防重複',
      color: C.gColor,
    },
    {
      num: '4', title: '預留庫存', en: 'Reserve',
      desc: '倉管確認庫存充足\n執行預留鎖定數量\n低庫存自動橘色警示',
      color: '#7b341e',
    },
    {
      num: '5', title: '出貨 & 通知', en: 'Ship & Notify',
      desc: '確認出貨狀態更新\nPDF 自動 Email 客戶\n月結對帳單一鍵寄送',
      color: '#1b4332',
    },
  ];

  const sW = 97, sH = 96;
  steps.forEach((step, i) => {
    const sx = 30 + i * (sW + 11);
    // Box
    doc.rect(sx, y, sW, sH).fill(C.lightGray);
    doc.rect(sx, y, sW, 5).fill(step.color);
    // Number circle
    doc.circle(sx + sW / 2, y + 30, 20).fill(step.color);
    doc.font(F).fontSize(18).fillColor(C.white)
      .text(step.num, sx + sW / 2 - 6, y + 19, { lineBreak: false });
    // Title
    doc.font(F).fontSize(9).fillColor(step.color)
      .text(step.title, sx, y + 58, { width: sW, align: 'center', lineBreak: false });
    doc.fontSize(7.5).fillColor(C.mid)
      .text(step.en, sx, y + 72, { width: sW, align: 'center', lineBreak: false });
    // Arrow
    if (i < steps.length - 1) {
      hArrow(doc, sx + sW + 2, y + sH / 2, sx + sW + 9, y + sH / 2, step.color);
    }
  });

  y += sH + 10;

  // Description cards
  steps.forEach((step, i) => {
    const sx = 30 + i * (sW + 11);
    doc.rect(sx, y, sW, 68).fill(C.white);
    doc.rect(sx, y, sW, 3).fill(step.color);
    doc.font(F).fontSize(7.5).fillColor(C.dark)
      .text(step.desc, sx + 4, y + 10, { width: sW - 8, lineBreak: true });
  });

  y += 84;
  doc.rect(30, y, 535, 1).fill(C.lightGreen);
  y = sectionTitle(doc, 30, y + 12, '重要使用技巧', 'Key Usage Tips');

  // ── 使用技巧 6 格卡片 ──────────────────────────────────
  const tips = [
    {
      title: '離線操作',    en: 'Offline Mode',
      desc:  '無網路時仍可建立報價、新增訂單，返回後點「Push 同步」自動上傳至伺服器',
      color: C.eColor,
    },
    {
      title: 'CSV 批次匯入', en: 'Batch Import',
      desc:  '產品與客戶支援 CSV 批次匯入，首次建置大量資料更快速有效率',
      color: C.sColor,
    },
    {
      title: '切換語言',    en: 'Language Toggle',
      desc:  '右上角設定可即時切換中文 / English，所有 UI 與 PDF 文件同步更新',
      color: C.gColor,
    },
    {
      title: '一鍵 Email', en: 'One-Click Email',
      desc:  '報價單、銷售訂單、月結對帳單可直接從 App 寄送 Email 給客戶',
      color: C.eColor,
    },
    {
      title: '低庫存警示',  en: 'Low Stock Alert',
      desc:  '庫存低於設定門檻時，庫存頁自動顯示紅色「低庫存」標籤即時提醒',
      color: C.sColor,
    },
    {
      title: '角色權限',    en: 'RBAC Security',
      desc:  '業務員無法存取系統設定，確保資料安全、操作責任明確、符合治理要求',
      color: C.gColor,
    },
  ];

  const tW = 170, tH = 66;
  tips.forEach((tip, i) => {
    const tx = 30 + (i % 3) * (tW + 12);
    const ty = y + Math.floor(i / 3) * (tH + 8);
    doc.rect(tx, ty, tW, tH).fill(C.lightGray);
    doc.rect(tx, ty, tW, 3).fill(tip.color);
    doc.font(F).fontSize(9.5).fillColor(tip.color)
      .text(tip.title, tx + 8, ty + 10, { lineBreak: false });
    doc.fontSize(7.5).fillColor(C.mid)
      .text(tip.en, tx + 8, ty + 24, { lineBreak: false });
    doc.fontSize(7.5).fillColor(C.dark)
      .text(tip.desc, tx + 8, ty + 38, { width: tW - 16, lineBreak: true });
  });

  // ── 深綠色封底頁尾 ─────────────────────────────────────
  doc.rect(0, 756, 595, 86).fill(C.darkGreen);
  doc.rect(0, 756, 595, 1).fill(C.accent);
  doc.font(F).fontSize(9).fillColor(C.accent)
    .text('NJ Stream ERP  ·  快速使用指南  ·  Page 5 / 5', 30, 772, { lineBreak: false });
  doc.fontSize(8).fillColor(C.lightGreen)
    .text('如需技術支援或功能諮詢，請聯繫系統管理員', 30, 790, { lineBreak: false });
  doc.fontSize(8).fillColor(C.lightGreen)
    .text('For technical support, please contact your system administrator.', 30, 806, { lineBreak: false });
  doc.fontSize(7.5).fillColor(C.accent)
    .text('© 2026 NJ Stream. All rights reserved.', 30, 824, { lineBreak: false });
}

// ─────────────────────────────────────────────────────────
// 主程式
// ─────────────────────────────────────────────────────────
async function main() {
  const doc = makeDoc();
  const chunks: Buffer[] = [];

  await new Promise<void>((resolve, reject) => {
    doc.on('data', (c: Buffer) => chunks.push(c));
    doc.on('end', resolve);
    doc.on('error', reject);

    page1(doc);
    doc.addPage();
    page2(doc);
    doc.addPage();
    page3(doc);
    doc.addPage();
    page4(doc);
    doc.addPage();
    page5(doc);

    doc.end();
  });

  const outDir  = join(process.cwd(), '..', '..');
  const outPath = join(outDir, 'NJ_Stream_ERP_Brochure.pdf');
  writeFileSync(outPath, Buffer.concat(chunks));
  console.log(`\n✅  Brochure saved → ${outPath}\n`);
}

main().catch(err => { console.error(err); process.exit(1); });
