import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controller/cinemax_player_controller.dart';
import '../models/strings.dart';
import '../models/track.dart';
import 'cx_style.dart';

/// Opens a right-side panel (used for Quality, Audio & Subtitles, More).
Future<void> showCxPanel(
  BuildContext context, {
  required double width,
  required WidgetBuilder builder,
}) {
  final screen = MediaQuery.of(context).size;
  final w = math.min(width, screen.width * 0.7);
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Colors.black45,
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (ctx, _, __) {
      return Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: CxStyle.panel,
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(16),
          ),
          child: SizedBox(
            width: w,
            height: double.infinity,
            child: SafeArea(child: builder(ctx)),
          ),
        ),
      );
    },
    transitionBuilder: (ctx, anim, _, child) {
      return SlideTransition(
        position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
            .animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      );
    },
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xB3FFFFFF),
                  fontSize: 14,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
            if (selected)
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: CxStyle.crimson,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? CxStyle.crimson : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? CxStyle.crimson : const Color(0x66FFFFFF),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }
}

/// Quality list: Auto + one entry per available height.
class QualityPanel extends StatelessWidget {
  const QualityPanel({super.key, required this.controller, required this.strings});

  final CinemaxPlayerController controller;
  final CinemaxPlayerStrings strings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final v = controller.value;
        final byHeight = <int, CinemaxTrack>{};
        for (final t in v.videoTracks) {
          final h = t.height ?? 0;
          final old = byHeight[h];
          if (old == null || (t.bitrate ?? 0) > (old.bitrate ?? 0)) {
            byHeight[h] = t;
          }
        }
        final tracks = byHeight.values.toList()
          ..sort((a, b) => (b.height ?? 0).compareTo(a.height ?? 0));
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ListView(
            children: [
              _Heading(strings.quality),
              _OptionTile(
                label: strings.auto,
                selected: v.videoAuto,
                onTap: () {
                  controller.selectQuality(null);
                  Navigator.of(context).pop();
                },
              ),
              for (final t in tracks)
                _OptionTile(
                  label: t.displayName,
                  selected: !v.videoAuto && t.selected,
                  onTap: () {
                    controller.selectQuality(t);
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

/// Two columns: audio languages and subtitles (with Off).
class AudioSubtitlesPanel extends StatelessWidget {
  const AudioSubtitlesPanel({
    super.key,
    required this.controller,
    required this.strings,
  });

  final CinemaxPlayerController controller;
  final CinemaxPlayerStrings strings;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final v = controller.value;
        final noText = v.textDisabled || !v.textTracks.any((t) => t.selected);
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: ListView(
                  children: [
                    _Heading(strings.audio),
                    if (v.audioTracks.isEmpty)
                      _OptionTile(
                        label: strings.noOptions,
                        selected: false,
                        onTap: () {},
                      ),
                    for (final t in v.audioTracks)
                      _OptionTile(
                        label: t.displayName,
                        selected: t.selected,
                        onTap: () => controller.selectAudio(t),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ListView(
                  children: [
                    _Heading(strings.subtitles),
                    _OptionTile(
                      label: strings.off,
                      selected: noText,
                      onTap: () => controller.selectSubtitle(null),
                    ),
                    for (final t in v.textTracks)
                      _OptionTile(
                        label: t.displayName,
                        selected: !v.textDisabled && t.selected,
                        onTap: () => controller.selectSubtitle(t),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Built-in "More" panel: playback speed and aspect ratio.
class MorePanel extends StatelessWidget {
  const MorePanel({super.key, required this.controller, required this.strings});

  final CinemaxPlayerController controller;
  final CinemaxPlayerStrings strings;

  static const List<double> _speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  static const List<int> _seekSteps = <int>[5, 10, 15];

  String _speedLabel(double s) => s == s.roundToDouble() ? '${s.toInt()}x' : '${s}x';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final v = controller.value;
        final mode = controller.resizeMode;
        final modes = <CinemaxResizeMode, String>{
          CinemaxResizeMode.fit: strings.fit,
          CinemaxResizeMode.fill: strings.fill,
          CinemaxResizeMode.zoom: strings.zoom,
        };
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: ListView(
            children: [
              _Heading(strings.speed),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in _speeds)
                    _Chip(
                      label: _speedLabel(s),
                      selected: (v.speed - s).abs() < 0.01,
                      onTap: () => controller.setSpeed(s),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _Heading(strings.aspectRatio),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final e in modes.entries)
                    _Chip(
                      label: e.value,
                      selected: mode == e.key,
                      onTap: () => controller.setResizeMode(e.key),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              _Heading(strings.seekStep),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final n in _seekSteps)
                    _Chip(
                      label: '${n}s',
                      selected: controller.seekStep.inSeconds == n,
                      onTap: () => controller.setSeekStep(Duration(seconds: n)),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
