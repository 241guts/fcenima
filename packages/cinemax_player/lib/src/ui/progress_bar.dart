import 'package:flutter/material.dart';

import 'cx_style.dart';

/// Red progress bar with round thumb, buffered range and yellow markers.
class CxProgressBar extends StatefulWidget {
  const CxProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.markers,
    required this.enabled,
    required this.onSeek,
    required this.onScrub,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final List<Duration> markers;
  final bool enabled;
  final ValueChanged<Duration> onSeek;

  /// Reports the dragged position, or null when the drag ends.
  final ValueChanged<Duration?> onScrub;

  @override
  State<CxProgressBar> createState() => _CxProgressBarState();
}

class _CxProgressBarState extends State<CxProgressBar> {
  double? _drag;

  Duration _toDuration(double fraction) => Duration(
        milliseconds: (fraction * widget.duration.inMilliseconds).round(),
      );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final total = widget.duration.inMilliseconds;

        double fractionOf(double dx) =>
            w <= 0 ? 0.0 : (dx / w).clamp(0.0, 1.0).toDouble();

        final played = total <= 0
            ? 0.0
            : (widget.position.inMilliseconds / total).clamp(0.0, 1.0).toDouble();
        final buffered = total <= 0
            ? 0.0
            : (widget.buffered.inMilliseconds / total).clamp(0.0, 1.0).toDouble();

        void startOrUpdate(double dx) {
          if (!widget.enabled) return;
          final f = fractionOf(dx);
          setState(() => _drag = f);
          widget.onScrub(_toDuration(f));
        }

        void end() {
          final f = _drag;
          if (f == null) return;
          setState(() => _drag = null);
          widget.onSeek(_toDuration(f));
          widget.onScrub(null);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            if (!widget.enabled) return;
            widget.onSeek(_toDuration(fractionOf(d.localPosition.dx)));
          },
          onHorizontalDragStart: (d) => startOrUpdate(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => startOrUpdate(d.localPosition.dx),
          onHorizontalDragEnd: (_) => end(),
          onHorizontalDragCancel: end,
          child: SizedBox(
            height: 32,
            width: double.infinity,
            child: CustomPaint(
              painter: _BarPainter(
                played: _drag ?? played,
                buffered: buffered,
                dragging: _drag != null,
                markers: total <= 0
                    ? const <double>[]
                    : <double>[
                        for (final m in widget.markers)
                          if (m.inMilliseconds > 0 && m.inMilliseconds < total)
                            m.inMilliseconds / total,
                      ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.played,
    required this.buffered,
    required this.dragging,
    required this.markers,
  });

  final double played;
  final double buffered;
  final bool dragging;
  final List<double> markers;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final w = size.width;

    final line = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(Offset(0, y), Offset(w, y), line..color = CxStyle.track);
    if (buffered > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(w * buffered, y),
        line..color = CxStyle.buffered,
      );
    }
    if (played > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(w * played, y),
        line..color = CxStyle.crimson,
      );
    }

    final tick = Paint()..color = CxStyle.marker;
    for (final f in markers) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(w * f, y), width: 2.4, height: 6),
          const Radius.circular(1.2),
        ),
        tick,
      );
    }

    canvas.drawCircle(
      Offset(w * played, y),
      dragging ? 8 : 6.5,
      Paint()..color = CxStyle.crimson,
    );
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.played != played ||
      old.buffered != buffered ||
      old.dragging != dragging ||
      old.markers != markers;
}
