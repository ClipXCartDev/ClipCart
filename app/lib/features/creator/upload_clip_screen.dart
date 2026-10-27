import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../services/creator_service.dart';
import '../../widgets/primary_button.dart';

// What a customer can change about this clip. 'logo' and 'username' were two
// labels for the page's one name, matching two editor tools that are now one,
// so they are one here too. Clips uploaded under the old labels keep them;
// they are free text that only an admin reads.
const _allLayers = ['subtitle', 'handle', 'cta', 'ending', 'aspect'];

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
  /// The picked file stays on hand after upload so the author can lay layers out
  /// on the real footage without re-downloading what they just sent.
  String? _baseLocalPath;
  /// The layer set that ships WITH this clip — the customer opens these in the
  /// same editor and restyles them (colour, font, wording) before exporting.
  Map<String, dynamic>? _overlays;
  String? _markKey;          // the creator's mark, as a storage key
  String? _markName;
  int _srtCount = 0;         // captions brought in from a subtitle file
  bool _importing = false;

  Future<void> _pickBase() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.video);
    if (res == null || res.files.single.path == null) return;
    setState(() => _uploading = true);
    try {
      final key = await context.read<CreatorService>().uploadBaseClip(res.files.single.path!, res.files.single.name);
      setState(() { _baseKey = key; _baseLocalPath = res.files.single.path; });
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Base clip uploaded')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Upload failed. Please try again.')));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Captions from a subtitle file, laid onto the clip.
  ///
  /// This is how subtitles arrive from every transcription tool there is, and
  /// without it the only way in was to type each caption and both its
  /// timestamps by hand — which nobody does for a forty-caption file. Parsed
  /// on the server so the web creator gets the same layers from the same file.
  Future<void> _importSubtitles() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['srt', 'vtt', 'txt'],
    );
    final path = res?.files.single.path;
    if (path == null) return;
    setState(() => _importing = true);
    try {
      final text = await File(path).readAsString();
      final caps = await context.read<CreatorService>().parseSubtitles(text);
      setState(() {
        // Captions join whatever the author already laid out rather than
        // replacing it: a creator who styled a handle and a CTA first should
        // not lose them by importing their subtitles second.
        final existing = [...((_overlays?['subs'] as List?) ?? const [])];
        _overlays = {...?_overlays, 'subs': [...existing, ...caps]};
        _srtCount = caps.length;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${caps.length} caption${caps.length == 1 ? '' : 's'} added — '
              'open Design the layers to style and position them'),
        ));
      }
    } on SubtitleImportError catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Couldn't read that file. Try an .srt or .vtt.")));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  /// The creator's own mark, drawn on every customer's copy of this clip.
  Future<void> _pickMark() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'webp'],
    );
    final file = res?.files.single;
    if (file?.path == null) return;
    setState(() => _uploading = true);
    try {
      final key = await context.read<CreatorService>().uploadMark(file!.path!, file.name);
      setState(() {
        _markKey = key;
        _markName = file.name;
      });
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Mark uploaded')));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('That upload did not go through. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Opens the editor in AUTHOR mode on the file just picked. What comes back
  /// is the clip's shipped layer set — captions positioned and styled on the
  /// real footage, which every customer then edits rather than starting blank.
  Future<void> _designLayers() async {
    final path = _baseLocalPath;
    if (path == null) return;
    final result = await context.push<Object?>('/editor', extra: {
      'authorFile': path,
      'authorInitial': _overlays,
      'title': _title.text.trim().isEmpty ? 'Design layers' : _title.text.trim(),
    });
    if (result is Map<String, dynamic> && mounted) {
      setState(() => _overlays = result);
      final n = (result['subs'] as List?)?.length ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$n layer${n == 1 ? '' : 's'} attached to this clip')));
    }
  }

  int get _overlayCount => (_overlays?['subs'] as List?)?.length ?? 0;

  /// The authored layers as the server stores them: the mark as a KEY, never a
  /// URL — the server signs a fresh one for each customer who opens the clip.
  Map<String, dynamic>? get _overlaysPayload {
    if (_overlays == null && _markKey == null) return null;
    return {...?_overlays, if (_markKey != null) 'logoKey': _markKey};
  }

  @override
  void dispose() {
    for (final c in [_title, _movie, _genre, _language, _category, _tags]) {
      c.dispose();
    }
    super.dispose();
  }

  /// One row for a file the creator attaches: same shape as the layer row
  /// above it, so the three reads as one list rather than three designs.
  Widget _fileRow({
    required IconData icon,
    required bool on,
    required String title,
    required String subtitle,
    required String action,
    required bool busy,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.card),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: on ? AppColors.brandTint : AppColors.surface,
          borderRadius: BorderRadius.circular(R.card),
          border: Border.all(color: on ? AppColors.brand : AppColors.line),
        ),
        child: Row(children: [
          Icon(icon, color: on ? AppColors.brand : AppColors.mut, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.mut, fontSize: 11.5)),
              ],
            ),
          ),
          if (busy)
            const SizedBox(
                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          else
            Text(action,
                style: const TextStyle(
                    color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13)),
        ]),
      ),
    );
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
        'overlays': _overlaysPayload,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Submitted for review')));
        context.pop();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('That did not go through. Please try again.')));
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
          const SizedBox(height: 10),
          // Layer design — only once there's footage to lay them out on.
          Opacity(
            opacity: _baseLocalPath == null ? 0.5 : 1,
            child: InkWell(
              onTap: _baseLocalPath == null ? null : _designLayers,
              borderRadius: BorderRadius.circular(R.card),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _overlayCount > 0 ? AppColors.brandTint : AppColors.surface,
                  borderRadius: BorderRadius.circular(R.card),
                  border: Border.all(color: _overlayCount > 0 ? AppColors.brand : AppColors.line),
                ),
                child: Row(children: [
                  Icon(_overlayCount > 0 ? Icons.layers_rounded : Icons.layers_outlined,
                      color: _overlayCount > 0 ? AppColors.brand : AppColors.mut, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                      Text(_overlayCount > 0 ? '$_overlayCount layer${_overlayCount == 1 ? '' : 's'} attached' : 'Design the layers (optional)',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: AppColors.ink)),
                      const SizedBox(height: 2),
                      Text(
                        _baseLocalPath == null
                            ? 'Upload the base clip first'
                            : 'Captions the customer opens already styled, then edits',
                        style: const TextStyle(color: AppColors.mut, fontSize: 11.5),
                      ),
                    ]),
                  ),
                  if (_baseLocalPath != null)
                    Text(_overlayCount > 0 ? 'Edit' : 'Open',
                        style: const TextStyle(color: AppColors.brand, fontWeight: FontWeight.w600, fontSize: 13)),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 10),
          _fileRow(
            icon: _srtCount > 0 ? Icons.closed_caption : Icons.closed_caption_outlined,
            on: _srtCount > 0,
            title: _srtCount > 0
                ? '$_srtCount caption${_srtCount == 1 ? '' : 's'} from your file'
                : 'Add subtitles (.srt / .vtt)',
            subtitle: _srtCount > 0
                ? 'Style and position them in Design the layers'
                : 'From any transcription tool — timings come across with them',
            action: _srtCount > 0 ? 'Replace' : 'Choose',
            busy: _importing,
            onTap: _importing ? null : _importSubtitles,
          ),
          const SizedBox(height: 10),
          _fileRow(
            icon: _markKey != null ? Icons.branding_watermark : Icons.branding_watermark_outlined,
            on: _markKey != null,
            title: _markKey == null ? 'Add your mark (optional)' : (_markName ?? 'Mark uploaded'),
            subtitle: _markKey == null
                ? 'A PNG that goes on every customer\'s copy of this clip'
                : 'Place and size it in Design the layers',
            action: _markKey == null ? 'Choose' : 'Replace',
            busy: false,
            onTap: _uploading ? null : _pickMark,
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
