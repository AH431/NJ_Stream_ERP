import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../providers/sync_provider.dart';

/// 下載 PDF 並以系統預設程式開啟
Future<void> downloadAndOpenPdf(
  BuildContext context, {
  required String apiPath,
  required String filename,
}) async {
  final sync = context.read<SyncProvider>();
  try {
    final bytes = await sync.downloadPdfBytes(apiPath);
    final dir   = await getTemporaryDirectory();
    final file  = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await OpenFilex.open(file.path);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('下載失敗：$e'), backgroundColor: Colors.red),
      );
    }
  }
}

/// 呼叫 email 寄送 API 並顯示結果 SnackBar
Future<void> sendEmail(
  BuildContext context, {
  required String apiPath,
  Map<String, dynamic>? body,
}) async {
  final sync = context.read<SyncProvider>();
  try {
    final msg = await sync.sendDocumentEmail(apiPath, body);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    }
  } catch (e) {
    if (context.mounted) {
      final errMsg = e.toString().contains('MISSING_EMAIL')
          ? '此客戶尚未設定 email，請先至客戶資料填寫。'
          : '寄送失敗：$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errMsg), backgroundColor: Colors.red),
      );
    }
  }
}

/// 月份選擇器 → 呼叫對帳單 email API
Future<void> pickMonthAndSendStatement(
  BuildContext context, {
  required int customerId,
}) async {
  final now = DateTime.now();
  int selectedYear  = now.year;
  int selectedMonth = now.month;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: const Text('寄送月結對帳單'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedYear,
                  items: List.generate(5, (i) => now.year - i)
                      .map((y) => DropdownMenuItem(value: y, child: Text('$y 年')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedYear = v!),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: selectedMonth,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(value: m, child: Text('$m 月')))
                      .toList(),
                  onChanged: (v) => setState(() => selectedMonth = v!),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),  child: const Text('寄送')),
        ],
      ),
    ),
  );

  if (confirmed != true || !context.mounted) return;

  await sendEmail(
    context,
    apiPath: '/api/v1/customers/$customerId/send-statement',
    body: {'year': selectedYear, 'month': selectedMonth},
  );
}
