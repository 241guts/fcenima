package com.cinemax.cinemax_player;

import android.content.Context;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;

import androidx.media3.common.AudioAttributes;
import androidx.media3.common.C;
import androidx.media3.common.Format;
import androidx.media3.common.MediaItem;
import androidx.media3.common.MimeTypes;
import androidx.media3.common.PlaybackException;
import androidx.media3.common.PlaybackParameters;
import androidx.media3.common.Player;
import androidx.media3.common.TrackGroup;
import androidx.media3.common.TrackSelectionOverride;
import androidx.media3.common.TrackSelectionParameters;
import androidx.media3.common.Tracks;
import androidx.media3.common.VideoSize;
import androidx.media3.common.text.Cue;
import androidx.media3.common.text.CueGroup;
import androidx.media3.common.util.UnstableApi;
import androidx.media3.datasource.DataSource;
import androidx.media3.datasource.DefaultDataSource;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.ExoPlayer;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.extractor.DefaultExtractorsFactory;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;

import io.flutter.plugin.common.EventChannel;
import io.flutter.view.TextureRegistry;

/**
 * One Media3 ExoPlayer instance rendering into a Flutter texture.
 * Talks to Dart through an EventChannel (state, tracks, cues and error events).
 */
@UnstableApi
final class NativePlayer implements EventChannel.StreamHandler, Player.Listener {

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final TextureRegistry.SurfaceProducer producer;
    private final EventChannel events;
    private final PlayerOptions options;
    private ExoPlayer player;
    private EventChannel.EventSink sink;
    private boolean released = false;

    private int videoWidth = 0;
    private int videoHeight = 0;

    private final Runnable ticker = new Runnable() {
        @Override
        public void run() {
            if (released) return;
            emitState();
            if (player.isPlaying() || player.getPlaybackState() == Player.STATE_BUFFERING) {
                mainHandler.postDelayed(this, 250);
            }
        }
    };

    NativePlayer(
            Context context,
            TextureRegistry.SurfaceProducer producer,
            EventChannel events,
            PlayerOptions options) {
        this.producer = producer;
        this.events = events;
        this.options = options;

        DefaultHttpDataSource.Factory http = new DefaultHttpDataSource.Factory()
                .setAllowCrossProtocolRedirects(true)
                .setConnectTimeoutMs(15000)
                .setReadTimeoutMs(15000)
                .setDefaultRequestProperties(options.headers);
        if (options.userAgent != null && !options.userAgent.trim().isEmpty()) {
            http.setUserAgent(options.userAgent);
        }
        DataSource.Factory dataSourceFactory = new DefaultDataSource.Factory(context, http);
        DefaultExtractorsFactory extractors =
                new DefaultExtractorsFactory().setConstantBitrateSeekingEnabled(true);

        player = new ExoPlayer.Builder(context)
                .setMediaSourceFactory(new DefaultMediaSourceFactory(dataSourceFactory, extractors))
                .setHandleAudioBecomingNoisy(true)
                .build();

        player.setAudioAttributes(
                new AudioAttributes.Builder()
                        .setUsage(C.USAGE_MEDIA)
                        .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                        .build(),
                true);
        player.setWakeMode(C.WAKE_MODE_NETWORK);
        player.setVideoSurface(producer.getSurface());
        player.addListener(this);
        player.setPlaybackParameters(new PlaybackParameters(options.speed));
        applyTrackPreferences();
        player.setMediaItem(buildMediaItem(), options.startPositionMs);
        player.setPlayWhenReady(options.autoPlay);
        player.prepare();

        producer.setCallback(new TextureRegistry.SurfaceProducer.Callback() {
            @Override
            public void onSurfaceAvailable() {
                if (released) return;
                player.setVideoSurface(producer.getSurface());
            }

            @Override
            public void onSurfaceCleanup() {
                if (released) return;
                player.setVideoSurface(null);
            }
        });

        events.setStreamHandler(this);
    }

    // ---- Commands from Dart ------------------------------------------------

    void play() {
        if (player.getPlaybackState() == Player.STATE_ENDED) player.seekTo(0);
        player.play();
    }

    void pause() {
        player.pause();
    }

    void seekTo(long positionMs) {
        player.seekTo(positionMs);
        emitState();
    }

    void setSpeed(float speed) {
        player.setPlaybackSpeed(speed);
    }

    void setVolume(float volume) {
        player.setVolume(volume);
        emitState();
    }

