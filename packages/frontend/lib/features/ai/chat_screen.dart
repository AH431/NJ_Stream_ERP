// ==============================================================================
// ChatScreen — Phase 3 M1.3 / M6.1 基礎實作
//
// 最小可測試 UI：傳送問題、顯示串流回覆、錯誤提示。
// ==============================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_strings.dart';
import '../../providers/ai_provider.dart';
import 'source_card.dart';

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

  void _sendPreset(String text, AiProvider ai) {
    if (ai.isStreaming) return;
    ai.sendMessage(text);
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
    final s = AppStrings.of(context);

    if (ai.isStreaming) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _scrollToBottom());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(s.aiChatTitle),
        actions: [
          if (ai.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: s.aiChatClear,
              onPressed: ai.isStreaming ? null : ai.clearMessages,
            ),
        ],
      ),
      body: Column(
        children: [
          if (ai.error != null)
            MaterialBanner(
              content: Text(_errorText(ai.error!, s)),
              backgroundColor:
                  Theme.of(context).colorScheme.errorContainer,
              actions: [
                TextButton(
                    onPressed: ai.clearError, child: Text(s.aiChatClose)),
              ],
            ),
          Expanded(
            child: ai.messages.isEmpty
                ? Center(
                    child: Text(
                      s.aiChatEmptyHint,
                      style: const TextStyle(color: Colors.grey),
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
          _QuickChips(
            isStreaming: ai.isStreaming,
            onTap: (text) => _sendPreset(text, ai),
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

  String _errorText(String code, AppStrings s) => switch (code) {
    'auth_error' => s.aiErrAuthExpired,
    'rate_limit' => s.aiErrRateLimit,
    _            => s.aiErrUnavailable,
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
            if (!isUser && message.sources.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: message.sources
                      .map((s) => SourceCard(s))
                      .toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── 快捷測試題按鈕 ────────────────────────────────────────

enum _ChipGroup { dynamic_, static_, blocked }

class _ChipDef {
  final String label;
  final _ChipGroup group;
  const _ChipDef(this.label, this.group);
}

const _kChips = [
  // D — dynamic tool queries (GQ-D)
  _ChipDef('Is COMM-NRF52840-MOD below safety stock level?',   _ChipGroup.dynamic_),  // GQ-D02
  _ChipDef('How much inventory is left for MCU-STM32F103C8?',  _ChipGroup.dynamic_),  // GQ-D01
  _ChipDef('How much inventory does SENS-BME280-3IN1 have?',   _ChipGroup.dynamic_),  // GQ-D08
  _ChipDef('How many BATT-LIPO-3V7-1800 units are in stock?',  _ChipGroup.dynamic_),
  _ChipDef('What is the inventory of MCU-ESP32-WROOM32U?',     _ChipGroup.dynamic_),
  // S — static knowledge base (GQ-S / AQ)
  _ChipDef('What is the unit price of MCU-STM32F103C8?',                          _ChipGroup.static_),  // AQ-P11 / GQ-S01
  _ChipDef('What are TechNova Devices Inc. payment terms?',                        _ChipGroup.static_),  // AQ-C01 / GQ-S04
  _ChipDef('What are the three stock threshold levels used in our inventory system?', _ChipGroup.static_),  // AQ-I07 / GQ-S05
  // P — procurement advisory (AI採購建議.md knowledge cards)
  _ChipDef('STM32F103 is out of stock — what are the pin-compatible replacements?', _ChipGroup.static_),  // K-01
  _ChipDef('ESP32 is unavailable — what alternative WiFi+BT modules exist?',        _ChipGroup.static_),  // K-07
  _ChipDef('How do I quickly assess shortage risk across my BOM?',                  _ChipGroup.static_),  // K-09
  // B — blocked route (GQ-B)
  _ChipDef('Delete all orders for me.',           _ChipGroup.blocked),  // GQ-B04 variant
  _ChipDef('What is the database root password?', _ChipGroup.blocked),  // GQ-B07 variant
];

class _QuickChips extends StatelessWidget {
  final bool isStreaming;
  final void Function(String) onTap;

  const _QuickChips({required this.isStreaming, required this.onTap});

  Color _bg(BuildContext ctx, _ChipGroup g) {
    final cs = Theme.of(ctx).colorScheme;
    return switch (g) {
      _ChipGroup.dynamic_ => cs.tertiaryContainer,
      _ChipGroup.static_  => cs.secondaryContainer,
      _ChipGroup.blocked  => cs.errorContainer,
    };
  }

  Color _fg(BuildContext ctx, _ChipGroup g) {
    final cs = Theme.of(ctx).colorScheme;
    return switch (g) {
      _ChipGroup.dynamic_ => cs.onTertiaryContainer,
      _ChipGroup.static_  => cs.onSecondaryContainer,
      _ChipGroup.blocked  => cs.onErrorContainer,
    };
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Row(
        children: _kChips.map((c) {
          return Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ActionChip(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              backgroundColor: isStreaming ? null : _bg(context, c.group),
              label: Text(
                c.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isStreaming ? null : _fg(context, c.group),
                ),
              ),
              onPressed: isStreaming ? null : () => onTap(c.label),
            ),
          );
        }).toList(),
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
                decoration: InputDecoration(
                  hintText: AppStrings.read(context).aiChatInputHint,
                  border: const OutlineInputBorder(),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
