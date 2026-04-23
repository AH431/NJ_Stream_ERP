import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:provider/provider.dart';

const _kLangKey = 'app_language';

class AppStrings extends ChangeNotifier {
  AppStrings(this._storage);

  final FlutterSecureStorage _storage;

  bool _isEnglish = false;
  bool get isEnglish => _isEnglish;

  Future<void> init() async {
    final saved = await _storage.read(key: _kLangKey);
    if (saved == 'en') {
      _isEnglish = true;
      notifyListeners();
    }
  }

  Future<void> setEnglish(bool value) async {
    if (_isEnglish == value) return;
    _isEnglish = value;
    notifyListeners();
    await _storage.write(key: _kLangKey, value: value ? 'en' : 'zh');
  }

  String _s(String zh, String en) => _isEnglish ? en : zh;

  /// Use inside build methods/widgets that should rebuild when language changes.
  static AppStrings of(BuildContext context) => context.watch<AppStrings>();

  /// Use inside event handlers, async callbacks, init flows, and save/delete
  /// actions. `of(context)` listens to provider changes and will assert when
  /// called from button handlers such as `onPressed`.
  static AppStrings read(BuildContext context) => context.read<AppStrings>();

  // ── Navigation ────────────────────────────────────────────────────────────
  String get navDashboard => _s('儀表板', 'Home');
  String get navCustomers => _s('客戶', 'Clients');
  String get navProducts => _s('產品', 'Products');
  String get navQuotations => _s('報價', 'Quotes');
  String get navOrders => _s('訂單', 'Orders');
  String get navInventory => _s('庫存', 'Stock');

  String get titleDashboard => _s('儀表板', 'Dashboard');
  String get titleCustomers => _s('客戶管理', 'Customer Mgmt');
  String get titleProducts => _s('產品管理', 'Product Mgmt');
  String get titleQuotations => _s('報價管理', 'Quotations');
  String get titleOrders => _s('訂單管理', 'Orders');
  String get titleInventory => _s('庫存查詢', 'Inventory');

  // ── AppBar actions ────────────────────────────────────────────────────────
  String tooltipSyncFailed(String err) =>
      _isEnglish ? 'Sync failed: $err' : '同步失敗：$err';
  String tooltipSyncPending(int n) =>
      _isEnglish ? 'Push $n pending operations' : '推送 $n 筆待同步操作';
  String get tooltipSynced => _s('已同步', 'Synced');
  String get tooltipLogout => _s('登出', 'Logout');
  String get menuDevSettings => _s('開發者設定', 'Developer Settings');

  // ── Logout dialog ─────────────────────────────────────────────────────────
  String get logoutTitle => _s('確認登出', 'Confirm Logout');
  String logoutBody(int pending) {
    if (pending > 0) {
      return _isEnglish
          ? 'You have $pending unsynced operations.\nThey will sync on next login.\nLog out now?'
          : '您有 $pending 筆操作尚未同步。\n登出後、這些操作將在下次登入後繼續同步。\n確定登出嗎？';
    }
    return _s('確定登出嗎？', 'Log out now?');
  }

  String get btnCancel => _s('取消', 'Cancel');
  String get btnLogout => _s('登出', 'Logout');

  // ── FAB tooltips ──────────────────────────────────────────────────────────
  String get fabAddCustomer => _s('新增客戶', 'Add Customer');
  String get fabAddProduct => _s('新增產品', 'Add Product');
  String get fabAddQuotation => _s('新增報價單', 'New Quotation');
  String get fabStockIn => _s('入庫', 'Stock In');
  String get snackStockInQueued => _s('入庫已排入待同步佇列，同步後庫存將更新',
      'Stock-in queued. Inventory will update after sync.');

  // ── Auth / Login ──────────────────────────────────────────────────────────
  String get loginTitle => _s('NJ Stream ERP — 登入', 'NJ Stream ERP — Login');
  String get loginFieldUsername => _s('帳號', 'Username');
  String get loginFieldPassword => _s('密碼', 'Password');
  String get btnLogin => _s('登入', 'Login');
  String get errEmptyCredentials =>
      _s('請輸入帳號與密碼', 'Please enter username and password.');
  String get errLoginFailed =>
      _s('登入失敗，請檢查帳號密碼。', 'Login failed. Please check your credentials.');
  String errLoginException(String e) => _isEnglish ? 'Error: $e' : '發生錯誤: $e';

