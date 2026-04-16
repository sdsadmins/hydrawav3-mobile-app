import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/constants/theme_constants.dart';
import '../providers/auth_provider.dart';
import '../../presentation/screens/select_organization_page.dart';

class OrganizationDropdown extends ConsumerWidget {
  const OrganizationDropdown({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authStateProvider);

    return PopupMenuButton<String>(
      onSelected: (value) {
        if (value == 'switch') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SelectOrganizationPage(),
            ),
          );
        }
      },
      child: Row(
        children: [
          const Icon(Icons.business, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            auth.selectedOrgName ?? 'Select Org',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 16),
        ],
      ),
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'switch',
          child: Row(
            children: [
              Icon(Icons.swap_horiz),
              SizedBox(width: 8),
              Text('Switch Organization'),
            ],
          ),
        ),
      ],
    );
  }
}