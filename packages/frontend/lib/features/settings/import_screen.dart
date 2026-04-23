import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/sync_provider.dart';

// 資料夾掃描關鍵字（檔名含此字串即符合）
const _typeKeywords = {
  'product':   'product',
  'customer':  'customer',
  'inventory': 'inventory',
};

/// CSV 候選資料夾清單（依優先序，第一個存在的目錄優先使用）
///
/// 路徑說明：
///   1. App 私有外部目錄/test_csv  — adb push 的預設目標（最優先）
///   2. App 私有外部目錄/csv       — 替代命名
///   3. App 私有外部目錄（根目錄）  — 直接放在外部目錄根
///   4. /sdcard/NJ_Stream_ERP/csv  — 用戶手動放置於公開目錄
///
/// 標準 adb push 指令（從 PC 傳至手機）：
///   adb push LOG/test_csv/ \
///     /sdcard/Android/data/com.example.nj_stream_erp/files/test_csv/
const _csvFolderCandidateNames = ['test_csv', 'csv', ''];  // '' = 外部目錄根
const _csvPublicFallback = '/sdcard/NJ_Stream_ERP/csv';    // 公開目錄備援

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
  List<String>? _candidatePaths;      // 所有候選路徑（供提示用）
  bool _noFolderFound = false;        // 所有候選路徑皆不存在

  // --------------------------------------------------------------------------

  String _typeLabel(AppStrings s) {
    switch (_selectedType) {
      case 'product':   return s.importTypeProduct;
      case 'customer':  return s.importTypeCustomer;
      case 'inventory': return s.importTypeInventory;
      default:          return _selectedType;
    }
  }

  String _formatStr(AppStrings s) {
    switch (_selectedType) {
      case 'product':   return s.importFormatProduct;
      case 'customer':  return s.importFormatCustomer;
      case 'inventory': return s.importFormatInventory;
      default:          return '';
    }
  }

  // --------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _initDirAndScan();
  }

  Future<void> _initDirAndScan() async {
    final extDir = await getExternalStorageDirectory();

    // 建立所有候選路徑（外部私有目錄的子目錄 + 公開備援）
    final candidates = <String>[];
    if (extDir != null) {
      for (final name in _csvFolderCandidateNames) {
        final path = name.isEmpty ? extDir.path : '${extDir.path}/$name';
        candidates.add(path);
      }
    }
    candidates.add(_csvPublicFallback);

    if (!mounted) return;
    setState(() => _candidatePaths = candidates);

    // 依優先序找第一個存在的資料夾
    String? foundPath;
    for (final path in candidates) {
      if (Directory(path).existsSync()) {
        foundPath = path;
        break;
      }
    }

    if (foundPath != null) {
      _dirController.text = foundPath;
      _scanDirectory();
    } else {
      // 所有候選路徑都不存在：顯示傳輸失敗通知
      if (mounted) {
        setState(() => _noFolderFound = true);
      }
    }
  }

  Future<void> _scanDirectory() async {
    final dirPath = _dirController.text.trim();
    if (dirPath.isEmpty) return;

    // 清除「找不到資料夾」狀態，讓用戶可手動重掃
    if (mounted) setState(() => _noFolderFound = false);

    final s = context.read<AppStrings>();

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
          _uploadError = s.importErrReadDir(e.osError?.message ?? e.message);
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isScanning = false; _uploadError = e.toString(); });
    }
  }

  Future<void> _selectAndPreview(String fullPath) async {
    final s = context.read<AppStrings>();
    try {
      final bytes = await File(fullPath).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true);
      final lines = content.trim().split(RegExp(r'\r?\n'));
      if (mounted) {
        setState(() {
          _selectedFilePath = fullPath;
          _previewLines = lines.take(8).toList();
          _succeeded = null;
          _failed = [];
          _uploadError = null;
        });
      }
    } on FileSystemException catch (e) {
      if (mounted) {
        setState(() => _uploadError = s.importErrReadFile(e.osError?.message ?? e.message));
      }
    }
  }

  Future<void> _confirmImport() async {
    if (_selectedFilePath == null) return;

    final scaffoldMsg = ScaffoldMessenger.of(context);
    final sync        = context.read<SyncProvider>();
    final s           = context.read<AppStrings>();
    final type        = _selectedType;
    final path        = _selectedFilePath!;

    if (mounted) setState(() { _succeeded = null; _failed = []; _uploadError = null; });

    Uint8List bytes;
    try {
      bytes = await File(path).readAsBytes();
    } on FileSystemException catch (e) {
      final msg = s.importErrReadFile(e.osError?.message ?? e.message);
      if (mounted) { setState(() => _uploadError = msg); _showErrorDialog(msg); }
      return;
    }

    final lines = utf8.decode(bytes, allowMalformed: true).trim().split(RegExp(r'\r?\n'));
    if (lines.length < 2) {
      if (mounted) setState(() => _uploadError = s.importErrTooShort);
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
              ? s.importSuccessTitle(succeeded)
              : s.importDoneMsg(succeeded, failed.length)),
          duration: const Duration(seconds: 5),
        ));
      }
    } on DioException catch (e) {
      final msg = (e.response?.data as Map<String, dynamic>?)?['message']
          ?? e.message ?? s.importErrTitle;
      if (mounted) { setState(() => _uploadError = msg); _showErrorDialog(msg); }
      else { scaffoldMsg.showSnackBar(SnackBar(content: Text('${s.importErrTitle}: $msg'), backgroundColor: Colors.red)); }
    } catch (e) {
      if (mounted) { setState(() => _uploadError = e.toString()); _showErrorDialog(e.toString()); }
      else { scaffoldMsg.showSnackBar(SnackBar(content: Text('${s.importErrTitle}: $e'), backgroundColor: Colors.red)); }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _showResultDialog(int succeeded, List<Map<String, dynamic>> failed) {
    final s = context.read<AppStrings>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.check_circle_outline, color: Colors.green.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(s.importSuccessTitle(succeeded))),
        ]),
        content: failed.isEmpty
            ? Text(s.importNoFailed)
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.importFailedSummary(failed.length),
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  ...failed.map((f) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      s.importFailedRow(f['row'] as int, '${f['reason']}'),
                      style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                    ),
                  )),
                ],
              ),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnOk)),
        ],
      ),
    );
  }

  void _showErrorDialog(String msg) {
    final s = context.read<AppStrings>();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.error_outline, color: Colors.red.shade600),
          const SizedBox(width: 8),
          Expanded(child: Text(s.importErrTitle)),
        ]),
        content: Text(msg),
        actions: [
          FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(s.btnOk)),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s     = AppStrings.of(context);
    final theme = Theme.of(context);
    final typeLabel = _typeLabel(s);

    return Scaffold(
      appBar: AppBar(title: Text(s.importTitle)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 類型選擇 ──────────────────────────────────────────────
            Text(s.importTypeLabel,
                style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'product',   label: Text(s.importTypeProduct)),
                ButtonSegment(value: 'customer',  label: Text(s.importTypeCustomer)),
                ButtonSegment(value: 'inventory', label: Text(s.importTypeInventory)),
              ],
              selected: {_selectedType},
              onSelectionChanged: (sel) {
                setState(() {
                  _selectedType      = sel.first;
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
                    s.importFormatTitle(typeLabel),
                    style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatStr(s),
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── 資料夾路徑 ────────────────────────────────────────────
            Text(s.importFolderLabel,
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
                  child: Text(s.importRescanBtn),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── 找不到任何候選資料夾的錯誤通知 ─────────────────────
            if (_noFolderFound) ...[
              _NoFolderCard(candidatePaths: _candidatePaths ?? []),
              const SizedBox(height: 20),
            ],

            // ── 符合的檔案清單 ────────────────────────────────────────
            Text(
              s.importFileListTitle(typeLabel),
              style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey),
            ),
            const SizedBox(height: 8),

            if (_isScanning)
              const Center(child: CircularProgressIndicator())
            else if (_matchingFiles.isEmpty && !_noFolderFound)
              _EmptyFilesHint(dirPath: _dirController.text, candidatePaths: _candidatePaths ?? [])
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
              Text(s.importPreviewLabel,
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
                        label: Text(s.importConfirmBtn(typeLabel)),
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
                title: s.importErrTitle,
                body: _uploadError!,
              ),

            if (_succeeded != null) ...[
              _ResultCard(
                color: Colors.green.shade50,
                borderColor: Colors.green.shade200,
                icon: Icons.check_circle_outline,
                iconColor: Colors.green,
                title: s.importSuccessTitle(_succeeded!),
                body: _failed.isEmpty
                    ? s.importNoFailed
                    : s.importFailedSummary(_failed.length),
              ),
              if (_failed.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.importFailedDetail,
                    style: theme.textTheme.labelMedium?.copyWith(color: Colors.grey)),
                const SizedBox(height: 6),
                ..._failed.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${s.isEnglish ? 'Row' : '第'} ${f['row']} ${s.isEnglish ? '' : '行'}  ',
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

// ── 所有候選資料夾皆不存在：傳輸失敗通知 ─────────────────────────────────────

class _NoFolderCard extends StatelessWidget {
  const _NoFolderCard({required this.candidatePaths});
  final List<String> candidatePaths;

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: Colors.red.shade700),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                s.isEnglish ? 'CSV folder not found. Please push files first.' : '找不到 CSV 資料夾，請先將檔案傳至手機',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: Colors.red.shade800,
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Text(
            s.isEnglish ? 'The following paths were searched but do not exist:' : '系統已依序搜尋下列路徑，全部不存在：',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
          const SizedBox(height: 6),
          // 列出所有候選路徑
          ...candidatePaths.asMap().entries.map((e) => Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.key + 1}. ',
                  style: TextStyle(fontSize: 11, color: Colors.red.shade600),
                ),
                Expanded(
                  child: Text(
                    e.value.isEmpty ? (s.isEnglish ? '(External Root)' : '(外部目錄根)') : e.value,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          )),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.grey.shade900,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.isEnglish ? '# Push CSV from PC to phone (run this adb command):' : '# 從電腦傳送 CSV 至手機（執行以下 adb 指令）',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10,
                    color: Colors.grey.shade400,
                  ),
                ),
                const SizedBox(height: 4),
                const SelectableText(
                  'adb push LOG/test_csv/ /sdcard/Android/data/com.example.nj_stream_erp/files/test_csv/',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: Colors.greenAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            s.isEnglish ? 'After pushing, tap "Re-scan" to load files.' : '傳送完成後，點「重新掃描」按鈕即可載入檔案。',
            style: TextStyle(fontSize: 12, color: Colors.red.shade700),
          ),
        ],
      ),
    );
  }
}

