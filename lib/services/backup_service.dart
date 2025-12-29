// backup_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:encrypt/encrypt.dart' as encrypt_package;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_selector/file_selector.dart';
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
    final hash = crypto.sha256.convert(utf8.encode(password));
    return encrypt_package.Key(Uint8List.fromList(hash.bytes));
  }

  // 生成固定IV
  encrypt_package.IV _generateIV(String password) {
    final hash = crypto.sha1.convert(utf8.encode(password));
    return encrypt_package.IV(Uint8List.fromList(hash.bytes.sublist(0, 16)));
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

  // 修改后的备份方法：在安卓上选择目录，在桌面平台选择文件
  Future<String> backupData(String password) async {
    try {
      // 收集所有数据
      final backupData = await _collectBackupData();
      final jsonString = jsonEncode(backupData.toJson());

      // 加密数据
      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(
          encrypt_package.AES(key, mode: encrypt_package.AESMode.cbc));
      final encrypted = encrypter.encrypt(jsonString, iv: iv);

      // 生成文件名
      final dateStr =
          DateTime.now().toString().replaceAll(RegExp(r'[:\.]'), '-');
      final fileName = 'ConnSSH-$dateStr.cntinfo';

      String savePath;

      if (Platform.isAndroid) {
        // Android平台：让用户选择目录
        final status = await Permission.storage.request();
        if (!status.isGranted) {
          throw Exception('需要存储权限才能保存文件');
        }

        // 获取默认的下载目录
        final defaultDir = await _getPlatformDefaultDownloadPath();

        // 让用户选择目录
        final selectedDirectory = await getDirectoryPath(
          initialDirectory: defaultDir,
        );

        if (selectedDirectory == null) {
          throw Exception('用户取消选择目录');
        }

        // 在选择的目录下创建文件
        final file = File('$selectedDirectory/$fileName');
        await file.writeAsBytes(encrypted.bytes);
        savePath = file.path;
      } else if (Platform.isIOS) {
        // iOS平台：使用getSaveLocation，因为iOS对文件系统访问有限制
        final suggestedPath = await _getPlatformDefaultDownloadPath();
        final result = await getSaveLocation(
          suggestedName: fileName,
          initialDirectory: suggestedPath,
        );

        if (result == null) {
          throw Exception('用户取消选择保存位置');
        }

        final file = File(result.path);
        await file.writeAsBytes(encrypted.bytes);
        savePath = result.path;
      } else if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        // 桌面平台：使用getSaveLocation选择文件
        final result = await getSaveLocation(
          suggestedName: fileName,
        );

        if (result == null) {
          throw Exception('用户取消选择保存位置');
        }

        // 确保文件扩展名正确
        String filePath = result.path;
        if (!filePath.toLowerCase().endsWith('.cntinfo')) {
          filePath = '$filePath.cntinfo';
        }

        final file = File(filePath);
        await file.writeAsBytes(encrypted.bytes);
        savePath = file.path;
      } else {
        throw Exception('不支持的平台');
      }

      return savePath;
    } catch (e) {
      debugPrint('备份失败: $e');
      rethrow;
    }
  }

  // 获取平台默认的下载目录路径
  static Future<String?> _getPlatformDefaultDownloadPath() async {
    if (Platform.isAndroid) {
      try {
        final externalDir = await getExternalStorageDirectory();
        if (externalDir != null) {
          final downloadDir = Directory('${externalDir.path}/Download');
          if (!await downloadDir.exists()) {
            await downloadDir.create(recursive: true);
          }
          return downloadDir.path;
        }
      } catch (e) {
        debugPrint('获取Android下载目录失败: $e');
      }

      // 备用方案：使用应用文档目录
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        return appDocDir.path;
      } catch (e) {
        debugPrint('获取应用文档目录失败: $e');
      }
    } else if (Platform.isIOS) {
      try {
        final appDocDir = await getApplicationDocumentsDirectory();
        return appDocDir.path;
      } catch (e) {
        debugPrint('获取iOS文档目录失败: $e');
      }
    } else if (Platform.isWindows) {
      // Windows: 使用下载目录
      final downloadsPath = Platform.environment['USERPROFILE'];
      if (downloadsPath != null) {
        final downloadDir = Directory('$downloadsPath\\Downloads');
        if (await downloadDir.exists()) {
          return downloadDir.path;
        }
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      // Linux/macOS: 使用用户目录下的Downloads
      final homePath = Platform.environment['HOME'];
      if (homePath != null) {
        final downloadDir = Directory('$homePath/Downloads');
        if (await downloadDir.exists()) {
          return downloadDir.path;
        }
      }
    }

    return null;
  }

  // 恢复数据方法保持不变
  Future<BackupData> restoreData(String filePath, String password) async {
    try {
      Uint8List encryptedBytes;

      // 读取文件
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('备份文件不存在');
      }

      encryptedBytes = await file.readAsBytes();

      // 解密数据
      final key = _generateKey(password);
      final iv = _generateIV(password);
      final encrypter = encrypt_package.Encrypter(
          encrypt_package.AES(key, mode: encrypt_package.AESMode.cbc));
      final encrypted = encrypt_package.Encrypted(encryptedBytes);
      final decryptedString = encrypter.decrypt(encrypted, iv: iv);

      // 解析JSON
      final Map<String, dynamic> jsonData = jsonDecode(decryptedString);
      return BackupData.fromJson(jsonData);
    } catch (e) {
      debugPrint('恢复失败: $e');
      if (e.toString().contains('Bad state: Unknown element type')) {
        throw Exception('密码错误或文件已损坏');
      }
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
      debugPrint('应用恢复数据失败: $e');
      throw Exception('应用恢复数据失败: $e');
    }
  }
}
