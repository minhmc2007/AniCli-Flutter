import 'package:flutter/material.dart';

enum AppLocale { en, vi }

class Translations {
  final AppLocale locale;
  const Translations(this.locale);

  static Translations of(BuildContext context) {
    return Translations(Localizations.localeOf(context).languageCode == 'vi' ? AppLocale.vi : AppLocale.en);
  }

  static const Map<String, Map<AppLocale, String>> _strings = {
    'tab_browse': {AppLocale.en: 'Browse', AppLocale.vi: 'Khám phá'},
    'tab_history': {AppLocale.en: 'History', AppLocale.vi: 'Lịch sử'},
    'tab_favorites': {AppLocale.en: 'Favorites', AppLocale.vi: 'Yêu thích'},
    'tab_settings': {AppLocale.en: 'Settings', AppLocale.vi: 'Cài đặt'},

    'incognito_history': {AppLocale.en: 'Incognito History', AppLocale.vi: 'Lịch sử ẩn danh'},
    'dark_favorites': {AppLocale.en: 'Dark Favorites', AppLocale.vi: 'Yêu thích ẩn danh'},
    'no_history': {AppLocale.en: 'Nothing here yet...', AppLocale.vi: 'Chưa có gì ở đây...'},
    'no_favorites': {AppLocale.en: 'No favorites yet!', AppLocale.vi: 'Chưa có yêu thích nào!'},
    'no_incognito_history': {AppLocale.en: 'No secrets here yet...', AppLocale.vi: 'Chưa có bí mật nào...'},
    'no_favorites_incognito': {AppLocale.en: 'Your stash is empty.', AppLocale.vi: 'Kho đồ trống rỗng.'},
    'clear_history': {AppLocale.en: 'Clear History', AppLocale.vi: 'Xóa lịch sử'},

    'episode': {AppLocale.en: 'Episode', AppLocale.vi: 'Tập'},
    'chapter': {AppLocale.en: 'Chapter', AppLocale.vi: 'Chương'},
    'chapters': {AppLocale.en: 'Chapters', AppLocale.vi: 'Danh sách chương'},
    'episodes': {AppLocale.en: 'Episodes', AppLocale.vi: 'Danh sách tập'},
    'tap_to_play': {AppLocale.en: 'Tap to play', AppLocale.vi: 'Nhấn để phát'},
    'tap_to_download': {AppLocale.en: 'Tap to download', AppLocale.vi: 'Nhấn để tải'},
    'download': {AppLocale.en: 'Download', AppLocale.vi: 'Tải xuống'},

    'search_hint': {AppLocale.en: 'Search anime or manga...', AppLocale.vi: 'Tìm anime hoặc manga...'},
    'trending': {AppLocale.en: 'Trending', AppLocale.vi: 'Thịnh hành'},
    'hot': {AppLocale.en: 'HOT', AppLocale.vi: 'HOT'},
    'manga_badge': {AppLocale.en: 'MANGA', AppLocale.vi: 'MANGA'},

    'settings_source': {AppLocale.en: 'Source', AppLocale.vi: 'Nguồn'},
    'settings_manga_source': {AppLocale.en: 'Manga Source', AppLocale.vi: 'Nguồn Manga'},
    'settings_performance': {AppLocale.en: 'Performance', AppLocale.vi: 'Hiệu suất'},
    'settings_general': {AppLocale.en: 'General', AppLocale.vi: 'Chung'},
    'settings_player': {AppLocale.en: 'Player', AppLocale.vi: 'Trình phát'},
    'settings_about': {AppLocale.en: 'About', AppLocale.vi: 'Thông tin'},
    'settings_visual_mode': {AppLocale.en: 'Visual Mode', AppLocale.vi: 'Chế độ hình ảnh'},
    'settings_language': {AppLocale.en: 'Language', AppLocale.vi: 'Ngôn ngữ'},

    'check_updates': {AppLocale.en: 'Check for Updates', AppLocale.vi: 'Kiểm tra cập nhật'},
    'clear_cache': {AppLocale.en: 'Clear Image Cache', AppLocale.vi: 'Xóa bộ nhớ đệm'},
    'backup_data': {AppLocale.en: 'Backup Data', AppLocale.vi: 'Sao lưu dữ liệu'},
    'restore_data': {AppLocale.en: 'Restore Data', AppLocale.vi: 'Khôi phục dữ liệu'},
    'use_internal_player': {AppLocale.en: 'Use Internal Player', AppLocale.vi: 'Dùng trình phát nội bộ'},
    'cache_duration': {AppLocale.en: 'Cache Duration (seconds)', AppLocale.vi: 'Thời gian lưu đệm (giây)'},

    'backup_saved': {AppLocale.en: 'Backup saved!', AppLocale.vi: 'Đã sao lưu!'},
    'data_restored': {AppLocale.en: 'Data restored! Restart app to apply.', AppLocale.vi: 'Đã khôi phục! Khởi động lại để áp dụng.'},
    'invalid_backup': {AppLocale.en: 'Invalid backup file', AppLocale.vi: 'Tệp sao lưu không hợp lệ'},
    'cache_cleared': {AppLocale.en: 'Image cache cleared!', AppLocale.vi: 'Đã xóa bộ nhớ đệm!'},
    'chapter_downloaded': {AppLocale.en: 'Chapter downloaded for offline reading', AppLocale.vi: 'Đã tải chương để đọc ngoại tuyến'},
    'downloaded_deleted': {AppLocale.en: 'Downloaded chapter deleted', AppLocale.vi: 'Đã xóa chương đã tải'},

    'auto': {AppLocale.en: 'Auto', AppLocale.vi: 'Tự động'},
    'best_looking': {AppLocale.en: 'Best Looking', AppLocale.vi: 'Đẹp nhất'},
    'balanced': {AppLocale.en: 'Balanced', AppLocale.vi: 'Cân bằng'},
    'best_performance': {AppLocale.en: 'Best Performance', AppLocale.vi: 'Hiệu suất cao nhất'},

    'en_source': {AppLocale.en: 'English', AppLocale.vi: 'Tiếng Anh'},
    'vi_source': {AppLocale.en: 'Vietnamese', AppLocale.vi: 'Tiếng Việt'},
    'nsfw_source': {AppLocale.en: 'NSFW', AppLocale.vi: 'Người lớn'},

    'continue_reading': {AppLocale.en: 'Continue', AppLocale.vi: 'Tiếp tục'},
    'previous_chapter': {AppLocale.en: 'Previous Chapter', AppLocale.vi: 'Chương trước'},
    'next_chapter': {AppLocale.en: 'Next Chapter', AppLocale.vi: 'Chương tiếp'},

    'save_backup': {AppLocale.en: 'Save Backup', AppLocale.vi: 'Lưu sao lưu'},
    'pick_backup': {AppLocale.en: 'Pick Backup File', AppLocale.vi: 'Chọn tệp sao lưu'},
  };

  String tr(String key, [List<String>? args]) {
    final map = _strings[key];
    if (map == null) return key;
    var s = map[locale] ?? map[AppLocale.en] ?? key;
    if (args != null) {
      for (int i = 0; i < args.length; i++) {
        s = s.replaceAll('{$i}', args[i]);
      }
    }
    return s;
  }
}

extension TranslateX on BuildContext {
  String tr(String key, [List<String>? args]) => Translations.of(this).tr(key, args);
}
