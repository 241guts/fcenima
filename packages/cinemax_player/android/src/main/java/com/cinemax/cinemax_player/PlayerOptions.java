package com.cinemax.cinemax_player;

import java.util.List;
import java.util.Map;

/** Everything the host app configured for one playback session. */
final class PlayerOptions {

    /** External subtitle file passed from Dart. */
    static final class SubtitleOption {
        final String url;
        final String language;
        final String label;
        final String mimeType;

        SubtitleOption(String url, String language, String label, String mimeType) {
            this.url = url;
            this.language = language;
            this.label = label;
            this.mimeType = mimeType;
        }
    }

    final String url;
    final Map<String, String> headers;
    final String mimeType;
    final String userAgent;
    final long startPositionMs;
    final boolean autoPlay;
    final float speed;
    final String preferredAudioLanguage;
    final String preferredSubtitleLanguage;
    final List<SubtitleOption> subtitles;

    PlayerOptions(
            String url,
            Map<String, String> headers,
            String mimeType,
            String userAgent,
            long startPositionMs,
            boolean autoPlay,
            float speed,
            String preferredAudioLanguage,
            String preferredSubtitleLanguage,
            List<SubtitleOption> subtitles) {
        this.url = url;
        this.headers = headers;
        this.mimeType = mimeType;
        this.userAgent = userAgent;
        this.startPositionMs = startPositionMs;
        this.autoPlay = autoPlay;
        this.speed = speed;
        this.preferredAudioLanguage = preferredAudioLanguage;
        this.preferredSubtitleLanguage = preferredSubtitleLanguage;
        this.subtitles = subtitles;
    }
}
