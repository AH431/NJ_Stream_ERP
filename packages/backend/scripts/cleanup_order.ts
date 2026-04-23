import { drizzle } from 'drizzle-orm/postgres-js';
import postgres from 'postgres';
import { eq } from 'drizzle-orm';
import * as schema from '../src/schemas/index.js';
import 'dotenv/config';

async function main() {
  const connectionString = process.env.DATABASE_URL;
  if (!connectionString) {
    console.error('DATABASE_URL is not set');
    return;
  }

  const sql = postgres(connectionString);
  const db = drizzle(sql, { schema });

  try {
    console.log('--- Order #38 Cleanup ---');
    
    // Check if it exists
    const orderId = 38;
    const [order] = await db.select().from(schema.salesOrders).where(eq(schema.salesOrders.id, orderId));
    
    if (order) {
      console.log('Order #38 found. Deleting related items first...');
      await db.delete(schema.orderItems).where(eq(schema.orderItems.orderId, orderId));
      
      console.log('Deleting Order #38...');
      await db.delete(schema.salesOrders).where(eq(schema.salesOrders.id, orderId));
      
      console.log('Checking related quotations...');
      await db.update(schema.quotations)
        .set({ status: 'sent', convertedToOrderId: null })
        .where(eq(schema.quotations.convertedToOrderId, orderId));
        
      console.log('Order #38 and related items have been HARD DELETED from backend.');
    } else {
      console.log('Order #38 not found in backend.');
    }

  } catch (error) {
    console.error('Error during cleanup:', error);
  } finally {
    await sql.end();
  }
}

main();
