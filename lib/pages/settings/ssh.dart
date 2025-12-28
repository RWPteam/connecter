import 'package:flutter/material.dart';
import '../toolbar_customizer.dart';
import '../../models/app_settings_model.dart';
import '../../services/setting_service.dart';

class SSHSettingsPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const SSHSettingsPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<SSHSettingsPage> createState() => _SSHSettingsPageState();
}

class _SSHSettingsPageState extends State<SSHSettingsPage> {
  bool _isLoading = true;
  double _fontSize = 12.0;
  String _termTheme = 'dark';
  String _termType = 'xterm-256color';

  final Map<String, String> _termThemeMap = {
    'dark': '深色',
    'black': '黑色',
    'light': '浅色',
  };

  final List<String> _termThemes = ['dark', 'black', 'light'];
  final List<String> _termTypes = [
    'xterm-256color',
    'xterm',
    'xterm-color',
    'vt100',
    'linux'
  ];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await widget.settingsService.getSettings();
    setState(() {
      _fontSize = settings.defaultFontSize;
      _termTheme = settings.defaultTermTheme;
      _termType = settings.termType;
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = AppSettings(
        defaultSftpPath: currentSettings.defaultSftpPath,
        defaultDownloadPath: currentSettings.defaultDownloadPath,
        defaultFontSize: _fontSize,
        defaultTermTheme: _termTheme,
        termType: _termType,
        defaultPageTheme: currentSettings.defaultPageTheme,
        defaultThemeMode: currentSettings.defaultThemeMode,
      );

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('设置已保存'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('保存失败'),
            content: Text(e.toString()),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('确定'),
              ),
            ],
          ),
        );
      }
    }
  }

  void _showFontSizeDialog() {
    double currentValue = _fontSize;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('字体大小设置'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text('大小: '),
                    Expanded(
                      child: Slider(
                        value: currentValue,
                        min: 8,
                        max: 24,
                        divisions: 16,
                        label: currentValue.toStringAsFixed(1),
                        onChanged: (value) {
                          setState(() {
                            currentValue = value;
                          });
                        },
                      ),
                    ),
                    Text('${currentValue.toInt()}px'),
                  ],
                ),
              ],
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              OutlinedButton(
                onPressed: () async {
                  setState(() {
                    _fontSize = currentValue;
                  });
                  Navigator.of(context).pop();
                  await _saveSettings();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showTermThemeDialog() {
    String currentValue = _termTheme;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端主题'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termThemes
              .map((theme) => RadioListTile<String>(
                    title: Text(_termThemeMap[theme] ?? theme),
                    value: theme,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termTheme = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showTermTypeDialog() {
    String currentValue = _termType;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('终端类型'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: _termTypes
              .map((type) => RadioListTile<String>(
                    title: Text(type),
                    value: type,
                    groupValue: currentValue,
                    onChanged: (value) {
                      if (value != null) {
                        Navigator.of(context).pop();
                        setState(() {
                          _termType = value;
                        });
                        _saveSettings();
                      }
                    },
                  ))
              .toList(),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  void _showCustomShortcutBarMessage() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ToolbarCustomizationPage(
          settingsService: widget.settingsService,
          onSettingsChanged: () {
            _loadSettings();
            widget.onSettingsChanged();
          },
        ),
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
        title: const Text('SSH设置'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  _buildSettingTile(
                    title: '字体大小',
                    subtitle: '${_fontSize.toInt()}px',
                    onTap: _showFontSizeDialog,
                    icon: Icons.text_fields,
                  ),
                  _buildSettingTile(
                    title: '终端主题',
                    subtitle: _termThemeMap[_termTheme] ?? _termTheme,
                    onTap: _showTermThemeDialog,
                    icon: Icons.palette,
                  ),
                  _buildSettingTile(
                    title: '终端类型',
                    subtitle: _termType,
                    onTap: _showTermTypeDialog,
                    icon: Icons.category,
                  ),
                  _buildSettingTile(
                    title: '自定义快捷栏',
                    subtitle: '配置快捷栏样式',
                    onTap: _showCustomShortcutBarMessage,
                    icon: Icons.dashboard_customize,
                  ),
                ],
              ),
            ),
    );
  }
}