  // ── Dashboard ─────────────────────────────────────────────────────────────
  String get dashPendingShipments => _s('待出貨訂單', 'Pending Shipments');
  String get dashPendingUnit => _s('筆', 'orders');
  String get dashMonthlyQuotations => _s('月報價', 'Monthly Quotations');
  String get dashCurrencyUnit => _s('元', 'NTD');
  String get dashLowStockAlert => _s('低庫存警示', 'Low Stock Alert');
  String get dashNoLowStock => _s('目前無低庫存品項', 'No low stock items.');
  String dashAvailable(int qty) => _isEnglish ? 'Available: $qty' : '可出貨 $qty';
  String dashOnHandReserved(int onHand, int reserved) => _isEnglish
      ? 'On Hand: $onHand  Reserved: $reserved'
      : '庫存 $onHand　預留 $reserved';
  String dashSafetyShortage(int min, int shortage) => _isEnglish
      ? 'Safety: $min  Shortage: $shortage'
      : '安全庫存 $min　缺 $shortage';

  // ── Customer List ─────────────────────────────────────────────────────────
  String get custEmptyTitle => _s('尚無客戶資料', 'No customers yet.');
  String get custEmptyAdd =>
      _s('點擊右下角 ＋ 新增第一位客戶', 'Tap ＋ to add your first customer.');
  String get custEmptySync => _s('下拉以同步取得最新資料', 'Pull down to sync.');
  String get custTooltipSync => _s('等待同步', 'Pending sync');
  String get custTooltipEmail => _s('寄月結對帳單', 'Send monthly statement');
  String get custTooltipDel => _s('刪除客戶', 'Delete customer');
  String get custDelTitle => _s('刪除客戶', 'Delete Customer');
  String custDelBody(String name) => _isEnglish
      ? 'Delete "$name"? This cannot be undone.'
      : '確定要刪除「$name」？此操作無法復原。';
  String get btnDelete => _s('刪除', 'Delete');
  String custDeleted(String name) =>
      _isEnglish ? '"$name" deleted.' : '已刪除「$name」';
  String get custTaxIdPrefix => _s('統編：', 'Tax ID: ');
  String get custTaxId => _s('統編：', 'Tax ID: ');

  // ── Customer Form ─────────────────────────────────────────────────────────
  String get custFormTitle => _s('新增客戶', 'New Customer');
  String get btnSave => _s('儲存', 'Save');
  String get custOfflineNote =>
      _s('離線時可直接儲存，連線後自動同步至伺服器。', 'Saved offline. Will sync when connected.');
  String get custFieldName => _s('客戶名稱 *', 'Customer Name *');
  String get custFieldContact => _s('聯絡人', 'Contact Person');
  String get custFieldEmail => _s('Email', 'Email');
  String get custEmailHelper =>
      _s('用於寄送報價單 / 對帳單', 'Used for sending quotations / statements');
  String get custFieldTaxId => _s('統一編號', 'Tax ID');
  String get btnSaving => _s('儲存中...', 'Saving...');
  String get btnSaveCustomer => _s('儲存客戶', 'Save Customer');
  String get errNameRequired => _s('請輸入客戶名稱', 'Customer name is required.');
  String get errEmailInvalid => _s('Email 格式不正確', 'Invalid email format.');
  String get errTaxIdInvalid => _s('統一編號須為 8 位數字', 'Tax ID must be 8 digits.');

  // ── Product List ──────────────────────────────────────────────────────────
  String get prodEmptyTitle => _s('尚無產品資料', 'No products yet.');
  String get prodEmptySync => _s('下拉以同步取得最新資料', 'Pull down to sync.');
  String get prodDelTitle => _s('刪除產品', 'Delete Product');
  String prodDelBody(String name) => _isEnglish
      ? 'Delete "$name"? This cannot be undone.'
      : '確定要刪除「$name」？此操作無法復原。';
  String prodDeleted(String name) =>
      _isEnglish ? '"$name" deleted.' : '已刪除「$name」';
  String prodMinStock(int level) =>
      _isEnglish ? 'Alert: $level units' : '警示：$level 件';

  // ── Product Form ──────────────────────────────────────────────────────────
  String get prodFormTitle => _s('新增產品', 'New Product');
  String get prodFieldName => _s('產品名稱 *', 'Product Name *');
  String get prodFieldSku => _s('SKU *', 'SKU *');
  String get prodFieldPrice => _s('單價 *', 'Unit Price *');
  String get prodFieldMinStock => _s('最低庫存警示', 'Min Stock Level');
  String get btnSaveProduct => _s('儲存產品', 'Save Product');
  String get btnSavingProduct => _s('儲存中…', 'Saving…');

