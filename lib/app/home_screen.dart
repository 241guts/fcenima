import 'dart:async';

import 'package:cinemax_player/cinemax_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import 'history_store.dart';
import 'link_utils.dart';
import 'strings.dart';

/// Start page: paste a link, pick options, play. Also receives links opened
/// from other apps (browser, share sheet, file manager).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _url = TextEditingController();
  final TextEditingController _title = TextEditingController();
  final TextEditingController _headers = TextEditingController();
  final TextEditingController _userAgent = TextEditingController();
  final TextEditingController _subtitleUrl = TextEditingController();
  final TextEditingController _subtitleLang = TextEditingController();
  final HistoryStore _store = HistoryStore();

  List<HistoryEntry> _history = <HistoryEntry>[];
  LinkFormat _format = LinkFormat.auto;
  bool _busy = false;
  StreamSubscription<String>? _linkSub;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    // Subscribe first, then read the launch link, so nothing is missed.
    _linkSub = CinemaxLinks.linkStream.listen(_openIncoming);
    CinemaxLinks.initialLink().then((link) {
      if (link != null && mounted) _openIncoming(link);
    });
  }

  @override
  void dispose() {
    _linkSub?.cancel();
    _url.dispose();
    _title.dispose();
    _headers.dispose();
    _userAgent.dispose();
    _subtitleUrl.dispose();
    _subtitleLang.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    final list = await _store.load();
    if (mounted) setState(() => _history = list);
  }

  // ---- incoming links -------------------------------------------------------

  Future<void> _openIncoming(String link) async {
    if (!mounted) return;
    final nav = Navigator.of(context);
    final hadPlayer = nav.canPop();
    nav.popUntil((route) => route.isFirst);
    // Let the old player finish closing (it restores the orientation).
    if (hadPlayer) await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted) return;
    _url.text = link;
    _title.clear();
    _headers.clear();
    _subtitleUrl.clear();
    _subtitleLang.clear();
    setState(() => _format = LinkFormat.auto);
    await _start();
  }

  // ---- playing ----------------------------------------------------------------

  Future<void> _start() async {
    if (_busy) return;
    final s = AppStrings.of(context);
    final url = LinkUtils.extractUrl(_url.text);
    if (url == null) {
      _snack(s.invalidLink);
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);

    final headers = LinkUtils.parseHeaders(_headers.text);
    final typedAgent = _userAgent.text.trim();
    final agent = typedAgent.isEmpty ? LinkUtils.defaultUserAgent : typedAgent;
    var format = _format;
    try {
      if (format == LinkFormat.auto) {
        format = LinkUtils.detect(url);
        if (format == LinkFormat.auto && LinkUtils.needsSniff(url)) {
          format = await LinkUtils.sniff(url, headers: headers, userAgent: agent);
        }
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;

    final subtitleLink = LinkUtils.extractUrl(_subtitleUrl.text) ?? '';
    final subtitleLang = _subtitleLang.text.trim();
    final title = _title.text.trim().isNotEmpty
        ? _title.text.trim()
        : LinkUtils.titleFromUrl(url);

    HistoryEntry? previous;
    for (final e in await _store.load()) {
      if (e.url == url) previous = e;
    }
    await _store.upsert(
      HistoryEntry(
        url: url,
        title: title,
        headers: headers,
        userAgent: typedAgent,
        format: _format,
        subtitleUrl: subtitleLink,
        subtitleLang: subtitleLang,
      ),
    );
    if (!mounted) return;

    final source = CinemaxMediaSource(
      url: url,
      headers: headers,
      mimeType: LinkUtils.mimeFor(format),
      userAgent: agent,
      subtitles: <CinemaxSubtitle>[
        if (subtitleLink.isNotEmpty)
          CinemaxSubtitle(
            url: subtitleLink,
            language: subtitleLang.isEmpty ? null : subtitleLang,
            label: subtitleLang.isEmpty ? 'Subtitles' : subtitleLang,
          ),
      ],
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Directionality(
          // The player design is left-to-right in every language.
          textDirection: TextDirection.ltr,
          child: CinemaxPlayerScreen(
            title: title,
            source: source,
            config: CinemaxPlayerConfig(
              startPosition: _resumePosition(previous),
              showSeriesButton: false,
            ),
            onProgress: (position, duration) => _store.updateProgress(
              url,
              position.inMilliseconds,
              duration.inMilliseconds,
            ),
          ),
        ),
      ),
    );
    _loadHistory();
  }

  Duration _resumePosition(HistoryEntry? e) {
    if (e == null) return Duration.zero;
    final p = e.positionMs;
    final d = e.durationMs;
    if (p < 10000) return Duration.zero;
    if (d > 0 && p > d - 20000) return Duration.zero;
    return Duration(milliseconds: p);
  }

  void _playEntry(HistoryEntry e) {
    _url.text = e.url;
    _title.text = e.title;
    _headers.text = LinkUtils.headersToText(e.headers);
    _userAgent.text = e.userAgent;
    _subtitleUrl.text = e.subtitleUrl;
    _subtitleLang.text = e.subtitleLang;
    setState(() => _format = e.format);
    _start();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text != null && text.isNotEmpty && mounted) {
      setState(() => _url.text = text.trim());
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- UI -----------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final s = AppStrings.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            _header(),
            const SizedBox(height: 22),
            _linkField(s),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                s.linkFormats,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ),
            const SizedBox(height: 18),
            Text(s.format, style: const TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            _formatChips(s),
            const SizedBox(height: 6),
            _advanced(s),
            const SizedBox(height: 14),
            _playButton(s),
            if (_history.isNotEmpty) ...[
              const SizedBox(height: 28),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.recent,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await _store.clear();
                      _loadHistory();
                    },
                    child: Text(s.clear),
                  ),
                ],
              ),
              for (final e in _history) _historyTile(e, s),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: CinemaxApp.crimson,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.play_arrow_rounded, size: 30, color: Colors.white),
        ),
        const SizedBox(width: 12),
        const Text(
          'Cinemax Player',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _linkField(AppStrings s) {
    return TextField(
      controller: _url,
      minLines: 2,
      maxLines: 4,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: s.linkHint,
        suffixIcon: _url.text.isEmpty
            ? IconButton(
                tooltip: s.paste,
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: _paste,
              )
            : IconButton(
                tooltip: s.clear,
                icon: const Icon(Icons.close_rounded),
                onPressed: () => setState(_url.clear),
              ),
      ),
    );
  }

  Widget _formatChips(AppStrings s) {
    final labels = <LinkFormat, String>{
      LinkFormat.auto: s.formatAuto,
      LinkFormat.hls: 'HLS',
      LinkFormat.dash: 'DASH',
      LinkFormat.smooth: 'Smooth',
      LinkFormat.direct: s.formatDirect,
    };
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in labels.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: _format == entry.key,
            showCheckmark: false,
            selectedColor: CinemaxApp.crimson,
            backgroundColor: CinemaxApp.surface,
            side: BorderSide.none,
            labelStyle: TextStyle(
              color: _format == entry.key ? Colors.white : Colors.white70,
            ),
            onSelected: (_) => setState(() => _format = entry.key),
          ),
      ],
    );
  }

  Widget _advanced(AppStrings s) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 8),
        title: Text(s.advanced, style: const TextStyle(color: Colors.white70)),
        children: [
          _field(_title, s.titleField),
          _field(_headers, s.headersField, lines: 3),
          _field(_userAgent, s.userAgentField),
          _field(_subtitleUrl, s.subtitleUrlField),
          _field(_subtitleLang, s.subtitleLangField),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label, {int lines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: TextField(
        controller: c,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }

  Widget _playButton(AppStrings s) {
    return FilledButton(
      onPressed: _busy ? null : _start,
      style: FilledButton.styleFrom(
        backgroundColor: CinemaxApp.crimson,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      child: _busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(s.checking),
              ],
            )
          : Text(
              s.play,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
    );
  }

  Widget _historyTile(HistoryEntry e, AppStrings s) {
    final progress = e.progress;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: CinemaxApp.surface,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _playEntry(e),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                child: Row(
                  children: [
                    const Icon(Icons.play_circle_outline_rounded, color: Colors.white54),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.title.isEmpty ? e.url : e.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            e.url,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: s.remove,
                      icon: const Icon(Icons.close_rounded, size: 20, color: Colors.white38),
                      onPressed: () async {
                        await _store.remove(e.url);
                        _loadHistory();
                      },
                    ),
                  ],
                ),
              ),
              if (progress != null && progress > 0)
                LinearProgressIndicator(
                  value: progress,
                  minHeight: 3,
                  color: CinemaxApp.crimson,
                  backgroundColor: Colors.white12,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
