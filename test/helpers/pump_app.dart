// `pumpApp` — pump a screen the way the app hosts it: ProviderScope +
// MaterialApp with the real app theme (lib/core/theme/app_theme.dart, via
// [qaThemeFor]), a
// mocked SharedPreferences, and a device-sized test view.
//
// ```dart
// await pumpApp(
//   tester,
//   const UsersScreen(),
//   device: QaDevice.phone,
//   overrides: [authStateProvider.overrideWith((ref) => FakeAuth())],
//   prefs: {'theme_mode': 'dark'},
// );
// ```
//
// The whole app is wrapped in a RepaintBoundary keyed [qaRootKey]; qa_snap.dart
// captures that boundary for screenshots (dialogs and bottom sheets included,
// since they live inside the MaterialApp's Navigator).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:hydrawav3/core/constants/theme_constants.dart';
import 'package:hydrawav3/core/storage/preferences.dart';
import 'package:hydrawav3/core/theme/app_theme.dart';

/// Key of the root RepaintBoundary that [pumpApp] puts around the app.
const qaRootKey = ValueKey<String>('qa-root-boundary');

/// Set by `loadAppFonts()` (qa_snap.dart) once Roboto is registered. While
/// true, [pumpApp] gives family-less component-theme text styles an explicit
/// 'Roboto' so screenshots show real glyphs everywhere (see [qaThemeFor]).
bool qaRealFonts = false;

/// The real app theme for [brightness]. With [qaRealFonts] on, text styles in
/// the AppBar and button themes that name no font family get 'Roboto' — in a
/// widget test a family-less style renders in the box test font, while on an
/// Android device it renders in the system font, which is Roboto.
ThemeData qaThemeFor(Brightness brightness) {
  final base =
      brightness == Brightness.dark ? AppTheme.darkTheme : AppTheme.lightTheme;
  if (!qaRealFonts) return base;

  TextStyle? fam(TextStyle? s) =>
      s == null || s.fontFamily != null ? s : s.copyWith(fontFamily: 'Roboto');
  ButtonStyle? btn(ButtonStyle? s) => s?.copyWith(
        textStyle: s.textStyle == null
            ? null
            : WidgetStateProperty.resolveWith(
                (states) => fam(s.textStyle!.resolve(states)),
              ),
      );

  return base.copyWith(
    appBarTheme: base.appBarTheme.copyWith(
      titleTextStyle: fam(base.appBarTheme.titleTextStyle),
      toolbarTextStyle: fam(base.appBarTheme.toolbarTextStyle),
    ),
    elevatedButtonTheme:
        ElevatedButtonThemeData(style: btn(base.elevatedButtonTheme.style)),
    textButtonTheme:
        TextButtonThemeData(style: btn(base.textButtonTheme.style)),
    outlinedButtonTheme:
        OutlinedButtonThemeData(style: btn(base.outlinedButtonTheme.style)),
    filledButtonTheme:
        FilledButtonThemeData(style: btn(base.filledButtonTheme.style)),
  );
}

/// Logical screen sizes used across the suite.
enum QaDevice {
  /// iPhone 14/15-class portrait.
  phone(Size(390, 844)),

  /// Narrow Android / iPhone SE-class portrait — catches overflow early.
  smallPhone(Size(320, 640)),

  /// 12.9" iPad portrait.
  tablet(Size(1024, 1366));

  const QaDevice(this.size);
  final Size size;
}

/// Sets the test view to [size] logical pixels at [pixelRatio], reset on
/// teardown.
void setTestViewSize(
  WidgetTester tester,
  Size size, {
  double pixelRatio = 2.0,
}) {
  tester.view.physicalSize = size * pixelRatio;
  tester.view.devicePixelRatio = pixelRatio;
  addTearDown(tester.view.reset);
}

/// Pumps [child] as the home of a themed MaterialApp inside a ProviderScope.
///
/// - [overrides] are added after the defaults, so they win.
///   `sharedPreferencesProvider` is always overridden with a mock instance
///   seeded from [prefs].
/// - [device] (default phone) or an explicit [size] sets the view; pass
///   `useTestViewSize: false` to keep the default 800x600 view.
/// - [themeMode] picks light (default) or dark from the real app theme.
/// - [textScale] applies the in-app text size setting the way app.dart does
///   (a linear TextScaler over the whole app).
/// - [settle], when given, pumps that much extra time after the first frame
///   (a fixed pump, not pumpAndSettle, so endless animations can't hang).
///
/// Returns the SharedPreferences instance so tests can assert on writes.
Future<SharedPreferences> pumpApp(
  WidgetTester tester,
  Widget child, {
  List<Override> overrides = const [],
  QaDevice device = QaDevice.phone,
  Size? size,
  double pixelRatio = 2.0,
  bool useTestViewSize = true,
  Map<String, Object> prefs = const {},
  ThemeMode themeMode = ThemeMode.light,
  double textScale = 1.0,
  Duration? settle,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();

  if (useTestViewSize) {
    setTestViewSize(tester, size ?? device.size, pixelRatio: pixelRatio);
  }

  // The app sets this global palette from the effective brightness (app.dart);
  // widgets that read ThemeConstants directly need it to match.
  ThemeConstants.useBrightness(
    themeMode == ThemeMode.dark ? Brightness.dark : Brightness.light,
  );
  addTearDown(() => ThemeConstants.useBrightness(Brightness.light));

  await tester.pumpWidget(
    RepaintBoundary(
      key: qaRootKey,
      child: ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(sp),
          ...overrides,
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: qaThemeFor(Brightness.light),
          darkTheme: qaThemeFor(Brightness.dark),
          themeMode: themeMode,
          builder: textScale == 1.0
              ? null
              : (context, app) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(textScale),
                    ),
                    child: app ?? const SizedBox.shrink(),
                  ),
          home: child,
        ),
      ),
    ),
  );

  if (settle != null) {
    await tester.pump();
    await tester.pump(settle);
  }
  return sp;
}

/// Pumps [frames] frames [step] apart — the usual "let the FutureProviders
/// resolve" loop, without pumpAndSettle's hang on endless animations.
Future<void> pumpFrames(
  WidgetTester tester, {
  int frames = 4,
  Duration step = const Duration(milliseconds: 150),
}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(step);
  }
}
