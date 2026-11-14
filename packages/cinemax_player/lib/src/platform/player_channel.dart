import 'package:flutter/services.dart';

/// Thin wrapper over the platform channels implemented in Kotlin.
class CinemaxPlayerChannel {
  CinemaxPlayerChannel._();

  static const MethodChannel _channel = MethodChannel('cinemax_player');

  static Future<int> create(Map<String, Object?> args) async {
    final id = await _channel.invokeMethod<int>('create', args);
    if (id == null) {
      throw PlatformException(
        code: 'create_failed',
        message: 'Native player was not created',
      );
    }
    return id;
  }

  static Future<void> call(
    int id,
    String method, [
    Map<String, Object?> args = const <String, Object?>{},
  ]) {
    return _channel.invokeMethod<void>(method, <String, Object?>{
      'id': id,
      ...args,
    });
  }

  static Future<bool> enterPip(double aspect) async {
    final ok = await _channel.invokeMethod<bool>(
      'enterPip',
      <String, Object?>{'aspect': aspect},
    );
    return ok ?? false;
  }

  static Stream<dynamic> events(int id) {
    return EventChannel('cinemax_player/events/$id').receiveBroadcastStream();
  }
}
