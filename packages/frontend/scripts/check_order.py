import sqlite3
import os
from pathlib import Path

# Path to the nj_stream_erp.sqlite file
# Based on database.dart, it's in getApplicationDocumentsDirectory()
# On Windows, this is usually C:\Users\<user>\Documents
docs_dir = Path.home() / "Documents"
db_path = docs_dir / "nj_stream_erp.sqlite"

if not db_path.exists():
    print(f"Database not found at {db_path}")
    exit(1)

conn = sqlite3.connect(str(db_path))
cursor = conn.cursor()

print(f"Checking SalesOrder #38...")
cursor.execute("SELECT * FROM sales_orders WHERE id = 38")
order = cursor.fetchone()

if order:
    print(f"Order #38: {order}")
    # Also check related items
    cursor.execute("SELECT * FROM order_items WHERE order_id = 38")
    items = cursor.fetchall()
    print(f"Items for Order #38: {items}")
else:
    print("Order #38 not found in local database.")

conn.close()
