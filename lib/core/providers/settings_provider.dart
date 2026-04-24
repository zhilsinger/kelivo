import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:socks5_proxy/socks_client.dart' as socks;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:convert';
import '../services/search/search_service.dart';
import '../services/tts/network_tts.dart';
import '../services/network/request_logger.dart';
import '../services/logging/flutter_logger.dart';
import '../models/api_keys.dart';
import '../models/backup.dart';
import '../models/provider_group.dart';
import '../services/haptics.dart';
import '../../utils/app_directories.dart';
import '../../utils/sandbox_path_resolver.dart';
import '../../utils/avatar_cache.dart';
import '../utils/openai_model_compat.dart';
import '../../utils/provider_grouping_logic.dart';

// Desktop: topic list position
enum DesktopTopicPosition { left, right }

// Desktop: send message shortcut
enum DesktopSendShortcut { enter, ctrlEnter }

enum _MigrationResult { noChange, applied, failed }

class SettingsProvider extends ChangeNotifier {
  static const String _providersOrderKey = 'providers_order_v1';
  static const String _providerGroupsKey =
      'provider_groups_v1'; // [{id,name,createdAt}]
  static const String _providerGroupMapKey =
      'provider_group_map_v1'; // providerKey -> groupId
  static const String _providerGroupCollapsedKey =
      'provider_group_collapsed_v1'; // groupId|__ungrouped__ -> bool
  static const String _providerUngroupedPositionKey =
      'provider_ungrouped_position_v1'; // display index among groups
  static const String providerUngroupedGroupKey = '__ungrouped__';
  static const List<String> _builtInProviderKeysInOrder = [
    'OpenAI',
    'SiliconFlow',
    'Gemini',
    'OpenRouter',
    'KelivoIN',
    'Tensdaq',
    'DeepSeek',
    'AIhubmix',
    'Aliyun',
    'Zhipu AI',
    'Claude',
    'Grok',
    'ByteDance',
  ];
  static const Set<String> _builtInProviderKeys = {
    ..._builtInProviderKeysInOrder,
  };
  static const String _themeModeKey = 'theme_mode_v1';
  static const String _providerConfigsKey = 'provider_configs_v1';
  static const String _providerConfigsBackupKey = 'provider_configs_backup_v1';
  static const String _migrationsVersionKey = 'migrations_version_v1';
  static const int _embeddingOverridesMigrationVersion = 3;
  static const Set<String> _embeddingTypeStrings = {'embedding', 'embeddings'};
  static const Set<String> _embeddingChatOnlyFields = {
    'abilities',
    'output',
    'builtInTools',
    'built_in_tools',
    'tools',
  };
  static const String _pinnedModelsKey = 'pinned_models_v1';
  static const String _selectedModelKey = 'selected_model_v1';
  static const String _titleModelKey = 'title_model_v1';
  static const String _titlePromptKey = 'title_prompt_v1';
  static const String _ocrModelKey = 'ocr_model_v1';
  static const String _ocrPromptKey = 'ocr_prompt_v1';
  static const String _summaryModelKey = 'summary_model_v1';
  static const String _summaryPromptKey = 'summary_prompt_v1';
  static const String _compressModelKey = 'compress_model_v1';
  static const String _compressPromptKey = 'compress_prompt_v1';
  static const String _themePaletteKey = 'theme_palette_v1';
  static const String _useDynamicColorKey = 'use_dynamic_color_v1';
  static const String _thinkingBudgetKey = 'thinking_budget_v1';
  static const String _displayShowUserAvatarKey = 'display_show_user_avatar_v1';
  static const String _displayShowModelIconKey = 'display_show_model_icon_v1';
  static const String _displayShowModelNameTimestampKey =
      'display_show_model_name_timestamp_v1';
  static const String _displayShowTokenStatsKey = 'display_show_token_stats_v1';
  static const String _displayShowUserNameTimestampKey =
      'display_show_user_name_timestamp_v1';
  static const String _displayShowUserNameKey = 'display_show_user_name_v1';
  static const String _displayShowUserTimestampKey =
      'display_show_user_timestamp_v1';
  static const String _displayShowModelNameKey = 'display_show_model_name_v1';
  static const String _displayShowModelTimestampKey =
      'display_show_model_timestamp_v1';
  static const String _displayShowUserMessageActionsKey =
      'display_show_user_message_actions_v1';
  static const String _displayAutoCollapseThinkingKey =
      'display_auto_collapse_thinking_v1';
  static const String _displayCollapseThinkingStepsKey =
      'display_collapse_thinking_steps_v1';
  static const String _displayShowToolResultSummaryKey =
      'display_show_tool_result_summary_v1';
  static const String _displayShowMessageNavKey = 'display_show_message_nav_v1';
  static const String _displayUseNewAssistantAvatarUxKey =
      'display_use_new_assistant_avatar_ux_v1';
  static const String _displayShowProviderInModelCapsuleKey =
      'display_show_provider_in_model_capsule_v1';
  static const String _displayShowProviderInChatMessageKey =
      'display_show_provider_in_chat_message_v1';
  static const String _displayHapticsOnGenerateKey =
      'display_haptics_on_generate_v1';
  static const String _displayHapticsOnDrawerKey =
      'display_haptics_on_drawer_v1';
  static const String _displayHapticsGlobalEnabledKey =
      'display_haptics_global_enabled_v1';
  static const String _displayHapticsIosSwitchKey =
      'display_haptics_ios_switch_v1';
  static const String _displayHapticsOnListItemTapKey =
      'display_haptics_on_list_item_tap_v1';
  static const String _displayHapticsOnCardTapKey =
      'display_haptics_on_card_tap_v1';
  static const String _displayShowAppUpdatesKey = 'display_show_app_updates_v1';
  static const String _displayKeepSidebarOpenOnAssistantTapKey =
      'display_keep_sidebar_open_on_assistant_tap_v1';
  static const String _displayKeepSidebarOpenOnTopicTapKey =
      'display_keep_sidebar_open_on_topic_tap_v1';
  static const String _displayKeepAssistantListExpandedOnSidebarCloseKey =
      'display_keep_assistant_list_expanded_on_sidebar_close_v1';
  static const String _displayNewChatOnAssistantSwitchKey =
      'display_new_chat_on_assistant_switch_v1';
  static const String _displayNewChatOnLaunchKey =
      'display_new_chat_on_launch_v1';
  static const String _displayNewChatAfterDeleteKey =
      'display_new_chat_after_delete_v1';
  static const String _displayEnterToSendOnMobileKey =
      'display_enter_to_send_on_mobile_v1';
  static const String _desktopSendShortcutKey = 'desktop_send_shortcut_v1';
  static const String _displayChatFontScaleKey = 'display_chat_font_scale_v1';
  static const String _displayAutoScrollEnabledKey =
      'display_auto_scroll_enabled_v1';
  static const String _displayAutoScrollIdleSecondsKey =
      'display_auto_scroll_idle_seconds_v1';
  static const String _displayChatBackgroundMaskStrengthKey =
      'display_chat_background_mask_strength_v1';
  static const String _displayEnableDollarLatexKey =
      'display_enable_dollar_latex_v1';
  static const String _displayEnableMathRenderingKey =
      'display_enable_math_rendering_v1';
  static const String _displayEnableUserMarkdownKey =
      'display_enable_user_markdown_v1';
  static const String _displayEnableReasoningMarkdownKey =
      'display_enable_reasoning_markdown_v1';
  static const String _displayEnableAssistantMarkdownKey =
      'display_enable_assistant_markdown_v1';
  static const String _displayShowChatListDateKey =
      'display_show_chat_list_date_v1';
  static const String _displayMobileCodeBlockWrapKey =
      'display_mobile_code_block_wrap_v1';
  static const String _displayAutoCollapseCodeBlockKey =
      'display_auto_collapse_code_block_v1';
  static const String _displayAutoCollapseCodeBlockLinesKey =
      'display_auto_collapse_code_block_lines_v1';
  static const String _displayDesktopAutoSwitchTopicsKey =
      'display_desktop_auto_switch_topics_v1';
  static const String _displayDesktopShowTrayKey =
      'display_desktop_show_tray_v1';
  static const String _displayDesktopMinimizeToTrayOnCloseKey =
      'display_desktop_minimize_to_tray_on_close_v1';
  static const String _displayUsePureBackgroundKey =
      'display_use_pure_background_v1';
  static const String _displayChatMessageBackgroundStyleKey =
      'display_chat_message_background_style_v1';
  // Network request logging (debug)
  static const String _requestLogEnabledKey = 'request_log_enabled_v1';
  // Flutter runtime logging (debug)
  static const String _flutterLogEnabledKey = 'flutter_log_enabled_v1';
  // Log settings: save response output, auto-delete, max size
  static const String _logSaveOutputKey = 'log_save_output_v1';
  static const String _logAutoDeleteDaysKey = 'log_auto_delete_days_v1';
  static const String _logMaxSizeMBKey = 'log_max_size_mb_v1';
  // Desktop topic panel placement + right sidebar open state
  static const String _desktopTopicPositionKey = 'desktop_topic_position_v1';
  static const String _desktopRightSidebarOpenKey =
      'desktop_right_sidebar_open_v1';
  // Android background chat generation mode
  static const String _androidBackgroundChatModeKey =
      'android_background_chat_mode_v1';
  // Agentic orchestration
  static const String _orchestrationEnabledKey = 'orchestration_enabled_v1';
  // Fonts
  static const String _displayAppFontFamilyKey = 'display_app_font_family_v1';
  static const String _displayCodeFontFamilyKey = 'display_code_font_family_v1';
  static const String _displayAppFontIsGoogleKey =
      'display_app_font_is_google_v1';
  static const String _displayCodeFontIsGoogleKey =
      'display_code_font_is_google_v1';
  static const String _displayAppFontLocalPathKey =
      'display_app_font_local_path_v1';
  static const String _displayCodeFontLocalPathKey =
      'display_code_font_local_path_v1';
  static const String _displayAppFontLocalAliasKey =
      'display_app_font_local_alias_v1';
  static const String _displayCodeFontLocalAliasKey =
      'display_code_font_local_alias_v1';
  static const String _appLocaleKey = 'app_locale_v1';
  static const String _translateModelKey = 'translate_model_v1';
  static const String _translatePromptKey = 'translate_prompt_v1';
  static const String _translateTargetLangKey = 'translate_target_lang_v1';
  static const String _ocrEnabledKey = 'ocr_enabled_v1';
  static const String _learningModeEnabledKey = 'learning_mode_enabled_v1';
  static const String _learningModePromptKey = 'learning_mode_prompt_v1';
  static const String _searchServicesKey = 'search_services_v1';
  static const String _searchCommonKey = 'search_common_v1';
  static const String _searchSelectedKey = 'search_selected_v1';
  static const String _searchEnabledKey = 'search_enabled_v1';
  static const String _searchAutoTestOnLaunchKey =
      'search_auto_test_on_launch_v1';
  static const String _webDavConfigKey = 'webdav_config_v1';
  static const String _s3ConfigKey = 's3_config_v1';
  // Global network proxy
  static const String _globalProxyEnabledKey = 'global_proxy_enabled_v1';
  static const String _globalProxyTypeKey =
      'global_proxy_type_v1'; // http|https|socks5
  static const String _globalProxyHostKey = 'global_proxy_host_v1';
  static const String _globalProxyPortKey = 'global_proxy_port_v1';
  static const String _globalProxyUsernameKey = 'global_proxy_username_v1';
  static const String _globalProxyPasswordKey = 'global_proxy_password_v1';
  static const String _globalProxyBypassKey = 'global_proxy_bypass_v1';
  static const String _defaultGlobalProxyBypassRules =
      'localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16,::1';
  // TTS services (network)
  static const String _ttsServicesKey = 'tts_services_v1';
  static const String _ttsSelectedKey = 'tts_selected_v1';
  // Desktop UI
  static const String _desktopSidebarWidthKey = 'desktop_sidebar_width_v1';
  static const String _desktopSidebarOpenKey = 'desktop_sidebar_open_v1';
  static const String _desktopRightSidebarWidthKey =
      'desktop_right_sidebar_width_v1';

