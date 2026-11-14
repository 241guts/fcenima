import 'dart:ui' show Size;

import 'track.dart';

enum CinemaxPlaybackState { idle, buffering, ready, ended }

/// Immutable snapshot of the player, rebuilt on every native event.
class CinemaxPlayerValue {
  const CinemaxPlayerValue({
    this.isInitialized = false,
    this.isPlaying = false,
    this.state = CinemaxPlaybackState.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.buffered = Duration.zero,
    this.videoSize = Size.zero,
    this.speed = 1.0,
    this.isMuted = false,
    this.error,
    this.videoTracks = const <CinemaxTrack>[],
    this.audioTracks = const <CinemaxTrack>[],
    this.textTracks = const <CinemaxTrack>[],
    this.textDisabled = true,
    this.videoAuto = true,
    this.cues = const <String>[],
  });

  final bool isInitialized;
  final bool isPlaying;
  final CinemaxPlaybackState state;
  final Duration position;
  final Duration duration;
  final Duration buffered;

  /// Display size of the video (pixel aspect ratio applied). Zero until known.
  final Size videoSize;
  final double speed;
  final bool isMuted;
  final String? error;
  final List<CinemaxTrack> videoTracks;
  final List<CinemaxTrack> audioTracks;
  final List<CinemaxTrack> textTracks;
  final bool textDisabled;

  /// True when quality is automatic (adaptive).
  final bool videoAuto;

  /// Subtitle lines that should be on screen right now (empty = none).
  final List<String> cues;

  bool get isBuffering => state == CinemaxPlaybackState.buffering;
  bool get isEnded => state == CinemaxPlaybackState.ended;

  CinemaxPlayerValue copyWith({
    bool? isInitialized,
    bool? isPlaying,
    CinemaxPlaybackState? state,
    Duration? position,
    Duration? duration,
    Duration? buffered,
    Size? videoSize,
    double? speed,
    bool? isMuted,
    String? error,
    bool clearError = false,
    List<CinemaxTrack>? videoTracks,
    List<CinemaxTrack>? audioTracks,
    List<CinemaxTrack>? textTracks,
    bool? textDisabled,
    bool? videoAuto,
    List<String>? cues,
  }) {
    return CinemaxPlayerValue(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      state: state ?? this.state,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      buffered: buffered ?? this.buffered,
      videoSize: videoSize ?? this.videoSize,
      speed: speed ?? this.speed,
      isMuted: isMuted ?? this.isMuted,
      error: clearError ? null : (error ?? this.error),
      videoTracks: videoTracks ?? this.videoTracks,
      audioTracks: audioTracks ?? this.audioTracks,
      textTracks: textTracks ?? this.textTracks,
      textDisabled: textDisabled ?? this.textDisabled,
      videoAuto: videoAuto ?? this.videoAuto,
      cues: cues ?? this.cues,
    );
  }
}
