import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt_package; // 添加别名
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';
import '../models/backup_data_model.dart';
import '../services/storage_service.dart';
import '../services/setting_service.dart';
import 'package:crypto/crypto.dart' as crypto;

class BackupService {
  final StorageService _storageService;
  final SettingsService _settingsService;

  BackupService({
    required StorageService storageService,
    required SettingsService settingsService,
  })  : _storageService = storageService,
        _settingsService = settingsService;

  // 生成加密密钥
  encrypt_package.Key _generateKey(String password) {
    // 使用完整路径
    // 使用SHA-256哈希密码作为密钥，截取32字节用于AES-256
    final hash = Sha256.convert(utf8.encode(password));
    return encrypt_package.Key(hash); // 使用完整路径
  }

  // 生成固定IV（为了确保相同的密码每次都能解密）
  encrypt_package.IV _generateIV(String password) {
    // 使用完整路径
    // 使用密码的SHA-1哈希的前16字节作为固定IV
    final hash = Sha1.convert(utf8.encode(password));
    return encrypt_package.IV(hash.sublist(0, 16)); // 使用完整路径
  }

  Future<BackupData> _collectBackupData() async {
    final connections = await _storageService.getConnections();
    final credentials = await _storageService.getCredentials();
    final recentConnections = await _storageService.getRecentConnections();
    final settings = await _settingsService.getSettings();

    return BackupData(
      connections: connections,
      credentials: credentials,
      recentConnections: recentConnections,
      settings: settings,
      backupTime: DateTime.now(),
      version: '1.2.2',
    );
  }

  Future<String> backupData(String password) async {
    try {
      // 收集所有数据
      final backupData = await _collectBackupData();
      final jsonString = jsonEncode(backupData.toJson());

      // 加密数据
      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(encrypt_package.AES(key,
          mode: encrypt_package.AESMode.cbc)); // 使用完整路径
      final encrypted = encrypter.encrypt(jsonString, iv: iv);

      // 生成文件名
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final fileName = '$timestamp-backup.cntinfo';

      // 保存文件
      String? filePath;
      if (Platform.isAndroid || Platform.isIOS) {
        final directory = await getExternalStorageDirectory();
        if (directory != null) {
          filePath = '${directory.path}/$fileName';
          final file = File(filePath);
          await file.writeAsBytes(encrypted.bytes);
        }
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        filePath = await FilePicker.platform.saveFile(
          dialogTitle: '保存备份文件',
          fileName: fileName,
          type: FileType.custom,
          allowedExtensions: ['cntinfo'],
        );
        if (filePath != null) {
          final file = File(filePath);
          await file.writeAsBytes(encrypted.bytes);
        }
      }

      return filePath ?? '';
    } catch (e) {
      throw Exception('备份失败: $e');
    }
  }

  Future<BackupData> restoreData(String filePath, String password) async {
    try {
      // 读取加密文件
      final file = File(filePath);
      final encryptedBytes = await file.readAsBytes();

      // 解密数据
      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(encrypt_package.AES(key,
          mode: encrypt_package.AESMode.cbc)); // 使用完整路径
      final encrypted = encrypt_package.Encrypted(encryptedBytes); // 使用完整路径
      final decryptedString = encrypter.decrypt(encrypted, iv: iv);

      // 解析JSON
      final Map<String, dynamic> jsonData = jsonDecode(decryptedString);
      return BackupData.fromJson(jsonData);
    } catch (e) {
      throw Exception('恢复失败: $e\n可能是密码错误或文件已损坏');
    }
  }

  Future<void> applyRestoredData(BackupData backupData) async {
    try {
      // 恢复设置
      await _settingsService.saveSettings(backupData.settings);

      // 清空现有数据
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('saved_connections');
      await prefs.remove('saved_credentials');
      await prefs.remove('recent_connections');

      // 恢复连接
      for (final connection in backupData.connections) {
        await _storageService.saveConnection(connection);
      }

      // 恢复凭证
      for (final credential in backupData.credentials) {
        await _storageService.saveCredential(credential);
      }

      // 恢复最近连接
      final recentConnectionsJson = json.encode(
        backupData.recentConnections.map((c) => c.toJson()).toList(),
      );
      await prefs.setString('recent_connections', recentConnectionsJson);
    } catch (e) {
      throw Exception('应用恢复数据失败: $e');
    }
  }
}

// SHA-256和SHA-1辅助类

class Sha256 {
  static Uint8List convert(List<int> bytes) {
    final digest = crypto.sha256.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }
}

class Sha1 {
  static Uint8List convert(List<int> bytes) {
    final digest = crypto.sha1.convert(bytes);
    return Uint8List.fromList(digest.bytes);
  }
}