  // ===== Supabase Sync Config =====
  static const String _supabaseUrlKey = 'supabase_url_v1';
  static const String _supabaseAnonKeyKey = 'supabase_anon_key_v1';

  // ===== Network TTS services =====
  List<TtsServiceOptions> _ttsServices = const <TtsServiceOptions>[];
  int _ttsServiceSelected = -1; // -1 => use System TTS
  List<TtsServiceOptions> get ttsServices => _ttsServices;
  int get ttsServiceSelected => _ttsServiceSelected;
  bool get usingSystemTts => _ttsServiceSelected < 0;
  TtsServiceOptions? get selectedTtsService =>
      (_ttsServiceSelected >= 0 && _ttsServiceSelected < _ttsServices.length)
      ? _ttsServices[_ttsServiceSelected]
      : null;

  List<String> _providersOrder = const [];
  List<String> get providersOrder => _providersOrder;

  // ===== Provider grouping =====
  List<ProviderGroup> _providerGroups = const <ProviderGroup>[];
  Map<String, String> _providerGroupMap =
      <String, String>{}; // providerKey -> groupId
  final Map<String, bool> _providerGroupCollapsed =
      <String, bool>{}; // groupId|__ungrouped__ -> bool
  int _providerUngroupedPosition = 0;

  List<ProviderGroup> get providerGroups => List.unmodifiable(_providerGroups);
  int get providerUngroupedDisplayIndex =>
      _providerUngroupedPosition.clamp(0, _providerGroups.length);

