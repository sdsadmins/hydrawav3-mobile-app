// QA screenshot helpers for widget tests.
//
// NAMING CONVENTION — every QA test's description starts with its catalog id
// in square brackets, then a short behaviour statement:
//
//   qaTestWidgets('[STK-04] break counts down', (tester) async { ... });
//
// The id ties the test (and its failure screenshot) back to the QA catalog
// entry; the runner greps for `[XXX-NN]` to map results to the catalog.
//
// What this file provides:
//
// - [qaTestWidgets] — a drop-in `testWidgets` wrapper. If the body throws, an
//   `expect` fails, or a FlutterError (overflow, build error...) is still
//   pending when the body returns, it captures the current frame as a PNG at
//   `build/qa/screens/<sanitised description>.png` and then fails the test
//   exactly as it would have anyway (the original error is rethrown /
//   re-reported, never swallowed).
// - [qaSnap] — an explicit step screenshot: `await qaSnap(tester, 'STK-04 paused')`.
// - [loadAppFonts] — registers Roboto (from the Flutter SDK cache,
//   `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts`) and MaterialIcons so
//   screenshots show real glyphs instead of the test font's boxes. Call it in
//   `setUpAll(loadAppFonts)`. Real fonts change text metrics, so only use it in
//   tests whose expectations were written with real fonts. A missing font
//   directory is reported once and otherwise ignored.
//
// Pump screens with `pumpApp` (pump_app.dart): it wraps the app in a
// RepaintBoundary keyed `qaRootKey`, which is what gets captured. Without it
// the first RepaintBoundary in the tree, then the root layer, is used.
//
// Output directory: `build/qa/screens/` under the package root, or the
// `QA_SCREENS_DIR` environment variable when set.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'pump_app.dart' show qaRealFonts, qaRootKey;

export 'pump_app.dart' show qaRootKey;

/// Where screenshots are written.
String get qaScreensDir {
  final env = Platform.environment['QA_SCREENS_DIR'];
  if (env != null && env.trim().isNotEmpty) return env;
  return '${Directory.current.path}/build/qa/screens';
}

/// `[STK-04] break counts down` -> `STK-04_break_counts_down`.
///
/// Keeps letters, digits, `.`, `_` and `-`; everything else becomes `_`,
/// runs collapse, and the result is capped at 150 characters.
String sanitizeQaName(String name) {
  var s = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  s = s.replaceAll(RegExp(r'_+'), '_').replaceAll(RegExp(r'^[_.]+|_+$'), '');
  if (s.isEmpty) s = 'unnamed';
  return s.length > 150 ? s.substring(0, 150) : s;
}

/// `testWidgets` that screenshots the frame on failure. See the file header.
void qaTestWidgets(
  String description,
  WidgetTesterCallback body, {
  bool? skip,
  Timeout? timeout,
  bool semanticsEnabled = true,
  TestVariant<Object?> variant = const DefaultTestVariant(),
  dynamic tags,
  int? retry,
}) {
  testWidgets(
    description,
    (tester) async {
      // Keep the details of any FlutterError reported during the body so a
      // pending one can be put back after we screenshot it.
      final original = FlutterError.onError;
      FlutterErrorDetails? lastDetails;
      FlutterError.onError = (details) {
        lastDetails = details;
        original?.call(details);
      };

      try {
        await body(tester);
      } catch (_) {
        FlutterError.onError = original;
        await _captureFailure(tester, description);
        rethrow;
      }
      FlutterError.onError = original;

      // A layout/build error the body never took is reported by the binding
      // after the body returns; screenshot it while the bad frame is still
      // up, then hand it back so the test fails with the usual report.
      final pending = tester.takeException();
      if (pending != null) {
        await _captureFailure(tester, description);
        original?.call(
          lastDetails ?? FlutterErrorDetails(exception: pending),
        );
      }
    },
    skip: skip,
    timeout: timeout,
    semanticsEnabled: semanticsEnabled,
    variant: variant,
    tags: tags,
    retry: retry,
  );
}

/// Captures the current frame to `<qaScreensDir>/<sanitised name>.png` and
/// returns the file, or null if nothing could be captured.
Future<File?> qaSnap(WidgetTester tester, String name) async {
  final path = '$qaScreensDir/${sanitizeQaName(name)}.png';
  final bytes = await _capturePng(tester);
  if (bytes == null) return null;
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(bytes);
  return file;
}

