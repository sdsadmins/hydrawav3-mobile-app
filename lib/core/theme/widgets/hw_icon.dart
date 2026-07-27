import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Asset paths for the handoff icon set (`IC` in the UI spec's `app.js`).
///
/// Every icon is a 24×24 stroke drawing. Stroke widths are deliberately varied
/// (most `2`, [arrow]/[guest] `2.2`, [clock]/[x] `2.4`, [caret] `2.6`,
/// [check] `3`) — they only read as one family if kept exactly as authored.
class HwIcons {
  HwIcons._();

  static const String _d = 'assets/icons/hw';

  // Bottom nav
  static const String home = '$_d/home.svg';
  static const String bolt = '$_d/bolt.svg';
  static const String assistant = '$_d/assistant.svg';
  static const String users = '$_d/users.svg';
  static const String more = '$_d/more.svg';

  // Chrome
  static const String back = '$_d/back.svg';
  static const String rotate = '$_d/rotate.svg';

  // Hub
  static const String wave = '$_d/wave.svg';
  static const String arrow = '$_d/arrow.svg';
  static const String chev = '$_d/chev.svg';
  static const String caret = '$_d/caret.svg';
  static const String check = '$_d/check.svg';
  static const String sliders = '$_d/sliders.svg';
  static const String offline = '$_d/offline.svg';
  static const String chat = '$_d/chat.svg';
  static const String play = '$_d/play.svg';
  static const String target = '$_d/target.svg';
  static const String chart = '$_d/chart.svg';
  static const String clock = '$_d/clock.svg';
  static const String star = '$_d/star.svg';
  static const String flask = '$_d/flask.svg';
  static const String book = '$_d/book.svg';
  static const String phone = '$_d/phone.svg';
  static const String briefcase = '$_d/briefcase.svg';
  static const String bag = '$_d/bag.svg';
  static const String drag = '$_d/drag.svg';
  static const String x = '$_d/x.svg';

  // More
  static const String pencil = '$_d/pencil.svg';
  static const String building = '$_d/building.svg';
  static const String sun = '$_d/sun.svg';
  static const String moon = '$_d/moon.svg';
  static const String bot = '$_d/bot.svg';
  static const String note = '$_d/note.svg';

  /// Baked copper (`#A87B5C`) in both themes — the spec fixes this one
  /// deliberately (Principles §2: "Guest = copper person mark"). Render it
  /// without a [HwIcon.color] so the bake survives.
  static const String guest = '$_d/guest.svg';

  static const String key = '$_d/key.svg';
  static const String bell = '$_d/bell.svg';
  static const String scale = '$_d/scale.svg';
  static const String gear = '$_d/gear.svg';
  static const String trash = '$_d/trash.svg';
  static const String doc = '$_d/doc.svg';
}

/// Renders a [HwIcons] asset at [size], tinted to [color].
///
/// Pass `color: null` for icons whose colour is baked into the file
/// ([HwIcons.guest], sport marks) so the tint doesn't flatten them.
class HwIcon extends StatelessWidget {
  final String asset;
  final double size;
  final Color? color;

  const HwIcon(this.asset, {super.key, this.size = 20, this.color});

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      asset,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}
