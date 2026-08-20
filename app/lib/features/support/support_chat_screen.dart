import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/support_service.dart';

/// In-app live support chat. Messages go to our backend; a CS agent replies from
/// the admin console. The screen polls every few seconds for new replies
/// (client: "normal in-app chat window jo backend se connect ho, CS reply de sake").
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});
  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  List<SupportMessage> _messages = [];
  bool _loading = true, _sending = false;
  String? _error;
  Timer? _poll;

  SupportService get _svc => context.read<SupportService>();

  @override
  void initState() {
    super.initState();
    _load(initial: true);
    _svc.markRead();
    // gentle polling for agent replies while the screen is open
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool initial = false}) async {
    try {
      final msgs = await _svc.thread();
      if (!mounted) return;
      final grew = msgs.length != _messages.length;
      setState(() { _messages = msgs; _loading = false; _error = null; });
      if (initial || grew) _jumpToEnd();
      _svc.markRead();
    } catch (e) {
      if (mounted && initial) setState(() { _loading = false; _error = '$e'; });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent + 80, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    // optimistic append
    setState(() => _messages = [..._messages, SupportMessage('tmp_${DateTime.now().microsecondsSinceEpoch}', true, text, DateTime.now())]);
    _jumpToEnd();
    try {
      await _svc.send(text);
      await _load();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send — check your connection')));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
            child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 10),
          const Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('ClipCart Support', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text('Usually replies within a few hours', style: TextStyle(color: Colors.grey, fontSize: 11)),
          ]),
        ]),
      ),
      body: Column(children: [
        Expanded(child: _body()),
        _composer(),
      ]),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    if (_error != null) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text("Couldn't load the chat.", style: TextStyle(color: Colors.grey.shade600)),
        TextButton(onPressed: () => _load(initial: true), child: const Text('Retry', style: TextStyle(color: AppColors.accentInk, fontWeight: FontWeight.w800))),
      ]));
    }
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      children: [
        _dayHint(),
        if (_messages.isEmpty) _welcome(),
        for (final m in _messages) _bubble(m),
      ],
    );
  }

  Widget _dayHint() => Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
          child: Text('Chat with our team', style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5, fontWeight: FontWeight.w600)),
        ),
      );

  Widget _welcome() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.grey.withOpacity(0.15))),
        child: const Text(
          '👋 Hi! Tell us what you need help with — export issues, payments, subscriptions, or anything else. Our team will reply right here.',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
      );

  Widget _bubble(SupportMessage m) {
    final mine = m.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppColors.brand : null,
          color: mine ? null : Theme.of(context).cardColor,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: Colors.grey.withOpacity(0.15)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(m.body, style: TextStyle(color: mine ? Colors.white : null, fontSize: 14, height: 1.35)),
          const SizedBox(height: 3),
          Text(_time(m.at), style: TextStyle(color: mine ? Colors.white70 : Colors.grey, fontSize: 10)),
        ]),
      ),
    );
  }

  String _time(DateTime d) {
    final hh = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '$hh:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  Widget _composer() {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.15))),
        ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: 'Type a message…',
                filled: true,
                fillColor: Theme.of(context).cardColor,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 46, height: 46,
              decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: _sending
                  ? const Padding(padding: EdgeInsets.all(13), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}
