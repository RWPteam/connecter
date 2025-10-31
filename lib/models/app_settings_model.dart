// models/app_settings_model.dart
class AppSettings {
  final String? defaultSftpPath;
  final String? defaultDownloadPath;

  const AppSettings({
    this.defaultSftpPath,
    this.defaultDownloadPath,
  });

  AppSettings copyWith({
    String? defaultSftpPath,
    String? defaultDownloadPath,
  }) {
    return AppSettings(
      defaultSftpPath: defaultSftpPath ?? this.defaultSftpPath,
      defaultDownloadPath: defaultDownloadPath ?? this.defaultDownloadPath,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'defaultSftpPath': defaultSftpPath,
      'defaultDownloadPath': defaultDownloadPath,
    };
  }

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    return AppSettings(
      defaultSftpPath: map['defaultSftpPath'],
      defaultDownloadPath: map['defaultDownloadPath'],
    );
  }

  // 默认设置
  static AppSettings get defaults {
    return const AppSettings(
      defaultSftpPath: '/',
      defaultDownloadPath: null, // null 表示使用平台默认
    );
  }
}