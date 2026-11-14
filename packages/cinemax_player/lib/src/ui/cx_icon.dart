import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Outline icon from assets/icons/<name>.svg, tinted with [color].
///
/// To use the designer's original vector icons, overwrite the SVG files in
/// assets/icons with the same file names. No Dart change is needed.
class CxIcon extends StatelessWidget {
  const CxIcon(
    this.name, {
    super.key,
    this.size = 24,
    this.color = Colors.white,
  });

  final String name;
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.asset(
      'assets/icons/$name.svg',
      package: 'cinemax_player',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
    );
  }
}
