// global_settings_page.dart
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:connssh/main.dart';
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';
import '../../services/backup_service.dart';
import '../../services/storage_service.dart';
import 'theme.dart';

class GlobalSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const GlobalSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<GlobalSettingsPage> createState() => _GlobalSettingsPageState();
}

class _GlobalSettingsPageState extends State<GlobalSettingsPage> {
  bool _isLoading = true;
  late BackupService _backupService;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _initBackupService();
  }

  void _initBackupService() {
    final storageService = StorageService();
    _backupService = BackupService(
      storageService: storageService,
      settingsService: widget.settingsService,
    );
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isLoading = false;
    });
  }

  void _showBackupDialog() {
    final passwordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool passwordObscure = true;
    bool confirmPasswordObscure = true;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('备份数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('请输入备份密码', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: passwordObscure,
                    decoration: InputDecoration(
                      labelText: '密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(passwordObscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => passwordObscure = !passwordObscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPasswordController,
                    obscureText: confirmPasswordObscure,
                    decoration: InputDecoration(
                      labelText: '确认密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(confirmPasswordObscure
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () => setState(() =>
                            confirmPasswordObscure = !confirmPasswordObscure),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '备份文件将包含所有连接、凭证和设置信息，请妥善保管',
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: () async {
                  if (passwordController.text.isEmpty) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(const SnackBar(content: Text('请输入密码')));
                    return;
                  }
                  if (passwordController.text !=
                      confirmPasswordController.text) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('两次输入的密码不一致')));
                    return;
                  }

                  final NavigatorState nav = Navigator.of(context);
                  ScaffoldMessenger.of(context);

                  nav.pop();

                  showDialog(
                    context: this.context,
                    barrierDismissible: false,
                    builder: (context) => const AlertDialog(
                      backgroundColor: Colors.transparent,
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 16),
                          Text('正在备份数据...'),
                        ],
                      ),
                    ),
                  );

                  try {
                    final filePath = await _backupService
                        .backupData(passwordController.text);

                    if (!mounted) return;

                    Navigator.of(this.context, rootNavigator: true).pop();

                    if (filePath.isNotEmpty) {
                      _showResultDialog('备份成功', '备份文件已保存到:\n$filePath');
                    } else {
                      _showResultDialog('备份失败', '请选择目录');
                    }
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.of(this.context, rootNavigator: true).pop();
                    _showResultDialog('备份失败', e.toString());
                  }
                },
                child: const Text('备份'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showResultDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  void _showRestoreDialog() {
    final passwordController = TextEditingController();
    bool isObscure = true;
    String? selectedFilePath;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('恢复数据'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    '选择备份文件并输入密码',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        // 使用 file_selector 选择文件
                        const XTypeGroup typeGroup = XTypeGroup(
                          label: 'ConnSSH Backup',
                          extensions: ['cntinfo'],
                        );
                        final XFile? file = await openFile(
                          acceptedTypeGroups: [typeGroup],
                        );

                        if (file != null) {
                          setState(() {
                            selectedFilePath = file.path;
                          });

                          // 显示选择的文件名
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('已选择文件: ${file.name}'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        }
                      } catch (e) {
                        debugPrint('选择文件失败: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('选择文件失败: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.folder_open),
                    label: Text(
                      selectedFilePath != null
                          ? selectedFilePath!.split('/').last
                          : '选择备份文件',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  if (selectedFilePath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '文件路径: ${selectedFilePath!.length > 50 ? '...${selectedFilePath!.substring(selectedFilePath!.length - 50)}' : selectedFilePath!}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.grey,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscure,
                    onChanged: (value) {
                      setState(() {});
                    },
                    decoration: InputDecoration(
                      labelText: '备份密码',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          isObscure ? Icons.visibility : Icons.visibility_off,
                        ),
                        onPressed: () {
                          setState(() {
                            isObscure = !isObscure;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '警告：恢复操作将覆盖当前所有连接、凭证和设置！',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: selectedFilePath == null ||
                        passwordController.text.isEmpty
                    ? null
                    : () async {
                        // 确认恢复
                        showDialog(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('确认恢复'),
                            content: const Text(
                              '此操作将覆盖所有现有数据，且不可撤销，确定要恢复吗？',
                            ),
                            actions: [
                              OutlinedButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('取消'),
                              ),
                              OutlinedButton(
                                onPressed: () async {
                                  Navigator.of(context).pop();
                                  if (Navigator.of(context, rootNavigator: true)
                                      .canPop()) {
                                    Navigator.of(context, rootNavigator: true)
                                        .pop();
                                  }

                                  showDialog(
                                    context: context,
                                    barrierDismissible: false,
                                    builder: (context) => const AlertDialog(
                                      backgroundColor: Colors.transparent,
                                      content: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          CircularProgressIndicator(),
                                          SizedBox(height: 16),
                                          Text('正在恢复数据...'),
                                        ],
                                      ),
                                    ),
                                  );

                                  try {
                                    final backupData =
                                        await _backupService.restoreData(
                                      selectedFilePath!,
                                      passwordController.text,
                                    );

                                    await _backupService.applyRestoredData(
                                      backupData,
                                    );

                                    // 关闭加载对话框
                                    if (Navigator.of(context,
                                            rootNavigator: true)
                                        .canPop()) {
                                      Navigator.of(context, rootNavigator: true)
                                          .pop();
                                    }

                                    // 刷新应用
                                    widget.onSettingsChanged();
                                    MyApp.of(context)?.loadSettings();

                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('恢复成功'),
                                        content: Text(
                                          '数据已成功恢复！\n'
                                          '备份时间：${backupData.backupTime.toString().substring(0, 19)}\n'
                                          '包含连接：${backupData.connections.length}个\n'
                                          '包含凭证：${backupData.credentials.length}个',
                                        ),
                                        actions: [
                                          OutlinedButton(
                                            onPressed: () {
                                              Navigator.of(context).pop();
                                              if (Navigator.of(context)
                                                  .canPop()) {
                                                Navigator.of(context).pop();
                                              }
                                            },
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                  } catch (e) {
                                    // 关闭加载对话框
                                    if (Navigator.of(context,
                                            rootNavigator: true)
                                        .canPop()) {
                                      Navigator.of(context, rootNavigator: true)
                                          .pop();
                                    }

                                    showDialog(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: const Text('恢复失败'),
                                        content: Text(e.toString()),
                                        actions: [
                                          OutlinedButton(
                                            onPressed: () =>
                                                Navigator.of(context).pop(),
                                            child: const Text('确定'),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                                child: const Text('确定恢复'),
                              ),
                            ],
                          ),
                        );
                      },
                child: const Text('恢复'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('恢复默认设置'),
        content: const Text('确定要恢复所有设置为默认值吗？此操作不可撤销。'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final defaultSettings = AppSettings();
              await widget.settingsService.saveSettings(defaultSettings);
              widget.onSettingsChanged();
              MyApp.of(context)?.loadSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已恢复默认设置'),
                    duration: Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 16.0),
      decoration: BoxDecoration(
        border: Border.all(
          color: Colors.grey,
          width: 1.0,
        ),
        borderRadius: BorderRadius.circular(12.0),
        color: Colors.transparent,
      ),
      child: ListTile(
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.grey.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey.shade600,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(
          Icons.arrow_forward_ios,
          size: 16,
          color: Colors.grey,
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16.0,
          vertical: 16.0,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12.0),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('全局设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildSettingTile(
                    icon: Icons.color_lens,
                    title: '主题设置',
                    subtitle: '主题风格和页面主题',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => ThemeSettingsPage(
                            settingsService: widget.settingsService,
                            onSettingsChanged: widget.onSettingsChanged,
                          ),
                        ),
                      );
                    },
                  ),
                  _buildSettingTile(
                    icon: Icons.backup,
                    title: '备份数据',
                    subtitle: '加密备份所有连接和设置',
                    onTap: _showBackupDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.restore,
                    title: '恢复数据',
                    subtitle: '从备份文件恢复数据',
                    onTap: _showRestoreDialog,
                  ),
                  _buildSettingTile(
                    icon: Icons.settings_backup_restore,
                    title: '恢复默认设置',
                    subtitle: '将所有设置恢复为默认值',
                    onTap: _resetToDefaults,
                  ),
                ],
              ),
            ),
    );
  }
}
