import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/screens/select_organization_page.dart'
    show organizationProvider;
import '../../devices/presentation/widgets/plan_sheet.dart';
import '../../devices/presentation/widgets/session_plan_widgets.dart';
import '../data/practitioner_repository.dart';

/// v5 `50-admin` — an organization's team, for the account owner (Main
/// admin): shared credits, the practitioner logins, and "Create practitioner
/// login". Backed by `practitioners/by-org` and `secondary/create`, the same
/// calls the web's Practitioners page makes.
Future<void> showOrgTeamSheet(
  BuildContext context, {
  required String orgId,
  required String orgName,
  String? creditsLeft,
  String? planName,
}) {
  return showPlanSheet<void>(
    context,
    title: orgName,
    subtitle: 'Main admin',
    builder: (_) => _TeamBody(
      orgId: orgId,
      orgName: orgName,
      creditsLeft: creditsLeft,
      planName: planName,
    ),
  );
}

const _copperInk = Color(0xFF8A5F42);
const _eyeColor = Color(0xFFC09D84);

class _Eyebrow extends StatelessWidget {
  final String text;
  const _Eyebrow(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
            color: _eyeColor,
          ),
        ),
      );
}

Color _ink(BuildContext c) =>
    PlanTones.dark(c) ? const Color(0xFFF1E4D6) : const Color(0xFF1A1A1A);

class _TeamBody extends ConsumerWidget {
  final String orgId;
  final String orgName;
  final String? creditsLeft;
  final String? planName;
  const _TeamBody({
    required this.orgId,
    required this.orgName,
    this.creditsLeft,
    this.planName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final team = ref.watch(practitionersByOrgProvider(orgId));
    final count = team.valueOrNull?.length;
    final sub = PlanTones.sub(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (creditsLeft != null) ...[
            const _Eyebrow('Shared credits'),
            Text(
              '$creditsLeft left',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFFA87B5C),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${planName ?? 'Plan'} · pooled across '
              '${count ?? '…'} practitioner${count == 1 ? '' : 's'} in this '
              'organization',
              style: TextStyle(fontSize: 12, color: sub),
            ),
            const SizedBox(height: 16),
          ],
          _Eyebrow('Practitioners${count == null ? '' : ' · $count'}'),
          team.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(PlanTones.copper),
                  ),
                ),
              ),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text("Couldn't load the team.",
                        style: TextStyle(fontSize: 13, color: sub)),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(practitionersByOrgProvider(orgId)),
                    child: const Text('Retry',
                        style: TextStyle(color: _copperInk)),
                  ),
                ],
              ),
            ),
            data: (list) => list.isEmpty
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(2, 4, 2, 6),
                    child: Text('No practitioner logins yet.',
                        style: TextStyle(fontSize: 12.5, color: sub)),
                  )
                : Column(
                    children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0)
                          Divider(
                              height: 1, color: PlanTones.hairline(context)),
                        _StaffRow(
                          p: list[i],
                          onTap: () => showPractitionerDetails(context, list[i]),
                        ),
                      ],
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          // `.v5a-new` — dashed "Create practitioner login".
          Semantics(
            button: true,
            label: 'Create practitioner login',
            child: PlanPress(
              onTap: () => _showCreatePractitioner(
                context,
                orgId: orgId,
                orgName: orgName,
              ),
              scale: .98,
              child: CustomPaint(
                painter: _DashedRRect(
                    color: const Color.fromRGBO(198, 158, 131, .7)),
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add_rounded, size: 17, color: _copperInk),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Create practitioner login',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: _copperInk,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// `.v5a-p` — a practitioner: name, then user ID · title.
class _StaffRow extends StatelessWidget {
  final Practitioner p;
  final VoidCallback onTap;
  const _StaffRow({required this.p, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final meta = [
      if (p.userName != null) p.userName!,
      if (p.title != null) p.title!,
    ].join(' · ');
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              PlanAvatar(initials: p.initials.isEmpty ? '?' : p.initials),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _ink(context),
                      ),
                    ),
                    if (meta.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: PlanTones.sub(context)),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: PlanTones.sub(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashedRRect extends CustomPainter {
  final Color color;
  const _DashedRRect({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
          Offset.zero & size, const Radius.circular(16)));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color;
    for (final m in path.computeMetrics()) {
      for (double d = 0; d < m.length; d += 9) {
        canvas.drawPath(m.extractPath(d, math.min(d + 5, m.length)), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedRRect old) => old.color != color;
}

// ───────────────────────────── details (web "View") ──────────────────────────

Future<void> showPractitionerDetails(BuildContext context, Practitioner p) {
  final rows = <(String, String?)>[
    ('ID', '#${p.id}'),
    ('Username', p.userName),
    ('Title', p.title),
    ('Phone', p.phone),
    ('Email', p.mail),
    ('Date of birth', p.dateOfBirth),
    ('Address', p.address),
    ('City', p.city),
    ('State', p.state),
    ('ZIP', p.zip),
    ('Country', p.country),
    (
      'Account enabled',
      p.isEnabled == null ? null : (p.isEnabled! ? 'Yes' : 'No')
    ),
  ];
  return showPlanSheet<void>(
    context,
    title: p.name,
    subtitle: p.mail,
    builder: (ctx) {
      final sub = PlanTones.sub(ctx);
      Widget cell((String, String?) r) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  r.$1.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: .6,
                    color: sub,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  r.$2 ?? '—',
                  style: TextStyle(fontSize: 14, color: _ink(ctx)),
                ),
              ],
            ),
          );
      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: LayoutBuilder(builder: (ctx, c) {
          final two = c.maxWidth >= 360;
          if (!two) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final r in rows) cell(r)],
            );
          }
          return Wrap(
            children: [
              for (final r in rows)
                SizedBox(width: c.maxWidth / 2, child: cell(r)),
            ],
          );
        }),
      );
    },
  );
}

