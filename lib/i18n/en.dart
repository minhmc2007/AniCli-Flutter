const Map<String, String> enStrings = {
  // Tabs
  'tab_browse': 'Browse',
  'tab_history': 'History',
  'tab_favorites': 'Favorites',
  'tab_settings': 'Settings',

  // History & Favorites
  'incognito_history': 'Incognito History',
  'dark_favorites': 'Dark Favorites',
  'no_history': 'Nothing here yet...',
  'no_favorites': 'No favorites yet!',
  'no_incognito_history': 'No secrets here yet...',
  'no_favorites_incognito': 'Your stash is empty.',
  'clear_history': 'Clear History',

  // Media labels
  'episode': 'Episode',
  'chapter': 'Chapter',
  'chapters': 'Chapters',
  'episodes': 'Episodes',
  'tap_to_play': 'Tap to play',
  'tap_to_download': 'Tap to download',
  'download': 'Download',
  'chapter_prefix': 'Chapter {0}',
  'episode_prefix': 'Episode {0}',

  // Browse
  'search_hint_anime': 'Search Anime...',
  'search_hint_manga': 'Search Manga...',
  'search_hint_nsfw': 'Search Hentai or Category...',
  'trending': 'Trending',
  'hot': 'HOT',
  'manga_badge': 'MANGA',
  'nsfw_badge': 'NSFW 18+',
  'mode_anime': 'Anime',
  'mode_manga': 'Manga',
  'no_results': 'No results found.',
  'hot_videos': 'Hot Videos',
  'spotlight': 'Spotlight',
  'popular_updates': 'Popular Updates',
  'latest_updates': 'Latest Updates',
  'trending_anime': 'Trending Anime',
  'results': 'Results',
  'prev': 'Prev',
  'next': 'Next',
  'page': 'Page {0}',

  // Manga source banners
  'manga_mangadex': 'MangaDex',
  'manga_zettruyen': 'ZetTruyen',
  'manga_truyenqq': 'TruyenQQ',
  'manga_en': 'EN Manga',
  'manga_vi': 'VN Manga',
  'manga_weebcentral': 'WeebCentral',
  'manga_mangadex_sub': "Read the world's library",
  'manga_zettruyen_sub': 'Truyện tranh Tiếng Việt',
  'manga_truyenqq_sub': 'Truyện tranh Việt Nam',
  'manga_en_sub': 'English Manga',
  'manga_vi_sub': 'Vietnamese Manga',
  'manga_weebcentral_sub': 'The Weeb Central',

  // Settings - sections
  'section_content': 'Content',
  'section_performance': 'Performance',
  'section_development': 'Development',
  'section_about': 'About',
  // Settings - labels
  'setting_anime_source': 'Anime Source',
  'setting_manga_source': 'Manga Source',
  'setting_language': 'Language / Ngôn ngữ',
  'setting_visual_mode': 'Visual Mode',
  'setting_video_cache': 'Video Cache',
  'setting_github_repo': 'GitHub Repository',
  'setting_reset_welcome': 'Reset Welcome Screen',

  // Settings - subtitles
  'setting_check_updates_sub': 'Version Check via GitHub Releases',
  'setting_clear_cache_sub': 'Fixes broken covers by removing old cached 404s',
  'setting_backup_sub': 'Export all data to a file',
  'setting_restore_sub': 'Import data from a backup file',
  'setting_internal_player_sub': 'Use built-in player instead of System MPV',
  'setting_github_repo_sub': 'minhmc2007/AniCli-Flutter',
  'setting_reset_welcome_sub': 'Reset OOBE flag for testing',

  // Settings - dropdown anime source
  'source_en': 'English (Multi-Provider)',
  'source_vi': 'Tiếng Việt (PhimAPI · Vietsub)',
  'source_nsfw': 'NSFW 18+ (HentaiVietsub)',

  // Settings - dropdown manga source
  'manga_source_en': 'EN Manga (MangaDex + WeebCentral)',
  'manga_source_vi': 'VN Manga (ZetTruyen + TruyenQQ)',
  'manga_source_mangadex': 'MangaDex (Multi-lang · R18)',
  'manga_source_zettruyen': 'ZetTruyen (Tiếng Việt)',
  'manga_source_weebcentral': 'WeebCentral (English)',
  'manga_source_truyenqq': 'TruyenQQ (Tiếng Việt)',

  // Settings - performance info
  'current_tier': 'Current Tier: {0}  •  Detected RAM: {1}',
  'buffer_duration': 'Buffer Duration: {0}',
  'unlimited': 'Unlimited',
  'seconds': 'seconds',

  // Settings - about
  'version': 'Version',
  'build_number': 'Build Number',

  // Settings - reset
  'reset_done': 'Reset! Restart app to see the Welcome Screen.',

  // Settings - source descriptions (for source select screen)
  'choose_source': 'Choose Anime Source',
  'choose_source_sub': 'Select your preferred anime content language',
  'source_en_title': 'English',
  'source_en_sub': 'Multi-Provider · Senshi · Anipub · Anineko · AllAnime · Animepahe',
  'source_vi_title': 'Tiếng Việt',
  'source_vi_sub': 'PhimAPI · Vietsub',

  // Settings - NSFW warning
  'nsfw_warning_title': 'Age Warning (18+)',
  'nsfw_warning_content': 'This source contains adult-only (NSFW) content.\n\nAre you 18 years or older and wish to proceed?',
  'nsfw_warning_confirm': 'I am 18+',
  'cancel': 'Cancel',

  // Settings - snackbars
  'cache_cleared': 'Image cache cleared!',
  'backup_failed': 'Backup failed: {0}',
  'restore_failed': 'Restore failed: {0}',
  'backup_saved': 'Backup saved!',
  'data_restored': 'Data restored! Restart app to apply.',
  'invalid_backup': 'Invalid backup file',
  'chapter_downloaded': 'Chapter downloaded for offline reading',
  'downloaded_deleted': 'Downloaded chapter deleted',
  'download_failed': 'Download failed: {0}',
  'url_launch_failed': 'Could not launch {0}',

  // Settings - general
  'settings_source': 'Source',
  'settings_manga_source': 'Manga Source',
  'settings_performance': 'Performance',
  'settings_general': 'General',
  'settings_player': 'Player',
  'settings_about': 'About',
  'settings_visual_mode': 'Visual Mode',
  'settings_language': 'Language',

  // Settings - player
  'use_internal_player': 'Use Internal Player',
  'cache_duration': 'Cache Duration (seconds)',

  // Performance mode
  'auto': 'Auto',
  'best_looking': 'Best Looking',
  'balanced': 'Balanced',
  'best_performance': 'Best Performance',
  'perf_auto_sub': 'Auto (Detect RAM)',
  'perf_best_looking_sub': 'Best Looking (High)',
  'perf_balanced_sub': 'Balanced (Mid)',
  'perf_best_performance_sub': 'Best Performance (Low)',

  // Source display
  'en_source': 'English',
  'vi_source': 'Vietnamese',
  'nsfw_source': 'NSFW',

  // Generic
  'continue_reading': 'Continue',
  'previous_chapter': 'Previous Chapter',
  'next_chapter': 'Next Chapter',
  'save_backup': 'Save Backup',
  'pick_backup': 'Pick Backup File',
  'check_updates': 'Check for Updates',
  'clear_cache': 'Clear Image Cache',
  'backup_data': 'Backup Data',
  'restore_data': 'Restore Data',
  'settings_title': 'Settings',

  // Welcome / Onboarding
  'welcome_title': 'Welcome',
  'welcome_subtitle': 'AniCli',
  'welcome_loading': 'Getting things ready...',
  'welcome_get_started': 'Get Started',

  // Manga reader
  'download_failed_title': 'Download failed: {0}',

  // Updater
  'updater_check_failed': 'Update check failed: {0}',
  'updater_checking': 'Checking for updates...',
  'updater_up_to_date': 'You are up to date! ({0})',
  'updater_available': 'New Update Available: {0}',
  'updater_update': 'Update',
  'updater_dismiss': 'Dismiss',
  'updater_new_version': 'New Version Available',
  'updater_later': 'Later',
  'updater_update_now': 'Update Now',
  'updater_allow_install': "Allow 'Install unknown apps' in Settings to update.",
  'updater_settings': 'Settings',
  'updater_package_manager': 'App managed by package manager. Please update via system.',
  'updater_no_asset': 'No compatible asset found.',
  'updater_downloading_title': 'Updating App',
  'updater_apk_removed': 'APK removed by Play Protect. Disable temporarily and try again.',
  'updater_install_error': 'Install Error: {0}',
  'updater_downloaded': 'Downloaded to Downloads folder.',

  // Download dialog
  'download_starting': 'Starting...',
  'download_downloading': 'Downloading...',
  'download_saved': 'Saved to: {0}',
  'download_error': 'Error: {0}',
  'download_failed_snack': 'Failed: {0}',
  'download_cancel': 'Cancel',

  // Player
  'playback_error': 'Playback error: {0}',
  'resume_title': 'Resume?',
  'resume_content': 'Left off at {0}. Continue?',
  'resume_start_over': 'Start Over',
  'resume_resume': 'Resume',
  'seek_back': '-10s',
  'seek_forward': '+10s',

  // Detail view
  'detail_download_unavailable': 'Download unavailable on mobile yet.',
  'detail_preparing_download': 'Preparing Download...',
  'detail_fetching_stream': 'Fetching Stream...',
  'detail_stream_not_found': 'Stream not found',
  'detail_download_not_found': 'Download link not found',
  'detail_select_ep_download': 'Select Ep to Download',
  'detail_play_title': '{0} - Ep {1}',

  // EpisodeRowCard (will be replaced with dynamic)
  // Using 'chapter_prefix' and 'episode_prefix' instead

  // History card
  // Using 'chapter_prefix' and 'episode_prefix' instead
};
