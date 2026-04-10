import 'dotenv/config';
import { buildApp } from '@/app.js';

const HOST = process.env.HOST ?? '0.0.0.0';
const PORT = Number(process.env.PORT ?? 3000);

const app = buildApp();

try {
  await app.listen({ host: HOST, port: PORT });
  app.log.info(`NJ_Stream_ERP backend running at http://${HOST}:${PORT}`);
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
