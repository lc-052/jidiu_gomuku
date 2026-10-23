import 'dart:math' as math;
import 'package:flutter/material.dart';

class ChatSheet extends StatefulWidget {
  final ValueNotifier<List<String>> messages;
  final Future<bool> Function(String) onSend;
  const ChatSheet({super.key, required this.messages, required this.onSend});
  @override
  State<ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<ChatSheet> {
  final _text = TextEditingController();
  bool _sending = false;
  String? _error;
  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final value = _text.text.trim();
    if (_sending || value.isEmpty) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    final sent = await widget.onSend(value);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (sent) {
        if (_text.text.trim() == value) _text.clear();
      } else {
        _error = '发送失败，消息已保留，请重试';
      }
    });
  }

  @override
  Widget build(BuildContext context) => AnimatedPadding(
        duration: const Duration(milliseconds: 150),
        padding:
            EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: SafeArea(
            child: SizedBox(
          height: math.min(500, MediaQuery.sizeOf(context).height * .7),
          child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: Column(children: [
                Row(children: [
                  Expanded(
                      child: Text('局内聊天',
                          style: Theme.of(context).textTheme.titleLarge)),
                  IconButton(
                      tooltip: '关闭聊天',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded))
                ]),
                Expanded(
                    child: ValueListenableBuilder<List<String>>(
                  valueListenable: widget.messages,
                  builder: (context, messages, _) => messages.isEmpty
                      ? const Center(child: Text('和对手打个招呼吧'))
                      : ListView.builder(
                          reverse: true,
                          itemCount: messages.length,
                          itemBuilder: (_, i) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: SelectableText(
                                  messages[messages.length - i - 1]))),
                )),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: TextField(
                          controller: _text,
                          maxLength: 100,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _send(),
                          decoration: InputDecoration(
                              labelText: '输入消息', errorText: _error))),
                  const SizedBox(width: 8),
                  IconButton.filled(
                      tooltip: '发送',
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.send_rounded)),
                ]),
              ])),
        )),
      );
}
