// toolbar_customization_page.dart
import 'package:flutter/material.dart';
import '../services/setting_service.dart';

final Map<int, String> _keyMapping = {
  1: '~',
  2: '|',
  3: '<',
  4: '>',
  5: '=',
  6: '!',
  7: '↑',
  8: '/',
  9: 'Ctrl',
  10: 'Alt',
  11: 'Esc',
  12: 'Del',
  13: 'Tab',
  14: '←',
  15: '↓',
  16: '→',
  17: '?',
  18: '\\',
  19: '*',
  20: '\$',
  21: '#',
  22: '-',
  23: '+',
  24: '`',
  25: '[',
  26: ']',
  27: '{',
  28: '}',
  29: '<',
  30: '>',
  31: ':',
  32: ';',
  33: '(',
  34: ')',
  35: "'",
  36: '"',
  37: ',',
  38: '.',
  39: '@',
  40: '&',
};

class ToolbarCustomizationPage extends StatefulWidget {
  final SettingsService settingsService;
  final Function() onSettingsChanged;

  const ToolbarCustomizationPage({
    Key? key,
    required this.settingsService,
    required this.onSettingsChanged,
  }) : super(key: key);

  @override
  State<ToolbarCustomizationPage> createState() =>
      _ToolbarCustomizationPageState();
}

class _ToolbarCustomizationPageState extends State<ToolbarCustomizationPage> {
  List<int?>? _currentLayout; // 改为可空类型，移除 late 关键字
  List<int>? _availableKeys; // 改为可空类型，移除 late 关键字
  bool _isModified = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final settings = await widget.settingsService.getSettings();

      // 创建初始布局
      List<int?> currentLayout = List<int?>.filled(16, null);
      for (int i = 0; i < settings.toolbarLayout.length && i < 16; i++) {
        currentLayout[i] = settings.toolbarLayout[i];
      }

      // 计算已使用的按键
      final usedKeys =
          currentLayout.where((key) => key != null).cast<int>().toSet();

      // 生成可用按键列表
      List<int> availableKeys = List.generate(40, (index) => index + 1)
        ..removeWhere((key) => usedKeys.contains(key));

