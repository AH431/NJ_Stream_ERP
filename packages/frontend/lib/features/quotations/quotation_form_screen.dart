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
  final GlobalKey cardKey = GlobalKey();
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
  bool _isSaving = false;

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
      final ctx = _rows.last.cardKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          alignmentPolicy: ScrollPositionAlignmentPolicy.explicit,
          alignment: 0.0,
        );
      }
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

  // ⚠ 高風險註記（維護者必讀）：
  //
  // [1] 禁止在事件回呼內使用 AppStrings.of()（context.watch 路徑）
  //     AppStrings.of() 呼叫 context.watch，在 build 以外觸發
  //     "Tried to listen to a value exposed with provider, from outside of the widget tree."
  //     → 事件流程統一用 context.read<AppStrings>()。
  //
  // [2] 禁止在此 await pushPendingOperations
  //     語意：只做「本地 insert + enqueueCreate + pop」。
  //     在這裡等待同步推送，token refresh / tunnel 失敗會使 Navigator.pop
  //     長時間卡住，使用者看到按鈕無反應。
  //
  // [3] 畫面切換時序與閃爍根因（重要）：
  //     t=0ms    : 點下儲存，_isSaving=true，按鈕切為 spinner（立即）。
  //     t≈10–30ms: insertQuotation + enqueueCreate（兩次本地 SQLite 寫入）完成。
  //     t≈30ms   : Navigator.pop() 呼叫；過場動畫開始（平台預設 ~300ms）。
  //     ⚠ 關鍵：Navigator.pop() 不阻塞——它只「發起」動畫，widget 要等動畫
  //       結束才真正 dispose。pop() 之後 mounted 持續為 true 約 300ms。
  //     → 若在 finally 無條件 setState(() => _isSaving = false)，會在動畫
  //       期間多觸發一次 rebuild：spinner 閃回 Save 文字 + Form.onChanged 守衛
  //       解除，若 enqueueCreate 的 notifyListeners 排在同一 frame，再多疊一次。
  //     → 修法：用 didPop flag；成功跳頁後不重設 _isSaving，讓 spinner
  //       維持到 widget 被 dispose，動畫全程無多餘 rebuild。
  //
  // [4] 禁止用整頁 GestureDetector 包住 Scaffold 來收鍵盤
  //     與底部按鈕 tap 事件競爭，導致偶發性點擊失效。
  //     若需收鍵盤，在欄位層級（onEditingComplete / FocusScope.of(context).unfocus()）處理。
  Future<void> _save() async {
    if (_isSaving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    // didPop：標記是否已成功呼叫 Navigator.pop。
    // finally 只在 !didPop（儲存失敗路徑）重設 _isSaving，
    // 避免成功路徑在 pop 動畫期間多觸發一次 rebuild（spinner 閃回 Save 文字）。
    var didPop = false;

    try {
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
      didPop = true; // 設於 pop 之前，確保 finally 能正確判斷
      Navigator.pop(context);
      // _isSaving 刻意保持 true：pop 動畫期間 widget 仍 mounted，
      // 不重設可防止 Form.onChanged 守衛解除造成額外 rebuild。
      // widget dispose 後 _isSaving 狀態自動失效。
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('儲存失敗：$e')),
      );
    } finally {
      // 僅錯誤路徑（!didPop）需要重設，讓使用者可以重試。
      // 成功路徑已呼叫 pop，不重設以避免動畫中多餘 rebuild。
      if (!didPop && mounted) setState(() => _isSaving = false);
    }
  }

  // --------------------------------------------------------------------------
  // Build
  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    // backgroundColor 必須設定：全域主題 scaffoldBackgroundColor=Colors.transparent
    // （讓 gradient 穿透），若此處不明確指定實心色，pop 動畫期間 form Scaffold 透明，
    // list 畫面從後方透出，造成鬼影重疊。Colors.white 對應 gradient 頂端色。
    return Scaffold(
      backgroundColor: Colors.white,
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
      onChanged: () { if (!_isSaving) setState(() {}); }, // 即時重算金額；save 期間跳過避免重建
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
                    onPressed: _isSaving ? null : _save,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      minimumSize: const Size(0, 44),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text(s.btnSaveQuotation),
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
      // ignore: deprecated_member_use
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
        key: row.cardKey,
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
                      // ignore: deprecated_member_use
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
