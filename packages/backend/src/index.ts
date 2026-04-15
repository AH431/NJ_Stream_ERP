import 'dotenv/config';
import { buildApp } from '@/app.js';

// 開發環境預設綁定 127.0.0.1（僅本機可連）
// 部署時透過環境變數覆寫：HOST=0.0.0.0
const HOST = process.env.HOST ?? '127.0.0.1';
const PORT = Number(process.env.PORT ?? 3000);

const app = buildApp();

try {
  await app.listen({ host: HOST, port: PORT });
  app.log.info(`NJ_Stream_ERP backend running at http://${HOST}:${PORT}`);
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
