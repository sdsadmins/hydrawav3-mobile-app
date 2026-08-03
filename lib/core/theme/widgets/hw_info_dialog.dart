import 'package:flutter/material.dart';

import '../../constants/theme_constants.dart';

/// The app's standard one-message info bubble: a tinted circular icon, a bold
/// title, a short body and one full-width dismiss button.
///
/// Extracted verbatim from the in-place dialog the Devices screen already used
/// for its "Advanced is a premium feature" prompt, so every popup in the app
/// keeps the same shape (surface background, 18px radius, 40px inset, 48px icon
/// disc, 44px action button).
///
/// Returns when the dialog closes — by the button, the barrier, or a
/// programmatic pop through [onDialogContext].
Future<void> showHwInfoDialog(
  BuildContext context, {
  required IconData icon,
  required String title,
  required String message,
  String actionLabel = 'Got it',
  Color? iconColor,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  VoidCallback? onAction,

  /// Receives this dialog route's OWN context. Keep it if the condition behind
  /// the message can resolve itself and you want to take the dialog away:
  /// `if (ctx.mounted) Navigator.of(ctx).pop()`. Popping through the caller's
  /// context instead would pop whatever happens to be on top once the user has
  /// already dismissed this one — `ctx.mounted` goes false the moment this route
  /// is gone, which makes the check exact.
  ValueChanged<BuildContext>? onDialogContext,
}) {
  final tint = iconColor ?? ThemeConstants.accent;
  return showDialog<void>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black.withValues(alpha: 0.25),
    // The session screen and the shell tabs both sit under nested navigators;
    // without this the dialog can render behind the bottom nav.
    useRootNavigator: useRootNavigator,
    builder: (ctx) {
      onDialogContext?.call(ctx);
      return Dialog(
        backgroundColor: ThemeConstants.surface,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: tint.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tint, size: 24),
              ),
              const SizedBox(height: 14),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: ThemeConstants.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: ThemeConstants.textSecondary,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    onAction?.call();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ThemeConstants.accent,
                    foregroundColor: ThemeConstants.onAccent,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    actionLabel,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
