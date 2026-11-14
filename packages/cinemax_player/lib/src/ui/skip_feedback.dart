import 'package:flutter/material.dart';

import 'cx_icon.dart';
import 'cx_style.dart';

/// Feedback shown on the tapped half of the screen after a double-tap seek:
/// a soft half-ellipse that fades in and out, the double-chevron icon sliding
/// in the seek direction, and the skipped seconds underneath.
///
/// Give it a new [key] for every tap to replay the animation.
class CxSkipFeedback extends StatefulWidget {
  const CxSkipFeedback({
    super.key,
    required this.forward,
    required this.seconds,
  });

  final bool forward;
  final int seconds;

  @override
  State<CxSkipFeedback> createState() => _CxSkipFeedbackState();
}

class _CxSkipFeedbackState extends State<CxSkipFeedback>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  )..forward();

  static final Animatable<double> _fade = TweenSequence<double>(
    <TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0, end: 1)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 20,
      ),
      TweenSequenceItem<double>(tween: ConstantTween<double>(1), weight: 50),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ],
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dir = widget.forward ? 1.0 : -1.0;
    return LayoutBuilder(
      builder: (context, cons) {
        final w = cons.maxWidth * 0.45;
        final h = cons.maxHeight;
        return Align(
          alignment:
              widget.forward ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              final t = _ctrl.value;
              final opacity = _fade.transform(t);
              final grow = Curves.easeOutCubic.transform(t.clamp(0.0, 0.4) / 0.4);
              final slide = Curves.easeOut.transform(t) * 18 * dir;
              final radius = Radius.elliptical(w, h / 2);
              return Opacity(
                opacity: opacity,
                child: Container(
                  width: w * (0.8 + 0.2 * grow),
                  height: h,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0x26FFFFFF),
                    borderRadius: widget.forward
                        ? BorderRadius.horizontal(left: radius)
                        : BorderRadius.horizontal(right: radius),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Transform.translate(
                        offset: Offset(slide, 0),
                        child: CxIcon(
                          widget.forward ? 'forward' : 'rewind',
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${widget.seconds}s',
                        style: CxStyle.barLabel.copyWith(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
