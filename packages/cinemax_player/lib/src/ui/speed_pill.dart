import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import 'cx_icon.dart';

/// Pill shown at the top center while the user holds the screen to change the
/// playback speed, for example "2.0x ▶▶".
class CxSpeedPill extends StatelessWidget {
  const CxSpeedPill({super.key, required this.speed});

  final double speed;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 120),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF35363A),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${speed.toStringAsFixed(1)}x',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                height: 1.2,
                decoration: TextDecoration.none,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 8),
            const CxIcon('forward', size: 16),
          ],
        ),
      ),
    );
  }
}
