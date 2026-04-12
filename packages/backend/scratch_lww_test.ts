import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import * as schema from './src/schemas/index.js';
import * as dotenv from 'dotenv';
import { randomUUID } from 'crypto';
dotenv.config();

const BASE_URL = 'http://127.0.0.1:3000/api/v1';

async function main() {
  console.log('\n=======================================');
  console.log('LWW 衝突解決實驗 (模擬 Fiddler 攔截請求網路)');
  console.log('=======================================\n');

  // 1. 登入取得 Token
  // 先印出 DB 中的 user
  const db = drizzle(postgres(process.env.DATABASE_URL!));
  const users = await db.select().from(schema.users);
  console.log('系統內 Users:', users.map(u => ({ username: u.username, role: u.role })));

  console.log('► 步驟 1：登入 admin_test');
  let loginRes = await fetch(`${BASE_URL}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username: 'admin_test', password: 'P@ssw0rd!' }),
  });
  if (!loginRes.ok) {
    console.error('Login failed!', await loginRes.text());
    process.exit(1);
  }
  const { accessToken } = await loginRes.json();
  console.log('  -> 成功取得 JWT Access Token\n');

  // 2. 新增測試客戶 (Push Create)
  console.log('► 步驟 2：Push 建立新客戶');
  const createOp = {
    id: randomUUID(),
    entityType: 'customer',
    operationType: 'create',
    createdAt: new Date().toISOString(),
    payload: {
      name: `LWW 測試公司 ${Date.now()}`,
      contact: '王總',
      createdAt: new Date().toISOString(),
      updatedAt: new Date().toISOString(),
    }
  };

  const pushCreateRes = await fetch(`${BASE_URL}/sync/push`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`
    },
    body: JSON.stringify({ operations: [createOp] }),
  });
  const createResult = await pushCreateRes.json();
  console.log('  -> Push 回應:', JSON.stringify(createResult));
  
  // 3. 利用 Pull 抓取剛建立的客戶
  console.log('\n► 步驟 3：Pull 抓取伺服器真實資料');
  const pullRes = await fetch(`${BASE_URL}/sync/pull?entityTypes=customer`, {
    headers: { 'Authorization': `Bearer ${accessToken}` }
  });
  const pullData = await pullRes.json();
  const newCustomer = pullData.customers.find((c: any) => c.name === createOp.payload.name);
  console.log('  -> 已取得伺服器最新紀錄, 真實 ID:', newCustomer.id);
  console.log('  -> 伺服器的 updatedAt:', newCustomer.updatedAt);

  // 4. 等待 2 秒，確保時間差
  console.log('\n► 步驟 4：模擬離線過期更新（舊的 updatedAt）');
  await new Promise(r => setTimeout(r, 2000));

  // 構造一個具有「過期 updatedAt」的更新請求（模擬客戶端時間比伺服器還舊）
  // 伺服器時間是 newCustomer.updatedAt
  // 我們讓 payloadUpdatedAt 比它舊 1 小時
  const pastDate = new Date(new Date(newCustomer.updatedAt).getTime() - 3600000).toISOString();
  console.log('  -> 準備傳送過期的 updatedAt:', pastDate);

  const updateOp = {
    id: randomUUID(),
    entityType: 'customer',
    operationType: 'update',
    createdAt: new Date().toISOString(),
    payload: {
      id: newCustomer.id,
      name: '不應該被更新的名字 (LWW被擋)',
      updatedAt: pastDate
    }
  };

  const pushUpdateRes = await fetch(`${BASE_URL}/sync/push`, {
    method: 'POST',
    headers: { 
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${accessToken}`
    },
    body: JSON.stringify({ operations: [updateOp] }),
  });
  const updateResult = await pushUpdateRes.json();
  console.log('\n► 步驟 5：LWW 衝突伺服器回應 (Fiddler Raw Body):');
  console.log(JSON.stringify(updateResult, null, 2));

  if (updateResult.failed && updateResult.failed.length > 0 && updateResult.failed[0].code === 'FORBIDDEN_OPERATION') {
    console.log('\n✅ 驗證成功！LWW 機制成功偵測到舊的 updated_at，拒絕更新並回傳 FORBIDDEN_OPERATION 與 server_state。\n');
  } else {
    console.log('\n❌ 驗證失敗！預期應該擋下，但行為不如預期。\n');
  }
}

main().catch(console.error);
