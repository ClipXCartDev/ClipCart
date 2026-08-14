import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Base clip uploaded ✓')));
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted for review 🎬')));
        context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upload clip', style: TextStyle(fontWeight: FontWeight.w800))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          InkWell(
            onTap: _uploading ? null : _pickBase,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _baseKey != null ? const Color(0xFF12B76A) : Colors.grey.withOpacity(0.4)),
              ),
              child: _uploading
                  ? const Center(child: Padding(padding: EdgeInsets.all(6), child: CircularProgressIndicator()))
                  : Column(children: [
                      Icon(_baseKey != null ? Icons.check_circle : Icons.upload_file, color: _baseKey != null ? const Color(0xFF12B76A) : const Color(0xFFFF4D6D), size: 26),
                      const SizedBox(height: 8),
                      Text(_baseKey != null ? 'Base clip uploaded ✓' : 'Tap to upload base clip (MP4)', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
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
          const Text('Access', style: TextStyle(fontWeight: FontWeight.w700)),
          Row(children: [
            ChoiceChip(label: const Text('Free'), selected: _access == 'free', onSelected: (_) => setState(() => _access = 'free')),
            const SizedBox(width: 8),
            ChoiceChip(label: const Text('Pro'), selected: _access == 'pro', onSelected: (_) => setState(() => _access = 'pro')),
          ]),
          const SizedBox(height: 16),
          const Text('Customizable layers', style: TextStyle(fontWeight: FontWeight.w700)),
          Wrap(
            spacing: 8,
            children: _allLayers.map((l) => FilterChip(
                  label: Text(l),
                  selected: _layers.contains(l),
                  onSelected: (v) => setState(() => v ? _layers.add(l) : _layers.remove(l)),
                )).toList(),
          ),
          const SizedBox(height: 20),
          PrimaryButton(label: 'Submit for review', icon: Icons.send, loading: _busy, onPressed: _busy ? null : _submit),
        ],
      ),
    );
  }
}
