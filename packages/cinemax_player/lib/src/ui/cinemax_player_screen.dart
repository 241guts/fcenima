import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controller/cinemax_player_controller.dart';
import '../models/media_source.dart';
import '../models/player_config.dart';
import '../models/strings.dart';
import 'cinemax_player.dart';

/// Ready-made full-screen player page.
///
/// ```dart
/// Navigator.of(context).push(MaterialPageRoute(
///   builder: (_) => CinemaxPlayerScreen(
///     source: CinemaxMediaSource(url: url, headers: headers),
///     title: 'House of the Dragon',
///     subtitle: 'Episode 2 Season 1',
///   ),
/// ));
/// ```
///
/// Pass either [source] (the screen owns the controller) or your own
/// [controller] (you own it, e.g. to switch episodes with controller.open).
class CinemaxPlayerScreen extends StatefulWidget {
  const CinemaxPlayerScreen({
    super.key,
    this.source,
    this.controller,
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
    this.onProgress,
    this.restoreOrientations = DeviceOrientation.values,
  }) : assert(
          source != null || controller != null,
          'Pass a source or a controller',
        );

  final CinemaxMediaSource? source;
  final CinemaxPlayerController? controller;
  final String title;
  final String? subtitle;
  final CinemaxPlayerConfig config;
  final CinemaxPlayerStrings strings;
  final VoidCallback? onBack;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback? onSeries;
  final VoidCallback? onMore;
  final VoidCallback? onCast;
  final VoidCallback? onFullscreenTap;
  final VoidCallback? onEnded;

  /// Called about every 5 seconds and once on exit. Use it to save the
  /// resume position.
  final void Function(Duration position, Duration duration)? onProgress;

  /// Orientations restored when the screen closes.
  final List<DeviceOrientation> restoreOrientations;

  @override
  State<CinemaxPlayerScreen> createState() => _CinemaxPlayerScreenState();
}

class _CinemaxPlayerScreenState extends State<CinemaxPlayerScreen> {
  late final CinemaxPlayerController _c;
  late final bool _owns;
  DateTime _lastReport = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _owns = widget.controller == null;
    _c = widget.controller ?? CinemaxPlayerController();
    if (widget.config.forceLandscape) {
      SystemChrome.setPreferredOrientations(const <DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _c.addListener(_onValue);
    final s = widget.source;
    if (s != null) _c.open(s, config: widget.config);
  }

  void _onValue() {
    final cb = widget.onProgress;
    if (cb == null) return;
    final v = _c.value;
    if (!v.isInitialized || v.duration <= Duration.zero) return;
    final now = DateTime.now();
    if (now.difference(_lastReport) >= const Duration(seconds: 5)) {
      _lastReport = now;
      cb(v.position, v.duration);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onValue);
    final v = _c.value;
    if (widget.onProgress != null && v.duration > Duration.zero) {
      widget.onProgress!(v.position, v.duration);
    }
    SystemChrome.setPreferredOrientations(widget.restoreOrientations);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (_owns) _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: CinemaxPlayer(
        controller: _c,
        title: widget.title,
        subtitle: widget.subtitle,
        config: widget.config,
        strings: widget.strings,
        onBack: widget.onBack,
        onPrevious: widget.onPrevious,
        onNext: widget.onNext,
        onSeries: widget.onSeries,
        onMore: widget.onMore,
        onCast: widget.onCast,
        onFullscreenTap: widget.onFullscreenTap,
        onEnded: widget.onEnded,
      ),
    );
  }
}
