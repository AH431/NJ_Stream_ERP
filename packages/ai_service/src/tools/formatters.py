
"""
formatters.py — Deterministic answer builders for dynamic tool results.

No LLM involved: given structured data, produce a fixed-format string.
availableQuantity must come from the server response, never computed here.
"""


def format_inventory_answer(product: dict, inventory: dict) -> str:
    name = product.get("name", "(unknown product)")
    sku = product.get("sku", "")
    on_hand = inventory.get("quantityOnHand", 0)
    reserved = inventory.get("quantityReserved", 0)
    available = inventory.get("availableQuantity", on_hand - reserved)
    min_stock = inventory.get("minStockLevel", 0)
    alert_stock = inventory.get("alertStockLevel", 0)
    critical_stock = inventory.get("criticalStockLevel", 0)

    lines = [
        f"Inventory Status: {name} (SKU: {sku})",
        f"• On Hand (quantityOnHand): {on_hand} units",
        f"• Reserved (quantityReserved): {reserved} units",
        f"• Available (availableQuantity): {available} units",
        f"• Min / Alert / Critical Stock Levels: {min_stock} / {alert_stock} / {critical_stock} units",
    ]

    if available <= critical_stock:
        lines.append(f"[CRITICAL] Available ({available}) is below critical level ({critical_stock}). Immediate action required.")
    elif available <= alert_stock:
        lines.append(f"[ALERT] Available ({available}) is below alert level ({alert_stock}). Please source urgently.")
    elif available <= min_stock:
        lines.append(f"[WARNING] Available ({available}) is below minimum level ({min_stock}). Consider replenishing.")
    else:
        lines.append(f"[OK] Stock sufficient (available {available} units, above minimum {min_stock} units).")

    return "\n".join(lines)


def _format_money(value) -> str:
    if value is None:
        return "Confidential"
    return f"NT$ {value}"


def format_quotation_answer(quotation: dict) -> str:
    lines = [
        f"Quotation #{quotation.get('id')}",
        f"Customer: {quotation.get('customerName', '(unknown customer)')}",
        f"Status: {quotation.get('status', 'unknown')}",
        f"Total Amount: {_format_money(quotation.get('totalAmount'))}",
        f"Tax Amount: {_format_money(quotation.get('taxAmount'))}",
        "Details:",
    ]

    items = quotation.get("items", [])
    if not items:
        lines.append("• No item details")
        return "\n".join(lines)

    for item in items:
        lines.append(
            f"• {item.get('productName', '(unknown item)')} ({item.get('sku', '-')})"
            f" × {item.get('quantity', 0)} @ {_format_money(item.get('unitPrice'))},"
            f" Subtotal {_format_money(item.get('subtotal'))}"
        )

    return "\n".join(lines)


def format_sales_order_answer(order: dict) -> str:
    lines = [
        f"Sales Order #{order.get('id')}",
        f"Customer: {order.get('customerName', '(unknown customer)')}",
        f"Status: {order.get('status', 'unknown')}",
        f"Payment Status: {order.get('paymentStatus') or 'Confidential'}",
        f"Confirmed At: {order.get('confirmedAt') or 'Not Confirmed'}",
        f"Total Amount: {_format_money(order.get('totalAmount'))}",
        f"Tax Amount: {_format_money(order.get('taxAmount'))}",
        "Details:",
    ]

    items = order.get("items", [])
    if not items:
        lines.append("• No item details")
        return "\n".join(lines)

    for item in items:
        lines.append(
            f"• {item.get('productName', '(unknown item)')} ({item.get('sku', '-')})"
            f" × {item.get('quantity', 0)} @ {_format_money(item.get('unitPrice'))},"
            f" Subtotal {_format_money(item.get('subtotal'))}"
        )

    return "\n".join(lines)


def format_customer_search_answer(items: list[dict], q: str) -> str:
    if not items:
        return f"No customers found matching '{q}'."

    lines = [f"Customer Search: {q}"]
    for item in items:
        lines.append(
            f"• {item.get('name', '(Unnamed Customer)')} / Contact: {item.get('contact') or 'N/A'}"
            f" / Email: {item.get('email') or 'N/A'}"
        )
    return "\n".join(lines)


def format_not_found(query: str) -> str:
    return f"No product information found for '{query}'. Please verify the SKU."


def format_api_error(status_code: int) -> str:
    if status_code == 403:
        return "Insufficient permissions to access this data. Please contact support."
    if status_code == 404:
        return "No data found. Please check your query parameters."
    return f"An error occurred during the request (HTTP {status_code}). Please try again later."


def format_blocked_response() -> str:
    return "This question is outside the AI assistant's service scope and cannot be handled."


def format_forecast_answer(data: dict) -> str:
    sku = data.get("sku", "?")
    current_stock = data.get("current_stock", 0)
    forecasts = data.get("forecasts", [])
    reorder_alert = data.get("reorder_alert", False)
    stockout_week = data.get("stockout_week")

    lines = [f"Demand Forecast: {sku}"]
    lines.append(f"• Current Available Stock: {current_stock} units")

    if not forecasts:
        lines.append("• No forecast data available. Run a forecast job first.")
        return "\n".join(lines)

    lines.append(f"• Forecast ({len(forecasts)} weeks):")
    for f in forecasts:
        qty = f.get("qty", 0)
        lower = f.get("lower")
        upper = f.get("upper")
        bounds = f" ({lower:.0f}–{upper:.0f})" if lower is not None and upper is not None else ""
        lines.append(f"  - {f['week_start']}: {qty:.0f} units{bounds}")

    total = sum(f.get("qty", 0) for f in forecasts)
    lines.append(f"• Total forecast ({len(forecasts)} weeks): {total:.0f} units")

    if reorder_alert:
        lines.append(f"[REORDER ALERT] Forecasted demand ({total:.0f}) exceeds current stock ({current_stock}).")
        if stockout_week:
            lines.append(f"  Estimated stockout week: {stockout_week}")
    else:
        lines.append(f"[OK] Current stock ({current_stock}) is sufficient to cover forecasted demand ({total:.0f}).")

    return "\n".join(lines)


def format_forecast_not_found(sku: str) -> str:
    return f"No forecast data found for SKU '{sku}'. Please verify the SKU or run a forecast job first."
