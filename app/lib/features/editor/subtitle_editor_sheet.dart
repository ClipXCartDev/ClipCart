import 'package:flutter/material.dart';

import '../../models/editor_state.dart';
import '../../services/font_service.dart';
import '../../widgets/primary_button.dart';

const _colorChoices = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF, 0xFFFF7A00, 0xFF9B5DE5];
const _kPanel = Color(0xFF17141B);
const _kAccent = Color(0xFFFF4D6D);

/// Add / edit one timed subtitle line (text, start–end, font, color, size, outline, box).
/// Preserves scale/align set via the on-canvas gestures + toolbar.
class SubtitleEditorSheet extends StatefulWidget {
  const SubtitleEditorSheet({super.key, required this.duration, required this.fonts, this.initial});
  final double duration;
  final List<CustomFont> fonts;
  final SubtitleSegment? initial;

  @override
  State<SubtitleEditorSheet> createState() => _SubtitleEditorSheetState();
}

class _SubtitleEditorSheetState extends State<SubtitleEditorSheet> {
  late final TextEditingController _text;
  late double _start;
  late double _end;
  String _fontKey = 'default';
  late int _color;
  late double _size;
  late double _stroke;
  late bool _bg;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? '');
    _start = i?.start ?? 0;
    _end = i?.end ?? (widget.duration < 3 ? widget.duration : 3);
    _fontKey = i?.fontFamily ?? 'default';
    _color = i?.color ?? 0xFFFFFFFF;
    _size = i?.fontSize ?? 44;
    _stroke = i?.strokeWidth ?? 0;
    _bg = i?.bgEnabled ?? true;
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    CustomFont? font;
    for (final f in widget.fonts) {
      if (f.family == _fontKey) font = f;
    }
    final i = widget.initial;
    Navigator.pop(
      context,
      SubtitleSegment(
        text: _text.text.trim().isEmpty ? 'Text' : _text.text.trim(),
        start: _start,
        end: _end <= _start ? _start + 0.5 : _end,
        fontFamily: font?.family,
        fontFilePath: font?.path,
        color: _color,
        fontSize: _size,
        // preserve transforms / align set on canvas + toolbar
        scale: i?.scale ?? 1.0,
        strokeWidth: _stroke,
        strokeColor: i?.strokeColor ?? 0xFF000000,
        bgEnabled: _bg,
        bgColor: i?.bgColor ?? 0x80000000,
        align: i?.align ?? TextAlignH.center,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final maxD = widget.duration <= 0 ? 1.0 : widget.duration;
    return Container(
      decoration: const BoxDecoration(color: _kPanel, borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 14),
            Text(widget.initial?.text.isEmpty ?? true ? 'Add text' : 'Edit text', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 14),
            TextField(
              controller: _text,
              maxLines: 2,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Text',
                labelStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.white10,
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _kAccent)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Timing:  ${_start.toStringAsFixed(1)}s → ${_end.toStringAsFixed(1)}s', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            RangeSlider(
              min: 0,
              max: maxD,
              divisions: (maxD * 10).clamp(1, 600).toInt(),
              values: RangeValues(_start.clamp(0, maxD), _end.clamp(0, maxD)),
              labels: RangeLabels('${_start.toStringAsFixed(1)}s', '${_end.toStringAsFixed(1)}s'),
              activeColor: _kAccent,
              onChanged: (v) => setState(() {
                _start = v.start;
                _end = v.end;
              }),
            ),
            const SizedBox(height: 4),
            Row(children: [
              const Text('Font', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButton<String>(
                  isExpanded: true,
                  dropdownColor: _kPanel,
                  value: _fontKey,
                  style: const TextStyle(color: Colors.white),
                  items: [
                    const DropdownMenuItem(value: 'default', child: Text('Default')),
                    ...widget.fonts.map((f) => DropdownMenuItem(value: f.family, child: Text(f.name, overflow: TextOverflow.ellipsis))),
                  ],
                  onChanged: (v) => setState(() => _fontKey = v ?? 'default'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _colorChoices.map((c) {
                final selected = c == _color;
                return GestureDetector(
                  onTap: () => setState(() => _color = c),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Color(c),
                      shape: BoxShape.circle,
                      border: Border.all(color: selected ? _kAccent : Colors.white24, width: selected ? 3 : 1),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text('Size: ${_size.round()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            Slider(min: 14, max: 96, value: _size.clamp(14, 96), activeColor: _kAccent, onChanged: (v) => setState(() => _size = v)),
            Text('Outline: ${_stroke.round()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: Colors.white)),
            Slider(min: 0, max: 10, value: _stroke.clamp(0, 10), activeColor: _kAccent, onChanged: (v) => setState(() => _stroke = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: _kAccent,
              value: _bg,
              onChanged: (v) => setState(() => _bg = v),
              title: const Text('Background box', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 4),
            PrimaryButton(label: 'Save', icon: Icons.check, onPressed: _save),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
