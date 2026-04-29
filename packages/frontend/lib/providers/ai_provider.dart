// ==============================================================================
// AiProvider — Phase 3 M1.3
//
// SSE 串流聊天：傳送問題給 /api/v1/ai/chat，以 LineSplitter 逐行解析 SSE events，
// 逐 token 累積回覆訊息。
//
// SSE event 格式（8.9）：
//   data: {"type":"token","content":"..."}
//   data: {"type":"done"}
// ==============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

// ── 資料模型 ──────────────────────────────────────────────

class ChatMessage {
  final String id;
  final String role; // 'user' | 'assistant'
  final String content;
  final bool isStreaming;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    this.isStreaming = false,
  });

  ChatMessage copyWith({String? content, bool? isStreaming}) => ChatMessage(
    id: id,
    role: role,
    content: content ?? this.content,
    isStreaming: isStreaming ?? this.isStreaming,
  );
}

// ── AiProvider ────────────────────────────────────────────

class AiProvider extends ChangeNotifier {
  final Dio _dio;

  AiProvider({required Dio dio}) : _dio = dio;

  final List<ChatMessage> _messages = [];
  List<ChatMessage> get messages => List.unmodifiable(_messages);

  bool _isStreaming = false;
  bool get isStreaming => _isStreaming;

  String? _error;
  String? get error => _error;

  StreamSubscription<String>? _currentSub;

  Future<void> sendMessage(String question) async {
    if (_isStreaming) return;

    _error = null;
    _messages.add(ChatMessage(id: _uid(), role: 'user', content: question));

    final assistantId = _uid();
    _messages.add(ChatMessage(
      id: assistantId,
      role: 'assistant',
      content: '',
      isStreaming: true,
    ));

    _isStreaming = true;
    notifyListeners();

    final completer = Completer<void>();

    try {
      final response = await _dio.post<ResponseBody>(
        '/api/v1/ai/chat',
        data: {'question': question},
        options: Options(responseType: ResponseType.stream),
      );

      _currentSub = response.data!.stream
          .cast<List<int>>()
          .transform(const Utf8Decoder())
          .transform(const LineSplitter())
          .listen(
        (line) {
          if (!line.startsWith('data: ')) return;
          final payload = line.substring(6).trim();
          if (payload.isEmpty) return;
          try {
            final event = jsonDecode(payload) as Map<String, dynamic>;
            switch (event['type'] as String?) {
              case 'token':
                _append(assistantId, (event['content'] as String?) ?? '');
              case 'done':
                _finalize(assistantId);
                if (!completer.isCompleted) completer.complete();
            }
          } catch (_) {
            // 跳過格式錯誤的 SSE 行
          }
        },
        onError: (Object e) {
          _error = 'stream_error';
          _finalize(assistantId);
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          _finalize(assistantId);
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } on DioException catch (e) {
      _error = switch (e.response?.statusCode) {
        401 || 403 => 'auth_error',
        429        => 'rate_limit',
        _          => 'stream_error',
      };
      _finalize(assistantId);
    } catch (_) {
      _error = 'stream_error';
      _finalize(assistantId);
    } finally {
      _currentSub = null;
      _isStreaming = false;
      notifyListeners();
    }
  }

  void _append(String id, String token) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx == -1) return;
    _messages[idx] = _messages[idx].copyWith(
      content: _messages[idx].content + token,
    );
    notifyListeners();
  }

  void _finalize(String id) {
    final idx = _messages.indexWhere((m) => m.id == id);
    if (idx != -1 && _messages[idx].isStreaming) {
      _messages[idx] = _messages[idx].copyWith(isStreaming: false);
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void clearMessages() {
    _currentSub?.cancel();
    _currentSub = null;
    _isStreaming = false;
    _messages.clear();
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _currentSub?.cancel();
    super.dispose();
  }

  String _uid() => DateTime.now().microsecondsSinceEpoch.toString();
}