      // 设置状态
      if (mounted) {
        setState(() {
          _currentLayout = currentLayout;
          _availableKeys = availableKeys;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('加载设置失败: $e');
      // 如果加载失败，设置默认值
      if (mounted) {
        setState(() {
          _currentLayout = List<int?>.filled(16, null);
          _availableKeys = List.generate(40, (index) => index + 1);
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveSettings() async {
    if (_currentLayout == null || _availableKeys == null) {
      return;
    }

    final usedKeys =
        _currentLayout!.where((key) => key != null).cast<int>().toList();

    if (usedKeys.length != 16) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('保存失败'),
          content: Text('快捷栏必须包含16个按键，当前有${usedKeys.length}个'),
          actions: [
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      return;
    }

    try {
      final currentSettings = await widget.settingsService.getSettings();
      final newSettings = currentSettings.copyWith(toolbarLayout: usedKeys);

      await widget.settingsService.saveSettings(newSettings);
      widget.onSettingsChanged();
      _isModified = false;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('快捷栏布局已保存'),
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

  void _resetToDefault() {
    if (_currentLayout == null || _availableKeys == null) {
      return;
    }

    final defaultLayout = [
      1,
      2,
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      13,
      14,
      15,
      16
    ];

    setState(() {
      // 清空当前布局中的按键，放回可用按键列表
      for (final oldKey in _currentLayout!.whereType<int>()) {
        if (!_availableKeys!.contains(oldKey)) {
          _availableKeys!.add(oldKey);
        }
      }

      // 设置默认布局
      for (int i = 0; i < _currentLayout!.length; i++) {
        _currentLayout![i] = i < defaultLayout.length ? defaultLayout[i] : null;
      }

      // 从可用按键中移除默认布局中的按键
      for (final key in defaultLayout) {
        _availableKeys!.remove(key);
      }
      _availableKeys!.sort();

      _isModified = true;
    });
  }

  void _addKeyToLayout(int key, int position) {
    if (_currentLayout == null || _availableKeys == null) {
      return;
    }

    // 如果该位置已有按键，先移除
    final oldKey = _currentLayout![position];
    if (oldKey != null) {
      _availableKeys!.add(oldKey);
      _availableKeys!.sort();
    }

    setState(() {
      _currentLayout![position] = key;
      _availableKeys!.remove(key);
      _isModified = true;
    });
  }

  void _removeKeyFromLayout(int position) {
    if (_currentLayout == null || _availableKeys == null) {
      return;
    }

    final key = _currentLayout![position];
    if (key != null) {
      setState(() {
        _currentLayout![position] = null;
        _availableKeys!.add(key);
        _availableKeys!.sort();
        _isModified = true;
      });
    }
  }

  void _swapKeys(int fromPosition, int toPosition) {
    if (_currentLayout == null || fromPosition == toPosition) {
      return;
    }

    setState(() {
      final temp = _currentLayout![fromPosition];
      _currentLayout![fromPosition] = _currentLayout![toPosition];
      _currentLayout![toPosition] = temp;
      _isModified = true;
    });
  }

  Widget _buildToolbarKey(int key) {
    final label = _keyMapping[key] ?? '?';
    final theme = Theme.of(context);

    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: theme.dividerColor,
          width: 2,
        ),
      ),
      child: Center(
        child: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: theme.textTheme.bodyLarge?.color ?? Colors.grey[700],
          ),
        ),
      ),
    );
  }

  Widget _buildToolbarLayout() {
    if (_currentLayout == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final cardColor = theme.cardColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            '当前快捷栏布局',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodySmall?.color ?? Colors.grey,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: primaryColor, width: 2),
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 8,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 1,
            ),
            itemCount: 16,
            itemBuilder: (context, position) {
              final key = _currentLayout![position];

              return DragTarget<int>(
                builder: (context, candidateData, rejectedData) {
                  return Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: candidateData.isNotEmpty
                          ? primaryColor.withOpacity(0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: candidateData.isNotEmpty
                            ? primaryColor
                            : theme.dividerColor,
                        width: 2,
                      ),
                    ),
                    child: key != null
                        ? Draggable<int>(
                            data: key,
                            feedback: Material(
                              elevation: 4,
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: theme.scaffoldBackgroundColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border:
                                      Border.all(color: primaryColor, width: 2),
                                ),
                                child: Center(
                                  child: Text(
                                    _keyMapping[key] ?? '?',
                                    style: TextStyle(
                                      color: primaryColor,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            childWhenDragging: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: theme.disabledColor.withOpacity(0.5),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                    color: theme.dividerColor, width: 1),
                              ),
                            ),
                            child: _buildToolbarKey(key),
                          )
                        : Center(
                            child: Icon(
                              Icons.add_circle_outline,
                              color: theme.iconTheme.color,
                              size: 24,
                            ),
                          ),
                  );
                },
                onWillAcceptWithDetails: (data) => true,
                onAccept: (data) {
                  if (data >= 1 && data <= 40 && _availableKeys != null) {
                    if (_availableKeys!.contains(data)) {
                      _addKeyToLayout(data, position);
                    } else {
                      final sourcePosition =
                          _currentLayout!.indexWhere((k) => k == data);
                      if (sourcePosition != -1) {
                        _swapKeys(sourcePosition, position);
                      }
                    }
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAvailableKeys() {
    if (_availableKeys == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final errorColor = theme.secondaryHeaderColor;
    final cardColor = theme.cardColor;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            '可选按键',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: theme.textTheme.bodySmall?.color ?? Colors.grey,
            ),
          ),
        ),
        DragTarget<int>(
          builder: (context, candidateData, rejectedData) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: candidateData.isNotEmpty
                    ? errorColor.withOpacity(0.1)
                    : cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: candidateData.isNotEmpty ? errorColor : primaryColor,
                  width: 1,
                ),
              ),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 1,
                ),
                itemCount: _availableKeys!.length,
                itemBuilder: (context, index) {
                  final key = _availableKeys![index];
                  return Draggable<int>(
                    data: key,
                    feedback: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color: theme.scaffoldBackgroundColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: primaryColor, width: 2),
                        ),
                        child: Center(
                          child: Text(
                            _keyMapping[key] ?? '?',
                            style: TextStyle(
                              color: primaryColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    childWhenDragging: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: theme.disabledColor.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: theme.dividerColor, width: 1),
                      ),
                    ),
                    child: _buildToolbarKey(key),
                  );
                },
              ),
            );
          },
          onWillAccept: (data) {
            return _availableKeys != null && !_availableKeys!.contains(data);
          },
          onAccept: (data) {
            if (_currentLayout != null) {
              final position = _currentLayout!.indexWhere((key) => key == data);
              if (position != -1) {
                _removeKeyFromLayout(position);
              }
            }
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;
    final usedKeysCount =
        _currentLayout?.where((key) => key != null).length ?? 0;
    final isComplete = usedKeysCount == 16;

    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义快捷栏'),
        actions: [],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: primaryColor))
          : (_currentLayout == null || _availableKeys == null)
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 48,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '加载失败',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey[700],
                        ),
                      ),
                      SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _loadSettings,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                )
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildToolbarLayout(),
                            const SizedBox(height: 24),
                            _buildAvailableKeys(),
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                OutlinedButton(
                                  onPressed: _resetToDefault,
                                  child: const Text('恢复默认'),
                                ),
                                OutlinedButton(
                                  onPressed: _isModified && isComplete
                                      ? _saveSettings
                                      : null,
                                  child: const Text('保存布局'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
