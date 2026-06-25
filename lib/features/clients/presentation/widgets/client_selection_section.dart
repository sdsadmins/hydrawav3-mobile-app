import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../intake/presentation/widgets/option_picker.dart';
import '../../domain/client_model.dart';
import '../providers/client_providers.dart';
import 'new_client_sheet.dart';

/// Client / Guest selector shown at the top of the session setup screen.
/// Mirrors the web `ClientSelectionSection`.
class ClientSelectionSection extends ConsumerWidget {
  const ClientSelectionSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(sessionClientModeProvider);
    final selected = ref.watch(selectedClientProvider);
    final isGuest = mode == ClientMode.guest;

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ThemeConstants.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people_alt_rounded,
                  size: 18, color: ThemeConstants.accent),
              const SizedBox(width: 8),
              Text(
                'SESSION CLIENT',
                style: TextStyle(
                  color: ThemeConstants.textPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Segmented Client | Guest
          _Segmented(
            isGuest: isGuest,
            onClient: () {
              ref.read(sessionClientModeProvider.notifier).state =
                  ClientMode.client;
            },
            onGuest: () {
              ref.read(sessionClientModeProvider.notifier).state =
                  ClientMode.guest;
              ref.read(selectedClientProvider.notifier).state = null;
            },
          ),
          const SizedBox(height: 16),
          if (isGuest)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ThemeConstants.surfaceVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: ThemeConstants.border),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      size: 18, color: ThemeConstants.textTertiary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Proceeding as Guest. No client history will be saved.',
                      style: TextStyle(
                        color: ThemeConstants.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else ...[
            PickerField(
              value: selected?.displayName,
              placeholder: 'Select a client',
              icon: Icons.search_rounded,
              trailing: selected != null
                  ? InkWell(
                      onTap: () => ref
                          .read(selectedClientProvider.notifier)
                          .state = null,
                      child: Icon(Icons.close_rounded,
                          color: ThemeConstants.textTertiary),
                    )
                  : null,
              onTap: () => _openClientPicker(context, ref),
            ),
            if (selected != null) ...[
              const SizedBox(height: 8),
              Text(
                _clientSummary(selected),
                style: TextStyle(
                  color: ThemeConstants.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showNewClientSheet(context, ref),
                icon: const Icon(Icons.add_rounded, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ThemeConstants.accent,
                  side: BorderSide(color: ThemeConstants.accent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                label: const Text('New Client'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _clientSummary(Client c) {
    final parts = <String>[];
    if (c.gender != null) parts.add('Gender: ${c.gender}');
    if (c.age != null) parts.add('Age: ${c.age}');
    if (c.weight != null) parts.add('Weight: ${c.weight!.toStringAsFixed(0)} kg');
    if (c.height != null) parts.add('Height: ${c.height!.toStringAsFixed(0)} cm');
    return parts.join(' · ');
  }

  Future<void> _openClientPicker(BuildContext context, WidgetRef ref) async {
    // Reset the search each time the picker opens.
    ref.read(clientSearchQueryProvider.notifier).state = '';
    final picked = await showModalBottomSheet<Client>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: ThemeConstants.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) => const _ClientPickerSheet(),
    );
    if (picked != null) {
      ref.read(selectedClientProvider.notifier).state = picked;
      ref.read(sessionClientModeProvider.notifier).state = ClientMode.client;
    }
  }
}

class _Segmented extends StatelessWidget {
  final bool isGuest;
  final VoidCallback onClient;
  final VoidCallback onGuest;

  const _Segmented({
    required this.isGuest,
    required this.onClient,
    required this.onGuest,
  });

  @override
  Widget build(BuildContext context) {
    // Matches the Bluetooth / WiFi toggle (_SegmentBtn) on the Devices screen.
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: ThemeConstants.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: ThemeConstants.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.20),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _seg('Client', Icons.person_rounded, !isGuest, onClient),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _seg('Guest', Icons.people_rounded, isGuest, onGuest),
          ),
        ],
      ),
    );
  }

  Widget _seg(String label, IconData icon, bool active, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: active ? ThemeConstants.segmentActiveBg : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: ThemeConstants.segmentActiveBg
                        .withValues(alpha: 0.22),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 18,
              color:
                  active ? ThemeConstants.onNav : ThemeConstants.textSecondary,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: active
                    ? ThemeConstants.onNav
                    : ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClientPickerSheet extends ConsumerWidget {
  const _ClientPickerSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredClientsProvider);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 4,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Select client',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: ThemeConstants.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              autofocus: true,
              onChanged: (v) =>
                  ref.read(clientSearchQueryProvider.notifier).state = v,
              style: TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search and choose a client…',
                hintStyle: TextStyle(color: ThemeConstants.textTertiary),
                prefixIcon:
                    Icon(Icons.search_rounded, color: ThemeConstants.textTertiary),
                filled: true,
                fillColor:
                    ThemeConstants.surfaceVariant.withValues(alpha: 0.7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: ThemeConstants.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: ThemeConstants.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: filtered.when(
                loading: () => const Padding(
                  padding: EdgeInsets.symmetric(vertical: 28),
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (e, _) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Failed to load clients: $e',
                    style: const TextStyle(color: ThemeConstants.error),
                  ),
                ),
                data: (clients) {
                  if (clients.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 28),
                      child: Center(
                        child: Text(
                          'No clients found',
                          style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const ClampingScrollPhysics(),
                    itemCount: clients.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (ctx, i) {
                      final c = clients[i];
                      return InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.of(ctx).pop(c),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: ThemeConstants.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: ThemeConstants.border),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      c.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: ThemeConstants.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      [
                                        if (c.gender != null) c.gender!,
                                        if (c.age != null) 'Age ${c.age}',
                                      ].join(' · '),
                                      style: TextStyle(
                                        color: ThemeConstants.textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: ThemeConstants.textTertiary),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
