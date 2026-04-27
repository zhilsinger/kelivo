import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/supabase_memory_context.dart';

/// Sidecar store for Supabase AI memory settings.
///
/// Separate from SettingsProvider per Extension-by-Addition rule.
/// All cloud memory toggles live here, not in the monolithic settings file.
class SupabaseMemorySettings extends ChangeNotifier {
  static const String _aiMemoryEnabledKey = 'supabase_ai_memory_enabled_v1';
  static const String _memoryModeKey = 'supabase_memory_mode_v1';
  static const String _maxChunksKey = 'supabase_max_chunks_v1';
  static const String _maxTokensKey = 'supabase_max_memory_tokens_v1';

  bool _aiMemoryEnabled = false;
  SupabaseMemoryMode _memoryMode = SupabaseMemoryMode.currentThread;
  int _maxChunksPerSearch = 8;
  int _maxMemoryTokens = 2000;

  bool get aiMemoryEnabled => _aiMemoryEnabled;
  SupabaseMemoryMode get memoryMode => _memoryMode;
  int get maxChunksPerSearch => _maxChunksPerSearch;
  int get maxMemoryTokens => _maxMemoryTokens;

  SupabaseMemorySettings() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _aiMemoryEnabled = prefs.getBool(_aiMemoryEnabledKey) ?? false;
    final modeStr = prefs.getString(_memoryModeKey) ?? 'currentThread';
    _memoryMode = _parseMode(modeStr);
    _maxChunksPerSearch = prefs.getInt(_maxChunksKey) ?? 8;
    _maxMemoryTokens = prefs.getInt(_maxTokensKey) ?? 2000;
    notifyListeners();
  }

  Future<void> setAiMemoryEnabled(bool v) async {
    if (_aiMemoryEnabled == v) return;
    _aiMemoryEnabled = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_aiMemoryEnabledKey, v);
  }

  Future<void> setMemoryMode(SupabaseMemoryMode v) async {
    if (_memoryMode == v) return;
    _memoryMode = v;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_memoryModeKey, v.name);
  }

  Future<void> setMaxChunksPerSearch(int v) async {
    final clamped = v.clamp(1, 50);
    if (_maxChunksPerSearch == clamped) return;
    _maxChunksPerSearch = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxChunksKey, clamped);
  }

  Future<void> setMaxMemoryTokens(int v) async {
    final clamped = v.clamp(100, 20000);
    if (_maxMemoryTokens == clamped) return;
    _maxMemoryTokens = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_maxTokensKey, clamped);
  }

  static SupabaseMemoryMode _parseMode(String s) {
    return SupabaseMemoryMode.values.firstWhere(
      (e) => e.name == s,
      orElse: () => SupabaseMemoryMode.currentThread,
    );
  }
}
