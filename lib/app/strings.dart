import 'package:flutter/widgets.dart';

/// UI texts of the app screens (English and Arabic).
/// The player itself keeps the English texts of the design.
class AppStrings {
  const AppStrings._(this._ar);

  final bool _ar;

  static AppStrings of(BuildContext context) {
    final code = Localizations.localeOf(context).languageCode;
    return AppStrings._(code == 'ar');
  }

  String _t(String en, String ar) => _ar ? ar : en;

  String get linkHint => _t('Paste a video link', 'الصق رابط الفيديو');
  String get linkFormats => 'm3u8 · mpd · mp4 · mkv · webm · ts · mov · mp3 · rtsp ...';
  String get paste => _t('Paste', 'لصق');
  String get clear => _t('Clear', 'مسح');
  String get play => _t('Play', 'تشغيل');
  String get checking => _t('Checking link...', 'جارٍ فحص الرابط...');
  String get invalidLink => _t('Enter a valid link', 'أدخل رابطاً صحيحاً');
  String get format => _t('Format', 'الصيغة');
  String get formatAuto => _t('Auto', 'تلقائي');
  String get formatDirect => _t('Direct file', 'ملف مباشر');
  String get advanced => _t('Advanced', 'خيارات متقدمة');
  String get titleField => _t('Title (optional)', 'العنوان (اختياري)');
  String get headersField => _t(
        'HTTP headers, one per line (Referer: https://site.com)',
        'ترويسات HTTP، كل سطر (Referer: https://site.com)',
      );
  String get userAgentField => _t('User-Agent (optional)', 'User-Agent (اختياري)');
  String get subtitleUrlField =>
      _t('Subtitle link (vtt / srt / ass)', 'رابط الترجمة (vtt / srt / ass)');
  String get subtitleLangField =>
      _t('Subtitle language code (e.g. ar)', 'رمز لغة الترجمة (مثل ar)');
  String get recent => _t('Recent', 'الأخيرة');
  String get remove => _t('Remove', 'حذف');
}