  // ── Quotation List ────────────────────────────────────────────────────────
  String get quotEmptyHint =>
      _s('尚無報價單\n下拉以同步取得最新資料', 'No quotations.\nPull down to sync.');
  String get quotStatusSent => _s('已發送', 'Sent');
  String get quotStatusConverted => _s('已轉訂', 'Converted');
  String get quotStatusExpired => _s('已過期', 'Expired');
  String get quotStatusDraft => _s('草稿', 'Draft');
  String get btnPdf => _s('PDF', 'PDF');
  String get btnSendEmail => _s('寄信', 'Email');
  String get btnConvert => _s('轉訂單', 'Convert');
  String get btnConvertOnline => _s('連線推送後轉訂單', 'Convert after sync');
  String get btnDelQuot => _s('刪除', 'Delete');

  // ── Quotation Form ────────────────────────────────────────────────────────
  String get quotFormTitle => _s('新增報價單', 'New Quotation');
  String get quotFieldCustomer => _s('客戶 *', 'Customer *');
  String get quotErrCustomer => _s('請選擇客戶', 'Please select a customer.');
  String get quotFieldProduct => _s('產品 *', 'Product *');
  String get quotErrProduct => _s('請選擇產品', 'Please select a product.');
  String get quotErrRequired => _s('必填', 'Required');
  String get quotFieldQty => _s('數量', 'Qty');
  String get quotErrQtyInvalid => _s('正整數', 'Positive integer');
  String get quotFieldPrice => _s('單價', 'Unit Price');
  String get quotErrPriceFmt => _s('格式錯誤', 'Invalid format');
  String get quotErrPriceEmpty => _s('請輸入單價', 'Please enter a unit price.');
  String get quotFieldSubtotal => _s('小計', 'Subtotal');
  String get quotBtnAddRow => _s('新增品項', 'Add item');
  String get quotWithTax => _s('含稅（5%）', 'Include Tax (5%)');
  String get quotLabelSubtotal => _s('小計：', 'Subtotal: ');
  String quotLabelTax(bool withTax) => _isEnglish
      ? (withTax ? 'Tax (5%): ' : 'Tax: ')
      : (withTax ? '稅額（5%）：' : '稅額：');
  String get quotLabelTotal => _s('合計：', 'Total: ');
  String get btnSaveQuotation => _s('儲存報價單', 'Save Quotation');
  String get quotSaveSuccess => _s('報價單已儲存', 'Quotation saved.');

  // ── Sales Order List ──────────────────────────────────────────────────────
  String get orderStatusConfirmed => _s('已確認', 'Confirmed');
  String get orderStatusShipped => _s('已出貨', 'Shipped');
  String get orderStatusCancelled => _s('已取消', 'Cancelled');
  String get orderStatusPending => _s('待處理', 'Pending');
  String get btnConfirmOrder => _s('確認訂單', 'Confirm');
  String get btnReserveInventory => _s('預留庫存', 'Reserve');
  String get btnInsufficientStock => _s('庫存不足', 'Insufficient');
  String get btnShipOrder => _s('出貨', 'Ship');
  String get btnCancelOrder => _s('取消', 'Cancel');
  String orderFromQuot(int id) =>
      _isEnglish ? 'From Quotation #$id' : '報價轉入 #$id';
  String orderCreatedAt(String dt) => _isEnglish ? 'Created: $dt' : '建立：$dt';

  // ── Reserve Inventory Dialog ──────────────────────────────────────────────
  String get reserveTitle => _s('預留庫存確認', 'Reserve Inventory');
  String get reserveWarning => _s('以下庫存將被預留，確認後不可撤回（需重新取消訂單才能釋放）。',
      'The following inventory will be reserved. This cannot be undone without cancelling the order.');
  String get reserveInsuffMsg => _s('庫存不足，無法預留。請先同步最新庫存後再執行。',
      'Insufficient stock. Please sync latest inventory before reserving.');
  String get btnWaitForStock => _s('等待到貨通知', 'Wait for restock');
  String get btnSplitOrder => _s('請拆單', 'Request split order');
  String get btnConfirmReserve => _s('確認預留', 'Confirm Reserve');
  String reserveQty(int qty) => _isEnglish ? 'Reserve $qty' : '預留 $qty';
  String reserveAvailable(int qty) =>
      _isEnglish ? 'Available $qty' : '可出貨 $qty';
  String get reserveNoRecord => _s('— 無本地記錄', '— No local record');

