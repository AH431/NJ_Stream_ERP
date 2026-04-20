import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../providers/sync_provider.dart';

// ── 常數 ──────────────────────────────────────────────────────────────────────

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

// 資料夾掃描關鍵字（檔名含此字串即符合）
const _typeKeywords = {
  'product':   'product',
  'customer':  'customer',
  'inventory': 'inventory',
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

  // 資料夾掃描
  final _dirController = TextEditingController();
  bool _isScanning = false;
  List<String> _matchingFiles = [];   // 符合關鍵字的 CSV 完整路徑清單
  String? _selectedFilePath;          // 已選取的檔案完整路徑
  List<String> _previewLines = [];    // 已選取檔案的前幾行

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _initDirAndScan();
  }

  Future<void> _initDirAndScan() async {
    final dir = await getExternalStorageDirectory();
    if (dir != null && mounted) {
      _dirController.text = '${dir.path}/test_csv';
      _scanDirectory();
    }
  }

  /// 掃描資料夾，列出符合目前類型關鍵字的 .csv 檔案
  Future<void> _scanDirectory() async {
    final dirPath = _dirController.text.trim();
    if (dirPath.isEmpty) return;

    if (mounted) {
      setState(() {
        _isScanning = true;
        _matchingFiles = [];
        _selectedFilePath = null;
        _previewLines = [];
      });
    }

    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        if (mounted) setState(() => _isScanning = false);
        return;
      }

      final keyword = _typeKeywords[_selectedType]!.toLowerCase();
      final files = dir
          .listSync()
          .whereType<File>()
          .where((f) {
            final name = f.uri.pathSegments.last.toLowerCase();
            return name.endsWith('.csv') && name.contains(keyword);
          })
          .map((f) => f.path)
          .toList()
        ..sort();

      if (mounted) setState(() { _matchingFiles = files; _isScanning = false; });
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() {
          _isScanning = false;
          _uploadError = '無法讀取資料夾：${e.osError?.message ?? e.message}';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isScanning = false; _uploadError = e.toString(); });
    }
  }

  /// 選取檔案並載入前幾行作為預覽
  Future<void> _selectAndPreview(String fullPath) async {
    try {
      final bytes = await File(fullPath).readAsBytes();
      final content = String.fromCharCodes(bytes);
      final lines = content.trim().split(RegExp(r'\r?\n'));
      setState(() {
        _selectedFilePath = fullPath;
        _previewLines = lines.take(8).toList();
        _succeeded = null;
        _failed = [];
        _uploadError = null;
      });
    } on FileSystemException catch (e) {
      setState(() => _uploadError = '無法讀取檔案：${e.osError?.message ?? e.message}');
    }
  }

  /// 確認並上傳選取的檔案
  Future<void> _confirmImport() async {
    if (_selectedFilePath == null) return;

    final scaffoldMsg = ScaffoldMessenger.of(context);
    final sync        = context.read<SyncProvider>();
    final type        = _selectedType;
    final path        = _selectedFilePath!;

    if (mounted) setState(() { _succeeded = null; _failed = []; _uploadError = null; });

    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      final msg = '無法讀取檔案：${e.osError?.message ?? e.message}';
      if (mounted) { setState(() => _uploadError = msg); _showErrorDialog(msg); }
      return;
    }

    final lines = String.fromCharCodes(bytes).trim().split(RegExp(r'\r?\n'));
    if (lines.length < 2) {
      if (mounted) setState(() => _uploadError = 'CSV 至少需要 header 行與一筆資料');
      return;
    }

    if (mounted) setState(() => _isUploading = true);

    try {
      final response = await sync.uploadImportCsv(
        type:     type,
        fileName: path.split('/').last,
        csvBytes: bytes,
      );
      final succeeded = response['succeeded'] as int? ?? 0;
      final failed    = (response['failed'] as List<dynamic>?)
              ?.cast<Map<String, dynamic>>() ?? [];

      if (mounted) {
        setState(() { _succeeded = succeeded; _failed = failed; _uploadError = null; });
        _showResultDialog(succeeded, failed);
      } else {
        scaffoldMsg.showSnackBar(SnackBar(
          content: Text(failed.isEmpty
              ? '成功匯入 $succeeded 筆'
              : '匯入完成：$succeeded 筆成功，${failed.length} 筆失敗'),
          duration: const Duration(seconds: 5),
        ));
      }
    } on DioException catch (e) {
      final msg = (e.response?.data as Map<String, dynamic>?)?['message']
          ?? e.message ?? '上傳失敗';
      if (mounted) { setState(() => _uploadError = msg); _showErrorDialog(msg); }
      else { scaffoldMsg.showSnackBar(SnackBar(content: Text('上傳失敗：$msg'), backgroundColor: Colors.red)); }
    } catch (e) {
      if (mounted) { setState(() => _uploadError = e.toString()); _showErrorDialog(e.toString()); }
      else { scaffoldMsg.showSnackBar(SnackBar(content: Text('錯誤：$e'), backgroundColor: Colors.red)); }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showResultDialog(int succeeded, List<Map<String, dynamic>> failed) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Text('成功匯入 $succeeded 筆'),
        ]),
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
                    child: Text('第 ${f['row']} 行：${f['reason']}',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                  )),
                ],
              ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 8),
          const Text('上傳失敗'),
        ]),
        content: Text(msg),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('確定')),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('CSV 資料匯入')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 類型選擇 ──────────────────────────────────────────────
            Text('資料類型',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'product',   label: Text('產品')),
                ButtonSegment(value: 'customer',  label: Text('客戶')),
                ButtonSegment(value: 'inventory', label: Text('庫存')),
              ],
              selected: {_selectedType},
              onSelectionChanged: (s) {
                setState(() {
                  _selectedType      = s.first;
                  _succeeded         = null;
                  _failed            = [];
                  _uploadError       = null;
                  _selectedFilePath  = null;
                  _previewLines      = [];
                });
                if (_dirController.text.isNotEmpty) _scanDirectory();
              },
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

            // ── 資料夾路徑 ────────────────────────────────────────────
            Text('資料夾',
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _dirController,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    onSubmitted: (_) => _scanDirectory(),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.tonal(
                  onPressed: _isScanning ? null : _scanDirectory,
                  child: const Text('重新掃描'),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── 符合的檔案清單 ────────────────────────────────────────
            Text(
              '符合「${_typeLabels[_selectedType]}」的 CSV 檔案',
              style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            if (_isScanning)
              const Center(child: CircularProgressIndicator())
            else if (_matchingFiles.isEmpty)
              _EmptyFilesHint(dirPath: _dirController.text)
            else
              Card(
                margin: EdgeInsets.zero,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: _matchingFiles.asMap().entries.map((entry) {
                    final idx      = entry.key;
                    final fullPath = entry.value;
                    final name     = fullPath.split('/').last;
                    final selected = _selectedFilePath == fullPath;
                    return Column(
                      children: [
                        if (idx > 0) const Divider(height: 1, indent: 56),
                        ListTile(
                          leading: Radio<String>(
                            value: fullPath,
                            groupValue: _selectedFilePath,
                            onChanged: (v) => _selectAndPreview(v!),
                          ),
                          title: Text(
                            name,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 13,
                              fontWeight:
                                  selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          selected: selected,
                          onTap: () => _selectAndPreview(fullPath),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),

            // ── 內容預覽 ──────────────────────────────────────────────
            if (_previewLines.isNotEmpty) ...[
              const SizedBox(height: 20),
              Text('內容預覽',
                  style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    _previewLines.join('\n'),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),

            // ── 確認匯入按鈕 ──────────────────────────────────────────
            if (_selectedFilePath != null || _isUploading)
              SizedBox(
                width: double.infinity,
                child: _isUploading
                    ? const Center(child: CircularProgressIndicator())
                    : FilledButton.icon(
                        onPressed: _confirmImport,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text('確認匯入${_typeLabels[_selectedType]!}'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
              ),

            const SizedBox(height: 16),

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
                Text('失敗明細',
                    style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
                const SizedBox(height: 6),
                ..._failed.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('第 ${f['row']} 行  ',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      Expanded(
                        child: Text('${f['reason']}',
                            style: TextStyle(
                                fontSize: 12, color: Colors.red.shade700)),
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

  @override
  void dispose() {
    _dirController.dispose();
    super.dispose();
  }
}

// ── 資料夾無符合檔案提示 ──────────────────────────────────────────────────────

class _EmptyFilesHint extends StatelessWidget {
  const _EmptyFilesHint({required this.dirPath});
  final String dirPath;

  @override
  Widget build(BuildContext context) {
    final exists = dirPath.isNotEmpty && Directory(dirPath).existsSync();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exists ? '目錄中無符合的 CSV 檔案' : '找不到資料夾',
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade800),
          ),
          const SizedBox(height: 6),
          Text(
            '請先執行 adb push 將 CSV 推送到手機：',
            style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
          ),
          const SizedBox(height: 4),
          const Text(
            'adb push LOG/test_csv/\n    /sdcard/Android/data/com.example.nj_stream_erp/files/test_csv/',
            style: TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
        ],
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
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13)),
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