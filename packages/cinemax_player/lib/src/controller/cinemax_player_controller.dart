import 'dart:async';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/media_source.dart';
import '../models/player_config.dart';
import '../models/player_value.dart';
import '../models/track.dart';
import '../platform/player_channel.dart';

enum CinemaxResizeMode { fit, fill, zoom }

/// Controls one native Media3 player. Create it, call [open], listen to it.
///
/// ```dart
/// final c = CinemaxPlayerController();
/// await c.open(CinemaxMediaSource(url: url));
/// ```
class CinemaxPlayerController extends ChangeNotifier {
  CinemaxPlayerValue _value = const CinemaxPlayerValue();
  int? _id;
  StreamSubscription<dynamic>? _sub;
  bool _disposed = false;
  CinemaxResizeMode _resizeMode = CinemaxResizeMode.fit;
  CinemaxMediaSource? _source;
  CinemaxPlayerConfig _config = const CinemaxPlayerConfig();

  CinemaxPlayerValue get value => _value;

  /// Flutter texture id the video is rendered into. Null before [open].
  int? get textureId => _id;
  CinemaxResizeMode get resizeMode => _resizeMode;

  Duration? _seekStepOverride;

  /// Double-tap seek amount. Starts from [CinemaxPlayerConfig.seekStep] and
  /// keeps the user's choice (More panel) when another episode is opened.
  Duration get seekStep => _seekStepOverride ?? _config.seekStep;

  void setSeekStep(Duration step) {
    _seekStepOverride = step;
    _notify();
  }

  /// Starts (or restarts with another episode) playback of [source].
  Future<void> open(
    CinemaxMediaSource source, {
    CinemaxPlayerConfig config = const CinemaxPlayerConfig(),
  }) async {
    await _release();
    if (_disposed) return;
    _source = source;
    _config = config;
    _value = CinemaxPlayerValue(speed: config.speed);
    _notify();
    try {
      final id = await CinemaxPlayerChannel.create(<String, Object?>{
        'url': source.url,
        'headers': source.headers,
        'mimeType': source.mimeType,
        'userAgent': source.userAgent,
        'startPositionMs': config.startPosition.inMilliseconds,
        'autoPlay': config.autoPlay,
        'speed': config.speed,
        'preferredAudioLanguage': config.preferredAudioLanguage,
        'preferredSubtitleLanguage': config.preferredSubtitleLanguage,
        'subtitles': source.subtitles.map((s) => s.toMap()).toList(),
      });
      if (_disposed) {
        unawaited(CinemaxPlayerChannel.call(id, 'dispose'));
        return;
      }
      _id = id;
      _sub = CinemaxPlayerChannel.events(id).listen(
        _onEvent,
        onError: (Object e) {
          _value = _value.copyWith(error: e.toString());
          _notify();
        },
      );
      _value = _value.copyWith(isInitialized: true);
      _notify();
    } on PlatformException catch (e) {
      _value = _value.copyWith(error: e.message ?? e.code);
      _notify();
    }
  }

  /// Re-opens the last source from the last known position.
  Future<void> retry() async {
    final s = _source;
    if (s == null) return;
    await open(
      s,
      config: _config.copyWith(
        startPosition: _value.position,
        autoPlay: true,
      ),
    );
  }

  Future<void> play() => _call('play');
  Future<void> pause() => _call('pause');

  Future<void> togglePlay() => _value.isPlaying ? pause() : play();

  Future<void> seekTo(Duration position) {
    var ms = position.inMilliseconds;
    final total = _value.duration.inMilliseconds;
    if (ms < 0) ms = 0;
    if (total > 0 && ms > total) ms = total;
    _value = _value.copyWith(position: Duration(milliseconds: ms));
    _notify();
    return _call('seekTo', <String, Object?>{'position': ms});
  }

  Future<void> seekBy(Duration delta) => seekTo(_value.position + delta);

  Future<void> setSpeed(double speed) {
    _value = _value.copyWith(speed: speed);
    _notify();
    return _call('setSpeed', <String, Object?>{'speed': speed});
  }

  Future<void> setMuted(bool muted) {
    _value = _value.copyWith(isMuted: muted);
    _notify();
    return _call('setVolume', <String, Object?>{'volume': muted ? 0.0 : 1.0});
  }

