import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/theme_constants.dart';
import '../../../../core/router/route_names.dart';
import '../providers/client_providers.dart';

/// Clients list (parity with the web `practitioner/clients`). Selecting a client
/// opens their AI report history.
class ClientsListScreen extends ConsumerWidget {
  const ClientsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = ref.watch(filteredClientsProvider);

    return Scaffold(
      backgroundColor: ThemeConstants.background,
      appBar: AppBar(
        backgroundColor: ThemeConstants.surface,
        foregroundColor: ThemeConstants.textPrimary,
        title: const Text('Clients'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              onChanged: (v) =>
                  ref.read(clientSearchQueryProvider.notifier).state = v,
              style:
                  TextStyle(color: ThemeConstants.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search clients…',
                hintStyle: TextStyle(color: ThemeConstants.textTertiary),
                prefixIcon: Icon(Icons.search_rounded,
                    color: ThemeConstants.textTertiary),
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
          ),
          Expanded(
            child: filtered.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load clients: $e',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ThemeConstants.error)),
                ),
              ),
              data: (clients) {
                if (clients.isEmpty) {
                  return Center(
                    child: Text('No clients found',
                        style: TextStyle(
                            color: ThemeConstants.textSecondary,
                            fontWeight: FontWeight.w700)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                  itemCount: clients.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final c = clients[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => context.pushNamed(
                        RouteNames.aiReports,
                        extra: {'clientId': c.id, 'title': c.displayName},
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: ThemeConstants.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: ThemeConstants.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: ThemeConstants.surfaceVariant,
                                borderRadius: BorderRadius.circular(999),
                                border:
                                    Border.all(color: ThemeConstants.border),
                              ),
                              child: Icon(Icons.person_rounded,
                                  size: 20,
                                  color: ThemeConstants.textSecondary),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(c.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: ThemeConstants.textPrimary,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (c.gender != null) c.gender!,
                                      if (c.age != null) 'Age ${c.age}',
                                    ].join(' · '),
                                    style: TextStyle(
                                        color: ThemeConstants.textSecondary,
                                        fontSize: 12),
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
    );
  }
}
