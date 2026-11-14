import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../controller/cinemax_player_controller.dart';
import '../models/player_config.dart';
import '../models/player_value.dart';
import '../models/strings.dart';
import '../utils.dart';
import 'cx_icon.dart';
import 'cx_style.dart';
import 'panels.dart';
import 'progress_bar.dart';
import 'skip_feedback.dart';
import 'speed_pill.dart';

/// The player UI (landscape, Netflix-style) on top of a native Media3 player.
///
/// Give it a [CinemaxPlayerController] that you opened with a source.
/// For a ready-made full-screen page use CinemaxPlayerScreen instead.
class CinemaxPlayer extends StatefulWidget {
  const CinemaxPlayer({
    super.key,
    required this.controller,
    required this.title,
    this.subtitle,
    this.config = const CinemaxPlayerConfig(),
    this.strings = const CinemaxPlayerStrings(),
    this.onBack,
    this.onPrevious,
    this.onNext,
    this.onSeries,
    this.onMore,
    this.onCast,
    this.onFullscreenTap,
    this.onEnded,
  });

  final CinemaxPlayerController controller;
  final String title;

  /// Second line under the title, for example "Episode 2 Season 1".
  final String? subtitle;
  final CinemaxPlayerConfig config;
  final CinemaxPlayerStrings strings;

  /// Back arrow. Defaults to Navigator.maybePop.
  final VoidCallback? onBack;

  /// Previous / next episode. A null callback dims the button.
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  /// Opens the episodes list in the host app.
  final VoidCallback? onSeries;

  /// Replaces the built-in "More" panel (speed and aspect ratio).
  final VoidCallback? onMore;

  /// Top-right AirPlay/cast icon.
  final VoidCallback? onCast;

  /// Bottom-right icon. Defaults to [onBack].
  final VoidCallback? onFullscreenTap;

  /// Called once when playback reaches the end.
  final VoidCallback? onEnded;

  @override
  State<CinemaxPlayer> createState() => _CinemaxPlayerState();
}