  /// Null selects automatic (adaptive) quality.
  Future<void> selectQuality(CinemaxTrack? track) => _call(
        'selectTrack',
        <String, Object?>{'type': 'video', 'trackId': track?.id},
      );

  Future<void> selectAudio(CinemaxTrack track) => _call(
        'selectTrack',
        <String, Object?>{'type': 'audio', 'trackId': track.id},
      );

  /// Null turns subtitles off.
  Future<void> selectSubtitle(CinemaxTrack? track) => _call(
        'selectTrack',
        <String, Object?>{'type': 'text', 'trackId': track?.id},
      );

  void setResizeMode(CinemaxResizeMode mode) {
    _resizeMode = mode;
    _notify();
  }

  /// Enters Android picture-in-picture. Returns false when unsupported.
  Future<bool> enterPip() {
    final Size s = _value.videoSize;
    final aspect = s.isEmpty ? 16 / 9 : s.width / s.height;
    return CinemaxPlayerChannel.enterPip(aspect);
  }

  // ---- internals ----------------------------------------------------------

  Future<void> _call(String method, [Map<String, Object?>? args]) async {
    final id = _id;
    if (id == null || _disposed) return;
    try {
      await CinemaxPlayerChannel.call(
        id,
        method,
        args ?? const <String, Object?>{},
      );
    } on PlatformException catch (e) {
      _value = _value.copyWith(error: e.message ?? e.code);
      _notify();
    }
  }

  void _onEvent(dynamic raw) {
    if (_disposed || raw is! Map) return;
    switch (raw['event']) {
      case 'state':
        _applyState(raw);
      case 'tracks':
        _applyTracks(raw);
      case 'cues':
        _value = _value.copyWith(
          cues: <String>[
            for (final c in (raw['cues'] as List<dynamic>? ?? const <dynamic>[]))
              c.toString(),
          ],
        );
        _notify();
      case 'error':
        _value = _value.copyWith(
          error: (raw['message'] as String?) ?? 'Playback error',
        );
        _notify();
    }
  }

  void _applyState(Map<dynamic, dynamic> m) {
    final w = (m['width'] as num?)?.toDouble() ?? 0;
    final h = (m['height'] as num?)?.toDouble() ?? 0;
    final state = switch (m['playbackState']) {
      'buffering' => CinemaxPlaybackState.buffering,
      'ready' => CinemaxPlaybackState.ready,
      'ended' => CinemaxPlaybackState.ended,
      _ => CinemaxPlaybackState.idle,
    };
    _value = _value.copyWith(
      isPlaying: m['isPlaying'] == true,
      state: state,
      position: Duration(milliseconds: (m['position'] as num?)?.toInt() ?? 0),
      duration: Duration(milliseconds: (m['duration'] as num?)?.toInt() ?? 0),
      buffered: Duration(milliseconds: (m['buffered'] as num?)?.toInt() ?? 0),
      videoSize: (w > 0 && h > 0) ? Size(w, h) : null,
      speed: (m['speed'] as num?)?.toDouble(),
      isMuted: ((m['volume'] as num?)?.toDouble() ?? 1.0) == 0.0,
    );
    _notify();
  }

  void _applyTracks(Map<dynamic, dynamic> m) {
    final all = <CinemaxTrack>[
      for (final t in (m['tracks'] as List<dynamic>? ?? const <dynamic>[]))
        CinemaxTrack.fromMap(Map<Object?, Object?>.from(t as Map)),
    ];
    _value = _value.copyWith(
      videoTracks: all.where((t) => t.type == CinemaxTrackType.video).toList(),
      audioTracks: all.where((t) => t.type == CinemaxTrackType.audio).toList(),
      textTracks: all.where((t) => t.type == CinemaxTrackType.text).toList(),
      textDisabled: m['textDisabled'] != false,
      videoAuto: m['videoAuto'] != false,
    );
    _notify();
  }

  Future<void> _release() async {
    await _sub?.cancel();
    _sub = null;
    final id = _id;
    _id = null;
    if (id != null) {
      try {
        await CinemaxPlayerChannel.call(id, 'dispose');
      } on PlatformException {
        // Already gone.
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_release());
    super.dispose();
  }
}