// ───────────────────────────── create ────────────────────────────────────────

String _generatePassword() {
  const letters = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ';
  const digits = '23456789';
  final r = math.Random.secure();
  final chars = [
    for (var i = 0; i < 7; i++) letters[r.nextInt(letters.length)],
    for (var i = 0; i < 3; i++) digits[r.nextInt(digits.length)],
  ]..shuffle(r);
  return chars.join();
}

Future<void> _showCreatePractitioner(
  BuildContext context, {
  required String orgId,
  required String orgName,
}) {
  return showPlanSheet<void>(
    context,
    title: 'New practitioner',
    subtitle: 'Creates their Hydrawav3 login',
    builder: (_) => _CreateForm(
      orgId: orgId,
      orgName: orgName,
      onCreated: (created) => _showCredentials(
        context,
        orgName: orgName,
        name: created.$1,
        userName: created.$2,
        password: created.$3,
      ),
    ),
  );
}

class _CreateForm extends ConsumerStatefulWidget {
  final String orgId;
  final String orgName;
  final void Function((String, String, String) created) onCreated;
  const _CreateForm({
    required this.orgId,
    required this.orgName,
    required this.onCreated,
  });

  @override
  ConsumerState<_CreateForm> createState() => _CreateFormState();
}

class _CreateFormState extends ConsumerState<_CreateForm> {
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _title = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zip = TextEditingController();
  final _country = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController(text: _generatePassword());
  DateTime? _dob;
  late final Set<int> _orgIds = {
    if (int.tryParse(widget.orgId) != null) int.parse(widget.orgId),
  };
  bool _userEdited = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    void suggest() {
      if (_userEdited) return;
      final s = '${_first.text}${_last.text}'
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      _user.text = s;
    }