// ── 資料夾存在但無符合檔案提示 ───────────────────────────────────────────────

class _EmptyFilesHint extends StatelessWidget {
  const _EmptyFilesHint({required this.dirPath, required this.candidatePaths});
  final String dirPath;
  final List<String> candidatePaths;

  @override
  Widget build(BuildContext context) {
    final s      = AppStrings.of(context);
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
            exists
                ? (s.isEnglish ? 'No matching CSV files found in folder' : '此資料夾內找不到符合的 CSV 檔案')
                : (s.isEnglish ? 'Specified folder does not exist' : '指定的資料夾不存在'),
            style: TextStyle(fontWeight: FontWeight.w600, color: Colors.orange.shade800),
          ),
          const SizedBox(height: 6),
          if (exists) ...[
            Text(
              s.isEnglish ? 'Ensure filenames contain keywords (product / customer / inventory)' : '請確認檔案命名包含關鍵字（product / customer / inventory）',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
            ),
            const SizedBox(height: 4),
            Text(
              '${s.isEnglish ? 'Current path' : '目前掃描路徑'}：$dirPath',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ] else ...[
            Text(
              s.importAdbHint,
              style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
            ),
            const SizedBox(height: 4),
            const SelectableText(
              'adb push LOG/test_csv/ /sdcard/Android/data/com.example.nj_stream_erp/files/test_csv/',
              style: TextStyle(fontFamily: 'monospace', fontSize: 11),
            ),
          ],
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