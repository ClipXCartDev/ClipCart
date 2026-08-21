import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../services/support_service.dart';

/// §26 Support — a real live chat with the CS team. Loads the account's support
/// thread, shows the conversation, polls for agent replies, and sends messages
/// (answered from the admin console via the same backend thread).
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
    // poll for new agent replies while the screen is open
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
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
      setState(() {
        _messages = msgs;
        _loading = false;
        _error = null;
      });
      _svc.markRead();
      if (initial || grew) _jumpToEnd();
    } catch (e) {
      if (mounted && initial) setState(() { _loading = false; _error = 'Could not load your messages.'; });
    }
  }

  void _jumpToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    // optimistic append
    final optimistic = SupportMessage('_local', true, body, DateTime.now());
    setState(() => _messages = [..._messages, optimistic]);
    _jumpToEnd();
    try {
      await _svc.send(body);
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send — check your connection')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 20, 8),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => Navigator.of(context).maybePop()),
              const SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                const Text('Support', style: T.pageTitle),
                Row(children: [
                  Container(width: 7, height: 7, decoration: const BoxDecoration(color: AppColors.greenDot, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text('Replies within 6 working hours', style: T.caption.copyWith(color: AppColors.inkFaint)),
                ]),
              ]),
            ]),
          ),
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          Expanded(child: _body()),
          _composer(),
        ]),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator(color: AppColors.brand));
    if (_error != null) {
      return Center(child: TextButton(onPressed: () { setState(() { _loading = true; _error = null; }); _load(initial: true); }, child: const Text('Retry', style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600))));
    }
    if (_messages.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        Icon(Icons.support_agent_rounded, size: 46, color: AppColors.inkGhost),
        SizedBox(height: 14),
        Center(child: Text('How can we help?', style: TextStyle(fontFamily: kSans, fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.ink))),
        SizedBox(height: 8),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text('Send us a message about your clip, an export, or your plan. A real person will reply here.',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: kSans, fontSize: 13.5, height: 1.5, color: AppColors.inkMuted)),
        ),
      ]);
    }
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      itemCount: _messages.length,
      itemBuilder: (_, i) => _bubble(_messages[i]),
    );
  }

  Widget _bubble(SupportMessage m) {
    final mine = m.fromUser;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        decoration: BoxDecoration(
          color: mine ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: AppColors.line),
        ),
        child: Text(m.body,
            style: TextStyle(fontFamily: kSans, fontSize: 14.5, height: 1.4, color: mine ? Colors.white : AppColors.ink)),
      ),
    );
  }

  Widget _composer() {
    return Container(
      decoration: const BoxDecoration(color: AppColors.bg, border: Border(top: BorderSide(color: AppColors.line))),
      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
      child: SafeArea(
        top: false,
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(color: AppColors.surfaceHover2, borderRadius: BorderRadius.circular(R.pill), border: Border.all(color: AppColors.line)),
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(fontFamily: kSans, fontSize: 14.5, color: AppColors.ink),
                decoration: const InputDecoration(isCollapsed: true, filled: false, border: InputBorder.none, hintText: 'Message support…'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 44, height: 44, alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.brand, shape: BoxShape.circle),
              child: _sending
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.arrow_upward_rounded, size: 22, color: Colors.white),
            ),
          ),
        ]),
      ),
    );
  }
}