  ProviderGroup? groupById(String id) {
    for (final g in _providerGroups) {
      if (g.id == id) return g;
    }
    return null;
  }

  String? groupIdForProvider(String providerKey) {
    final gid = _providerGroupMap[providerKey];
    if (gid == null) return null;
    return groupById(gid) == null ? null : gid;
  }

  bool get providerGroupingActive {
    for (final entry in _providerGroupMap.entries) {
      final gid = entry.value;
      if (groupById(gid) != null) return true;
    }
    return false;
  }

  bool isGroupCollapsed(String groupIdOrUngrouped) =>
      _providerGroupCollapsed[groupIdOrUngrouped] ?? false;

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;
  // Theme palette & dynamic color
  String _themePaletteId = 'default';
  String get themePaletteId => _themePaletteId;
  bool _useDynamicColor = true; // when supported on Android
  bool get useDynamicColor => _useDynamicColor;
  bool _dynamicColorSupported = false; // runtime capability, not persisted
  bool get dynamicColorSupported => _dynamicColorSupported;

  // When enabled, force pure white/black backgrounds regardless of theme color
  bool _usePureBackground = false;
  bool get usePureBackground => _usePureBackground;

  // Desktop UI persisted state
  double _desktopSidebarWidth = 240;
  bool _desktopSidebarOpen = true;
  double get desktopSidebarWidth => _desktopSidebarWidth;
  bool get desktopSidebarOpen => _desktopSidebarOpen;
  double _desktopRightSidebarWidth = 300;
  double get desktopRightSidebarWidth => _desktopRightSidebarWidth;

  // Desktop: topic list position (left or right) and right sidebar open state
  DesktopTopicPosition _desktopTopicPosition = DesktopTopicPosition.left;
  DesktopTopicPosition get desktopTopicPosition => _desktopTopicPosition;
  bool get desktopTopicsOnRight =>
      _desktopTopicPosition == DesktopTopicPosition.right;
  bool _desktopRightSidebarOpen = true;
  bool get desktopRightSidebarOpen => _desktopRightSidebarOpen;

  // ===== Agentic Orchestration =====
  bool _orchestrationEnabled = false;
  bool get orchestrationEnabled => _orchestrationEnabled;

  // ===== Supabase Sync =====
  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;
  bool get supabaseConfigured =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  Map<String, ProviderConfig> _providerConfigs = {};
  Map<String, ProviderConfig> get providerConfigs =>
      Map.unmodifiable(_providerConfigs);
  bool get hasAnyActiveModel =>
      _providerConfigs.values.any((c) => c.enabled && c.models.isNotEmpty);
  // Returns a config for the given key without mutating internal state when missing.
  // This avoids implicitly creating providers during read paths (e.g., rendering old chats).
  ProviderConfig getProviderConfig(String key, {String? defaultName}) {
    final existed = _providerConfigs[key];
    if (existed != null) return existed;
    // Return a non-persisted, default-constructed config for read-only scenarios.
    return ProviderConfig.defaultsFor(key, displayName: defaultName);
  }

  String resolveOpenAIUpstreamModelId(String providerKey, String modelId) {
    final cfg = getProviderConfig(providerKey);
    final kind = ProviderConfig.classify(
      cfg.id,
      explicitType: cfg.providerType,
    );
    if (kind != ProviderKind.openai) return modelId;
    final rawOv = cfg.modelOverrides[modelId];
    final ov = rawOv is Map ? rawOv.cast<String, dynamic>() : null;
    return resolveApiModelIdOverride(ov, modelId);
  }

  bool supportsOpenAIXhighReasoning(String providerKey, String modelId) {
    final cfg = getProviderConfig(providerKey);
    final kind = ProviderConfig.classify(
      cfg.id,
      explicitType: cfg.providerType,
    );
    if (kind != ProviderKind.openai) return false;
    final modelForCheck = resolveOpenAIUpstreamModelId(providerKey, modelId);
    return openAISupportsXhighReasoning(modelForCheck);
  }

  // Explicitly ensure a provider config exists in memory (without persisting to storage).
  // Useful for seeding first-run defaults.
  ProviderConfig ensureProviderConfig(String key, {String? defaultName}) {
    final existed = _providerConfigs[key];
    if (existed != null) return existed;
    final cfg = ProviderConfig.defaultsFor(key, displayName: defaultName);
    _providerConfigs[key] = cfg;
    return cfg;
  }

  // Search service settings
  List<SearchServiceOptions> _searchServices = [
    SearchServiceOptions.defaultOption,
  ];
  List<SearchServiceOptions> get searchServices =>
      List.unmodifiable(_searchServices);
  SearchCommonOptions _searchCommonOptions = const SearchCommonOptions();
  SearchCommonOptions get searchCommonOptions => _searchCommonOptions;
  int _searchServiceSelected = 0;
  int get searchServiceSelected => _searchServiceSelected;
  bool _searchEnabled = false;
  bool get searchEnabled => _searchEnabled;
  bool _searchAutoTestOnLaunch = false;
  bool get searchAutoTestOnLaunch => _searchAutoTestOnLaunch;
  // Ephemeral connection test results: serviceId -> connected (true), failed (false), or null (not tested)
  final Map<String, bool?> _searchConnection = <String, bool?>{};
  Map<String, bool?> get searchConnection =>
      Map.unmodifiable(_searchConnection);

