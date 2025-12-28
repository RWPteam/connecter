import '../models/app_settings_model.dart';
import '../models/connection_model.dart';
import '../models/credential_model.dart';

class BackupData {
  final List<ConnectionInfo> connections;
  final List<Credential> credentials;
  final List<ConnectionInfo> recentConnections;
  final AppSettings settings;
  final DateTime backupTime;
  final String version;

  BackupData({
    required this.connections,
    required this.credentials,
    required this.recentConnections,
    required this.settings,
    required this.backupTime,
    required this.version,
  });

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'backupTime': backupTime.toIso8601String(),
      'connections': connections.map((c) => c.toJson()).toList(),
      'credentials': credentials.map((c) => c.toJson()).toList(),
      'recentConnections': recentConnections.map((c) => c.toJson()).toList(),
      'settings': settings.toMap(), // 改为使用 toMap()
    };
  }

  factory BackupData.fromJson(Map<String, dynamic> json) {
    return BackupData(
      version: json['version'],
      backupTime: DateTime.parse(json['backupTime']),
      connections: (json['connections'] as List)
          .map((c) => ConnectionInfo.fromJson(c))
          .toList(),
      credentials: (json['credentials'] as List)
          .map((c) => Credential.fromJson(c))
          .toList(),
      recentConnections: (json['recentConnections'] as List)
          .map((c) => ConnectionInfo.fromJson(c))
          .toList(),
      settings: AppSettings.fromMap(json['settings']), // 改为使用 fromMap()
    );
  }
}
