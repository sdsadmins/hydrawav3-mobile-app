// TEMP-LOG-EXPORT: internal-test only. Lets a tester share the on-disk log file
// (written by logger.dart) via the native share sheet so we can diagnose field
// issues. Delete this whole file — and everything tagged TEMP-LOG-EXPORT — when
// the investigation is done.
import 'dart:io';

import 'package:share_plus/share_plus.dart';

import 'logger.dart';

/// Returns false if there is no log file yet (logging hasn't started or the
/// device couldn't open the file).
Future<bool> shareLogFile() async {
  final path = logFilePath;
  if (path == null) return false;
  final file = File(path);
  if (!await file.exists()) return false;
  await Share.shareXFiles(
    [XFile(path, mimeType: 'text/plain')],
    subject: 'Hydrawav app logs',
    text: 'Hydrawav diagnostic logs',
  );
  return true;
}
