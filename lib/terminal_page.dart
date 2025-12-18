// TerminalPage.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/ssh_service.dart';

class TerminalPage extends StatefulWidget {
  final ConnectionInfo connection;
  final Credential credential;

  const TerminalPage({
    super.key,
    required this.connection,
    required this.credential,
  });

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

const int _maxSessions = 2;

class _TerminalPageState extends State<TerminalPage> {
  late final List<Terminal> _terminals;
  final List<SSHClient?> _sshClients = List.filled(_maxSessions, null);
  final List<SSHSession?> _sessions = List.filled(_maxSessions, null);
  final List<bool> _isConnecteds = List.filled(_maxSessions, false);
  final List<bool> _isConnectings = List.filled(_maxSessions, false);
  final List<String> _statuses = List.filled(_maxSessions, '未连接');
  final List<StreamSubscription?> _stdoutSubs = List.filled(_maxSessions, null);
  final List<StreamSubscription?> _stderrSubs = List.filled(_maxSessions, null);

  int _activeIndex = 0;
  bool _isMultiWindowMode = false;
  Terminal get terminal => _terminals[_activeIndex];
  SSHSession? get _session => _sessions[_activeIndex];
  bool get _isConnected => _isConnecteds[_activeIndex];
  bool get _isConnecting => _isConnectings[_activeIndex];
  String get _status => _statuses[_activeIndex];

  // 用于控制 TerminalView 的焦点
  final FocusNode _terminalFocusNode = FocusNode();

  //StreamSubscription? _stdoutSubscription;
  //StreamSubscription? _stderrSubscription;

  double _fontSize = 14.0;
  OverlayEntry? _fontSliderOverlay;
  Timer? _hideSliderTimer;

  bool _isSliderVisible = false;
  bool _menuIsOpen = false;
  bool _ismobile = defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.ohos ||
      defaultTargetPlatform == TargetPlatform.iOS;

  bool _isThemeSelectorVisible = false;
  OverlayEntry? _themeSelectorOverlay;
  Timer? _hideThemeSelectorTimer;
  TerminalTheme _currentTheme = TerminalThemes.defaultTheme;

  bool get _shouldBeReadOnly {
    return !_isConnected ||
        _menuIsOpen ||
        _isSliderVisible ||
        _isThemeSelectorVisible;
  }

