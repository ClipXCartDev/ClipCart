import 'package:flutter/material.dart';

import '../../models/editor_state.dart';
import '../../services/font_service.dart';
import '../../widgets/primary_button.dart';

const _colorChoices = [0xFFFFFFFF, 0xFF000000, 0xFFFF4D6D, 0xFFFFC400, 0xFF12B76A, 0xFF3B9EFF];

/// Add / edit one timed subtitle line (text, start–end, font, color, size).
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

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _text = TextEditingController(text: i?.text ?? '');
    _start = i?.start ?? 0;
    _end = i?.end ?? (widget.duration < 3 ? widget.duration : 3);
    _fontKey = i?.fontFamily ?? 'default';
    _color = i?.color ?? 0xFFFFFFFF;
    _size = i?.fontSize ?? 28;
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
    Navigator.pop(
      context,
      SubtitleSegment(
        text: _text.text.trim().isEmpty ? 'Subtitle' : _text.text.trim(),
        start: _start,
        end: _end <= _start ? _start + 0.5 : _end,
        fontFamily: font?.family,
        fontFilePath: font?.path,
        color: _color,
        fontSize: _size,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(9)))),
            const SizedBox(height: 14),
            Text(widget.initial == null ? 'Add subtitle' : 'Edit subtitle', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 14),
            TextField(controller: _text, maxLines: 2, decoration: const InputDecoration(labelText: 'Text')),
            const SizedBox(height: 16),
            Text('Timing:  ${_start.toStringAsFixed(1)}s → ${_end.toStringAsFixed(1)}s', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            RangeSlider(
              min: 0,
              max: widget.duration <= 0 ? 1 : widget.duration,
              divisions: (widget.duration * 10).clamp(1, 600).toInt(),
              values: RangeValues(_start.clamp(0, widget.duration), _end.clamp(0, widget.duration)),
              labels: RangeLabels('${_start.toStringAsFixed(1)}s', '${_end.toStringAsFixed(1)}s'),
              activeColor: const Color(0xFFFF4D6D),
              onChanged: (v) => setState(() {
                _start = v.start;
                _end = v.end;
              }),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Text('Font', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _fontKey,
                    items: [
                      const DropdownMenuItem(value: 'default', child: Text('Default')),
                      ...widget.fonts.map((f) => DropdownMenuItem(value: f.family, child: Text(f.name, overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _fontKey = v ?? 'default'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Color', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
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
                      border: Border.all(color: selected ? const Color(0xFFFF4D6D) : Colors.grey.shade300, width: selected ? 3 : 1),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Text('Size: ${_size.round()}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            Slider(min: 14, max: 64, value: _size, activeColor: const Color(0xFFFF4D6D), onChanged: (v) => setState(() => _size = v)),
            const SizedBox(height: 8),
            PrimaryButton(label: 'Save subtitle', icon: Icons.check, onPressed: _save),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
