// ==============================================================================
// ChatScreen — Phase 3 M1.3 / M6.1 基礎實作
//
// 最小可測試 UI：傳送問題、顯示串流回覆、錯誤提示。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/ai_provider.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send(AiProvider ai) {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    _controller.clear();
    ai.sendMessage(q);
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ai = context.watch<AiProvider>();

    if (ai.isStreaming) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI 問庫存'),
        actions: [
          if (ai.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '清除對話',
              onPressed: ai.isStreaming ? null : ai.clearMessages,
            ),
        ],
      ),
      body: Column(
        children: [
          if (ai.error != null)
            MaterialBanner(
              content: Text(_errorText(ai.error!)),
              backgroundColor:
                  Theme.of(context).colorScheme.errorContainer,
              actions: [
                TextButton(
                    onPressed: ai.clearError, child: const Text('關閉')),
              ],
            ),
          Expanded(
            child: ai.messages.isEmpty
                ? const Center(
                    child: Text(
                      '輸入問題，例如：IC-8800 現在庫存多少？',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    itemCount: ai.messages.length,
                    itemBuilder: (_, i) => _MessageTile(ai.messages[i]),
                  ),
          ),
          _InputBar(
            controller: _controller,
            isStreaming: ai.isStreaming,
            onSend: () => _send(ai),
          ),
        ],
      ),
    );
  }

  String _errorText(String code) => switch (code) {
    'auth_error' => '登入已過期，請重新登入',
    'rate_limit' => '請求過於頻繁，請稍後再試',
    _            => 'AI 服務暫時無法使用，請稍後再試',
  };
}

// ── 訊息氣泡 ──────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final ChatMessage message;
  const _MessageTile(this.message);

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final cs = Theme.of(context).colorScheme;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: isUser
              ? cs.primaryContainer
              : cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              message.content.isEmpty && message.isStreaming
                  ? '▌'
                  : message.content,
              style: TextStyle(
                color: isUser ? cs.onPrimaryContainer : cs.onSurface,
              ),
            ),
            if (message.isStreaming && message.content.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: SizedBox(
                  height: 2,
                  width: 40,
                  child: LinearProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 輸入列 ────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool isStreaming;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.isStreaming,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                enabled: !isStreaming,
                decoration: const InputDecoration(
                  hintText: '輸入問題…',
                  border: OutlineInputBorder(),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => onSend(),
                textInputAction: TextInputAction.send,
              ),
            ),
            const SizedBox(width: 8),
            isStreaming
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    icon: const Icon(Icons.send),
                    onPressed: onSend,
                  ),
          ],
        ),
      ),
    );
  }
}
