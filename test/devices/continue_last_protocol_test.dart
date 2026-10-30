import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hydrawav3/features/clients/domain/client_model.dart';
import 'package:hydrawav3/features/clients/presentation/providers/client_providers.dart';
import 'package:hydrawav3/features/devices/presentation/widgets/continue_last_protocol.dart';
import 'package:hydrawav3/features/history/data/history_repository.dart';
import 'package:hydrawav3/features/history/domain/session_history_model.dart';
import 'package:hydrawav3/features/protocols/domain/protocol_model.dart';
import 'package:hydrawav3/features/protocols/presentation/providers/protocol_provider.dart';

/// Session Plan: "Continue with (last protocol)" puts the selected client's
/// last protocol on every switched-on unit.
void main() {
  const malik = Client(id: 'c1', clientName: 'Malik Carter');
  final yesterday = DateTime.now().subtract(const Duration(days: 1));

  Future<List<(String, String)>> pump(WidgetTester tester,
      {ClientMode mode = ClientMode.client,
      Map<String, String> current = const {}}) async {
    final fonts = Platform.environment['ROBOTO_DIR'];
    if (fonts != null) {
      final l = FontLoader('Roboto');
      for (final f in ['regular', 'medium', 'bold', 'black']) {
        l.addFont(Future.value(ByteData.view(
            File('$fonts/roboto-$f.ttf').readAsBytesSync().buffer)));
      }
      await l.load();
    }
    tester.view.physicalSize = const Size(390, 300) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final applied = <(String, String)>[];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        selectedClientProvider.overrideWith((ref) => malik),
        sessionClientModeProvider.overrideWith((ref) => mode),
        clientHistoryProvider.overrideWith((ref, id) async => [
              SessionHistoryItem(
                id: 's1',
                clientId: 'c1',
                createdAt: yesterday,
                protocols: const [
                  HistoryProtocol(
                      protocol: 'Deep-Tension Recovery', duration: 600),
                ],
              ),
            ]),
        protocolSelectionOptionsProvider.overrideWith((ref, g) async => const [
              ProtocolSelectionOption(
                  id: 'p-deep', templateName: 'Deep-Tension Recovery'),
              ProtocolSelectionOption(id: 'p-en', templateName: 'Energizing 3'),
            ]),
      ],
      child: MaterialApp(
        builder: (c, child) => RepaintBoundary(child: child),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: ContinueLastProtocol(
                unitIds: const ['u1', 'u2'],
                protocolIdByUnit: current,
                onApply: (u, p) async {
                  applied.add((u, p));
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return applied;
  }

  testWidgets('offers the last protocol and applies it to every unit',
      (tester) async {
    final applied = await pump(tester);
    expect(find.text('Continue with Deep-Tension Recovery'), findsOneWidget);
    expect(find.text("Malik's last session · Yesterday · on 2 units"),
        findsOneWidget);

    final dir = Platform.environment['SHOTS'];
    if (dir != null) {
      final ro = tester.renderObject<RenderRepaintBoundary>(
          find.byType(RepaintBoundary).first);
      await tester.runAsync(() async {
        final img = await ro.toImage(pixelRatio: 1);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/continue_last.png')
            .writeAsBytesSync(d!.buffer.asUint8List());
      });
    }

    await tester.tap(find.text('Continue with Deep-Tension Recovery'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(applied, [('u1', 'p-deep'), ('u2', 'p-deep')]);
    expect(find.text('Set Deep-Tension Recovery on 2 units'), findsOneWidget);
  });

  testWidgets('hidden for a guest, and once every unit already runs it',
      (tester) async {
    await pump(tester, mode: ClientMode.guest);
    expect(find.textContaining('Continue with'), findsNothing);
    await pump(tester, current: const {'u1': 'p-deep', 'u2': 'p-deep'});
    expect(find.textContaining('Continue with'), findsNothing);
  });
}