  // ── Ship Order Dialog ─────────────────────────────────────────────────────
  String get shipTitle => _s('出貨確認', 'Confirm Shipment');
  String get shipWarningBody => _s('確認後在庫數量與預留數量將同步扣除，此操作不可逆。',
      'On-hand and reserved quantities will be deducted. This cannot be undone.');
  String get shipBannerNoReserve => _s(
      '部分商品尚未執行庫存預留，服務端將拒絕出貨並觸發強制同步。建議先執行「預留庫存」。',
      'Some items are not yet reserved. The server will reject shipment and force a sync. Please reserve inventory first.');
  String get shipBannerInsufficient => _s('部分商品在庫數量不足，建議先同步確認庫存後再執行出貨。',
      'Some items have insufficient on-hand stock. Please sync inventory before shipping.');
  String get btnConfirmShip => _s('確認出貨', 'Confirm Shipment');
  String shipQty(int qty) => _isEnglish ? 'Ship $qty' : '出貨 $qty';
  String get shipNoRecord => _s('— 無本地記錄', '— No local record');

  // ── Inventory List ────────────────────────────────────────────────────────
  String get invColOnHand => _s('在庫', 'On Hand');
  String get invColReserved => _s('已預留', 'Reserved');
  String get invColAvailable => _s('可出貨', 'Available');
  String get invLowStockBadge => _s('⚠ 低庫存', '⚠ Low Stock');
  String invMinStock(int level) => _isEnglish ? 'Min: $level' : '最低庫存閾值：$level';
  String get invEmptyHint =>
      _s('尚無庫存記錄\n下拉以同步取得最新庫存資料', 'No inventory records.\nPull down to sync.');

  // ── Stock-in Dialog ───────────────────────────────────────────────────────
  String get stockInTitle => _s('入庫', 'Stock In');
  String get stockInFieldProd => _s('產品', 'Product');
  String get stockInFieldQty => _s('入庫數量', 'Quantity');
  String get stockInNoProducts => _s('尚無產品', 'No products available.');
  String get stockInErrQty => _s('請輸入正整數', 'Please enter a positive integer.');
  String get btnSubmitStockIn => _s('入庫', 'Submit');

  // ── Dev Settings ──────────────────────────────────────────────────────────
  String get devTitle => _s('開發者設定', 'Developer Settings');
  String get devSectionCompile => _s('編譯期預設值', 'Compile-time Defaults');
  String get devCurrentCustomUrl => _s('目前使用自訂 URL', 'Using custom URL');
  String get devSectionImport => _s('資料匯入', 'Data Import');
  String get devSectionMaintain => _s('資料維護', 'Maintenance');
  String get devCleanupTitle => _s('清理舊記錄', 'Cleanup Records');
  String get devCleanupDesc => _s('刪除後端 30 天前的已處理記錄與軟刪除資料，\n及本地 7 天前的已完成同步記錄。',
      'Delete backend records > 30 days old and local records > 7 days old.');
  String get btnResetDefault => _s('重置為預設', 'Reset to Default');
  String get btnSaveSettings => _s('儲存', 'Save');
  String get btnOpenImport => _s('開啟匯入', 'Open Import');
  String get btnRunCleanup => _s('執行清理', 'Run Cleanup');

