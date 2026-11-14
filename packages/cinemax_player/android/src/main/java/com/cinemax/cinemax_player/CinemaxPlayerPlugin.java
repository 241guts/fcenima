package com.cinemax.cinemax_player;

import android.app.Activity;
import android.app.PictureInPictureParams;
import android.content.Intent;
import android.net.Uri;
import android.os.Build;
import android.util.Rational;
import android.view.WindowManager;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.EventChannel;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import io.flutter.view.TextureRegistry;

/**
 * Flutter plugin entry point. Keeps a map of NativePlayer instances keyed by
 * their texture id and routes method calls from Dart to the right one.
 * Also reports links opened from other apps (VIEW / SEND intents).
 */
public class CinemaxPlayerPlugin
        implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {

    private static final Pattern URL_PATTERN =
            Pattern.compile("(?i)\\b((?:https?|rtsps?|rtmps?)://[^\\s<>\"']+)");

    private MethodChannel channel;
    private EventChannel linkChannel;
    private EventChannel.EventSink linkSink;
    private FlutterPlugin.FlutterPluginBinding pluginBinding;
    private ActivityPluginBinding activityBinding;
    private Activity activity;
    private final Map<Long, NativePlayer> players = new HashMap<>();

    private String initialLink;
    private boolean initialLinkRead = false;

    private final PluginRegistry.NewIntentListener newIntentListener =
            new PluginRegistry.NewIntentListener() {
                @Override
                public boolean onNewIntent(Intent intent) {
                    String link = extractLink(intent);
                    if (link == null) return false;
                    if (linkSink != null) {
                        linkSink.success(link);
                    } else {
                        // Dart is not listening yet: hand it over as the initial link.
                        initialLink = link;
                        initialLinkRead = false;
                    }
                    return true;
                }
            };

    // ---- FlutterPlugin -------------------------------------------------------

    @Override
    public void onAttachedToEngine(FlutterPlugin.FlutterPluginBinding binding) {
        pluginBinding = binding;
        channel = new MethodChannel(binding.getBinaryMessenger(), "cinemax_player");
        channel.setMethodCallHandler(this);
        linkChannel = new EventChannel(binding.getBinaryMessenger(), "cinemax_player/links");
        linkChannel.setStreamHandler(new EventChannel.StreamHandler() {
            @Override
            public void onListen(Object arguments, EventChannel.EventSink events) {
                linkSink = events;
            }

            @Override
            public void onCancel(Object arguments) {
                linkSink = null;
            }
        });
    }

    @Override
    public void onDetachedFromEngine(FlutterPlugin.FlutterPluginBinding binding) {
        if (channel != null) channel.setMethodCallHandler(null);
        channel = null;
        if (linkChannel != null) linkChannel.setStreamHandler(null);
        linkChannel = null;
        linkSink = null;
        for (NativePlayer p : new ArrayList<>(players.values())) p.release();
        players.clear();
        updateKeepScreenOn();
        pluginBinding = null;
    }

    // ---- ActivityAware -------------------------------------------------------

    @Override
    public void onAttachedToActivity(ActivityPluginBinding binding) {
        attach(binding);
        if (!initialLinkRead && initialLink == null) {
            Intent intent = binding.getActivity().getIntent();
            boolean fromHistory = intent != null
                    && (intent.getFlags() & Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) != 0;
            if (!fromHistory) initialLink = extractLink(intent);
        }
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detach();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(ActivityPluginBinding binding) {
        attach(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detach();
    }

    private void attach(ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addOnNewIntentListener(newIntentListener);
        updateKeepScreenOn();
    }

    private void detach() {
        if (activityBinding != null) {
            activityBinding.removeOnNewIntentListener(newIntentListener);
        }
        activityBinding = null;
        activity = null;
    }

    // ---- MethodChannel -------------------------------------------------------

    @Override
    public void onMethodCall(MethodCall call, MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "create":
                    create(call, result);
                    break;
                case "enterPip": {
                    Double aspect = call.argument("aspect");
                    result.success(enterPip(aspect));
                    break;
                }
                case "getInitialLink": {
                    String link = initialLink;
                    initialLink = null;
                    initialLinkRead = true;
                    result.success(link);
                    break;
                }
                default:
                    routeToPlayer(call, result);
            }
        } catch (Exception e) {
            result.error("native_error", e.getMessage() != null ? e.getMessage() : e.toString(), null);
        }
    }

    private void routeToPlayer(MethodCall call, MethodChannel.Result result) {
        Number idNumber = call.argument("id");
        NativePlayer player = idNumber != null ? players.get(idNumber.longValue()) : null;
        if (idNumber == null || player == null) {
            result.error("no_player", "Unknown player id", null);
            return;
        }
        switch (call.method) {
            case "play":
                player.play();
                break;
            case "pause":
                player.pause();
                break;
            case "seekTo": {
                Number position = call.argument("position");
                player.seekTo(position != null ? position.longValue() : 0L);
                break;
            }
            case "setSpeed": {
                Number speed = call.argument("speed");
                player.setSpeed(speed != null ? speed.floatValue() : 1f);
                break;
            }
            case "setVolume": {
                Number volume = call.argument("volume");
                player.setVolume(volume != null ? volume.floatValue() : 1f);
                break;
            }
            case "selectTrack": {
                String type = call.argument("type");
                String trackId = call.argument("trackId");
                player.selectTrack(type != null ? type : "", trackId);
                break;
            }
            case "dispose": {
                NativePlayer removed = players.remove(idNumber.longValue());
                if (removed != null) removed.release();
                updateKeepScreenOn();
                break;
            }
            default:
                result.notImplemented();
                return;
        }
        result.success(null);
    }

    @SuppressWarnings("unchecked")
    private void create(MethodCall call, MethodChannel.Result result) {
        FlutterPlugin.FlutterPluginBinding b = pluginBinding;
        if (b == null) {
            result.error("no_engine", "Plugin is not attached to an engine", null);
            return;
        }
        String url = call.argument("url");
        if (url == null || url.trim().isEmpty()) {
            result.error("bad_args", "url is required", null);
            return;
        }

        List<PlayerOptions.SubtitleOption> subtitles = new ArrayList<>();
        List<Map<String, Object>> rawSubs = call.argument("subtitles");
        if (rawSubs != null) {
            for (Map<String, Object> m : rawSubs) {
                Object u = m.get("url");
                if (!(u instanceof String)) continue;
                subtitles.add(new PlayerOptions.SubtitleOption(
                        (String) u,
                        m.get("language") instanceof String ? (String) m.get("language") : null,
                        m.get("label") instanceof String ? (String) m.get("label") : null,
                        m.get("mimeType") instanceof String ? (String) m.get("mimeType") : null));
            }
        }

        Map<String, String> headers = call.argument("headers");
        if (headers == null) headers = new HashMap<>();
        Number start = call.argument("startPositionMs");
        Boolean autoPlay = call.argument("autoPlay");
        Number speed = call.argument("speed");

        PlayerOptions options = new PlayerOptions(
                url,
                headers,
                (String) call.argument("mimeType"),
                (String) call.argument("userAgent"),
                start != null ? start.longValue() : 0L,
                autoPlay == null || autoPlay,
                speed != null ? speed.floatValue() : 1f,
                (String) call.argument("preferredAudioLanguage"),
                (String) call.argument("preferredSubtitleLanguage"),
                subtitles);

        TextureRegistry.SurfaceProducer producer = b.getTextureRegistry().createSurfaceProducer();
        long id = producer.id();
        try {
            EventChannel events =
                    new EventChannel(b.getBinaryMessenger(), "cinemax_player/events/" + id);
            players.put(id, new NativePlayer(b.getApplicationContext(), producer, events, options));
        } catch (Exception e) {
            producer.release();
            result.error("create_failed", e.getMessage() != null ? e.getMessage() : e.toString(), null);
            return;
        }
        updateKeepScreenOn();
        result.success(id);
    }

    private boolean enterPip(Double aspect) {
        Activity act = activity;
        if (act == null) return false;
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false;
        try {
            double ratio = aspect != null ? aspect : (16.0 / 9.0);
            ratio = Math.max(0.42, Math.min(2.38, ratio));
            PictureInPictureParams params = new PictureInPictureParams.Builder()
                    .setAspectRatio(new Rational((int) (ratio * 1000), 1000))
                    .build();
            return act.enterPictureInPictureMode(params);
        } catch (Exception e) {
            return false;
        }
    }

    private void updateKeepScreenOn() {
        final Activity act = activity;
        if (act == null) return;
        final boolean keepOn = !players.isEmpty();
        act.runOnUiThread(new Runnable() {
            @Override
            public void run() {
                if (keepOn) {
                    act.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                } else {
                    act.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
                }
            }
        });
    }

    // ---- Incoming links ------------------------------------------------------

    /** Returns the media link carried by a VIEW or SEND intent, or null. */
    @SuppressWarnings("deprecation")
    private static String extractLink(Intent intent) {
        if (intent == null) return null;
        String action = intent.getAction();
        if (Intent.ACTION_VIEW.equals(action)) {
            Uri data = intent.getData();
            return data != null ? data.toString() : null;
        }
        if (Intent.ACTION_SEND.equals(action)) {
            CharSequence text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT);
            if (text != null) {
                Matcher m = URL_PATTERN.matcher(text);
                if (m.find()) return m.group(1);
            }
            Object stream = intent.getParcelableExtra(Intent.EXTRA_STREAM);
            if (stream instanceof Uri) return stream.toString();
        }
        return null;
    }
}