Future<void> _captureFailure(WidgetTester tester, String description) async {
  try {
    final file = await qaSnap(tester, description);
    if (file != null) {
      // ignore: avoid_print
      print('qa_snap: failure screenshot -> ${file.path}');
    }
  } catch (e) {
    // Never let the screenshot mask the real failure.
    // ignore: avoid_print
    print('qa_snap: could not capture "$description": $e');
  }
}

RenderRepaintBoundary? _rootBoundary(WidgetTester tester) {
  for (final finder in [
    find.byKey(qaRootKey),
    find.byType(RepaintBoundary),
  ]) {
    final elements = finder.evaluate();
    if (elements.isEmpty) continue;
    final ro = elements.first.renderObject;
    if (ro is RenderRepaintBoundary) return ro;
  }
  return null;
}

Future<Uint8List?> _capturePng(WidgetTester tester) async {
  final boundary = _rootBoundary(tester);

  // A failure mid-frame can leave the boundary unpainted; try one frame so
  // there is something to read. If that frame throws too, give up quietly.
  if (boundary != null && boundary.debugNeedsPaint) {
    try {
      await tester.pump();
    } catch (_) {}
  }

  return tester.runAsync<Uint8List?>(() async {
    ui.Image? image;
    if (boundary != null && !boundary.debugNeedsPaint) {
      image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio.clamp(1.0, 2.0).toDouble(),
      );
    } else {
      // No usable boundary: fall back to the root layer of the view.
      final view = tester.binding.renderViews.first;
      final layer = view.debugLayer;
      if (layer is OffsetLayer) {
        image = await layer.toImage(Offset.zero & view.size);
      }
    }
    if (image == null) return null;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data?.buffer.asUint8List();
  });
}

// ---------------------------------------------------------------------------
// Fonts
// ---------------------------------------------------------------------------

Future<void>? _fontsLoaded;

/// Registers Roboto + MaterialIcons from the Flutter SDK so screenshots are
/// readable. Idempotent; safe to call from several `setUpAll`s.
Future<void> loadAppFonts() {
  TestWidgetsFlutterBinding.ensureInitialized();
  return _fontsLoaded ??= _loadFonts();
}

Future<void> _loadFonts() async {
  final dir = _materialFontsDir();
  if (dir == null) {
    // ignore: avoid_print
    print('qa_snap: material_fonts not found (set FLUTTER_ROOT); '
        'screenshots will use the test font.');
    return;
  }

  Future<ByteData> read(File f) async =>
      ByteData.view(Uint8List.fromList(await f.readAsBytes()).buffer);

  // One family, every weight/style file: the engine picks the face by the
  // font's own weight metadata, so w700 text gets Roboto-Bold, etc.
  final roboto = dir.listSync().whereType<File>().where((f) {
    final n = f.uri.pathSegments.last;
    return n.startsWith('Roboto-') && n.endsWith('.ttf');
  }).toList();
  if (roboto.isNotEmpty) {
    final loader = FontLoader('Roboto');
    for (final f in roboto) {
      loader.addFont(read(f));
    }
    await loader.load();
    // Text whose style names no family at all (component-theme styles such
    // as AppBar titles and button labels are not merged with the theme's
    // fontFamily) uses the test engine's built-in box font, which a
    // FontLoader cannot replace. pumpApp fills in 'Roboto' for those styles
    // once this flag is set, mirroring Android where the system font is
    // Roboto.
    qaRealFonts = true;
  }

  final icons = File('${dir.path}/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(read(icons))).load();
  }
}

/// `$FLUTTER_ROOT/bin/cache/artifacts/material_fonts`, found from the
/// environment or, failing that, from the flutter_tester executable path
/// (`<root>/bin/cache/artifacts/engine/<platform>/flutter_tester`).
Directory? _materialFontsDir() {
  final roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] case final r?) r,
  ];
  final exe = Platform.resolvedExecutable;
  final i =
      exe.indexOf('${Platform.pathSeparator}bin${Platform.pathSeparator}cache');
  if (i > 0) roots.add(exe.substring(0, i));

  for (final root in roots) {
    final d = Directory('$root/bin/cache/artifacts/material_fonts');
    if (d.existsSync()) return d;
  }
  return null;
}