  // ── Import Screen ─────────────────────────────────────────────────────────
  String get importTitle => _s('CSV 資料匯入', 'CSV Import');
  String get importTypeLabel => _s('資料類型', 'Data Type');
  String get importTypeProduct => _s('產品', 'Products');
  String get importTypeCustomer => _s('客戶', 'Customers');
  String get importTypeInventory => _s('庫存', 'Inventory');
  String importFormatTitle(String type) =>
      _isEnglish ? 'CSV Format ($type)' : 'CSV 格式（$type）';
  String importBtnLabel(String type) =>
      _isEnglish ? 'Select CSV and import $type' : '選擇 CSV 並匯入$type';
  String importSuccessTitle(int n) =>
      _isEnglish ? 'Imported $n rows successfully' : '成功匯入 $n 筆';
  String get importNoFailed => _s('無失敗行', 'No failed rows.');
  String importFailedSummary(int n) =>
      _isEnglish ? '$n rows failed (see below)' : '另有 $n 行失敗（見下方）';
  String importFailedRow(int row, String reason) =>
      _isEnglish ? 'Row $row: $reason' : '第 $row 行：$reason';
  String get importErrTitle => _s('上傳失敗', 'Upload Failed');
  String get importErrNoContent => _s('無法讀取檔案內容', 'Cannot read file content.');
  String get importErrTooShort => _s('CSV 至少需要 header 行與一筆資料',
      'CSV must have a header row and at least one data row.');
  String get importFailedDetail => _s('失敗明細', 'Failed Rows');
  String get importFolderLabel => _s('資料夾', 'Folder');
  String get importRescanBtn => _s('重新掃描', 'Re-scan');
  String importFileListTitle(String type) =>
      _isEnglish ? 'CSV files matching "$type"' : '符合「$type」的 CSV 檔案';
  String get importPreviewLabel => _s('內容預覽', 'Content Preview');
  String importConfirmBtn(String type) =>
      _isEnglish ? 'Confirm import: $type' : '確認匯入$type';
  String get importNoMatchFiles =>
      _s('目錄中無符合的 CSV 檔案', 'No matching CSV files in directory.');
  String get importDirNotFound => _s('找不到資料夾', 'Directory not found.');
  String get importAdbHint =>
      _s('請先執行 adb push 將 CSV 推送到手機：', 'Push the CSV to your device first:');
  String importErrReadDir(String detail) =>
      _isEnglish ? 'Cannot read directory: $detail' : '無法讀取資料夾：$detail';
  String importErrReadFile(String detail) =>
      _isEnglish ? 'Cannot read file: $detail' : '無法讀取檔案：$detail';
  String importDoneMsg(int succeeded, int failed) => _isEnglish
      ? 'Import complete: $succeeded succeeded, $failed failed'
      : '匯入完成：$succeeded 筆成功，$failed 筆失敗';
  String get importFormatProduct => _isEnglish
      ? 'name,sku,unitPrice,minStockLevel\nExample: Widget-A,SKU-001,25.50,10'
      : 'name,sku,unitPrice,minStockLevel\n範例：螺絲A,SKU-001,25.50,10';
  String get importFormatCustomer => _isEnglish
      ? 'name,contact,taxId\nExample: TW Electronics,02-12345678,12345678'
      : 'name,contact,taxId\n範例：台灣電子,02-12345678,12345678';
  String get importFormatInventory => _isEnglish
      ? 'sku,quantity\nExample: SKU-001,100'
      : 'sku,quantity\n範例：SKU-001,100';
  String get btnOk => _s('確定', 'OK');

  // ── Dev Settings Extra ──────────────────────────────────────────────────
  String get devSectionLang => _s('語言切換', 'Language');
  String get devSwitchLang => _s('切換為中文', 'Switch to Chinese');
  String get devResetApiTitle => _s('重置 API URL', 'Reset API URL');
  String devResetApiBody(String url) => _isEnglish
      ? 'Will restore to compile-time default:\n$url'
      : '將恢復為編譯期預設值：\n$url';
  String get devResetApiDone => _s('已重置為預設 URL', 'Reset to default URL');

  String devCleanupSuccess(int proc, int soft, int local) => _isEnglish
      ? 'Cleanup: $proc ops, $soft soft-deleted; $local local'
      : '清理：後端 processed $proc 筆，軟刪除 $soft 筆；本地 $local 筆';
  String get devClearCustTitle => _s('清空手機端客戶名單', 'Clear Local Clients');
  String get devClearCustDesc => _s('僅刪除此裝置上的客戶快照，不影響伺服器資料。',
      'Delete local client snapshots only, server data remains.');
  String get devConfirmClearTitle => _s('確認清空？', 'Confirm Clear?');
  String get devConfirmClearBody => _s('這將刪除手機上的所有客戶資料（快照），稍後可透過「下拉同步」重新取得。',
      'This will delete all customer data on this phone. Pull to sync later to restore.');
  String get devClearCustSuccess =>
      _s('本地客戶名單已清空', 'Local client list cleared.');

  // ── Document Actions ──────────────────────────────────────────────────────
  String get msgEmailSent => _s('郵件已寄送', 'Email sent successfully.');
  String msgEmailFailed(String e) =>
      _isEnglish ? 'Failed to send: $e' : '寄送失敗：$e';
}
