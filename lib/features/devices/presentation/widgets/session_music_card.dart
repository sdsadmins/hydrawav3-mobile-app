import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../musics/presentation/providers/music_provider.dart';
import '../../../musics/services/session_music_controller.dart';
import 'ref_palette.dart';

/// University-only "Session music" toggle card — a 1:1 port of the cowork-os
/// handoff `togglecard` (`app.js` → `renderSetup`, `styles.css`), backed by the
/// REAL session-music feature (`sessionMusicControllerProvider` +
/// `musicListProvider`). Same functionality (pick / change / clear an
/// Atmosphere track, looping while the session runs) — design only.
class SessionMusicCard extends ConsumerWidget {
  const SessionMusicCard({super.key});

  void _openPicker(BuildContext context, WidgetRef ref, RefPalette p) {
    final controller = ref.read(sessionMusicControllerProvider.notifier);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, r, _) {
          final music = r.watch(sessionMusicControllerProvider);
          final tracksAsync = r.watch(musicListProvider);
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: p.line,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    'Session music',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: p.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Loops quietly while the session runs.',
                    style: TextStyle(fontSize: 13, color: p.ink3),
                  ),
                  const SizedBox(height: 14),
                  // "No music" — clears the selection.
                  _TrackRow(
                    palette: p,
                    icon: Icons.music_off_rounded,
                    label: 'No music',
                    selected: !music.hasTrack,
                    onTap: () {
                      controller.clear();
                      Navigator.of(ctx).pop();
                    },
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 340),
                    child: tracksAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      ),
                      error: (e, _) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Failed to load tracks: $e',
                          style: TextStyle(fontSize: 13, color: p.ink2),
                        ),
                      ),
                      data: (tracks) {
                        if (tracks.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              'No tracks available.',
                              style: TextStyle(fontSize: 13, color: p.ink2),
                            ),
                          );
                        }
                        return SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final t in tracks)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _TrackRow(
                                    palette: p,
                                    icon: Icons.music_note_rounded,
                                    label: t.name,
                                    selected: music.activeTrackId == t.id,
                                    enabled: t.isPlayable,
                                    onTap: () {
                                      controller.selectTrack(t);
                                      Navigator.of(ctx).pop();
                                    },
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = RefPalette.of(context);
    final music = ref.watch(sessionMusicControllerProvider);
    final controller = ref.read(sessionMusicControllerProvider.notifier);
    final on = music.hasTrack;

    // .togglecard
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: p.card,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: p.cardline, width: 1.5),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 26,
            child: Icon(Icons.music_note_rounded, size: 18, color: p.copperInk),
          ),
          const SizedBox(width: 4),
          // Tap the label to choose / change the track.
          Expanded(
            child: InkWell(
              onTap: () => _openPicker(context, ref, p),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Session music',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                      color: p.ink,
                    ),
                  ),
                  Text(
                    on
                        ? '${music.activeTrackName ?? 'Track'}, tap to change'
                        : 'Off, tap to choose a track',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, height: 1.4, color: p.ink3),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // .sw — on when a track is selected.
          GestureDetector(
            onTap: () {
              if (on) {
                controller.clear();
              } else {
                _openPicker(context, ref, p);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 46,
              height: 27,
              decoration: BoxDecoration(
                color: on ? p.copper : p.bg2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: on ? p.copper : p.line),
              ),
              child: AnimatedAlign(
                duration: const Duration(milliseconds: 180),
                alignment: on ? Alignment.centerRight : Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Container(
                    width: 19,
                    height: 19,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Color(0x47000000),
                          blurRadius: 3,
                          offset: Offset(0, 1),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrackRow extends StatelessWidget {
  final RefPalette palette;
  final IconData icon;
  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;
  const _TrackRow({
    required this.palette,
    required this.icon,
    required this.label,
    required this.selected,
    this.enabled = true,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
        color: selected ? p.tanSoft : p.card2,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: enabled ? onTap : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: selected ? p.copper : p.cardline,
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Icon(icon,
                    size: 18,
                    color: selected ? p.copperInk : p.ink2),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: p.ink,
                    ),
                  ),
                ),
                if (selected)
                  Icon(Icons.check_circle_rounded, size: 20, color: p.copper),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
