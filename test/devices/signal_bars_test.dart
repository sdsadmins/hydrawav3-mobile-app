import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hydrawav3/features/devices/presentation/widgets/device_center_widgets.dart';

/// Signal bars follow the v6 `bars4` cut-offs, from an averaged live reading.
void main() {
  test('four levels at -52 / -58 / -70 dBm', () {
    expect(signalOf(-45).bars, 4);
    expect(signalOf(-52).bars, 4);
    expect(signalOf(-53).bars, 3);
    expect(signalOf(-58).bars, 3);
    expect(signalOf(-59).bars, 2);
    expect(signalOf(-70).bars, 2);
    expect(signalOf(-71).bars, 1);
    expect(signalOf(-90).bars, 1);
  });

  test('words follow the prototype: strong ≥ -58, then good, then weak', () {
    expect(signalOf(-50).word, 'Strong signal');
    expect(signalOf(-58).word, 'Strong signal');
    expect(signalOf(-65).word, 'Good signal');
    expect(signalOf(-80).word, 'Weak signal');
  });

  test('one unlucky reading no longer decides the bars', () {
    final a = RssiAverage(4);
    expect(a.value, isNull);
    a
      ..add(-50)
      ..add(-52)
      ..add(-78) // a hand over the antenna
      ..add(-50);
    expect(a.value, -58); // still 3 bars, not 1
    expect(signalOf(a.value!).bars, 3);
  });

  test('keeps only the last readings', () {
    final a = RssiAverage(4);
    for (final r in [-90, -90, -90, -90, -50, -50, -50, -50]) {
      a.add(r);
    }
    expect(a.value, -50);
  });

  test('ignores "unavailable" values (0, iOS 127)', () {
    final a = RssiAverage(4)
      ..add(0)
      ..add(127);
    expect(a.value, isNull);
    a.add(-60);
    expect(a.value, -60);
  });

  testWidgets('draws four bars', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: Center(child: SignalBars(3))),
    ));
    final bars = find.descendant(
        of: find.byType(SignalBars), matching: find.byType(Container));
    expect(bars, findsNWidgets(4));
    expect(tester.takeException(), isNull);
  });
}