  @override
  void initState() {
    super.initState();
    // 初始化两个终端实例
    _terminals = List.generate(_maxSessions, (index) {
      final t = Terminal(maxLines: 10000);

      // 这里的回调需要根据索引来发送数据
      t.onOutput = (data) {
        if (_sessions[index] != null && _isConnecteds[index]) {
          try {
            _sessions[index]!.write(utf8.encode(data));
          } catch (_) {}
        }
      };

      t.onResize = (width, height, pixelWidth, pixelHeight) {
        _sessions[index]
            ?.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      return t;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initFontSize();
      _connectToHost(0); // 默认连接第一个
    });
  }

  void _initFontSize() {
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    // 保持之前的初始化逻辑
    if (_fontSize == 14.0 && !isWideScreen) {
      _fontSize = 12.0;
    } else if (_fontSize == 10.0 && isWideScreen) {
      _fontSize = 14.0;
    }
  }

  Future<void> _connectToHost(int index) async {
    try {
      if (!mounted) return;
      setState(() {
        _isConnectings[index] = true;
        _statuses[index] = '连接中...';
      });

      final sshService = SshService();
      final client =
          await sshService.connect(widget.connection, widget.credential);
      _sshClients[index] = client;

      final t = _terminals[index];
      final width = t.viewWidth > 0 ? t.viewWidth : 80;
      final height = t.viewHeight > 0 ? t.viewHeight : 24;

      final session = await client.shell(
        pty: SSHPtyConfig(
          width: width,
          height: height,
          type: 'xterm-256color',
        ),
      );
      _sessions[index] = session;

      // 监听输出
      _stdoutSubs[index] = session.stdout.listen((data) {
        if (!mounted) return;
        try {
          t.write(utf8.decode(data));
        } catch (_) {}
      });

      _stderrSubs[index] = session.stderr.listen((data) {
        if (!mounted) return;
        try {
          t.write(utf8.decode(data));
        } catch (_) {
          t.write('错误: <stderr 解码失败>');
        }
      });

      session.done.then((_) {
        if (!mounted) return;
        setState(() {
          _isConnecteds[index] = false;
          _isConnectings[index] = false;
          _statuses[index] = '连接已断开';
        });
        t.write('\r\n连接已断开\r\n');
      });

      if (mounted) {
        setState(() {
          _isConnecteds[index] = true;
          _isConnectings[index] = false;
          _statuses[index] = '已连接';
        });
        if (_activeIndex == index) _terminalFocusNode.requestFocus();
      }

      t.write('\x1B[2J\x1B[1;1H');
      t.buffer.clear();
      t.write('连接到 ${widget.connection.name}-${index + 1} 成功\r\n');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecteds[index] = false;
          _isConnectings[index] = false;
          _statuses[index] = '连接失败: $e';
        });
        _terminals[index].write('连接失败: $e\r\n');
      }
    }
  }

  void _enableMultiWindow() {
    setState(() {
      _isMultiWindowMode = true;
      _activeIndex = 1; // 自动切到第二个窗口
    });
    _connectToHost(1);
  }

  Future<void> _disableMultiWindow() async {
    // 弹出确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('提示'),
        content: const Text('即将关闭第二个连接，请确认工作已保存'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认关闭', style: TextStyle(color: Colors.red))),
        ],
      ),
    );

    if (confirm == true) {
      // 释放第二个会话资源
      _stdoutSubs[1]?.cancel();
      _stderrSubs[1]?.cancel();
      _sessions[1]?.close();
      _sshClients[1]?.close();

      setState(() {
        _isMultiWindowMode = false;
        _activeIndex = 0; // 回到第一个窗口
        _isConnecteds[1] = false;
      });
      _terminalFocusNode.requestFocus();
    }
  }

  void _clearTerminal() {
    terminal.buffer.clear();
    terminal.setCursor(0, 0); // 重置光标
    if (_isConnected) {
      // 发送 clear 命令和 VT100 清屏序列
      _session?.write(Uint8List.fromList(utf8.encode('\x1B[2J\x1B[Hclear\r')));
    }
  }

  void _sendCtrlC() => _session?.write(Uint8List.fromList([3])); // ASCII ETX
  void _sendCtrlD() => _session?.write(Uint8List.fromList([4])); // ASCII EOT
  void _sendTab() => _session?.write(Uint8List.fromList([9])); // ASCII HT

  @override
  void dispose() {
    for (var sub in _stdoutSubs) {
      sub?.cancel();
    }
    for (var sub in _stderrSubs) {
      sub?.cancel();
    }
    for (var s in _sessions) {
      s?.close();
    }
    for (var c in _sshClients) {
      c?.close();
    }
    _terminalFocusNode.dispose();
    _hideSliderTimer?.cancel();
    _hideThemeSelectorTimer?.cancel();
    try {
      _fontSliderOverlay?.remove();
    } catch (_) {}
    try {
      _themeSelectorOverlay?.remove();
    } catch (_) {}
    super.dispose();
  }

  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Colors.green.shade800;
    return Colors.red;
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    return [
      const PopupMenuItem<String>(value: 'reconnect', child: Text('重新连接')),
      PopupMenuItem<String>(
        value: 'commands',
        child: Row(
          children: const [
            Text('发送命令'),
            SizedBox(width: 8),
            Icon(Icons.arrow_right, size: 16, color: Colors.grey),
          ],
        ),
      ),
      const PopupMenuItem<String>(value: 'clear', child: Text('清屏')),
      const PopupMenuItem<String>(value: 'fontsize', child: Text('字体大小')),
      const PopupMenuItem<String>(value: 'theme', child: Text('主题')),
      const PopupMenuItem<String>(value: 'disconnect', child: Text('断开连接并返回')),
    ];
  }

  void _onMenuSelected(String value) {
    switch (value) {
      case 'fontsize':
        _showFontSlider();
        break;
      case 'reconnect':
        _reconnect();
        break;
      case 'commands':
        _showCommandsSubMenu();
        break;
      case 'clear':
        _clearTerminal();
        break;
      case 'theme':
        _showThemeSelector();
        break;
      case 'disconnect':
        Navigator.of(context).pop();
        break;
    }
  }

  void _showThemeSelector() {
    if (_isThemeSelectorVisible) return;
    setState(() => _isThemeSelectorVisible = true);
    FocusScope.of(context).unfocus();
    _hideThemeSelectorTimer?.cancel();

    _themeSelectorOverlay ??= OverlayEntry(builder: (context) {
      return StatefulBuilder(builder: (context, setStateOverlay) {
        return Stack(
          children: [
            Positioned.fill(
                child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _hideThemeSelector,
              child: Container(color: Colors.transparent),
            )),
            Positioned.fill(
                child: Center(
                    child: GestureDetector(
              // 添加 GestureDetector 以阻止内部事件冒泡
              onTap: () {},
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(16),
                color: Colors.grey[900]!.withOpacity(0.9),
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.7,
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('选择主题',
                          style: TextStyle(color: Colors.white, fontSize: 18)),
                      const SizedBox(height: 16),
                      _buildThemeOption('默认', TerminalThemes.defaultTheme),
                      const SizedBox(height: 12),
                      _buildThemeOption('纯黑', TerminalThemes.whiteOnBlack),
                    ],
                  ),
                ),
              ),
            )))
          ],
        );
      });
    });
    Overlay.of(context).insert(_themeSelectorOverlay!);
    _resetHideThemeSelectorTimer();
  }

  Widget _buildThemeOption(String title, TerminalTheme theme) {
    final bool isSelected = _currentTheme == theme;

    return Material(
      color:
          isSelected ? Colors.blueAccent.withOpacity(0.1) : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: () => _switchTheme(theme),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _switchTheme(TerminalTheme newTheme) {
    setState(() => _currentTheme = newTheme);
    _hideThemeSelector();
  }

  void _hideThemeSelector() {
    setState(() {
      _menuIsOpen = false;
      _isThemeSelectorVisible = false;
    });
    // 恢复焦点到终端
    if (_isConnected) _terminalFocusNode.requestFocus();

    _hideThemeSelectorTimer?.cancel();
    try {
      _themeSelectorOverlay?.remove();
    } catch (_) {}
    _themeSelectorOverlay = null;
  }

  void _resetHideThemeSelectorTimer() {
    _hideThemeSelectorTimer?.cancel();
    _hideThemeSelectorTimer =
        Timer(const Duration(seconds: 5), _hideThemeSelector);
  }

  void _reconnect() {
    _sessions[_activeIndex]?.close();
    _sshClients[_activeIndex]?.close();
    setState(() {
      _isConnecteds[_activeIndex] = false;
      _terminals[_activeIndex].buffer.clear();
    });
    _connectToHost(_activeIndex);
  }

  void _showCommandsSubMenu() {
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(button.size.topRight(Offset.zero),
            ancestor: overlay),
        button.localToGlobal(button.size.bottomRight(Offset.zero),
            ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    showMenu<String>(
      context: context,
      position: position,
      items: const [
        PopupMenuItem<String>(value: 'enter', child: Text('发送 Enter')),
        PopupMenuItem<String>(value: 'tab', child: Text('发送 Tab')),
        PopupMenuItem<String>(value: 'ctrlc', child: Text('发送 Ctrl+C')),
        PopupMenuItem<String>(value: 'ctrld', child: Text('发送 Ctrl+D')),
      ],
    ).then((value) {
      if (value != null) _handleCommand(value);
      setState(() => _menuIsOpen = false);
      if (_isConnected) _terminalFocusNode.requestFocus();
    });
  }

  void _handleCommand(String command) {
    switch (command) {
      case 'enter':
        _session?.write(Uint8List.fromList([13])); // Carriage Return (\r)
        break;
      case 'tab':
        _sendTab();
        break;
      case 'ctrlc':
        _sendCtrlC();
        break;
      case 'ctrld':
        _sendCtrlD();
        break;
    }
  }

  void _showFontSlider() {
    if (_isSliderVisible) return;
    setState(() => _isSliderVisible = true);
    // 暂时移除焦点
    FocusScope.of(context).unfocus();
    _hideSliderTimer?.cancel();

    _fontSliderOverlay ??= OverlayEntry(
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateOverlay) {
            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: _hideFontSlider,
                    child: Container(color: Colors.transparent),
                  ),
                ),
                Positioned(
                  bottom: 50,
                  left: 20,
                  right: 20,
                  child: GestureDetector(
                    // 添加 GestureDetector 以阻止内部事件冒泡
                    onTap: () {},
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.grey[900]!.withOpacity(0.9),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('字体大小',
                                    style: TextStyle(color: Colors.white)),
                                Text('${_fontSize.toInt()}',
                                    style:
                                        const TextStyle(color: Colors.white)),
                              ],
                            ),
                            Slider(
                              value: _fontSize,
                              min: 8,
                              max: 24,
                              divisions: 16,
                              onChanged: (v) {
                                setStateOverlay(() => _fontSize = v);
                                if (mounted) setState(() => _fontSize = v);
                                _resetHideSliderTimer();
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    Overlay.of(context).insert(_fontSliderOverlay!);
    _resetHideSliderTimer();
  }

  void _hideFontSlider() {
    setState(() {
      _menuIsOpen = false;
      _isSliderVisible = false;
    });
    // 恢复焦点
    if (_isConnected) _terminalFocusNode.requestFocus();

    _hideSliderTimer?.cancel();
    try {
      _fontSliderOverlay?.remove();
    } catch (_) {}
    _fontSliderOverlay = null;
  }

  void _resetHideSliderTimer() {
    _hideSliderTimer?.cancel();
    _hideSliderTimer = Timer(const Duration(seconds: 3), _hideFontSlider);
  }

  @override
  Widget build(BuildContext context) {
    String displayTitle = _isMultiWindowMode
        ? "${widget.connection.name}-${_activeIndex + 1}"
        : widget.connection.name;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: _getAppBarColor(),
        foregroundColor: Colors.white,
        title: InkWell(
          // 点击标题也可以快速切换
          onTap: _isMultiWindowMode
              ? () => setState(() => _activeIndex = _activeIndex == 0 ? 1 : 0)
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(displayTitle,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold)),
              Text(_status,
                  style: const TextStyle(fontSize: 12, color: Colors.white70)),
            ],
          ),
        ),
        actions: [
          // 切换按钮只有在多窗口模式下显示
          if (_isMultiWindowMode)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              tooltip: "切换窗口",
              onPressed: () {
                setState(() => _activeIndex = _activeIndex == 0 ? 1 : 0);
                _terminalFocusNode.requestFocus();
              },
            ),
          PopupMenuButton<String>(
            onSelected: (val) {
              if (val == 'multi_window') {
                _isMultiWindowMode
                    ? _disableMultiWindow()
                    : _enableMultiWindow();
              } else {
                _onMenuSelected(val);
              }
            },
            itemBuilder: (context) => [
              ..._buildMenuItems().where(
                  (item) => (item as PopupMenuItem).value != 'disconnect'),
              PopupMenuItem<String>(
                value: 'multi_window',
                child: Text(_isMultiWindowMode ? '关闭多会话' : '多会话（Beta）'),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                  value: 'disconnect', child: Text('断开连接并返回')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: TerminalView(
          _terminals[_activeIndex],
          key: ValueKey(_activeIndex),
          focusNode: _terminalFocusNode,
          autofocus: true,
          textStyle: TerminalStyle(fontSize: _fontSize, fontFamily: 'maple'),
          theme: _currentTheme,
          showToolbar: _ismobile,
          readOnly: _shouldBeReadOnly,
        ),
      ),
    );
  }
}
