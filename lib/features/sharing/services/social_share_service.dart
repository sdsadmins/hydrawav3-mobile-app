import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../session/domain/session_model.dart';

class SocialShareService {
  /// Generate share text from a session record.
  String generateShareText(SessionRecord record) {
    final duration = Duration(seconds: record.elapsedSeconds);
    final minutes = duration.inMinutes;

    String text = 'Just completed a $minutes-minute ${record.protocolName} '
        'session with Hydrawav3!';

    if (record.discomfortBefore != null && record.discomfortAfter != null) {
      final improvement = record.discomfortBefore! - record.discomfortAfter!;
      if (improvement > 0) {
        text += ' Discomfort reduced by $improvement points.';
      }
    }

    text += '\n\nhttps://hydrawav3.app';
    return text;
  }

  /// Share using the platform share sheet.
  Future<void> share(SessionRecord record) async {
    final text = generateShareText(record);
    await Share.share(text);
  }

  /// Share to a specific platform via URL scheme.
  Future<void> shareToFacebook(SessionRecord record) async {
    final text = Uri.encodeComponent(generateShareText(record));
    final url = 'https://www.facebook.com/sharer/sharer.php?quote=$text';
    await _launchUrl(url);
  }

  Future<void> shareToLinkedIn(SessionRecord record) async {
    final text = Uri.encodeComponent(generateShareText(record));
    final url =
        'https://www.linkedin.com/sharing/share-offsite/?url=https://hydrawav3.app&summary=$text';
    await _launchUrl(url);
  }

  /// Copy share text to clipboard.
  Future<void> copyToClipboard(SessionRecord record) async {
    final text = generateShareText(record);
    await Clipboard.setData(ClipboardData(text: text));
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
