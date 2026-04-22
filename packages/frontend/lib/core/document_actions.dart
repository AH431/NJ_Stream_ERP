import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'app_strings.dart';
import '../providers/sync_provider.dart';

/// 下載 PDF 並以系統預設程式開啟
Future<void> downloadAndOpenPdf(
  BuildContext context, {
  required String apiPath,
  required String filename,
}) async {
  final sync = context.read<SyncProvider>();
  final s    = context.read<AppStrings>();
  try {
    final bytes = await sync.downloadPdfBytes(apiPath);
    final dir   = await getTemporaryDirectory();
    final file  = File('${dir.path}/$filename');
    await file.writeAsBytes(bytes);
    await OpenFilex.open(file.path);
  } catch (e) {
    if (context.mounted) {
      final msg = s.isEnglish ? 'Download failed: $e' : '下載失敗：$e';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
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
  final s    = context.read<AppStrings>();
  try {
    final msg = await sync.sendDocumentEmail(apiPath, body);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.green),
      );
    }
  } catch (e) {
    if (context.mounted) {
      // DioException 的 toString() 不包含 response body，需從 response.data 讀取
      String errMsg;
      if (e is DioException) {
        final data = e.response?.data;
        final code = data is Map ? data['code'] as String? : null;
        if (code == 'MISSING_EMAIL') {
          errMsg = s.isEnglish
              ? 'No email on file for this customer. Please update the customer record.'
              : '此客戶尚未設定 email，請先至客戶資料填寫。';
        } else {
          final serverMsg = data is Map ? data['message'] as String? : null;
          errMsg = s.isEnglish
              ? 'Send failed: ${serverMsg ?? e.message ?? e.toString()}'
              : '寄送失敗：${serverMsg ?? e.message ?? e.toString()}';
        }
      } else {
        errMsg = s.isEnglish ? 'Send failed: $e' : '寄送失敗：$e';
      }
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
  final s   = context.read<AppStrings>();
  final now = DateTime.now();
  int selectedYear  = now.year;
  int selectedMonth = now.month;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(s.isEnglish ? 'Send Monthly Statement' : '寄送月結對帳單'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DropdownButton<int>(
                  value: selectedYear,
                  items: List.generate(5, (i) => now.year - i)
                      .map((y) => DropdownMenuItem(
                            value: y,
                            child: Text(s.isEnglish ? '$y' : '$y 年'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => selectedYear = v!),
                ),
                const SizedBox(width: 16),
                DropdownButton<int>(
                  value: selectedMonth,
                  items: List.generate(12, (i) => i + 1)
                      .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(s.isEnglish ? 'Month $m' : '$m 月'),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => selectedMonth = v!),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.btnCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.isEnglish ? 'Send' : '寄送'),
          ),
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
