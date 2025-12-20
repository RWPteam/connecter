import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/app_settings_model.dart';

class SettingsService {
  static const String _settingsKey = 'app_settings';

  Future<AppSettings> getSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString(_settingsKey);

    if (jsonString == null) {
      return AppSettings.defaults;
    }

    try {
      final Map<String, dynamic> jsonMap = json.decode(jsonString);
      return AppSettings.fromMap(jsonMap);
    } catch (e) {
      debugPrint('Error parsing settings: $e');
      return AppSettings.defaults;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final currentJson = prefs.getString(_settingsKey);
      bool actualFirstRunStatus = false;

      if (currentJson != null) {
        final currentMap = json.decode(currentJson);
        actualFirstRunStatus = currentMap['isFirstRun'] ?? false;
      }
      final settingsToSave = settings.copyWith(
          isFirstRun:
              actualFirstRunStatus == false ? false : settings.isFirstRun);

      final jsonString = json.encode(settingsToSave.toMap());
      await prefs.setString(_settingsKey, jsonString);
    } catch (e) {
      debugPrint('Error saving settings: $e');
      rethrow;
    }
  }

  Future<void> markAsNotFirstRun() async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(isFirstRun: false);
      await saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('标记为非第一次运行失败: $e');
      throw Exception('标记为非第一次运行失败: $e');
    }
  }

  static Future<String?> getPlatformDefaultDownloadPath() async {
    if (Platform.isAndroid) {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir != null) {
        final downloadDir = Directory('${externalDir.path}/Download');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir.path;
      }
    }

    return null;
  }
}
