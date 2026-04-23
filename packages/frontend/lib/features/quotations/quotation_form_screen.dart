// ==============================================================================
// QuotationFormScreen — 新增報價單（Issue #8 Phase 5）
//
// 功能：
//   - 客戶下拉選擇
//   - 動態明細行：產品選擇、數量、單價（可改）、唯讀小計
//   - 含稅 / 未稅切換（taxAmount = subtotalSum × 0.05 或 0）
//   - 金額摘要（小計、稅額、合計）
//   - 儲存：insertQuotation + enqueueCreate
//
// 金額規範：全部用 Decimal，禁止 double 參與計算
// ==============================================================================

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:drift/drift.dart' show Value;

import '../../core/app_strings.dart';
import '../../database/database.dart';
import '../../database/dao/customer_dao.dart';
import '../../database/dao/product_dao.dart';
import '../../database/dao/quotation_dao.dart';
import '../../providers/sync_provider.dart';

// ==============================================================================
// 明細行狀態
// ==============================================================================

class _ItemRow {
  int? productId;
  String productName = '';
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;

  _ItemRow()
      : qtyCtrl = TextEditingController(text: '1'),
        priceCtrl = TextEditingController(text: '0.00');

  void dispose() {
    qtyCtrl.dispose();
    priceCtrl.dispose();
  }

  Decimal get qty => Decimal.parse(qtyCtrl.text.isEmpty ? '0' : qtyCtrl.text);

  Decimal get price {
    final raw = priceCtrl.text.trim();
    return Decimal.tryParse(raw) ?? Decimal.zero;
  }

  Decimal get subtotal => qty * price;
}

// ==============================================================================
// QuotationFormScreen
// ==============================================================================

class QuotationFormScreen extends StatefulWidget {
  const QuotationFormScreen({super.key});

  @override
  State<QuotationFormScreen> createState() => _QuotationFormScreenState();
}

class _QuotationFormScreenState extends State<QuotationFormScreen> {
  final _formKey = GlobalKey<FormState>();

  int? _selectedCustomerId;
  final List<_ItemRow> _rows = [_ItemRow()];
  bool _withTax = true;

  List<Customer> _customers = [];
  List<Product> _products = [];
  bool _masterDataLoaded = false;

  final _scrollController = ScrollController();

