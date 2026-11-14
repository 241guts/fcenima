import 'package:flutter/services.dart';

/// Links opened from other apps ("Open with", share sheet, browser links).
///
/// Android only. [initialLink] is the link that launched the app (read it
/// once at startup); [linkStream] delivers links that arrive while the app is
/// already running.
class CinemaxLinks {
  CinemaxLinks._();

  static const MethodChannel _method = MethodChannel('cinemax_player');
  static const EventChannel _events = EventChannel('cinemax_player/links');

  static Future<String?> initialLink() async {
    try {
      return await _method.invokeMethod<String>('getInitialLink');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Stream<String> get linkStream => _events
      .receiveBroadcastStream()
      .where((dynamic e) => e is String && e.isNotEmpty)
      .map((dynamic e) => e as String);
}
