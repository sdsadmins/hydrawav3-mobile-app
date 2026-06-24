import 'dart:async';
import 'dart:io';

import 'package:logger/logger.dart' as log;
import 'package:path_provider/path_provider.dart';

// TEMP-LOG-EXPORT: file sink for [appLogger]. Persists every log line to disk so
// it can be exported and shared for field debugging (see `log_export.dart`).
// LOCAL only — nothing is transmitted unless the user explicitly shares the
// file, so no store privacy-disclosure impact. To remove: delete everything
// tagged TEMP-LOG-EXPORT and drop the `output:` arg below (logger reverts to
// console-only, its original behavior).
final _fileOutput = _FileLogOutput(); // TEMP-LOG-EXPORT

final appLogger = log.Logger(
  printer: log.PrettyPrinter(
    methodCount: 2,
    errorMethodCount: 8,
    lineLength: 120,
    colors: true,
    printEmojis: true,
    printTime: true,
  ),
  // TEMP-LOG-EXPORT: tee to console (colored, dev) AND the on-disk file (plain).
  output: log.MultiOutput([log.ConsoleOutput(), _fileOutput]),
);

/// Start persisting logs to a file. Call once at startup (before `runApp`).
/// Best-effort: failures here never block app launch.
Future<void> initFileLogging() => _fileOutput.init(); // TEMP-LOG-EXPORT

/// Absolute path of the current log file, or null if logging hasn't started.
String? get logFilePath => _fileOutput.filePath; // TEMP-LOG-EXPORT

// TEMP-LOG-EXPORT
class _FileLogOutput extends log.LogOutput {
  IOSink? _sink;
  String? _path;

  // Lines captured before the file is opened (path_provider is async, the
  // logger is built synchronously). Bounded so early logging can't grow forever.
  final List<String> _buffer = <String>[];
  static const int _maxBufferLines = 2000;
  static const int _maxFileBytes = 2 * 1024 * 1024; // 2 MB before rotation

  // Strips ANSI color codes the PrettyPrinter adds for the console, so the
  // shared file is plain readable text.
  static final RegExp _ansi = RegExp(r'\x1B\[[0-9;]*m');

  String? get filePath => _path;

  @override
  Future<void> init() async {
    // Idempotent: the logger framework may also call init() at construction
    // (before plugins are ready, where it no-ops via the catch); our explicit
    // startup call then opens the file for real. Guard against a double-open.
    if (_sink != null) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/hydrawav_logs.txt');
      // Rotate: keep one backup so the active file stays small.
      if (await file.exists() && await file.length() > _maxFileBytes) {
        final backup = File('${dir.path}/hydrawav_logs.old.txt');
        if (await backup.exists()) await backup.delete();
        await file.rename(backup.path);
      }
      _path = file.path;
      _sink = file.openWrite(mode: FileMode.append);
      _sink!.writeln('=== log session started ===');
      if (_buffer.isNotEmpty) {
        for (final l in _buffer) {
          _sink!.writeln(l);
        }
        _buffer.clear();
      }
    } catch (_) {
      // File logging is best-effort; never break startup.
    }
  }

  @override
  void output(log.OutputEvent event) {
    final sink = _sink;
    if (sink == null) {
      for (final line in event.lines) {
        _buffer.add(line.replaceAll(_ansi, ''));
      }
      if (_buffer.length > _maxBufferLines) {
        _buffer.removeRange(0, _buffer.length - _maxBufferLines);
      }
      return;
    }
    for (final line in event.lines) {
      sink.writeln(line.replaceAll(_ansi, ''));
    }
  }
}
