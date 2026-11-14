/// Playback and UI settings the host app can tune.
class CinemaxPlayerConfig {
  const CinemaxPlayerConfig({
    this.autoPlay = true,
    this.startPosition = Duration.zero,
    this.speed = 1.0,
    this.preferredAudioLanguage,
    this.preferredSubtitleLanguage,
    this.controlsTimeout = const Duration(seconds: 4),
    this.seekStep = const Duration(seconds: 10),
    this.pauseOnBackground = true,
    this.showSeriesButton = true,
    this.forceLandscape = true,
    this.markers = const <Duration>[],
  });

  final bool autoPlay;

  /// Where to start (resume position).
  final Duration startPosition;
  final double speed;

  /// Language codes such as `ar`, `en`. Null keeps the stream default.
  final String? preferredAudioLanguage;

  /// Null starts with subtitles off.
  final String? preferredSubtitleLanguage;

  /// How long the controls stay visible while playing.
  final Duration controlsTimeout;

  /// Double-tap left/right seek amount.
  final Duration seekStep;
  final bool pauseOnBackground;
  final bool showSeriesButton;

  /// Used by CinemaxPlayerScreen: lock the screen to landscape.
  final bool forceLandscape;

  /// Small yellow ticks drawn on the progress bar (intro, recap, ...).
  final List<Duration> markers;

  CinemaxPlayerConfig copyWith({bool? autoPlay, Duration? startPosition}) {
    return CinemaxPlayerConfig(
      autoPlay: autoPlay ?? this.autoPlay,
      startPosition: startPosition ?? this.startPosition,
      speed: speed,
      preferredAudioLanguage: preferredAudioLanguage,
      preferredSubtitleLanguage: preferredSubtitleLanguage,
      controlsTimeout: controlsTimeout,
      seekStep: seekStep,
      pauseOnBackground: pauseOnBackground,
      showSeriesButton: showSeriesButton,
      forceLandscape: forceLandscape,
      markers: markers,
    );
  }
}
