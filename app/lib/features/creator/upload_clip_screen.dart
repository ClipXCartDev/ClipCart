import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/creator_service.dart';
import '../../widgets/primary_button.dart';

const _allLayers = ['subtitle', 'logo', 'username', 'cta', 'ending', 'aspect'];

class UploadClipScreen extends StatefulWidget {
  const UploadClipScreen({super.key});
  @override
  State<UploadClipScreen> createState() => _UploadClipScreenState();
}

class _UploadClipScreenState extends State<UploadClipScreen> {
  final _title = TextEditingController();
  final _movie = TextEditingController();
  final _genre = TextEditingController();
  final _language = TextEditingController(text: 'English');
  final _category = TextEditingController();
  final _tags = TextEditingController();
  String _access = 'free';
  final Set<String> _layers = {'subtitle', 'logo'};
  bool _busy = false;
  bool _uploading = false;
  String? _baseKey;

  Future<void> _pickBase() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      final key = await context.read<CreatorService>().uploadBaseClip(res.files.single.path!, res.files.single.name);
      setState(() => _baseKey = key);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Base clip uploaded')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _movie, _genre, _language, _category, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Title required')));
      return;
    }
    setState(() => _busy = true);
    try {
      await context.read<CreatorService>().createClip({
        'title': _title.text.trim(),
        'movie_name': _movie.text.trim().isEmpty ? null : _movie.text.trim(),
        'genre': _genre.text.trim().isEmpty ? null : _genre.text.trim(),
        'language': _language.text.trim(),
        'tags': _tags.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList(),
        'layers': _layers.toList(),
        'access': _access,
        'base_clip_path': _baseKey,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted for review')));
        context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Brand-violet selectable chip (uniform selection across the app).
  Widget _brandChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand : AppColors.surface,
          borderRadius: BorderRadius.circular(R.pill),
          border: Border.all(color: selected ? AppColors.brand : AppColors.line),
        ),
        child: Text(label,
            style: TextStyle(fontFamily: kSans, fontSize: 12.5, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Colors.white : AppColors.inkMuted)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload clip', style: TextStyle(fontWeight: FontWeight.w600))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: _uploading ? null : _pickBase,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _baseKey != null ? AppColors.okBg : AppColors.surface,
                borderRadius: BorderRadius.circular(R.card),
                border: Border.all(color: _baseKey != null ? AppColors.ok : AppColors.line),
              ),
              child: _uploading
                  ? const Center(child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator()))
                  : Column(children: [
                      Icon(_baseKey != null ? Icons.check_circle : Icons.upload_file, color: _baseKey != null ? AppColors.ok : AppColors.brand, size: 26),
                      const SizedBox(height: 8),
                      Text(_baseKey != null ? 'Base clip uploaded' : 'Tap to upload base clip (MP4)', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.mut, fontSize: 12)),
                    ]),
            ),
          ),
          const SizedBox(height: 14),
          TextField(controller: _title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 10),
          TextField(controller: _movie, decoration: const InputDecoration(labelText: 'Movie name')),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: _genre, decoration: const InputDecoration(labelText: 'Genre'))),
            const SizedBox(width: 10),
            Expanded(child: TextField(controller: _language, decoration: const InputDecoration(labelText: 'Language'))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: _tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
          const SizedBox(height: 16),
          const Text('Access', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(children: [
            _brandChip('Free', _access == 'free', () => setState(() => _access = 'free')),
            const SizedBox(width: 8),
            _brandChip('Pro', _access == 'pro', () => setState(() => _access = 'pro')),
          ]),
          const SizedBox(height: 16),
          const Text('Customizable layers', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _allLayers
                .map((l) => _brandChip(l, _layers.contains(l), () => setState(() => _layers.contains(l) ? _layers.remove(l) : _layers.add(l))))
                .toList(),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Submit for review', icon: Icons.send, loading: _busy, onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }
}
