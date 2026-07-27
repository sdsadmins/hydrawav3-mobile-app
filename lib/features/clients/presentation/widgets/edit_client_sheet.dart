import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/exceptions.dart';
import '../../../../core/theme/hw_tokens.dart';
import '../../../../core/theme/widgets/hw_primitives.dart';
import '../../data/client_repository.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';

/// Edit an existing client / player — the UI spec's `editPlayerSheet(id)`
/// (app.js:1809).
///
/// `PATCH /clients/:id` has always existed but was used only by the four lease
/// operations; nothing could change a name, sport or jersey number after
/// creation. This is that missing path.
Future<bool?> showEditClientSheet(
  BuildContext context,
  WidgetRef ref,
  Client client,
) {
  return showHwSheet<bool>(
    context: context,
    builder: (_) => _EditClientSheet(client: client),
  );
}

class _EditClientSheet extends ConsumerStatefulWidget {
  final Client client;
  const _EditClientSheet({required this.client});

  @override
  ConsumerState<_EditClientSheet> createState() => _EditClientSheetState();
}

class _EditClientSheetState extends ConsumerState<_EditClientSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.client.clientName);
  late final _nickname =
      TextEditingController(text: widget.client.nickname ?? '');
  late final _sport = TextEditingController(text: widget.client.sport ?? '');
  late final _jersey = TextEditingController(
    text: (widget.client.jerseyNumber ?? 0) > 0
        ? '${widget.client.jerseyNumber}'
        : '',
  );
  late final _age = TextEditingController(
    text: widget.client.age == null ? '' : '${widget.client.age}',
  );
  late final _phone = TextEditingController(text: widget.client.phone ?? '');

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final c in [_name, _nickname, _sport, _jersey, _age, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isPlayer => widget.client.isPlayer;

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });

    // Send only what changed — a PATCH that echoes every field back risks
    // clobbering values this form doesn't show (height, weight, positions).
    final patch = <String, dynamic>{};
    void put(String key, Object? value, Object? original) {
      if (value != original) patch[key] = value;
    }

    put('clientName', _name.text.trim(), widget.client.clientName);
    put('nickname', _nickname.text.trim(),
        widget.client.nickname ?? '');
    put('phone', _phone.text.trim(), widget.client.phone ?? '');
    final age = int.tryParse(_age.text.trim());
    if (age != null && age != widget.client.age) patch['age'] = age;

    if (_isPlayer) {
      put('sport', _sport.text.trim(), widget.client.sport ?? '');
      final jersey = int.tryParse(_jersey.text.trim()) ?? 0;
      if (jersey != (widget.client.jerseyNumber ?? 0)) {
        patch['jerseyNumber'] = jersey;
      }
    }

    if (patch.isEmpty) {
      if (mounted) Navigator.pop(context, false);
      return;
    }

    try {
      await ref
          .read(clientRepositoryProvider)
          .updateClient(widget.client.id, patch);
      ref.invalidate(clientListProvider);
      if (!mounted) return;
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } on ServerException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Unable to save right now.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = RefPalette.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _isPlayer ? 'Edit player' : 'Edit client',
            style: TextStyle(
              fontSize: HwType.lg,
              fontWeight: FontWeight.w700,
              color: p.ink,
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(fontSize: HwType.cap, color: p.low),
            ),
          ],
          const SizedBox(height: HwSpace.s3),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  HwField(
                    label: 'Full name',
                    controller: _name,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Name is required.'
                        : null,
                  ),
                  HwField(label: 'Nickname', controller: _nickname),
                  if (_isPlayer) ...[
                    HwField(
                      label: 'Sport',
                      controller: _sport,
                      hint: 'e.g. Football',
                    ),
                    HwField(
                      label: 'Jersey #',
                      controller: _jersey,
                      hint: '00',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                  HwField(
                    label: 'Age',
                    controller: _age,
                    keyboardType: TextInputType.number,
                    validator: (v) {
                      final t = v?.trim() ?? '';
                      if (t.isEmpty) return null;
                      final n = int.tryParse(t);
                      return (n == null || n <= 0)
                          ? 'Enter a valid age.'
                          : null;
                    },
                  ),
                  HwField(
                    label: 'Phone',
                    controller: _phone,
                    hint: '(555) 123-4567',
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: HwSpace.s2),
          HwButton(
            label: 'Save changes',
            busy: _saving,
            onTap: _save,
          ),
          HwSkipLink(
            label: 'Cancel',
            onTap: () => Navigator.pop(context, false),
          ),
        ],
      ),
    );
  }
}
