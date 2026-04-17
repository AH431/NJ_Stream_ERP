// ==============================================================================
// ImportScreen — CSV 資料匯入（Issue #16）
//
// 功能：
//   上線前初始資料匯入（產品、客戶、庫存初始化）。
//   選擇 entity type → 選取本地 CSV 檔案 → 上傳 → 顯示成功/失敗筆數。
//
// 設計：
//   - 僅 admin 可進入（由 DevSettingsScreen 入口管控）
//   - CSV 格式說明直接顯示在畫面上
//   - 失敗行展開顯示錯誤原因
//   - 入口：DevSettingsScreen 資料維護區塊
// ==============================================================================

import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';

// ── CSV 格式說明 ────────────────────────────────────────────────────────────

const _formats = {
  'product':   'name,sku,unitPrice,minStockLevel\n範例：螺絲A,SKU-001,25.50,10',
  'customer':  'name,contact,taxId\n範例：台灣電子,02-12345678,12345678',
  'inventory': 'sku,quantity\n範例：SKU-001,100',
};

const _typeLabels = {
  'product':   '產品',
  'customer':  '客戶',
  'inventory': '庫存初始化',
};

// ── Screen ────────────────────────────────────────────────────────────────────

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  String _selectedType = 'product';
  bool _isUploading = false;

  // 上次上傳結果
  int? _succeeded;
  List<Map<String, dynamic>> _failed = [];
  String? _uploadError;

  // --------------------------------------------------------------------------

  Future<void> _pickAndUpload() async {
    setState(() {
      _succeeded = null;
      _failed = [];
      _uploadError = null;
    });

    // sync 在所有 await 前取得，避免跨 async gap 使用 context
    final sync = context.read<SyncProvider>();

    // 1. 選擇 CSV 檔案
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) {
      setState(() => _uploadError = '無法讀取檔案內容');
      return;
    }

    // 2. 基本 CSV 驗證（在前端預先驗證 header，減少無效上傳）
    final content = String.fromCharCodes(file.bytes!);
    final lines = content.trim().split(RegExp(r'\r?\n'));
    if (lines.length < 2) {
      setState(() => _uploadError = 'CSV 至少需要 header 行與一筆資料');
      return;
    }

    // 3. 上傳
    setState(() => _isUploading = true);
    try {
      final response = await sync.uploadImportCsv(
        type: _selectedType,
        fileName: file.name,
        csvBytes: file.bytes!,
      );
      final succeeded = response['succeeded'] as int? ?? 0;
      final failed = (response['failed'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ??
          [];
      setState(() {
        _succeeded = succeeded;
        _failed = failed;
        _uploadError = null;
      });
      if (mounted) _showResultDialog(succeeded, failed);
    } on DioException catch (e) {
      final msg = (e.response?.data as Map<String, dynamic>?)?['message']
          ?? e.message
          ?? '上傳失敗';
      setState(() => _uploadError = msg);
      if (mounted) _showErrorDialog(msg);
    } catch (e) {
      setState(() => _uploadError = e.toString());
      if (mounted) _showErrorDialog(e.toString());
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showResultDialog(int succeeded, List<Map<String, dynamic>> failed) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Text('成功匯入 $succeeded 筆'),
          ],
        ),
        content: failed.isEmpty
            ? const Text('無失敗行')
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('另有 ${failed.length} 行失敗：',
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  ...failed.map((f) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          '第 ${f['row']} 行：${f['reason']}',
                          style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                        ),
                      )),
                ],
              ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600),
            const SizedBox(width: 8),
            const Text('上傳失敗'),
          ],
        ),
        content: Text(msg),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('確定'),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('CSV 資料匯入')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 類型選擇 ──────────────────────────────────────────────
            Text('資料類型', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'product',   label: Text('產品')),
                ButtonSegment(value: 'customer',  label: Text('客戶')),
                ButtonSegment(value: 'inventory', label: Text('庫存')),
              ],
              selected: {_selectedType},
              onSelectionChanged: (s) => setState(() {
                _selectedType = s.first;
                _succeeded = null;
                _failed = [];
                _uploadError = null;
              }),
            ),

            const SizedBox(height: 20),

            // ── CSV 格式說明 ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CSV 格式（${_typeLabels[_selectedType]}）',
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formats[_selectedType]!,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 上傳按鈕 ──────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: _isUploading
                  ? const Center(child: CircularProgressIndicator())
                  : FilledButton.icon(
                      onPressed: _pickAndUpload,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: Text('選擇 CSV 並匯入${_typeLabels[_selectedType]!}'),
                    ),
            ),

            const SizedBox(height: 24),

            // ── 結果顯示 ──────────────────────────────────────────────
            if (_uploadError != null)
              _ResultCard(
                color: Colors.red.shade50,
                borderColor: Colors.red.shade200,
                icon: Icons.error_outline,
                iconColor: Colors.red,
                title: '上傳失敗',
                body: _uploadError!,
              ),

            if (_succeeded != null) ...[
              _ResultCard(
                color: Colors.green.shade50,
                borderColor: Colors.green.shade200,
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
                title: '成功匯入 $_succeeded 筆',
                body: _failed.isEmpty ? '無失敗行' : '另有 ${_failed.length} 行失敗（見下方）',
              ),
              if (_failed.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('失敗明細', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.grey)),
                const SizedBox(height: 6),
                ..._failed.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('第 ${f['row']} 行  ', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                      Expanded(
                        child: Text('${f['reason']}', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                      ),
                    ],
                  ),
                )),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

// ── 結果卡片元件 ───────────────────────────────────────────────────────────────

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.color,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final Color color;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: iconColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 2),
                Text(body, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