class _CinemaxPlayerState extends State<CinemaxPlayer>
    with WidgetsBindingObserver {
  bool _visible = true;
  bool _locked = false;
  bool _showUnlock = false;
  bool _panelOpen = false;
  bool _pip = false;
  Duration? _scrub;
  Timer? _hideTimer;
  Timer? _unlockTimer;
  Timer? _skipTimer;
  int _skipSide = 0; // -1 rewind, 1 forward, 0 hidden
  int _skipSeconds = 0;
  int _skipTick = 0;

  // Hold-to-speed-up: starts at 2.0x, drag right up to 5.0x, left down to 0.5x.
  static const double _boostStart = 2.0;
  static const double _boostMin = 0.5;
  static const double _boostMax = 5.0;
  static const double _boostPxPerStep = 10; // logical px per 0.1x
  double? _boostPrev; // speed before the hold; null when not boosting
  double _boostSpeed = _boostStart;
  Offset _lastTap = Offset.zero;
  CinemaxPlaybackState _lastState = CinemaxPlaybackState.idle;
  bool _lastPlaying = false;

  CinemaxPlayerController get _c => widget.controller;
  CinemaxPlayerStrings get _s => widget.strings;

  static const TextStyle _timeStyle = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    decoration: TextDecoration.none,
    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_onController);
  }

  @override
  void didUpdateWidget(covariant CinemaxPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _unlockTimer?.cancel();
    _skipTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _c.removeListener(_onController);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (_pip && mounted) setState(() => _pip = false);
    } else if (state == AppLifecycleState.paused &&
        !_pip &&
        widget.config.pauseOnBackground) {
      _c.pause();
    }
  }

  // ---- state helpers ------------------------------------------------------

  void _onController() {
    final v = _c.value;
    if (v.state == CinemaxPlaybackState.ended &&
        _lastState != CinemaxPlaybackState.ended) {
      widget.onEnded?.call();
      _hideTimer?.cancel();
      if (mounted) setState(() => _visible = true);
    }
    if (v.isPlaying != _lastPlaying) {
      _lastPlaying = v.isPlaying;
      if (v.isPlaying) {
        _scheduleHide();
      } else {
        _hideTimer?.cancel();
      }
    }
    _lastState = v.state;
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    if (!_c.value.isPlaying || _panelOpen || _scrub != null) return;
    _hideTimer = Timer(widget.config.controlsTimeout, () {
      if (!mounted || _panelOpen || _scrub != null) return;
      setState(() => _visible = false);
    });
  }

  void _showControls() {
    setState(() => _visible = true);
    _scheduleHide();
  }

  void _onTap() {
    if (_locked) {
      setState(() => _showUnlock = !_showUnlock);
      if (_showUnlock) _scheduleUnlockHide();
      return;
    }
    if (_visible) {
      _hideTimer?.cancel();
      setState(() => _visible = false);
    } else {
      _showControls();
    }
  }

  void _onDoubleTap() {
    if (_locked) return;
    final w = context.size?.width ?? 0;
    final step = _c.seekStep;
    final forward = _lastTap.dx >= w / 2;
    _c.seekBy(forward ? step : -step);
    _showSkipFeedback(forward, step);
    _showControls();
  }

  void _onBoostStart(LongPressStartDetails d) {
    if (_locked || _pip) return;
    _boostPrev = _c.value.speed;
    _boostSpeed = _boostStart;
    _c.setSpeed(_boostSpeed);
    setState(() {});
  }

  void _onBoostMove(LongPressMoveUpdateDetails d) {
    if (_boostPrev == null) return;
    final steps = (d.localOffsetFromOrigin.dx / _boostPxPerStep).truncate();
    final raw = (_boostStart + steps * 0.1).clamp(_boostMin, _boostMax);
    final s = (raw * 10).round() / 10;
    if ((s - _boostSpeed).abs() < 0.001) return;
    _boostSpeed = s;
    _c.setSpeed(s);
    setState(() {});
  }

  void _onBoostEnd() {
    final prev = _boostPrev;
    if (prev == null) return;
    _boostPrev = null;
    _c.setSpeed(prev);
    if (mounted) setState(() {});
  }

  /// Replays the skip animation; repeated taps on the same side add up.
  void _showSkipFeedback(bool forward, Duration step) {
    final side = forward ? 1 : -1;
    final again = side == _skipSide && (_skipTimer?.isActive ?? false);
    _skipSeconds = again ? _skipSeconds + step.inSeconds : step.inSeconds;
    _skipSide = side;
    _skipTick++;
    _skipTimer?.cancel();
    _skipTimer = Timer(const Duration(milliseconds: 750), () {
      if (mounted) setState(() => _skipSide = 0);
    });
    setState(() {});
  }

  void _back() {
    final cb = widget.onBack;
    if (cb != null) {
      cb();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  void _togglePlay() {
    _c.togglePlay();
    _scheduleHide();
  }

  // ---- lock ---------------------------------------------------------------

  void _lock() {
    _hideTimer?.cancel();
    setState(() {
      _locked = true;
      _visible = false;
      _showUnlock = true;
    });
    _scheduleUnlockHide();
  }

  void _unlock() {
    _unlockTimer?.cancel();
    setState(() {
      _locked = false;
      _showUnlock = false;
      _visible = true;
    });
    _scheduleHide();
  }

  void _scheduleUnlockHide() {
    _unlockTimer?.cancel();
    _unlockTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _showUnlock = false);
    });
  }

  // ---- panels / actions ---------------------------------------------------

  Future<void> _openPanel(double width, WidgetBuilder builder) async {
    _hideTimer?.cancel();
    setState(() => _panelOpen = true);
    await showCxPanel(context, width: width, builder: builder);
    if (!mounted) return;
    setState(() => _panelOpen = false);
    _scheduleHide();
  }

  void _openQuality() => _openPanel(
        320,
        (_) => QualityPanel(controller: _c, strings: _s),
      );

  void _openAudioSubs() => _openPanel(
        560,
        (_) => AudioSubtitlesPanel(controller: _c, strings: _s),
      );

  void _openMore() {
    final cb = widget.onMore;
    if (cb != null) {
      cb();
      return;
    }
    _openPanel(380, (_) => MorePanel(controller: _c, strings: _s));
  }

  Future<void> _enterPip() async {
    // Set first: the lifecycle "paused" event can arrive before the result.
    setState(() => _pip = true);
    final ok = await _c.enterPip();
    if (!ok && mounted) setState(() => _pip = false);
  }

  // ---- build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: _c,
        builder: (context, _) {
          final v = _c.value;
          final showControls = _visible && !_locked && !_pip && v.error == null;
          return ColoredBox(
            color: Colors.black,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildVideo(v),
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _onTap,
                    onDoubleTapDown: (d) => _lastTap = d.localPosition,
                    onDoubleTap: _onDoubleTap,
                    onLongPressStart: _onBoostStart,
                    onLongPressMoveUpdate: _onBoostMove,
                    onLongPressEnd: (_) => _onBoostEnd(),
                    onLongPressCancel: _onBoostEnd,
                  ),
                ),
                Positioned.fill(
                  child: IgnorePointer(
                    ignoring: !showControls,
                    child: AnimatedOpacity(
                      opacity: showControls ? 1 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: _buildControls(v),
                    ),
                  ),
                ),
                if (_skipSide != 0 && !_locked && !_pip)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CxSkipFeedback(
                        key: ValueKey<int>(_skipTick),
                        forward: _skipSide > 0,
                        seconds: _skipSeconds,
                      ),
                    ),
                  ),
                if (v.cues.isNotEmpty && !_pip) _buildCaptions(v, showControls),
                if (_boostPrev != null && !_pip)
                  Positioned(
                    top: 44,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: Center(child: CxSpeedPill(speed: _boostSpeed)),
                    ),
                  ),
                if (_locked && !_pip) _buildLockOverlay(),
                if (v.error != null) _buildError(v),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Subtitle text drawn over the video (white with a dark outline).
  Widget _buildCaptions(CinemaxPlayerValue v, bool controlsShown) {
    final pad = MediaQuery.of(context).padding;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      left: pad.left + 64,
      right: pad.right + 64,
      bottom: controlsShown ? 104 : 22 + math.max(pad.bottom, 0),
      child: IgnorePointer(
        child: Text(
          v.cues.join('\n'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
            height: 1.3,
            decoration: TextDecoration.none,
            shadows: <Shadow>[
              Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(0, 1)),
              Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(1, 0)),
              Shadow(color: Color(0xFF000000), blurRadius: 3, offset: Offset(-1, 0)),
              Shadow(color: Color(0xFF000000), blurRadius: 6),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideo(CinemaxPlayerValue v) {
    final id = _c.textureId;
    if (id == null || !v.isInitialized) return const SizedBox.expand();
    final size = v.videoSize.isEmpty ? const Size(16, 9) : v.videoSize;
    final fit = switch (_c.resizeMode) {
      CinemaxResizeMode.fit => BoxFit.contain,
      CinemaxResizeMode.fill => BoxFit.fill,
      CinemaxResizeMode.zoom => BoxFit.cover,
    };
    return ClipRect(
      child: SizedBox.expand(
        child: FittedBox(
          fit: fit,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: Texture(textureId: id),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(CinemaxPlayerValue v) {
    return LayoutBuilder(
      builder: (context, cons) {
        final pad = MediaQuery.of(context).padding;
        final left = pad.left + 28;
        final right = pad.right + 28;
        final spacing = (cons.maxWidth * 0.135).clamp(84.0, 150.0).toDouble();
        final loading = !v.isInitialized ||
            v.state == CinemaxPlaybackState.buffering ||
            v.state == CinemaxPlaybackState.idle;
        final canSeek = v.duration > Duration.zero;
        return Stack(
          children: [
            const Positioned.fill(child: IgnorePointer(child: _Shade())),
            Positioned(
              top: pad.top + 14,
              left: left,
              right: right,
              child: _buildTopBar(),
            ),
            Center(child: _buildCenter(v, spacing, loading)),
            Positioned(
              left: left,
              right: right,
              bottom: math.max(pad.bottom, 0) + 12,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildProgress(v, canSeek),
                  const SizedBox(height: 6),
                  _buildBottomBar(),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar() {
    final subtitle = widget.subtitle;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Tap(
          onTap: _back,
          padding: const EdgeInsets.fromLTRB(0, 2, 10, 8),
          child: const CxIcon('back', size: 20),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: CxStyle.title,
              ),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: CxStyle.subtitle,
                  ),
                ),
            ],
          ),
        ),
        _Tap(
          onTap: widget.onCast,
          child: const CxIcon('airplay', size: 20),
        ),
        const SizedBox(width: 12),
        _Tap(onTap: _enterPip, child: const CxIcon('pip', size: 20)),
      ],
    );
  }

  Widget _buildCenter(CinemaxPlayerValue v, double spacing, bool loading) {
    final ended = v.state == CinemaxPlaybackState.ended;
    Widget cell(Widget child) =>
        SizedBox(width: spacing, child: Center(child: child));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        cell(
          _Tap(
            onTap: widget.onPrevious,
            child: Opacity(
              opacity: widget.onPrevious == null ? 0.35 : 1,
              child: const CxIcon('previous', size: 30),
            ),
          ),
        ),
        cell(
          loading
              ? const SizedBox(
                  width: 44,
                  height: 44,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                )
              : _Tap(
                  onTap: _togglePlay,
                  child: CxIcon(
                    ended ? 'replay' : (v.isPlaying ? 'pause' : 'play'),
                    size: 44,
                  ),
                ),
        ),
        cell(
          _Tap(
            onTap: widget.onNext,
            child: Opacity(
              opacity: widget.onNext == null ? 0.35 : 1,
              child: const CxIcon('next', size: 30),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgress(CinemaxPlayerValue v, bool canSeek) {
    final shown = _scrub ?? v.position;
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(formatDuration(shown), style: _timeStyle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: CxProgressBar(
            position: v.position,
            duration: v.duration,
            buffered: v.buffered,
            markers: widget.config.markers,
            enabled: canSeek,
            onScrub: (d) {
              if (d != null) _hideTimer?.cancel();
              setState(() => _scrub = d);
            },
            onSeek: (d) {
              _c.seekTo(d);
              _scheduleHide();
            },
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          child: Text(
            formatDuration(v.duration),
            textAlign: TextAlign.right,
            style: _timeStyle,
          ),
        ),
        const SizedBox(width: 10),
        _Tap(
          onTap: widget.onFullscreenTap ?? _back,
          padding: const EdgeInsets.all(6),
          child: const CxIcon('exit_fullscreen', size: 20),
        ),
      ],
    );
  }

  Widget _buildBottomBar() {
    final items = <Widget>[
      _BarItem(icon: 'unlock', label: _s.block, onTap: _lock),
      _BarItem(icon: 'more', label: _s.more, onTap: _openMore),
      if (widget.config.showSeriesButton)
        _BarItem(icon: 'series', label: _s.series, onTap: widget.onSeries),
      _BarItem(icon: 'settings', label: _s.quality, onTap: _openQuality),
      _BarItem(
        icon: 'subtitles',
        label: _s.audioAndSubtitles,
        onTap: _openAudioSubs,
      ),
    ];
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 30),
            items[i],
          ],
        ],
      ),
    );
  }

  Widget _buildLockOverlay() {
    final pad = MediaQuery.of(context).padding;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_showUnlock,
        child: AnimatedOpacity(
          opacity: _showUnlock ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: EdgeInsets.only(left: pad.left + 28),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _unlock,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0x40FFFFFF),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const CxIcon('lock', size: 22),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildError(CinemaxPlayerValue v) {
    final pad = MediaQuery.of(context).padding;
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0xD9000000),
        child: Stack(
          children: [
            Positioned(
              top: pad.top + 14,
              left: pad.left + 28,
              child: _Tap(
                onTap: _back,
                padding: const EdgeInsets.fromLTRB(0, 2, 10, 8),
                child: const CxIcon('back', size: 20),
              ),
            ),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const CxIcon('warning', size: 34),
                    const SizedBox(height: 10),
                    Text(
                      _s.playbackError,
                      style: CxStyle.title,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      v.error ?? '',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: CxStyle.subtitle,
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _c.retry,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 22,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.white70),
                        ),
                        child: Text(_s.retry, style: CxStyle.barLabel),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Shade extends StatelessWidget {
  const _Shade();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Color(0x99000000),
            Color(0x33000000),
            Color(0x33000000),
            Color(0xB3000000),
          ],
          stops: <double>[0, 0.3, 0.6, 1],
        ),
      ),
    );
  }
}

class _Tap extends StatelessWidget {
  const _Tap({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(8),
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({required this.icon, required this.label, this.onTap});

  final String icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CxIcon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label, style: CxStyle.barLabel),
          ],
        ),
      ),
    );
  }
}