    /** type: "video" | "audio" | "text". trackId null = auto (video) / off (text). */
    void selectTrack(String type, String trackId) {
        final int trackType;
        switch (type) {
            case "video":
                trackType = C.TRACK_TYPE_VIDEO;
                break;
            case "audio":
                trackType = C.TRACK_TYPE_AUDIO;
                break;
            case "text":
                trackType = C.TRACK_TYPE_TEXT;
                break;
            default:
                return;
        }
        TrackSelectionParameters.Builder builder =
                player.getTrackSelectionParameters().buildUpon();
        if (trackId == null) {
            if (trackType == C.TRACK_TYPE_TEXT) {
                builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true);
            } else {
                builder.clearOverridesOfType(trackType);
            }
        } else {
            String[] parts = trackId.split(":");
            if (parts.length != 2) return;
            int gi;
            int ti;
            try {
                gi = Integer.parseInt(parts[0]);
                ti = Integer.parseInt(parts[1]);
            } catch (NumberFormatException e) {
                return;
            }
            List<Tracks.Group> groups = player.getCurrentTracks().getGroups();
            if (gi < 0 || gi >= groups.size()) return;
            Tracks.Group group = groups.get(gi);
            if (ti < 0 || ti >= group.length) return;
            builder.setTrackTypeDisabled(trackType, false);
            builder.setOverrideForType(new TrackSelectionOverride(group.getMediaTrackGroup(), ti));
        }
        player.setTrackSelectionParameters(builder.build());
        emitTracks();
    }

    void release() {
        if (released) return;
        released = true;
        mainHandler.removeCallbacksAndMessages(null);
        events.setStreamHandler(null);
        sink = null;
        producer.setCallback(null);
        player.removeListener(this);
        player.release();
        producer.release();
    }

    // ---- EventChannel.StreamHandler ---------------------------------------

    @Override
    public void onListen(Object arguments, EventChannel.EventSink eventSink) {
        sink = eventSink;
        emitState();
        emitTracks();
    }

    @Override
    public void onCancel(Object arguments) {
        sink = null;
    }

    // ---- Player.Listener --------------------------------------------------

    @Override
    public void onPlaybackStateChanged(int playbackState) {
        emitState();
        startTicker();
    }

    @Override
    public void onIsPlayingChanged(boolean isPlaying) {
        emitState();
        startTicker();
    }

    @Override
    public void onPlaybackParametersChanged(PlaybackParameters playbackParameters) {
        emitState();
    }

    @Override
    public void onVideoSizeChanged(VideoSize videoSize) {
        if (videoSize.width > 0 && videoSize.height > 0) {
            producer.setSize(videoSize.width, videoSize.height);
            videoWidth = (int) (videoSize.width * videoSize.pixelWidthHeightRatio);
            videoHeight = videoSize.height;
        }
        emitState();
    }

    @Override
    public void onTracksChanged(Tracks tracks) {
        emitTracks();
    }

    @Override
    public void onTrackSelectionParametersChanged(TrackSelectionParameters parameters) {
        emitTracks();
    }

    @Override
    public void onCues(CueGroup cueGroup) {
        EventChannel.EventSink s = sink;
        if (s == null) return;
        List<String> texts = new ArrayList<>();
        for (Cue cue : cueGroup.cues) {
            if (cue.text == null) continue;
            String t = cue.text.toString().trim();
            if (!t.isEmpty()) texts.add(t);
        }
        Map<String, Object> m = new HashMap<>();
        m.put("event", "cues");
        m.put("cues", texts);
        s.success(m);
    }

    @Override
    public void onPlayerError(PlaybackException error) {
        if (error.errorCode == PlaybackException.ERROR_CODE_BEHIND_LIVE_WINDOW) {
            // Live stream fell behind the window: jump back to the live edge.
            player.seekToDefaultPosition();
            player.prepare();
            return;
        }
        EventChannel.EventSink s = sink;
        if (s == null) return;
        String message = error.getErrorCodeName();
        Throwable cause = error.getCause();
        if (cause != null && cause.getMessage() != null && !cause.getMessage().isEmpty()) {
            message = message + ": " + cause.getMessage();
        } else if (error.getMessage() != null && !error.getMessage().isEmpty()) {
            message = message + ": " + error.getMessage();
        }
        Map<String, Object> m = new HashMap<>();
        m.put("event", "error");
        m.put("code", error.getErrorCodeName());
        m.put("message", message);
        s.success(m);
    }

    // ---- Helpers -----------------------------------------------------------

    private void startTicker() {
        mainHandler.removeCallbacks(ticker);
        mainHandler.post(ticker);
    }

    private void emitState() {
        EventChannel.EventSink s = sink;
        if (s == null || released) return;
        long duration = player.getDuration();
        String state;
        switch (player.getPlaybackState()) {
            case Player.STATE_BUFFERING:
                state = "buffering";
                break;
            case Player.STATE_READY:
                state = "ready";
                break;
            case Player.STATE_ENDED:
                state = "ended";
                break;
            default:
                state = "idle";
        }
        Map<String, Object> m = new HashMap<>();
        m.put("event", "state");
        m.put("isPlaying", player.isPlaying());
        m.put("playbackState", state);
        m.put("position", player.getCurrentPosition());
        m.put("duration", (duration == C.TIME_UNSET || duration < 0) ? 0L : duration);
        m.put("buffered", player.getBufferedPosition());
        m.put("width", videoWidth);
        m.put("height", videoHeight);
        m.put("speed", (double) player.getPlaybackParameters().speed);
        m.put("volume", (double) player.getVolume());
        s.success(m);
    }

    private void emitTracks() {
        EventChannel.EventSink s = sink;
        if (s == null || released) return;
        List<Map<String, Object>> list = new ArrayList<>();
        List<Tracks.Group> groups = player.getCurrentTracks().getGroups();
        TrackSelectionParameters params = player.getTrackSelectionParameters();
        Map<TrackGroup, TrackSelectionOverride> overrides = params.overrides;

        for (int gi = 0; gi < groups.size(); gi++) {
            Tracks.Group group = groups.get(gi);
            String type;
            switch (group.getType()) {
                case C.TRACK_TYPE_VIDEO:
                    type = "video";
                    break;
                case C.TRACK_TYPE_AUDIO:
                    type = "audio";
                    break;
                case C.TRACK_TYPE_TEXT:
                    type = "text";
                    break;
                default:
                    continue;
            }
            TrackSelectionOverride override = overrides.get(group.getMediaTrackGroup());
            for (int ti = 0; ti < group.length; ti++) {
                if (!group.isTrackSupported(ti)) continue;
                Format f = group.getTrackFormat(ti);
                // For video the "selected" flag follows the user's choice, not the
                // rendition that happens to be playing right now.
                boolean selected;
                if (group.getType() == C.TRACK_TYPE_VIDEO && override != null) {
                    selected = override.trackIndices.contains(ti);
                } else {
                    selected = group.isTrackSelected(ti);
                }
                Map<String, Object> t = new HashMap<>();
                t.put("id", gi + ":" + ti);
                t.put("type", type);
                t.put("language", f.language);
                t.put("label", f.label);
                t.put("width", f.width);
                t.put("height", f.height);
                t.put("bitrate", f.bitrate);
                t.put("selected", selected);
                list.add(t);
            }
        }

        boolean videoAuto = true;
        for (TrackSelectionOverride o : overrides.values()) {
            if (o.getType() == C.TRACK_TYPE_VIDEO) {
                videoAuto = false;
                break;
            }
        }
        Map<String, Object> m = new HashMap<>();
        m.put("event", "tracks");
        m.put("tracks", list);
        m.put("textDisabled", params.disabledTrackTypes.contains(C.TRACK_TYPE_TEXT));
        m.put("videoAuto", videoAuto);
        s.success(m);
    }

    private void applyTrackPreferences() {
        TrackSelectionParameters.Builder builder =
                player.getTrackSelectionParameters().buildUpon();
        if (options.preferredAudioLanguage != null) {
            builder.setPreferredAudioLanguage(options.preferredAudioLanguage);
        }
        if (options.preferredSubtitleLanguage != null) {
            builder.setPreferredTextLanguage(options.preferredSubtitleLanguage);
        } else if (options.subtitles.isEmpty()) {
            builder.setTrackTypeDisabled(C.TRACK_TYPE_TEXT, true);
        }
        player.setTrackSelectionParameters(builder.build());
    }

    private MediaItem buildMediaItem() {
        MediaItem.Builder builder = new MediaItem.Builder().setUri(options.url);
        if (options.mimeType != null && !options.mimeType.trim().isEmpty()) {
            builder.setMimeType(options.mimeType);
        }
        List<MediaItem.SubtitleConfiguration> subs = new ArrayList<>();
        for (int i = 0; i < options.subtitles.size(); i++) {
            PlayerOptions.SubtitleOption sub = options.subtitles.get(i);
            String mime = (sub.mimeType != null && !sub.mimeType.isEmpty())
                    ? sub.mimeType
                    : guessSubtitleMime(sub.url);
            MediaItem.SubtitleConfiguration.Builder sb =
                    new MediaItem.SubtitleConfiguration.Builder(Uri.parse(sub.url))
                            .setMimeType(mime)
                            .setLanguage(sub.language)
                            .setLabel(sub.label);
            // The first external subtitle is shown by default.
            if (i == 0) sb.setSelectionFlags(C.SELECTION_FLAG_DEFAULT);
            subs.add(sb.build());
        }
        if (!subs.isEmpty()) builder.setSubtitleConfigurations(subs);
        return builder.build();
    }

    private static String guessSubtitleMime(String url) {
        int q = url.indexOf('?');
        String path = (q >= 0 ? url.substring(0, q) : url).toLowerCase(Locale.ROOT);
        if (path.endsWith(".srt")) return MimeTypes.APPLICATION_SUBRIP;
        if (path.endsWith(".ass") || path.endsWith(".ssa")) return MimeTypes.TEXT_SSA;
        if (path.endsWith(".ttml") || path.endsWith(".xml") || path.endsWith(".dfxp")) {
            return MimeTypes.APPLICATION_TTML;
        }
        return MimeTypes.TEXT_VTT;
    }
}
