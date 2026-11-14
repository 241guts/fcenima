import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'link_utils.dart';

/// One link the user played, with what is needed to play it again.
class HistoryEntry {
  HistoryEntry({
    required this.url,
    this.title = '',
    this.headers = const <String, String>{},
    this.userAgent = '',
    this.format = LinkFormat.auto,
    this.subtitleUrl = '',
    this.subtitleLang = '',
    this.positionMs = 0,
    this.durationMs = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String url;
  final String title;
  final Map<String, String> headers;
  final String userAgent;
  final LinkFormat format;
  final String subtitleUrl;
  final String subtitleLang;
  final int positionMs;
  final int durationMs;
  final int updatedAt;

  /// 0..1 watched fraction, or null when the length is unknown.
  double? get progress {
    if (durationMs <= 0) return null;
    return (positionMs / durationMs).clamp(0.0, 1.0).toDouble();
  }

  HistoryEntry copyWith({int? positionMs, int? durationMs}) {
    return HistoryEntry(
      url: url,
      title: title,
      headers: headers,
      userAgent: userAgent,
      format: format,
      subtitleUrl: subtitleUrl,
      subtitleLang: subtitleLang,
      positionMs: positionMs ?? this.positionMs,
      durationMs: durationMs ?? this.durationMs,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'url': url,
        'title': title,
        'headers': headers,
        'userAgent': userAgent,
        'format': format.name,
        'subtitleUrl': subtitleUrl,
        'subtitleLang': subtitleLang,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'updatedAt': updatedAt,
      };

  static HistoryEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final url = raw['url'];
    if (url is! String || url.isEmpty) return null;
    final rawHeaders = raw['headers'];
    final headers = <String, String>{};
    if (rawHeaders is Map) {
      rawHeaders.forEach((Object? k, Object? v) {
        if (k is String && v is String) headers[k] = v;
      });
    }
    final formatName = raw['format'];
    final format = LinkFormat.values.firstWhere(
      (f) => f.name == formatName,
      orElse: () => LinkFormat.auto,
    );
    return HistoryEntry(
      url: url,
      title: raw['title'] is String ? raw['title'] as String : '',
      headers: headers,
      userAgent: raw['userAgent'] is String ? raw['userAgent'] as String : '',
      format: format,
      subtitleUrl:
          raw['subtitleUrl'] is String ? raw['subtitleUrl'] as String : '',
      subtitleLang:
          raw['subtitleLang'] is String ? raw['subtitleLang'] as String : '',
      positionMs: raw['positionMs'] is num ? (raw['positionMs'] as num).toInt() : 0,
      durationMs: raw['durationMs'] is num ? (raw['durationMs'] as num).toInt() : 0,
      updatedAt: raw['updatedAt'] is num ? (raw['updatedAt'] as num).toInt() : null,
    );
  }
}

/// Recent links and resume positions, kept in SharedPreferences.
class HistoryStore {
  static const String _key = 'history_v1';
  static const int _max = 30;

  Future<List<HistoryEntry>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final text = prefs.getString(_key);
      if (text == null || text.isEmpty) return <HistoryEntry>[];
      final decoded = jsonDecode(text);
      if (decoded is! List) return <HistoryEntry>[];
      final list = <HistoryEntry>[];
      for (final item in decoded) {
        final e = HistoryEntry.fromJson(item);
        if (e != null) list.add(e);
      }
      return list;
    } catch (_) {
      return <HistoryEntry>[];
    }
  }

  Future<void> _save(List<HistoryEntry> list) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _key,
        jsonEncode(list.take(_max).map((e) => e.toJson()).toList()),
      );
    } catch (_) {
      // History is a convenience: never break playback because of it.
    }
  }

  /// Puts [entry] first, keeping the saved position of the same link.
  Future<void> upsert(HistoryEntry entry) async {
    final list = await load();
    var merged = entry;
    for (final old in list) {
      if (old.url == entry.url) {
        merged = entry.copyWith(
          positionMs: old.positionMs,
          durationMs: old.durationMs,
        );
      }
    }
    list.removeWhere((e) => e.url == entry.url);
    list.insert(0, merged);
    await _save(list);
  }

  Future<void> updateProgress(String url, int positionMs, int durationMs) async {
    final list = await load();
    for (var i = 0; i < list.length; i++) {
      if (list[i].url == url) {
        list[i] = list[i].copyWith(positionMs: positionMs, durationMs: durationMs);
        await _save(list);
        return;
      }
    }
  }

  Future<void> remove(String url) async {
    final list = await load();
    list.removeWhere((e) => e.url == url);
    await _save(list);
  }

  Future<void> clear() => _save(<HistoryEntry>[]);
}
