import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SideChatStore {
  static const String _prefsKey = 'side_chat_parents_v1';

  static Future<void> setParent(
      String sideChatId, String parentId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    final map = raw != null && raw.isNotEmpty
        ? Map<String, String>.from(jsonDecode(raw) as Map)
        : <String, String>{};
    map[sideChatId] = parentId;
    await prefs.setString(_prefsKey, jsonEncode(map));
  }

  static Future<String?> getParent(String sideChatId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return null;
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map[sideChatId] as String?;
  }

  static Future<bool> isSideChat(String conversationId) async {
    final parent = await getParent(conversationId);
    return parent != null;
  }

  static Future<void> remove(String sideChatId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    final map = Map<String, String>.from(jsonDecode(raw) as Map);
    map.remove(sideChatId);
    await prefs.setString(_prefsKey, jsonEncode(map));
  }
}