  // --------------------------------------------------------------------------
  // 初始化
  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _loadMasterData();
  }

  Future<void> _loadMasterData() async {
    final db = Provider.of<AppDatabase>(context, listen: false);
    final customers = await db.getActiveCustomers();
    final products = await db.getActiveProducts();

    if (!mounted) return;
    setState(() {
      _customers = customers;
      _products = products;
      _masterDataLoaded = true;
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  // --------------------------------------------------------------------------
  // 金額計算（全 Decimal，禁 double）
  // --------------------------------------------------------------------------

  Decimal get _subtotalSum =>
      _rows.fold(Decimal.zero, (acc, r) => acc + r.subtotal);

  Decimal get _taxAmount =>
      _withTax ? _subtotalSum * Decimal.parse('0.05') : Decimal.zero;

  Decimal get _totalAmount => _subtotalSum + _taxAmount;

  // --------------------------------------------------------------------------
  // 明細行操作
  // --------------------------------------------------------------------------

  void _addRow() {
    setState(() => _rows.add(_ItemRow()));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  void _removeRow(int index) {
    if (_rows.length <= 1) return;
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  void _onProductSelected(int index, int? productId) {
    if (productId == null) return;
    final product = _products.firstWhere((p) => p.id == productId);
    setState(() {
      _rows[index].productId = productId;
      _rows[index].productName = product.name;
      _rows[index].priceCtrl.text = product.unitPrice.toStringAsFixed(2);
    });
  }

  // --------------------------------------------------------------------------
  // 儲存
  // --------------------------------------------------------------------------

  // 高風險註記：
  // - 不要在 onPressed/_save 事件流程中呼叫 AppStrings.of(context)。
  //   AppStrings.of 內部使用 context.watch，會觸發 Provider assertion：
  //   "Tried to listen to a value exposed with provider, from outside of the widget tree."
  //   若事件流程需要文案，請使用 AppStrings.read(context) 或 context.read<AppStrings>()。
  // - Save Quotation 保持舊版語意：只做本地 insert + enqueueCreate + pop。
  //   不要在這裡 await pushPendingOperations；token refresh / tunnel / sync 失敗
  //   會卡住 Navigator.pop，讓使用者感覺按鈕沒反應。
  // - 不要用整頁 GestureDetector 包 Scaffold 來收鍵盤；它可能和底部按鈕 tap
  //   競爭。若要完成輸入，優先用欄位層級處理。
  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final db = Provider.of<AppDatabase>(context, listen: false);
    final sync = Provider.of<SyncProvider>(context, listen: false);

    final now = DateTime.now().toUtc();
    final localId = SyncProvider.nextLocalId();
    final userId = sync.userId!;

    final subtotalSum = _subtotalSum;
    final taxAmount = _taxAmount;
    final totalAmount = _totalAmount;

    final items = _rows
        .map((r) => QuotationItemModel(
              productId: r.productId!,
              quantity: int.parse(r.qtyCtrl.text),
              unitPrice: r.price.toStringAsFixed(2),
              subtotal: r.subtotal.toStringAsFixed(2),
            ))
        .toList();

    final itemsJson = QuotationItemModel.toJsonString(items);

    await db.insertQuotation(QuotationsCompanion(
      id: Value(localId),
      customerId: Value(_selectedCustomerId!),
      createdBy: Value(userId),
      items: Value(itemsJson),
      totalAmount: Value(totalAmount),
      taxAmount: Value(taxAmount),
      status: const Value('draft'),
      createdAt: Value(now),
      updatedAt: Value(now),
    ));

    // Payload 的 items 為 List<Map>（後端格式）
    await sync.enqueueCreate('quotation', {
      'id': localId,
      'customerId': _selectedCustomerId,
      'createdBy': userId,
      'items': items.map((i) => i.toJson()).toList(),
      'totalAmount': totalAmount.toStringAsFixed(2),
      'taxAmount': taxAmount.toStringAsFixed(2),
      'subtotalSum': subtotalSum.toStringAsFixed(2),
      'withTax': _withTax,
      'status': 'draft',
      'convertedToOrderId': null,
      'createdAt': now.toIso8601String(),
      'updatedAt': now.toIso8601String(),
      'deletedAt': null,
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(s.quotFormTitle)),
      body: _masterDataLoaded
          ? _buildForm()
          : const Center(child: CircularProgressIndicator()),
    );
  }

  Widget _buildForm() {
    final s = AppStrings.of(context);
    return Form(
      key: _formKey,
      onChanged: () => setState(() {}), // 即時重算金額
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildCustomerDropdown(),
                  const SizedBox(height: 16),
                  ..._buildItemRows(),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    title: Text(s.quotWithTax),
                    value: _withTax,
                    onChanged: (v) => setState(() => _withTax = v),
                  ),
                  const SizedBox(height: 80), // 留白防止被底部操作列擋住最後一筆
                ],
              ),
            ),
          ),
          _buildAmountSummary(),
          // 增加 Padding 解決手機系統列遮擋問題
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 4, 16, MediaQuery.of(context).padding.bottom + 8),
            decoration: BoxDecoration(
              color: Theme.of(context).scaffoldBackgroundColor,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, -2))
              ],
            ),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(s.quotBtnAddRow,
                      style: const TextStyle(fontSize: 14)),
                  style: OutlinedButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 44),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 44),
                    ),
                    child: Text(s.btnSaveQuotation),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------
  // 客戶下拉
  // --------------------------------------------------------------------------

  Widget _buildCustomerDropdown() {
    final s = AppStrings.of(context);
    return DropdownButtonFormField<int>(
      decoration: InputDecoration(
          labelText: s.quotFieldCustomer, border: const OutlineInputBorder()),
      value: _selectedCustomerId,
      items: _customers
          .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
          .toList(),
      onChanged: (v) => setState(() => _selectedCustomerId = v),
      validator: (v) => v == null ? s.quotErrCustomer : null,
    );
  }

  // --------------------------------------------------------------------------
  // 明細行
  // --------------------------------------------------------------------------

  List<Widget> _buildItemRows() {
    final s = AppStrings.of(context);
    return List.generate(_rows.length, (i) {
      final row = _rows[i];
      return Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      isExpanded: true, // 確保長名稱會自動縮略而不溢出
                      decoration: InputDecoration(
                        labelText: s.quotFieldProduct,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      value: row.productId,
                      items: _products
                          .map((p) => DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.name} (${p.sku})',
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) => _onProductSelected(i, v),
                      validator: (v) => v == null ? s.quotErrProduct : null,
                    ),
                  ),
                  if (_rows.length > 1)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline,
                          color: Colors.red),
                      onPressed: () => _removeRow(i),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  // 數量
                  SizedBox(
                    width: 65,
                    child: TextFormField(
                      controller: row.qtyCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Qty',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      style: const TextStyle(fontSize: 13),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        final n = int.tryParse(v ?? '');
                        if (n == null || n <= 0) return s.quotErrQtyInvalid;
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 單價
                  Expanded(
                    child: TextFormField(
                      controller: row.priceCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Price',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      style: const TextStyle(fontSize: 13),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                      validator: (v) {
                        if (v == null || v.isEmpty) return s.quotErrPriceEmpty;
                        if (!RegExp(r'^\d+(\.\d{1,2})?$').hasMatch(v)) {
                          return s.quotErrPriceFmt;
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 唯讀小計
                  SizedBox(
                    width: 85,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                          labelText: 'Total',
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                      child: Text(
                        row.subtotal.toStringAsFixed(2),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    });
  }

  // --------------------------------------------------------------------------
  // 金額摘要（固定底部）
  // --------------------------------------------------------------------------

  Widget _buildAmountSummary() {
    final s = AppStrings.of(context);
    final sub = _subtotalSum.toStringAsFixed(2);
    final tax = _taxAmount.toStringAsFixed(2);
    final total = _totalAmount.toStringAsFixed(2);

    final style = TextStyle(
        fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant);

    return Container(
      width: double.infinity,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Wrap(
        alignment: WrapAlignment.end,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 12,
        children: [
          Text('${s.quotLabelSubtotal}$sub', style: style),
          Text('${s.quotLabelTax(_withTax)}$tax', style: style),
          Text(
            '${s.quotLabelTotal}$total',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