  // ===== Global Proxy Settings =====
  bool _globalProxyEnabled = false;
  String _globalProxyType = 'http';
  String _globalProxyHost = '';
  String _globalProxyPort = '8080';
  String _globalProxyUsername = '';
  String _globalProxyPassword = '';
  String _globalProxyBypass = _defaultGlobalProxyBypassRules;

  bool get globalProxyEnabled => _globalProxyEnabled;
  String get globalProxyType => _globalProxyType; // http|https|socks5
  String get globalProxyHost => _globalProxyHost;
  String get globalProxyPort => _globalProxyPort;
  String get globalProxyUsername => _globalProxyUsername;
  String get globalProxyPassword => _globalProxyPassword;
  String get globalProxyBypass => _globalProxyBypass;

  SettingsProvider() {
    _load();
  }

  // ===== Agentic Orchestration =====
  Future<void> setOrchestrationEnabled(bool value) async {
    if (_orchestrationEnabled == value) return;
    _orchestrationEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_orchestrationEnabledKey, value);
  }

  Future<_MigrationResult> _migrateEmbeddingModelOverrides(
    SharedPreferences prefs,
  ) async {
    Map<String, ProviderConfig>? nextProviderConfigs;
    int providersChanged = 0;
    int modelsChanged = 0;

    for (final entry in _providerConfigs.entries) {
      final providerKey = entry.key;
      final cfg = entry.value;
      Map<String, dynamic>? nextOverrides;

      for (final ovEntry in cfg.modelOverrides.entries) {
        final modelKey = ovEntry.key;
        final rawOv = ovEntry.value;
        if (rawOv is! Map) continue;

        final normalizedRawOv = rawOv.map((k, v) => MapEntry(k.toString(), v));
        final t = (normalizedRawOv['type'] ?? normalizedRawOv['t'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        if (!_embeddingTypeStrings.contains(t)) continue;

        final hasChatOnlyKeys = _embeddingChatOnlyFields.any(
          normalizedRawOv.containsKey,
        );
        if (!hasChatOnlyKeys) continue;

        nextOverrides ??= Map<String, dynamic>.from(cfg.modelOverrides);
        final m = Map<String, dynamic>.from(normalizedRawOv);
        for (final k in _embeddingChatOnlyFields) {
          m.remove(k);
        }
        nextOverrides[modelKey] = m;
        modelsChanged++;
      }

      if (nextOverrides == null) continue;
      nextProviderConfigs ??= Map<String, ProviderConfig>.from(
        _providerConfigs,
      );
      nextProviderConfigs[providerKey] = cfg.copyWith(
        modelOverrides: nextOverrides,
      );
      providersChanged++;
    }

    if (nextProviderConfigs == null) return _MigrationResult.noChange;
    try {
      final map = nextProviderConfigs.map((k, v) => MapEntry(k, v.toJson()));
      final encoded = jsonEncode(map);
      final ok = await prefs.setString(_providerConfigsKey, encoded);
      if (!ok) return _MigrationResult.failed;
    } catch (e, st) {
      assert(() {
        debugPrint(
          '[SettingsProvider] provider configs migration persist failed: $e',
        );
        debugPrint('$st');
        return true;
      }());
      return _MigrationResult.failed;
    }

    _providerConfigs = nextProviderConfigs;
    assert(() {
      debugPrint(
        '[SettingsProvider] embedding overrides migration: providers=$providersChanged, models=$modelsChanged',
      );
      return true;
    }());
    return _MigrationResult.applied;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _providersOrder = prefs.getStringList(_providersOrderKey) ?? [];
    final m = prefs.getString(_themeModeKey);
    switch (m) {
      case 'light':
        _themeMode = ThemeMode.light;
        break;
      case 'dark':
        _themeMode = ThemeMode.dark;
        break;
      default:
        _themeMode = ThemeMode.system;
    }
    _themePaletteId = prefs.getString(_themePaletteKey) ?? 'default';
    _useDynamicColor = prefs.getBool(_useDynamicColorKey) ?? true;
    // Agentic orchestration
    _orchestrationEnabled = prefs.getBool(_orchestrationEnabledKey) ?? false;
    // Load Supabase config
    _supabaseUrl = prefs.getString(_supabaseUrlKey) ?? '';
    _supabaseAnonKey = prefs.getString(_supabaseAnonKeyKey) ?? '';
    var providerConfigsLoaded = false;
    final cfgStr = prefs.getString(_providerConfigsKey);
    if (cfgStr != null && cfgStr.isNotEmpty) {
      try {
        final raw = jsonDecode(cfgStr) as Map<String, dynamic>;
        _providerConfigs = raw.map(
          (k, v) =>
              MapEntry(k, ProviderConfig.fromJson(v as Map<String, dynamic>)),
        );
        providerConfigsLoaded = true;
      } catch (e, st) {
        assert(() {
          debugPrint('[SettingsProvider] providerConfigs decode failed: $e');
          debugPrint('$st');
          return true;
        }());
      }
    }

    // Cleanup legacy embedding overrides persisted before type-switch safeguards.
    try {
      final migrationVersion = prefs.getInt(_migrationsVersionKey) ?? 0;
      if (providerConfigsLoaded &&
          migrationVersion < _embeddingOverridesMigrationVersion) {
        try {
          FlutterLogger.log(
            '[SettingsProvider] provider modelOverrides migration start',
            tag: 'Migration',
          );
        } catch (_) {}

        var backupOk = true;
        if (!prefs.containsKey(_providerConfigsBackupKey)) {
          final backup = _providerConfigs.map(
            (k, v) => MapEntry(k, v.toJson()),
          );
          backupOk = await prefs.setString(
            _providerConfigsBackupKey,
            jsonEncode(backup),
          );
          assert(() {
            debugPrint(
              '[SettingsProvider] provider configs backup saved before migration.',
            );
            return true;
          }());
          if (!backupOk) {
            assert(() {
              debugPrint(
                '[SettingsProvider] provider configs backup failed; abort migration.',
              );
              return true;
            }());
          }
        }

        if (backupOk) {
          final result = await _migrateEmbeddingModelOverrides(prefs);
          if (result != _MigrationResult.failed) {
            await prefs.setInt(
              _migrationsVersionKey,
              _embeddingOverridesMigrationVersion,
            );
          }
          assert(() {
            if (result == _MigrationResult.applied) {
              debugPrint(
                '[SettingsProvider] provider modelOverrides migration applied.',
              );
            }
            return true;
          }());
          try {
            FlutterLogger.log(
              '[SettingsProvider] provider modelOverrides migration done (result=$result)',
              tag: 'Migration',
            );
          } catch (_) {}
        }
      }
    } catch (e, st) {
      try {
        FlutterLogger.log(
          '[SettingsProvider] provider modelOverrides migration failed: $e\n$st',
          tag: 'Migration',
        );
      } catch (_) {}
      assert(() {
        debugPrint(
          '[SettingsProvider] provider modelOverrides migration failed: $e',
        );
        debugPrint('$st');
        return true;
      }());
    }

    // load provider grouping
    try {
      final groupsStr = prefs.getString(_providerGroupsKey) ?? '';
      _providerGroups = groupsStr.isEmpty
          ? const <ProviderGroup>[]
          : ProviderGroup.decodeList(groupsStr);
    } catch (_) {
      _providerGroups = const <ProviderGroup>[];
    }
    try {
      final mapStr = prefs.getString(_providerGroupMapKey) ?? '';
      if (mapStr.isNotEmpty) {
        final raw = jsonDecode(mapStr) as Map<String, dynamic>;
        _providerGroupMap = raw.map((k, v) => MapEntry(k, v.toString()));
      } else {
        _providerGroupMap = <String, String>{};
      }
    } catch (_) {
      _providerGroupMap = <String, String>{};
    }
    try {
      final collapsedStr = prefs.getString(_providerGroupCollapsedKey) ?? '';
      if (collapsedStr.isNotEmpty) {
        final raw = jsonDecode(collapsedStr) as Map<String, dynamic>;
        _providerGroupCollapsed
          ..clear()
          ..addAll(
            raw.map(
              (k, v) => MapEntry(k, (v is bool) ? v : (v.toString() == 'true')),
            ),
          );
      } else {
        _providerGroupCollapsed.clear();
      }
    } catch (_) {
      _providerGroupCollapsed.clear();
    }
    _providerUngroupedPosition =
        prefs.getInt(_providerUngroupedPositionKey) ?? _providerGroups.length;
    // load pinned models
    final pinned = prefs.getStringList(_pinnedModelsKey) ?? const <String>[];
    _pinnedModels
      ..clear()
      ..addAll(pinned);
    // load selected model
    final sel = prefs.getString(_selectedModelKey);
    if (sel != null && sel.contains('::')) {
      final parts = sel.split('::');
      if (parts.length >= 2) {
        _currentModelProvider = parts[0];
        _currentModelId = parts.sublist(1).join('::');
      }
    }
    // load title model
    final titleSel = prefs.getString(_titleModelKey);
    if (titleSel != null && titleSel.contains('::')) {
      final parts = titleSel.split('::');
      if (parts.length >= 2) {
        _titleModelProvider = parts[0];
        _titleModelId = parts.sublist(1).join('::');
      }
    }
    // load title prompt
    final tp = prefs.getString(_titlePromptKey);
    _titlePrompt = (tp == null || tp.trim().isEmpty) ? defaultTitlePrompt : tp;
    // load translate model
    final translateSel = prefs.getString(_translateModelKey);
    if (translateSel != null && translateSel.contains('::')) {
      final parts = translateSel.split('::');
      if (parts.length >= 2) {
        _translateModelProvider = parts[0];
        _translateModelId = parts.sublist(1).join('::');
      }
    }
    // load translate prompt
    final transp = prefs.getString(_translatePromptKey);
    _translatePrompt = (transp == null || transp.trim().isEmpty)
        ? defaultTranslatePrompt
        : transp;
    // load translate target language
    final targetLang = prefs.getString(_translateTargetLangKey);
    if (targetLang != null && targetLang.trim().isNotEmpty) {
      _translateTargetLang = targetLang.trim();
    }
    // load OCR model
    final ocrSel = prefs.getString(_ocrModelKey);
    if (ocrSel != null && ocrSel.contains('::')) {
      final parts = ocrSel.split('::');
      if (parts.length >= 2) {
        _ocrModelProvider = parts[0];
        _ocrModelId = parts.sublist(1).join('::');
      }
    }
    // load OCR prompt
    final ocrp = prefs.getString(_ocrPromptKey);
    _ocrPrompt = (ocrp == null || ocrp.trim().isEmpty)
        ? defaultOcrPrompt
        : ocrp;
    // load OCR enabled (only effective when model is configured)
    _ocrEnabled = prefs.getBool(_ocrEnabledKey) ?? false;
    if (_ocrModelProvider == null || _ocrModelId == null) {
      _ocrEnabled = false;
    }
    // load summary model
    final summarySel = prefs.getString(_summaryModelKey);
    if (summarySel != null && summarySel.contains('::')) {
      final parts = summarySel.split('::');
      if (parts.length >= 2) {
        _summaryModelProvider = parts[0];
        _summaryModelId = parts.sublist(1).join('::');
      }
    }
    // load summary prompt
    final summaryp = prefs.getString(_summaryPromptKey);
    _summaryPrompt = (summaryp == null || summaryp.trim().isEmpty)
        ? defaultSummaryPrompt
        : summaryp;
    // load compress model
    final compressSel = prefs.getString(_compressModelKey);
    if (compressSel != null && compressSel.contains('::')) {
      final parts = compressSel.split('::');
      if (parts.length >= 2) {
        _compressModelProvider = parts[0];
        _compressModelId = parts.sublist(1).join('::');
      }
    }
    // load compress prompt
    final compressp = prefs.getString(_compressPromptKey);
    _compressPrompt = (compressp == null || compressp.trim().isEmpty)
        ? defaultCompressPrompt
        : compressp;
    // learning mode
    _learningModeEnabled = prefs.getBool(_learningModeEnabledKey) ?? false;
    final lmp = prefs.getString(_learningModePromptKey);
    _learningModePrompt = (lmp == null || lmp.trim().isEmpty)
        ? defaultLearningModePrompt
        : lmp;
    // load thinking budget (reasoning strength)
    _thinkingBudget = prefs.getInt(_thinkingBudgetKey);

    // display settings
    _showUserAvatar = prefs.getBool(_displayShowUserAvatarKey) ?? true;
    _showModelIcon = prefs.getBool(_displayShowModelIconKey) ?? true;
    _showModelNameTimestamp =
        prefs.getBool(_displayShowModelNameTimestampKey) ?? true;
    _showTokenStats = prefs.getBool(_displayShowTokenStatsKey) ?? true;
    _showUserNameTimestamp =
        prefs.getBool(_displayShowUserNameTimestampKey) ?? true;
    // new split settings: default to the legacy combined setting value for backward compat
    final legacyUserNameTs = _showUserNameTimestamp;
    _showUserName = prefs.getBool(_displayShowUserNameKey) ?? legacyUserNameTs;
    _showUserTimestamp =
        prefs.getBool(_displayShowUserTimestampKey) ?? legacyUserNameTs;
    final legacyModelNameTs = _showModelNameTimestamp;
    _showModelName =
        prefs.getBool(_displayShowModelNameKey) ?? legacyModelNameTs;
    _showModelTimestamp =
        prefs.getBool(_displayShowModelTimestampKey) ?? legacyModelNameTs;
    _showUserMessageActions =
        prefs.getBool(_displayShowUserMessageActionsKey) ?? true;
    _autoCollapseThinking =
        prefs.getBool(_displayAutoCollapseThinkingKey) ?? true;
    _collapseThinkingSteps =
        prefs.getBool(_displayCollapseThinkingStepsKey) ?? false;
    _showToolResultSummary =
        prefs.getBool(_displayShowToolResultSummaryKey) ?? false;
    _showMessageNavButtons = prefs.getBool(_displayShowMessageNavKey) ?? true;
    _useNewAssistantAvatarUx =
        prefs.getBool(_displayUseNewAssistantAvatarUxKey) ?? false;
    _showProviderInModelCapsule =
        prefs.getBool(_displayShowProviderInModelCapsuleKey) ?? true;
    _showProviderInChatMessage =
        prefs.getBool(_displayShowProviderInChatMessageKey) ?? false;
    _hapticsOnGenerate = prefs.getBool(_displayHapticsOnGenerateKey) ?? false;
    _hapticsOnDrawer = prefs.getBool(_displayHapticsOnDrawerKey) ?? true;
    _hapticsGlobalEnabled =
        prefs.getBool(_displayHapticsGlobalEnabledKey) ?? true;
    _hapticsIosSwitch = prefs.getBool(_displayHapticsIosSwitchKey) ?? true;
    _hapticsOnListItemTap =
        prefs.getBool(_displayHapticsOnListItemTapKey) ?? true;
    _hapticsOnCardTap = prefs.getBool(_displayHapticsOnCardTapKey) ?? true;
    // Apply global haptics to service layer
    Haptics.setEnabled(_hapticsGlobalEnabled);
    _showAppUpdates = prefs.getBool(_displayShowAppUpdatesKey) ?? true;
    _keepSidebarOpenOnAssistantTap =
        prefs.getBool(_displayKeepSidebarOpenOnAssistantTapKey) ?? false;
    _keepSidebarOpenOnTopicTap =
        prefs.getBool(_displayKeepSidebarOpenOnTopicTapKey) ?? false;
    _keepAssistantListExpandedOnSidebarClose =
        prefs.getBool(_displayKeepAssistantListExpandedOnSidebarCloseKey) ??
        false;
    _requestLogEnabled = prefs.getBool(_requestLogEnabledKey) ?? false;
    await RequestLogger.setEnabled(_requestLogEnabled);
    _flutterLogEnabled = prefs.getBool(_flutterLogEnabledKey) ?? false;
    await FlutterLogger.setEnabled(_flutterLogEnabled);
    _logSaveOutput = prefs.getBool(_logSaveOutputKey) ?? true;
    RequestLogger.saveOutput = _logSaveOutput;
    _logAutoDeleteDays = prefs.getInt(_logAutoDeleteDaysKey) ?? 0;
    _logMaxSizeMB = prefs.getInt(_logMaxSizeMBKey) ?? 0;
    // Run log cleanup based on current settings
    RequestLogger.cleanupLogs(
      autoDeleteDays: _logAutoDeleteDays,
      maxSizeMB: _logMaxSizeMB,
    );
    _newChatOnLaunch = prefs.getBool(_displayNewChatOnLaunchKey) ?? true;
    _newChatOnAssistantSwitch =
        prefs.getBool(_displayNewChatOnAssistantSwitchKey) ?? false;
    _newChatAfterDelete = prefs.getBool(_displayNewChatAfterDeleteKey) ?? false;
    // Enter to send on mobile: iOS defaults to true, Android defaults to false
    final enterToSendPref = prefs.getBool(_displayEnterToSendOnMobileKey);
    if (enterToSendPref == null) {
      _enterToSendOnMobile = Platform.isIOS;
      await prefs.setBool(_displayEnterToSendOnMobileKey, _enterToSendOnMobile);
    } else {
      _enterToSendOnMobile = enterToSendPref;
    }
    // Desktop send shortcut: Enter (default) or Ctrl/Cmd+Enter
    final sendShortcutStr = prefs.getString(_desktopSendShortcutKey);
    switch (sendShortcutStr) {
      case 'ctrlEnter':
        _desktopSendShortcut = DesktopSendShortcut.ctrlEnter;
        break;
      case 'enter':
      default:
        _desktopSendShortcut = DesktopSendShortcut.enter;
    }
    _chatFontScale = prefs.getDouble(_displayChatFontScaleKey) ?? 1.0;
    _autoScrollEnabled = prefs.getBool(_displayAutoScrollEnabledKey) ?? true;
    _autoScrollIdleSeconds =
        prefs.getInt(_displayAutoScrollIdleSecondsKey) ?? 8;
    _chatBackgroundMaskStrength =
        prefs.getDouble(_displayChatBackgroundMaskStrengthKey) ?? 1.0;
    final pureBgPref = prefs.getBool(_displayUsePureBackgroundKey);
    if (pureBgPref == null) {
      final isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      _usePureBackground = isDesktop;
      await prefs.setBool(_displayUsePureBackgroundKey, _usePureBackground);
    } else {
      _usePureBackground = pureBgPref;
    }
    // display: markdown/math rendering
    _enableDollarLatex = prefs.getBool(_displayEnableDollarLatexKey) ?? true;
    _enableMathRendering =
        prefs.getBool(_displayEnableMathRenderingKey) ?? true;
    _enableUserMarkdown = prefs.getBool(_displayEnableUserMarkdownKey) ?? true;
    _enableReasoningMarkdown =
        prefs.getBool(_displayEnableReasoningMarkdownKey) ?? true;
    _enableAssistantMarkdown =
        prefs.getBool(_displayEnableAssistantMarkdownKey) ?? true;
    _showChatListDate = prefs.getBool(_displayShowChatListDateKey) ?? false;
    _mobileCodeBlockWrap =
        prefs.getBool(_displayMobileCodeBlockWrapKey) ?? false;
    _autoCollapseCodeBlock =
        prefs.getBool(_displayAutoCollapseCodeBlockKey) ?? false;
    _autoCollapseCodeBlockLines =
        (prefs.getInt(_displayAutoCollapseCodeBlockLinesKey) ?? 2).clamp(
          1,
          999,
        );
    _desktopAutoSwitchTopics =
        prefs.getBool(_displayDesktopAutoSwitchTopicsKey) ?? false;
    // Desktop: tray settings (default enabled on desktop platforms)
    final trayPref = prefs.getBool(_displayDesktopShowTrayKey);
    if (trayPref == null) {
      final isDesktop =
          Platform.isMacOS || Platform.isWindows || Platform.isLinux;
      _desktopShowTray = isDesktop;
      await prefs.setBool(_displayDesktopShowTrayKey, _desktopShowTray);
    } else {
      _desktopShowTray = trayPref;
    }
    final minimizeTrayPref = prefs.getBool(
      _displayDesktopMinimizeToTrayOnCloseKey,
    );
    if (minimizeTrayPref == null) {
      _desktopMinimizeToTrayOnClose = _desktopShowTray;
      await prefs.setBool(
        _displayDesktopMinimizeToTrayOnCloseKey,
        _desktopMinimizeToTrayOnClose,
      );
    } else {
      // Enforce invariant: cannot minimize to tray if tray is hidden.
      _desktopMinimizeToTrayOnClose = minimizeTrayPref && _desktopShowTray;
      if (minimizeTrayPref && !_desktopShowTray) {
        await prefs.setBool(
          _displayDesktopMinimizeToTrayOnCloseKey,
          _desktopMinimizeToTrayOnClose,
        );
      }
    }
    // desktop: topic panel placement + right sidebar open state
    final topicPos = prefs.getString(_desktopTopicPositionKey);
    switch (topicPos) {
      case 'right':
        _desktopTopicPosition = DesktopTopicPosition.right;
        break;
      case 'left':
      default:
        _desktopTopicPosition = DesktopTopicPosition.left;
    }
    _desktopRightSidebarOpen =
        prefs.getBool(_desktopRightSidebarOpenKey) ?? true;
    // Chat message background style (default | frosted | solid)
    final bgStyleStr =
        prefs.getString(_displayChatMessageBackgroundStyleKey) ?? 'default';
    switch (bgStyleStr) {
      case 'frosted':
        _chatMessageBackgroundStyle = ChatMessageBackgroundStyle.frosted;
        break;
      case 'solid':
        _chatMessageBackgroundStyle = ChatMessageBackgroundStyle.solid;
        break;
      default:
        _chatMessageBackgroundStyle = ChatMessageBackgroundStyle.defaultStyle;
    }
    // desktop UI
    _desktopSidebarWidth = prefs.getDouble(_desktopSidebarWidthKey) ?? 300;
    _desktopSidebarOpen = prefs.getBool(_desktopSidebarOpenKey) ?? true;
    _desktopRightSidebarWidth =
        prefs.getDouble(_desktopRightSidebarWidthKey) ?? 300;
    // Load app locale; default to follow system on first launch
    _appLocaleTag = prefs.getString(_appLocaleKey);
    if (_appLocaleTag == null || _appLocaleTag!.isEmpty) {
      _appLocaleTag = 'system';
      await prefs.setString(_appLocaleKey, 'system');
    }

    // Android background chat mode (Android only; default ON on first run)
    try {
      final rawBg = prefs.getString(_androidBackgroundChatModeKey);
      if (rawBg == null) {
        // Default to OFF to avoid permission prompts on first launch
        _androidBackgroundChatMode = AndroidBackgroundChatMode.off;
        await prefs.setString(_androidBackgroundChatModeKey, 'off');
      } else {
        switch (rawBg) {
          case 'on_notify':
            _androidBackgroundChatMode = AndroidBackgroundChatMode.onNotify;
            break;
          case 'on':
            _androidBackgroundChatMode = AndroidBackgroundChatMode.on;
            break;
          case 'off':
          default:
            _androidBackgroundChatMode = AndroidBackgroundChatMode.off;
        }
      }
    } catch (_) {
      _androidBackgroundChatMode = AndroidBackgroundChatMode.off;
    }

    // load search settings
    final searchServicesStr = prefs.getString(_searchServicesKey);
    if (searchServicesStr != null && searchServicesStr.isNotEmpty) {
      try {
        final list = jsonDecode(searchServicesStr) as List;
        _searchServices = list
            .map(
              (e) => SearchServiceOptions.fromJson(e as Map<String, dynamic>),
            )
            .toList();
      } catch (_) {}
    }
    final searchCommonStr = prefs.getString(_searchCommonKey);
    if (searchCommonStr != null && searchCommonStr.isNotEmpty) {
      try {
        _searchCommonOptions = SearchCommonOptions.fromJson(
          jsonDecode(searchCommonStr) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    _searchServiceSelected = prefs.getInt(_searchSelectedKey) ?? 0;
    _searchEnabled = prefs.getBool(_searchEnabledKey) ?? false;
    _searchAutoTestOnLaunch =
        prefs.getBool(_searchAutoTestOnLaunchKey) ?? false;

    // load global proxy
    _globalProxyEnabled = prefs.getBool(_globalProxyEnabledKey) ?? false;
    _globalProxyType = prefs.getString(_globalProxyTypeKey) ?? 'http';
    _globalProxyHost = prefs.getString(_globalProxyHostKey) ?? '';
    _globalProxyPort = prefs.getString(_globalProxyPortKey) ?? '8080';
    _globalProxyUsername = prefs.getString(_globalProxyUsernameKey) ?? '';
    _globalProxyPassword = prefs.getString(_globalProxyPasswordKey) ?? '';
    final bypass = prefs.getString(_globalProxyBypassKey);
    if (bypass == null) {
      _globalProxyBypass = _defaultGlobalProxyBypassRules;
      await prefs.setString(_globalProxyBypassKey, _globalProxyBypass);
    } else {
      _globalProxyBypass = bypass;
    }

    // load network TTS services
    try {
      final ttsStr = prefs.getString(_ttsServicesKey) ?? '';
      if (ttsStr.isNotEmpty) {
        final list = jsonDecode(ttsStr) as List;
        _ttsServices = [
          for (final e in list)
            if (e is Map<String, dynamic>)
              TtsServiceOptions.fromJson(e)
            else
              TtsServiceOptions.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
      } else {
        _ttsServices = const <TtsServiceOptions>[];
      }
    } catch (_) {
      _ttsServices = const <TtsServiceOptions>[];
    }
    _ttsServiceSelected = prefs.getInt(_ttsSelectedKey) ?? -1;
    if (_ttsServiceSelected >= _ttsServices.length) {
      _ttsServiceSelected = _ttsServices.isEmpty ? -1 : 0;
      await prefs.setInt(_ttsSelectedKey, _ttsServiceSelected);
    }
    // webdav config
    final webdavStr = prefs.getString(_webDavConfigKey);
    if (webdavStr != null && webdavStr.isNotEmpty) {
      try {
        _webDavConfig = WebDavConfig.fromJson(
          jsonDecode(webdavStr) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    // s3 config
    final s3Str = prefs.getString(_s3ConfigKey);
    if (s3Str != null && s3Str.isNotEmpty) {
      try {
        _s3Config = S3Config.fromJson(
          jsonDecode(s3Str) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    if (_providerConfigs.isEmpty) {
      // Seed a couple of sensible defaults on first launch, but do not recreate
      // providers implicitly during later reads (e.g., when switching chats).
      ensureProviderConfig('KelivoIN', defaultName: 'KelivoIN');
      ensureProviderConfig('Tensdaq', defaultName: 'Tensdaq');
      ensureProviderConfig('SiliconFlow', defaultName: 'SiliconFlow');
      ensureProviderConfig('AIhubmix', defaultName: 'AIhubmix');
    }

    // kick off a one-time connectivity test for services (exclude local Bing)
    if (_searchAutoTestOnLaunch) {
      _initSearchConnectivityTests();
    }

    // Attempt to reload any user-installed local fonts (mobile platforms)
    await _reloadLocalFontsIfAny();

    // Final cleanup pass for provider order + grouping state (best-effort).
    if (_cleanupProviderOrderAndGrouping()) {
      try {
        await prefs.setStringList(_providersOrderKey, _providersOrder);
        await prefs.setString(
          _providerGroupMapKey,
          jsonEncode(_providerGroupMap),
        );
        await prefs.setString(
          _providerGroupCollapsedKey,
          jsonEncode(_providerGroupCollapsed),
        );
      } catch (_) {}
    }

    notifyListeners();
  }

  Future<void> setGlobalProxyEnabled(bool v) async {
    _globalProxyEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_globalProxyEnabledKey, _globalProxyEnabled);
  }

  Future<void> setGlobalProxyType(String v) async {
    _globalProxyType = v.trim().isEmpty ? 'http' : v.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyTypeKey, _globalProxyType);
  }

  Future<void> setGlobalProxyHost(String v) async {
    _globalProxyHost = v.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyHostKey, _globalProxyHost);
  }

  Future<void> setGlobalProxyPort(String v) async {
    _globalProxyPort = v.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyPortKey, _globalProxyPort);
  }

  Future<void> setGlobalProxyUsername(String v) async {
    _globalProxyUsername = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyUsernameKey, _globalProxyUsername);
  }

  Future<void> setGlobalProxyPassword(String v) async {
    _globalProxyPassword = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyPasswordKey, _globalProxyPassword);
  }

  Future<void> setGlobalProxyBypass(String v) async {
    _globalProxyBypass = v.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_globalProxyBypassKey, _globalProxyBypass);
  }

  // Apply global proxy to Dart IO layer; provider-level proxies take precedence at call sites.
  String _lastProxySignature = '';
  void applyGlobalProxyOverridesIfNeeded() {
    try {
      final enabled = _globalProxyEnabled;
      final host = _globalProxyHost.trim();
      final portStr = _globalProxyPort.trim();
      final user = _globalProxyUsername.trim();
      final pass = _globalProxyPassword;
      final type = _globalProxyType;
      final bypass = _globalProxyBypass;
      final sig = [enabled, type, host, portStr, user, pass, bypass].join('|');
      if (_lastProxySignature == sig) return;
      _lastProxySignature = sig;
      if (!enabled || host.isEmpty || portStr.isEmpty) {
        HttpOverrides.global = null;
        return;
      }
      final port = int.tryParse(portStr) ?? 8080;
      if (type == 'socks5') {
        HttpOverrides.global = _SocksProxyHttpOverrides(
          host: host,
          port: port,
          username: user.isEmpty ? null : user,
          password: pass,
          bypassRules: bypass,
        );
      } else {
        HttpOverrides.global = _ProxyHttpOverrides(
          host: host,
          port: port,
          username: user.isEmpty ? null : user,
          password: pass,
          bypassRules: bypass,
        );
      }
    } catch (_) {
      // ignore
    }
  }

  // ===== Supabase Config =====
  Future<void> setSupabaseConfig(String url, String anonKey) async {
    _supabaseUrl = url.trim();
    _supabaseAnonKey = anonKey.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_supabaseUrlKey, _supabaseUrl);
    await prefs.setString(_supabaseAnonKeyKey, _supabaseAnonKey);
  }

  Future<void> clearSupabaseConfig() async {
    _supabaseUrl = '';
    _supabaseAnonKey = '';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_supabaseUrlKey);
    await prefs.remove(_supabaseAnonKeyKey);
  }

  Future<void> setTtsServices(List<TtsServiceOptions> v) async {
    _ttsServices = List.unmodifiable(v);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final list = v.map((e) => e.toJson()).toList();
    await prefs.setString(_ttsServicesKey, jsonEncode(list));
    if (_ttsServiceSelected >= _ttsServices.length) {
      _ttsServiceSelected = _ttsServices.isEmpty ? -1 : 0;
      await prefs.setInt(_ttsSelectedKey, _ttsServiceSelected);
    }
  }

  Future<void> setTtsServiceSelected(int index) async {
    _ttsServiceSelected = index;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_ttsSelectedKey, _ttsServiceSelected);
  }
}