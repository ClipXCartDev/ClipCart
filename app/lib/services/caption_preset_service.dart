import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/runtime_config.dart';
import '../models/caption_preset.dart';
import '../models/editor_state.dart';

/// The caption looks the editor offers.
///
/// Two sets, shown as one row: the ones the business decides, which come from
/// the server so they can be changed without an app release, and the ones the
/// person using the app saved for themselves, which never leave the device.
///
/// The server's set is cached, because the editor must be able to draw its
/// preset row on a train. Order of preference: what the server just said, what
/// it said last time, and failing both the list the app ships with.
class CaptionPresetService extends ChangeNotifier {
  static const _kCache = 'cc_caption_presets';
  static const _kCustom = 'cc_caption_presets_custom';

  /// Where the old Styles gallery kept its saves. Read once, then left alone.
  static const _kLegacy = 'cc_saved_styles';

  static const _maxCustom = 30;

  final _store = const FlutterSecureStorage();

  List<CaptionPreset> _shipped = CaptionPreset.bundled;
  List<CaptionPreset> _custom = [];
  bool _loaded = false;

  /// The business's presets, then the person's own.
  List<CaptionPreset> get all => [..._shipped, ..._custom];

  List<CaptionPreset> get custom => List.unmodifiable(_custom);

  /// Reads the cache and the saved presets, then asks the server.
  ///
  /// The cache is applied before the request so the editor opens with
  /// something real rather than a flash of the bundled list.
  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    await _readCache();
    await _readCustom();
    notifyListeners();
    await refresh();
  }

  /// Ask the server again. Safe to call whenever the editor opens — a failure
  /// leaves whatever was already there.
  Future<void> refresh() async {
    try {
      final r = await Dio().get(
        '${RuntimeConfig.apiBaseUrl}/config/caption-presets',
        options: Options(
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
        ),
      );
      final body = r.data is String ? jsonDecode(r.data as String) : r.data;
      final list = (body as Map)['presets'];
      final parsed = _parse(list);
      if (parsed.isEmpty) return; // an empty answer is not an instruction
      _shipped = parsed;
      await _store.write(key: _kCache, value: jsonEncode(list));
      notifyListeners();
    } catch (_) {
      // offline, or the server is unhappy: the cache or the bundled list stands
    }
  }

  Future<void> saveCustom(CaptionPreset p) async {
    final named = CaptionPreset.fromJson({...p.toJson(), 'custom': true});
    // Saving over a name replaces it rather than making a second one with the
    // same label, which is what people mean by saving again.
    _custom = [named, ..._custom.where((x) => x.name.toLowerCase() != named.name.toLowerCase())];
    if (_custom.length > _maxCustom) _custom = _custom.sublist(0, _maxCustom);
    await _writeCustom();
    notifyListeners();
  }

  Future<void> removeCustom(String name) async {
    _custom = _custom.where((x) => x.name.toLowerCase() != name.toLowerCase()).toList();
    await _writeCustom();
    notifyListeners();
  }

  // ── storage ─────────────────────────────────────────────────────────────

  List<CaptionPreset> _parse(Object? list) {
    if (list is! List) return const [];
    final out = <CaptionPreset>[];
    for (final e in list) {
      if (e is Map) {
        try {
          out.add(CaptionPreset.fromJson(Map<String, dynamic>.from(e)));
        } catch (_) {/* one bad preset must not cost the whole row */}
      }
    }
    return out;
  }

  Future<void> _readCache() async {
    try {
      final raw = await _store.read(key: _kCache);
      if (raw == null) return;
      final parsed = _parse(jsonDecode(raw));
      if (parsed.isNotEmpty) _shipped = parsed;
    } catch (_) {}
  }

  Future<void> _readCustom() async {
    try {
      final raw = await _store.read(key: _kCustom);
      if (raw != null) {
        _custom = _parse(jsonDecode(raw)).map((p) => _asCustom(p)).toList();
        return;
      }
    } catch (_) {}
    await _adoptLegacy();
  }

  CaptionPreset _asCustom(CaptionPreset p) =>
      CaptionPreset.fromJson({...p.toJson(), 'custom': true});

  /// Styles saved by the gallery this replaces.
  ///
  /// It stored seven fields and applied five, which is the whole reason for
  /// the change — so what is recovered is partial by nature. The rest comes
  /// from the preset defaults, which is still closer to what its author meant
  /// than losing their styles on upgrade.
  Future<void> _adoptLegacy() async {
    try {
      final raw = await _store.read(key: _kLegacy);
      if (raw == null) return;
      final out = <CaptionPreset>[];
      for (final e in jsonDecode(raw) as List) {
        final m = Map<String, dynamic>.from(e as Map);
        final d = Map<String, dynamic>.from(m['data'] as Map? ?? const {});
        final animIndex = (d['anim'] as num?)?.toInt() ?? 0;
        out.add(CaptionPreset(
          name: (m['name'] as String?)?.trim().isNotEmpty == true ? m['name'] as String : 'Saved style',
          font: d['font'] as String?,
          color: (d['color'] as num?)?.toInt() ?? 0xFFFFFFFF,
          bgEnabled: (d['bg'] as bool?) ?? false,
          bgColor: (d['bgc'] as num?)?.toInt() ?? 0x00000000,
          strokeWidth: (d['sw'] as num?)?.toDouble() ?? 0,
          strokeColor: (d['sc'] as num?)?.toInt() ?? 0xFF000000,
          anim: animIndex >= 0 && animIndex < OverlayAnim.values.length
              ? OverlayAnim.values[animIndex]
              : OverlayAnim.none,
          custom: true,
        ));
      }
      if (out.isEmpty) return;
      _custom = out;
      await _writeCustom();
    } catch (_) {/* nothing to recover */}
  }

  Future<void> _writeCustom() async {
    try {
      await _store.write(
          key: _kCustom, value: jsonEncode(_custom.map((e) => e.toJson()).toList()));
    } catch (_) {/* the list is still right in memory for this session */}
  }
}
