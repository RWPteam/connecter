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
      debugPrint('Data causing error: $jsonString');

      // 修复逻辑：清空无效的设置数据
      await _clearInvalidSettings();

      return AppSettings.defaults;
    }
  }

  Future<void> saveSettings(AppSettings settings) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final currentJson = prefs.getString(_settingsKey);
      bool actualFirstRunStatus = false;

      if (currentJson != null) {
        try {
          final currentMap = json.decode(currentJson);
          actualFirstRunStatus = currentMap['isFirstRun'] ?? false;
        } catch (e) {
          // 如果当前设置也是无效格式，清除它
          debugPrint('Current settings is invalid format, clearing...');
          await _clearInvalidSettings();
          actualFirstRunStatus = false;
        }
      }

      final settingsToSave = settings.copyWith(
          isFirstRun:
              actualFirstRunStatus == false ? false : settings.isFirstRun);

      final jsonString = json.encode(settingsToSave.toMap());
      await prefs.setString(_settingsKey, jsonString);
    } catch (e) {
      debugPrint('Error saving settings: $e');

      // 尝试清除可能存在的无效数据
      await _clearInvalidSettings();

      // 然后重新尝试保存
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(settings.toMap());
      await prefs.setString(_settingsKey, jsonString);
    }
  }

  Future<void> markAsNotFirstRun() async {
    try {
      final currentSettings = await getSettings();
      final updatedSettings = currentSettings.copyWith(isFirstRun: false);
      await saveSettings(updatedSettings);
    } catch (e) {
      debugPrint('标记为非第一次运行失败: $e');

      // 清除无效设置后重试
      await _clearInvalidSettings();

      // 创建默认设置并标记为非首次运行
      final defaultSettings = AppSettings.defaults.copyWith(isFirstRun: false);
      await saveSettings(defaultSettings);
    }
  }

  /// 清除无效的设置数据
  Future<void> _clearInvalidSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // 移除当前无效的设置
      await prefs.remove(_settingsKey);

      debugPrint('Cleared invalid settings data');
    } catch (e) {
      debugPrint('Error clearing invalid settings: $e');
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
