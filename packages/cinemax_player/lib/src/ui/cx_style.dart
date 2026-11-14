import 'package:flutter/material.dart';

/// Colors and text styles taken from the design.
class CxStyle {
  CxStyle._();

  static const Color crimson = Color(0xFFE5163F);
  static const Color marker = Color(0xFFE9C646);
  static const Color track = Color(0x47FFFFFF);
  static const Color buffered = Color(0x73FFFFFF);
  static const Color panel = Color(0xF2101114);

  static const TextStyle title = TextStyle(
    color: Colors.white,
    fontSize: 15,
    fontWeight: FontWeight.w700,
    height: 1.2,
    decoration: TextDecoration.none,
  );

  static const TextStyle subtitle = TextStyle(
    color: Color(0xB3FFFFFF),
    fontSize: 12,
    fontWeight: FontWeight.w400,
    height: 1.2,
    decoration: TextDecoration.none,
  );

  static const TextStyle barLabel = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.2,
    decoration: TextDecoration.none,
  );
}
