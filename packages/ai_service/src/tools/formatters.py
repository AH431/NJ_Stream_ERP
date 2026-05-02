"""
formatters.py — Deterministic answer builders for dynamic tool results.

No LLM involved: given structured data, produce a fixed-format string.
availableQuantity must come from the server response, never computed here.
"""


def format_inventory_answer(product: dict, inventory: dict) -> str:
    name = product.get("name", "（未知產品）")
    sku = product.get("sku", "")
    on_hand = inventory.get("quantityOnHand", 0)
    reserved = inventory.get("quantityReserved", 0)
    available = inventory.get("availableQuantity", on_hand - reserved)
    min_stock = inventory.get("minStockLevel", 0)
    alert_stock = inventory.get("alertStockLevel", 0)
    critical_stock = inventory.get("criticalStockLevel", 0)

    lines = [
        f"【{name}（{sku}）庫存狀況】",
        f"• 實際庫存（quantityOnHand）：{on_hand} 件",
        f"• 已預留（quantityReserved）：{reserved} 件",
        f"• 可用庫存（availableQuantity）：{available} 件",
        f"• 安全水位 / 警急水位 / 危急水位：{min_stock} / {alert_stock} / {critical_stock} 件",
    ]

    if available <= critical_stock:
        lines.append(f"🔴 危急：可用庫存（{available}）已低於危急水位（{critical_stock}），請立即處理。")
    elif available <= alert_stock:
        lines.append(f"🟠 警急：可用庫存（{available}）低於警急水位（{alert_stock}），請緊急詢源。")
    elif available <= min_stock:
        lines.append(f"🟡 警告：可用庫存（{available}）低於安全水位（{min_stock}），建議補貨。")
    else:
        lines.append(f"✅ 庫存充足（可用 {available} 件，高於安全水位 {min_stock} 件）。")

    return "\n".join(lines)


def _format_money(value) -> str:
    if value is None:
        return "保密"
    return f"NT$ {value}"


def format_quotation_answer(quotation: dict) -> str:
    lines = [
        f"【報價單 #{quotation.get('id')}】",
        f"客戶：{quotation.get('customerName', '（未知客戶）')}",
        f"狀態：{quotation.get('status', 'unknown')}",
        f"總金額：{_format_money(quotation.get('totalAmount'))}",
        f"稅額：{_format_money(quotation.get('taxAmount'))}",
        "明細：",
    ]

    items = quotation.get("items", [])
    if not items:
        lines.append("• 無明細資料")
        return "\n".join(lines)

    for item in items:
        lines.append(
            f"• {item.get('productName', '（未知品項）')} ({item.get('sku', '-')})"
            f" × {item.get('quantity', 0)}，單價 {_format_money(item.get('unitPrice'))}，"
            f"小計 {_format_money(item.get('subtotal'))}"
        )

    return "\n".join(lines)


def format_sales_order_answer(order: dict) -> str:
    lines = [
        f"【銷售訂單 #{order.get('id')}】",
        f"客戶：{order.get('customerName', '（未知客戶）')}",
        f"狀態：{order.get('status', 'unknown')}",
        f"付款狀態：{order.get('paymentStatus') or '保密'}",
        f"確認時間：{order.get('confirmedAt') or '未確認'}",
        f"總金額：{_format_money(order.get('totalAmount'))}",
        f"稅額：{_format_money(order.get('taxAmount'))}",
        "明細：",
    ]

    items = order.get("items", [])
    if not items:
        lines.append("• 無明細資料")
        return "\n".join(lines)

    for item in items:
        lines.append(
            f"• {item.get('productName', '（未知品項）')} ({item.get('sku', '-')})"
            f" × {item.get('quantity', 0)}，單價 {_format_money(item.get('unitPrice'))}，"
            f"小計 {_format_money(item.get('subtotal'))}"
        )

    return "\n".join(lines)


def format_customer_search_answer(items: list[dict], q: str) -> str:
    if not items:
        return f"查無符合「{q}」的客戶資料。"

    lines = [f"【客戶搜尋：{q}】"]
    for item in items:
        lines.append(
            f"• {item.get('name', '（未命名客戶）')} / 聯絡人：{item.get('contact') or '未提供'}"
            f" / Email：{item.get('email') or '未提供'}"
        )
    return "\n".join(lines)


def format_not_found(query: str) -> str:
    return f"查無「{query}」的產品資料，請確認 SKU 是否正確。"


def format_api_error(status_code: int) -> str:
    if status_code == 403:
        return "您的帳號權限不足，無法查詢此資料，請聯絡業務或管理員。"
    if status_code == 404:
        return "查無此資料，請確認查詢條件是否正確。"
    return f"查詢時發生錯誤（HTTP {status_code}），請稍後再試。"


def format_blocked_response() -> str:
    return "此問題超出 AI 助理的服務範圍，無法處理。"
