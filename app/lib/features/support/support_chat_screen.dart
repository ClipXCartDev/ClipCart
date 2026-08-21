import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../services/support_service.dart';

/// §26 Send a query — the new-request compose screen. A topic, subject and
/// description are collected and submitted to the backend support thread
/// (the same [SupportService.send] a CS agent answers from the admin console).
class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});
  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  static const _topics = ['Export or render', 'Payment', 'Editing', 'Account'];

  final _subject = TextEditingController();
  final _detail = TextEditingController();
  int _topic = 0;
  bool _hasAttachment = true;
  bool _sending = false;

  SupportService get _svc => context.read<SupportService>();

  @override
  void dispose() {
    _subject.dispose();
    _detail.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    final subject = _subject.text.trim();
    final detail = _detail.text.trim();
    if (subject.isEmpty && detail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Add a subject or a short description first')));
      return;
    }
    setState(() => _sending = true);
    // Compose the ticket body from the structured fields.
    final body = '[${_topics[_topic]}] ${subject.isEmpty ? '(no subject)' : subject}\n\n$detail';
    try {
      await _svc.send(body);
      if (!mounted) return;
      Navigator.of(context).maybePop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request sent — we\'ll reply within 6 working hours')),
      );
    } catch (_) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not send — check your connection')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          _NavRow(title: 'New request', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                // ── topic ──────────────────────────────────────────────────
                const FieldLabel('Topic', topGap: 4),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < _topics.length; i++)
                      PillChip(_topics[i], selected: _topic == i, onTap: () => setState(() => _topic = i)),
                  ],
                ),

                // ── subject ────────────────────────────────────────────────
                const FieldLabel('Subject'),
                TextField(
                  controller: _subject,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(hintText: 'A short summary'),
                ),

                // ── describe ───────────────────────────────────────────────
                const FieldLabel('Describe the issue'),
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.thumb),
                    border: Border.all(color: AppColors.line),
                  ),
                  constraints: const BoxConstraints(minHeight: 104),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: TextField(
                    controller: _detail,
                    minLines: 4,
                    maxLines: 8,
                    decoration: const InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: 'What happened, and what did you expect?',
                    ),
                  ),
                ),

                // ── attachments ────────────────────────────────────────────
                const FieldLabel('Attachments'),
                Row(children: [
                  if (_hasAttachment) ...[
                    _ExampleThumb(onRemove: () => setState(() => _hasAttachment = false)),
                    const SizedBox(width: 12),
                  ],
                  _AddTile(onTap: () => setState(() => _hasAttachment = true)),
                ]),

                const SizedBox(height: 18),
                const InfoPanel(
                  'A screen recording or screenshot helps us fix this faster. Please include the clip name, the time it happened, and what you were doing just before.',
                ),

                const SizedBox(height: 12),
                // ── auto-attached card ─────────────────────────────────────
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(R.thumb),
                    border: Border.all(color: AppColors.line),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: const Column(children: [
                    _AutoRow(icon: Icons.receipt_long_outlined, label: 'Attached automatically', value: 'app logs', divider: true),
                    _AutoRow(icon: Icons.smartphone_outlined, label: 'Device', value: 'Android · v3.0.0', divider: false),
                  ]),
                ),
              ],
            ),
          ),
          // ── sticky footer ─────────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              color: AppColors.bg,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  PrimaryBtn('Send request', loading: _sending, onTap: _send),
                  const SizedBox(height: 10),
                  const Text(
                    'You\'ll get a reply here and by email within 6 working hours.',
                    textAlign: TextAlign.center,
                    style: T.caption,
                  ),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ── nav row ──────────────────────────────────────────────────────────────────

class _NavRow extends StatelessWidget {
  const _NavRow({required this.title, required this.onBack});
  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 20, 10),
        child: Row(children: [
          CircleIconBtn(Icons.arrow_back_rounded, onTap: onBack),
          const SizedBox(width: 12),
          Text(title, style: T.pageTitle),
        ]),
      );
}

// ── attachment tiles ─────────────────────────────────────────────────────────

class _ExampleThumb extends StatelessWidget {
  const _ExampleThumb({required this.onRemove});
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 64,
        height: 64,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.mediaPlaceholder,
              borderRadius: BorderRadius.circular(R.thumb),
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white70, size: 22),
          ),
          Positioned(
            top: -6,
            right: -6,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppColors.ink,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg, width: 2),
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 12),
              ),
            ),
          ),
        ]),
      );
}

class _AddTile extends StatelessWidget {
  const _AddTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: const DottedBorderBox(
          size: 64,
          child: Icon(Icons.add_rounded, color: AppColors.inkFaint, size: 22),
        ),
      );
}

/// A 64×64 rounded box with a 1px dashed [lineStrong] border.
class DottedBorderBox extends StatelessWidget {
  const DottedBorderBox({super.key, required this.size, required this.child});
  final double size;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DashedRectPainter(color: AppColors.lineStrong, radius: R.thumb),
        child: SizedBox(width: size, height: size, child: Center(child: child)),
      );
}

class _DashedRectPainter extends CustomPainter {
  _DashedRectPainter({required this.color, required this.radius});
  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final rrect = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(radius));
    final path = Path()..addRRect(rrect);
    const dash = 4.0, gap = 3.0;
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), paint);
        d += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedRectPainter old) => old.color != color || old.radius != radius;
}

// ── auto-attached rows ───────────────────────────────────────────────────────

class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.icon, required this.label, required this.value, required this.divider});
  final IconData icon;
  final String label, value;
  final bool divider;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          border: divider ? const Border(bottom: BorderSide(color: AppColors.line)) : null,
        ),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.inkFaint),
          const SizedBox(width: 11),
          Expanded(child: Text(label, style: T.bodySmall.copyWith(color: AppColors.inkMuted))),
          Text(value, style: T.dataMuted),
        ]),
      );
}
