import nodemailer from 'nodemailer';
import type { Transporter } from 'nodemailer';

let _transporter: Transporter | null = null;

async function getTransporter(): Promise<Transporter> {
  if (_transporter) return _transporter;

  // 開發環境：自動使用 Ethereal 假 SMTP，信件不會真的寄出
  // 寄完後終端機會印出預覽連結
  if (process.env.NODE_ENV === 'development' && !process.env.SMTP_HOST) {
    const testAccount = await nodemailer.createTestAccount();
    console.log('[email] 使用 Ethereal 測試帳號:', testAccount.user);
    _transporter = nodemailer.createTransport({
      host:   testAccount.smtp.host,
      port:   testAccount.smtp.port,
      secure: testAccount.smtp.secure,
      auth:   { user: testAccount.user, pass: testAccount.pass },
    });
    return _transporter;
  }

  const host = process.env.SMTP_HOST;
  const port = Number(process.env.SMTP_PORT ?? 587);
  const user = process.env.SMTP_USER;
  const pass = process.env.SMTP_PASS;

  if (!host || !user || !pass) {
    throw new Error('SMTP 設定不完整，請確認 SMTP_HOST / SMTP_USER / SMTP_PASS 已設定於 .env。');
  }

  _transporter = nodemailer.createTransport({
    host,
    port,
    secure: port === 465,
    auth: { user, pass },
  });

  return _transporter;
}

export interface SendDocumentOptions {
  to: string;
  subject: string;
  text: string;
  attachmentFilename: string;
  pdfBuffer: Buffer;
}

export async function sendDocumentEmail(opts: SendDocumentOptions): Promise<{ previewUrl: string | false }> {
  const transporter = await getTransporter();
  const from = process.env.SMTP_FROM ?? process.env.SMTP_USER ?? 'noreply@nj-stream.local';

  const info = await transporter.sendMail({
    from,
    to:      opts.to,
    subject: opts.subject,
    text:    opts.text,
    attachments: [{
      filename:    opts.attachmentFilename,
      content:     opts.pdfBuffer,
      contentType: 'application/pdf',
    }],
  });

  const previewUrl = nodemailer.getTestMessageUrl(info);
  if (previewUrl) {
    console.log('[email] Ethereal 預覽連結:', previewUrl);
  }

  return { previewUrl };
}