    _first.addListener(suggest);
    _last.addListener(suggest);
  }

  @override
  void dispose() {
    for (final c in [
      _first, _last, _email, _phone, _title, _address, _city, _state, _zip,
      _country, _user, _pass,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    final required = <(String, TextEditingController)>[
      ('First name', _first),
      ('Last name', _last),
      ('Email', _email),
      ('Phone', _phone),
      ('Title', _title),
      ('Address', _address),
      ('City', _city),
      ('Country', _country),
      ('User name', _user),
      ('Password', _pass),
    ];
    for (final (label, c) in required) {
      if (c.text.trim().isEmpty) {
        return setState(() => _error = '$label is required');
      }
    }
    if (_pass.text.trim().length < 8) {
      return setState(() => _error = 'Password must be at least 8 characters');
    }
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(_email.text.trim())) {
      return setState(() => _error = 'Enter a valid email address');
    }
    if (_orgIds.isEmpty) {
      return setState(() => _error = 'Pick at least one organization');
    }
    setState(() {
      _error = null;
      _saving = true;
    });
    final dob = _dob == null
        ? null
        : '${_dob!.year.toString().padLeft(4, '0')}-'
            '${_dob!.month.toString().padLeft(2, '0')}-'
            '${_dob!.day.toString().padLeft(2, '0')}';
    try {
      await ref.read(practitionerRepositoryProvider).create(NewPractitioner(
            firstName: _first.text.trim(),
            lastName: _last.text.trim(),
            userName: _user.text.trim(),
            password: _pass.text.trim(),
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            title: _title.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            state: _state.text.trim(),
            zip: _zip.text.trim(),
            country: _country.text.trim(),
            dateOfBirth: dob,
            organizationIds: _orgIds.toList(),
          ));
      for (final id in _orgIds) {
        ref.invalidate(practitionersByOrgProvider('$id'));
      }
      if (!mounted) return;
      final created = (
        '${_first.text.trim()} ${_last.text.trim()}',
        _user.text.trim(),
        _pass.text.trim(),
      );
      Navigator.of(context).pop();
      widget.onCreated(created);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Widget _field(String label, TextEditingController c,
      {String? tag,
      String? hint,
      TextInputType? type,
      List<TextInputFormatter>? fmt}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PlanFieldLabel(label, tag: tag),
          PlanTextField(
            controller: c,
            hint: hint,
            keyboardType: type,
            inputFormatters: fmt,
          ),
        ],
      ),
    );
  }

  Widget _half(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 10),
          Expanded(child: b),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final orgs = ref.watch(organizationProvider).valueOrNull ?? const [];
    final sub = PlanTones.sub(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _half(
            _field('First name', _first, hint: 'Jane'),
            _field('Last name', _last, hint: 'Doe'),
          ),
          _field('Email', _email,
              hint: 'jane@clinic.com', type: TextInputType.emailAddress),
          _half(
            _field('Phone', _phone,
                hint: '(555) 123-4567', type: TextInputType.phone),
            _field('Title', _title, hint: 'e.g. Physiotherapist'),
          ),
          _field('Address', _address, hint: '123 Main St'),
          _half(
            _field('City', _city, hint: 'Los Angeles'),
            _field('State', _state, tag: 'optional', hint: 'California'),
          ),
          _half(
            _field('ZIP', _zip, tag: 'optional', hint: '90001'),
            _field('Country', _country, hint: 'USA'),
          ),
          const PlanFieldLabel('Date of birth', tag: 'optional'),
          PlanPress(
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: _dob ?? DateTime(now.year - 30),
                firstDate: DateTime(1920),
                lastDate: now,
              );
              if (picked != null) setState(() => _dob = picked);
            },
            scale: .98,
            child: PlanSelectBox(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _dob == null
                          ? 'Select date'
                          : '${_dob!.month}/${_dob!.day}/${_dob!.year}',
                      style: TextStyle(
                        fontSize: 15,
                        color: _dob == null ? sub : _ink(context),
                      ),
                    ),
                  ),
                  Icon(Icons.calendar_today_rounded, size: 17, color: sub),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const PlanFieldLabel('Organizations', tag: 'tap all that apply'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final o in orgs)
                if (int.tryParse('${o['id']}') != null)
                  PlanChoiceChip(
                    label: '${o['name'] ?? 'Organization'}',
                    selected: _orgIds.contains(int.parse('${o['id']}')),
                    onTap: () => setState(() {
                      final id = int.parse('${o['id']}');
                      if (!_orgIds.remove(id)) _orgIds.add(id);
                    }),
                  ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            'LOGIN',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.3,
              color: _eyeColor,
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const PlanFieldLabel('User name'),
                Focus(
                  onFocusChange: (f) {
                    if (f) _userEdited = true;
                  },
                  child: PlanTextField(controller: _user, hint: 'janedoe'),
                ),
              ],
            ),
          ),
          const PlanFieldLabel('First-time password'),
          Row(
            children: [
              Expanded(child: PlanTextField(controller: _pass)),
              const SizedBox(width: 8),
              Tooltip(
                message: 'New password',
                child: PlanPress(
                  onTap: () => setState(() => _pass.text = _generatePassword()),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: PlanTones.hairline(context)),
                    ),
                    child: const Icon(Icons.refresh_rounded,
                        size: 20, color: _copperInk),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'You\'ll see the user name and password once more after creating, '
            'to hand over.',
            style: TextStyle(fontSize: 12, height: 1.4, color: sub),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFFC0553B),
              ),
            ),
          ],
          const SizedBox(height: 16),
          PlanPrimaryButton(
            label: 'Create login',
            busy: _saving,
            onTap: _submit,
          ),
        ],
      ),
    );
  }
}

// ───────────────────────────── credentials (`credentialsSheet`) ─────────────

Future<void> _showCredentials(
  BuildContext context, {
  required String orgName,
  required String name,
  required String userName,
  required String password,
}) {
  return showPlanSheet<void>(
    context,
    title: 'Practitioner login created',
    subtitle: orgName,
    builder: (ctx) {
      final sub = PlanTones.sub(ctx);
      void copy(String text, String what) {
        Clipboard.setData(ClipboardData(text: text));
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('$what copied')),
        );
      }

      Widget row(String label, String value, {String? copyAs}) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Text(label, style: TextStyle(fontSize: 12, color: sub)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    value,
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: _ink(ctx),
                    ),
                  ),
                ),
                if (copyAs != null) ...[
                  const SizedBox(width: 8),
                  Semantics(
                    button: true,
                    label: 'Copy $copyAs',
                    child: PlanPress(
                      onTap: () => copy(value, copyAs),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: PlanTones.hairline(ctx)),
                        ),
                        child: const Icon(Icons.copy_rounded,
                            size: 14, color: _copperInk),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          );

      return SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: PlanTones.hairline(ctx)),
              ),
              child: Column(
                children: [
                  row('Organization', orgName),
                  Divider(height: 1, color: PlanTones.hairline(ctx)),
                  row('Name', name),
                  Divider(height: 1, color: PlanTones.hairline(ctx)),
                  row('User name', userName, copyAs: 'User name'),
                  Divider(height: 1, color: PlanTones.hairline(ctx)),
                  row('First-time password', password, copyAs: 'Password'),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Share these once. They sign in to Hydrawav3 with them.',
              style: TextStyle(fontSize: 12, height: 1.4, color: sub),
            ),
            const SizedBox(height: 14),
            PlanPrimaryButton(
              label: 'Copy both',
              onTap: () => copy('$userName / $password', 'Login'),
            ),
            Center(
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  'Back to the team',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: sub,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
