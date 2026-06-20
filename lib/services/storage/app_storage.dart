import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static late SharedPreferences _prefs;
  static const _secureStorage = FlutterSecureStorage();

  // SharedPreferences keys
  static const _kProviders = 'providers';
  static const _kSelectedMode = 'selected_mode';
  static const _kOnboarded = 'onboarded';
  static const _kChatMessages = 'chat_messages';

  // Secure storage key prefix
  static const _kApiKeyPrefix = 'api_key_';

  /// Initialize SharedPreferences. Call once at app startup.
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  // --------------- Providers ---------------

  static Future<void> saveProviders(List<Map<String, dynamic>> providers) async {
    final json = jsonEncode(providers);
    await _prefs.setString(_kProviders, json);
  }

  static Future<List<Map<String, dynamic>>> loadProviders() async {
    final json = _prefs.getString(_kProviders);
    if (json == null) return [];
    final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }

  // --------------- API Keys (secure) ---------------

  static Future<void> saveApiKey(String providerId, String apiKey) async {
    await _secureStorage.write(key: '$_kApiKeyPrefix$providerId', value: apiKey);
  }

  static Future<String?> getApiKey(String providerId) async {
    return _secureStorage.read(key: '$_kApiKeyPrefix$providerId');
  }

  static Future<void> deleteApiKey(String providerId) async {
    await _secureStorage.delete(key: '$_kApiKeyPrefix$providerId');
  }

  // --------------- Selected Mode ---------------

  static Future<void> saveSelectedMode(String mode) async {
    await _prefs.setString(_kSelectedMode, mode);
  }

  static Future<String> getSelectedMode() async {
    return _prefs.getString(_kSelectedMode) ?? 'chat';
  }

  // --------------- Onboarded ---------------

  static Future<void> saveOnboarded(bool value) async {
    await _prefs.setBool(_kOnboarded, value);
  }

  static Future<bool> isOnboarded() async {
    return _prefs.getBool(_kOnboarded) ?? false;
  }

  // --------------- Chat Messages ---------------

  static Future<void> saveChatMessages(List<Map<String, dynamic>> messages) async {
    final json = jsonEncode(messages);
    await _prefs.setString(_kChatMessages, json);
  }

  static Future<List<Map<String, dynamic>>> loadChatMessages() async {
    final json = _prefs.getString(_kChatMessages);
    if (json == null) return [];
    final List<dynamic> decoded = jsonDecode(json) as List<dynamic>;
    return decoded.cast<Map<String, dynamic>>();
  }
}
