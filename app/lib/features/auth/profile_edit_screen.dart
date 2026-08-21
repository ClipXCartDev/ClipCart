import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/ui_kit.dart';
import '../../state/auth_controller.dart';

/// Profile — the user fills their own details (Name, Age, Gender, Nationality).
/// Email is shown but is NOT editable.
class ProfileEditScreen extends StatefulWidget {
  const ProfileEditScreen({super.key});
  @override
  State<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends State<ProfileEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _age;
  late final TextEditingController _nationality;
  String? _gender;
  bool _saving = false;
  String? _error;

  static const _genders = ['Male', 'Female', 'Other', 'Prefer not to say'];

  @override
  void initState() {
    super.initState();
    final u = context.read<AuthController>().user;
    _name = TextEditingController(text: u?.name ?? '');
    _age = TextEditingController(text: u?.age?.toString() ?? '');
    _nationality = TextEditingController(text: u?.nationality ?? '');
    _gender = u?.gender;
  }

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _nationality.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final ageText = _age.text.trim();
    final err = await context.read<AuthController>().updateProfile(
          name: _name.text.trim().isEmpty ? null : _name.text.trim(),
          age: ageText.isEmpty ? null : int.tryParse(ageText),
          gender: _gender,
          nationality: _nationality.text.trim().isEmpty ? null : _nationality.text.trim(),
        );
    if (!mounted) return;
    if (err == null) {
      context.pop();
      return;
    }
    setState(() {
      _saving = false;
      _error = err;
    });
  }

  Widget _field(String label, TextEditingController c, {String? hint, TextInputType? keyboard, List<TextInputFormatter>? formatters}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FieldLabel(label),
      SizedBox(
        height: H.field,
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          inputFormatters: formatters,
          style: const TextStyle(fontFamily: kSans, fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.ink),
          decoration: InputDecoration(hintText: hint),
        ),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final email = context.read<AuthController>().user?.email ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 20, 10),
            child: Row(children: [
              CircleIconBtn(Icons.arrow_back_rounded, onTap: () => context.pop()),
              const SizedBox(width: 12),
              const Text('Edit profile', style: T.pageTitle),
            ]),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
              children: [
          // email — read-only
          const FieldLabel('Email', topGap: 0),
          Container(
            height: H.field,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceHover2,
              borderRadius: BorderRadius.circular(R.button),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              Expanded(child: Text(email, maxLines: 1, overflow: TextOverflow.ellipsis, style: T.body.copyWith(color: AppColors.inkMuted))),
              const Icon(Icons.lock_outline_rounded, size: 16, color: AppColors.inkFaint),
            ]),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Email can’t be changed.', style: TextStyle(fontFamily: kSans, fontSize: 12, color: AppColors.inkFaint)),
          ),
          const SizedBox(height: 18),
          _field('Full name', _name, hint: 'Your name'),
          const SizedBox(height: 16),
          _field('Age', _age, hint: 'e.g. 24', keyboard: TextInputType.number, formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)]),
          const SizedBox(height: 16),
          const FieldLabel('Gender'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final g in _genders)
                PillChip(g, selected: _gender == g, onTap: () => setState(() => _gender = _gender == g ? null : g)),
            ],
          ),
          const SizedBox(height: 16),
          _field('Nationality', _nationality, hint: 'e.g. Indian'),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(fontFamily: kSans, fontSize: 13, color: AppColors.errText)),
          ],
          const SizedBox(height: 28),
          PrimaryBtn('Save', loading: _saving, onTap: _save),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
