import psycopg2
import os

db_url = "postgresql://postgres:ifGuJTX66Pwu9AHKUK2ntFLlUgzKzCgq@localhost:5432/nj_erp"

try:
    conn = psycopg2.connect(db_url)
    cursor = conn.cursor()

    print(f"Checking SalesOrder #38 in backend...")
    cursor.execute("SELECT * FROM sales_orders WHERE id = 38")
    order = cursor.fetchone()

    if order:
        print(f"Order #38 found: {order}")
        # Check if it was converted from quotation
        cursor.execute("SELECT id, status FROM quotations WHERE converted_to_order_id = 38")
        quot = cursor.fetchone()
        if quot:
            print(f"Related Quotation: {quot}")
        
        # Check order items
        cursor.execute("SELECT * FROM order_items WHERE order_id = 38")
        items = cursor.fetchall()
        print(f"Order Items: {items}")
    else:
        print("Order #38 not found in backend database.")

    conn.close()
except Exception as e:
    print(f"Error: {e}")
