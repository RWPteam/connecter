// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'models/connection_model.dart';
import 'models/credential_model.dart';
import 'services/setting_service.dart';
import 'models/app_settings_model.dart';
import 'services/ssh_service.dart';
//import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

enum ViewMode { list, icon }

class ClipboardItem {
  final String path;
  final bool isDirectory;
  final String name;

  ClipboardItem({
    required this.path,
    required this.isDirectory,
    required this.name,
  });
}

class SftpPage extends StatefulWidget {
  final ConnectionInfo connection;
  final Credential credential;

  const SftpPage({
    super.key,
    required this.connection,
    required this.credential,
  });

  @override
  State<SftpPage> createState() => _SftpPageState();
}

class _SftpPageState extends State<SftpPage> {
  final SshService _sshService = SshService();
  final SettingsService _settingsService = SettingsService();

  SSHClient? _sshClient;
  dynamic _sftpClient;
  // 修改剪貼板為支持多個檔案
  final List<ClipboardItem> _clipboardItems = [];
  bool _clipboardIsCut = false;
  List<dynamic> _fileList = [];
  String _currentPath = '/';
  bool _isLoading = true;
  bool _isConnected = false;
  bool _isConnecting = false;
  String _status = '連線中...';
  final Set<String> _selectedFiles = {};
  bool _isMultiSelectMode = false;
  double _uploadProgress = 0.0;
  double _downloadProgress = 0.0;
  String _currentOperation = '';
  bool _cancelOperation = false;
  dynamic _currentUploader;
  dynamic _currentDownloadFile;
  AppSettings _appSettings = AppSettings.defaults;
  ViewMode _viewMode = ViewMode.list;
  DateTime? _lastBackPressedTime;
  bool _isProgressDialogOpen = false;

  // 判斷是否為移動設備
  bool get _ismobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.ohos ||
      defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    _preConnection();
  }

  Color _getIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
  }

  Color _getDisabledIconColor(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? Colors.grey
        : Colors.grey[600]!;
  }

  // 獲取AppBar背景色
  Color _getAppBarColor() {
    if (_isConnecting) return Colors.grey.shade700;
    if (_isConnected) return Theme.of(context).primaryColor;
    return Colors.red;
  }

  Future<void> _preConnection() async {
    try {
      final settings = await _settingsService.getSettings();
      setState(() {
        _appSettings = settings;
        _currentPath =
            widget.connection.sftpPath ?? settings.defaultSftpPath ?? '/';
      });
    } catch (e) {
      debugPrint('加載設定失敗: $e');
      setState(() => _currentPath = '/');
    }
    await _connectSftp();
  }

  Future<void> _connectSftp() async {
    try {
      if (!mounted) return;
      setState(() {
        //清除已經保存的檔案選擇狀態，以防重連後產生衝突
        _isMultiSelectMode = false;
        _selectedFiles.clear();
        _isLoading = true;
        _isConnecting = true;
        _status = '連線中...';
      });

      _sshClient =
          await _sshService.connect(widget.connection, widget.credential);
      _sftpClient = await _sshClient!.sftp();

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
          _status = '已連線';
        });
      }

      try {
        await _loadDirectory(_currentPath);
      } catch (e) {
        debugPrint('初始路徑 $_currentPath 不可用，回退到根目錄: $e');
        await _loadDirectory('/');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _isLoading = false;
          _status = '連線失敗: $e';
        });
        _showErrorDialog('SFTP連線失敗', e.toString());
      }
    }
  }

  // 檢查連線狀態的輔助方法
  Future<bool> _checkConnection() async {
    if (!_isConnected || _sshClient == null || _sftpClient == null) {
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '連線已斷開';
        });
        _showErrorDialog('連線錯誤', '請重新連線伺服器');
      }
      return false;
    }

    // 嘗試執行一個簡單的命令來驗證連線是否仍然有效
    try {
      await _sshClient!.execute('pwd').timeout(const Duration(seconds: 5));
      return true;
    } catch (e) {
      debugPrint('連線檢查失敗: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
          _status = '連線已斷開';
        });
        _showErrorDialog('連線已斷開', '伺服器連線已斷開，請重新連線');
      }
      return false;
    }
  }

  Widget _buildSingleRowToolbar(Color iconColor, Color disabledIconColor,
      bool hasSelection, bool singleSelection, bool isWideScreen) {
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              if (_currentPath != '/')
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: _goToParentDirectory,
                  tooltip: '上級目錄',
                )
              else
                IconButton(
                  icon: const Icon(Icons.circle_outlined),
                  onPressed: null,
                  tooltip: '/',
                ),
              const SizedBox(width: 3),
              _buildIconButton(Icons.upload, '上傳檔案', _uploadFile, iconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  Icons.download,
                  '下載檔案',
                  hasSelection ? _downloadSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  Icons.delete,
                  '刪除檔案',
                  hasSelection ? _deleteSelectedFiles : null,
                  hasSelection ? iconColor : disabledIconColor),
              const SizedBox(width: 3),
              _buildIconButton(Icons.create_new_folder, '新增資料夾',
                  _createDirectory, iconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  Icons.drive_file_rename_outline,
                  '重新命名',
                  singleSelection ? _renameFile : null,
                  singleSelection ? iconColor : disabledIconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  _isMultiSelectMode
                      ? Icons.check_box_outline_blank
                      : Icons.check_box,
                  _isMultiSelectMode ? '取消選擇' : '全選',
                  _selectAllFiles,
                  iconColor),
              _buildIconButton(
                  Icons.copy,
                  '複製',
                  hasSelection ? _copySelected : null,
                  hasSelection ? iconColor : disabledIconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  Icons.cut,
                  '剪下',
                  hasSelection ? _cutSelected : null,
                  hasSelection ? iconColor : disabledIconColor),
              const SizedBox(width: 3),
              _buildIconButton(
                  Icons.paste,
                  '貼上',
                  _clipboardItems.isNotEmpty ? _pasteFile : null,
                  _clipboardItems.isNotEmpty ? iconColor : disabledIconColor),
            ]),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            if (isWideScreen)
              TextButton.icon(
                icon: Icon(Icons.info,
                    color: singleSelection ? iconColor : disabledIconColor),
                label: Text('屬性',
                    style: TextStyle(
                        color:
                            singleSelection ? iconColor : disabledIconColor)),
                onPressed: singleSelection ? _showFileDetails : null,
              )
            else
              _buildIconButton(
                  Icons.info,
                  '屬性',
                  singleSelection ? _showFileDetails : null,
                  singleSelection ? iconColor : disabledIconColor),
            const SizedBox(width: 3),
            if (isWideScreen)
              TextButton.icon(
                icon: Icon(Icons.view_module, color: disabledIconColor),
                label: Text('切換視圖', style: TextStyle(color: disabledIconColor)),
                onPressed: () => setState(() => _viewMode =
                    _viewMode == ViewMode.list ? ViewMode.icon : ViewMode.list),
              )
            else
              _buildIconButton(
                  Icons.view_module,
                  '切換視圖',
                  () => setState(() => _viewMode = _viewMode == ViewMode.list
                      ? ViewMode.icon
                      : ViewMode.list),
                  disabledIconColor),
          ]),
        ),
      ],
    );
  }

  Widget _buildDoubleRowToolbar(Color iconColor, Color disabledIconColor,
      bool hasSelection, bool singleSelection) {
    double buttonWidth = (MediaQuery.of(context).size.width - 4) / 6;

    return Column(
      children: [
        SizedBox(
          height: 40,
          child: Row(
            children: [
              SizedBox(
                width: buttonWidth,
                child: _currentPath != '/'
                    ? _buildIconButton(Icons.arrow_back, '上級目錄',
                        _goToParentDirectory, iconColor, iconSize: 20)
                    : _buildIconButton(
                        Icons.circle_outlined, '/', null, disabledIconColor,
                        iconSize: 20),
              ),
              // 上傳按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.upload, '上傳', _uploadFile, iconColor,
                    iconSize: 20),
              ),
              // 下載按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.download,
                    '下載',
                    hasSelection ? _downloadSelectedFiles : null,
                    hasSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 刪除按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.delete,
                    '刪除',
                    hasSelection ? _deleteSelectedFiles : null,
                    hasSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 新增資料夾按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(Icons.create_new_folder, '新增資料夾',
                    _createDirectory, iconColor,
                    iconSize: 20),
              ),
              // 全選按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    _isMultiSelectMode
                        ? Icons.check_box_outline_blank
                        : Icons.check_box,
                    _isMultiSelectMode ? '取消全選' : '全選',
                    _selectAllFiles,
                    iconColor,
                    iconSize: 20),
              ),
            ],
          ),
        ),
        // 第二行：次要操作按鈕和功能按鈕
        SizedBox(
          height: 40,
          child: Row(
            children: [
              // 複製按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.copy,
                    '複製',
                    hasSelection ? _copySelected : null,
                    hasSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 剪下按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.cut,
                    '剪下',
                    hasSelection ? _cutSelected : null,
                    hasSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 貼上按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.paste,
                    '貼上',
                    _clipboardItems.isNotEmpty ? _pasteFile : null,
                    _clipboardItems.isNotEmpty ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 重新命名按鈕 - 替換原來的刷新按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.drive_file_rename_outline,
                    '重新命名',
                    singleSelection ? _renameFile : null,
                    singleSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 屬性按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.info,
                    '屬性',
                    singleSelection ? _showFileDetails : null,
                    singleSelection ? iconColor : disabledIconColor,
                    iconSize: 20),
              ),
              // 切換視圖按鈕
              SizedBox(
                width: buttonWidth,
                child: _buildIconButton(
                    Icons.view_module,
                    '切換視圖',
                    () => setState(() => _viewMode = _viewMode == ViewMode.list
                        ? ViewMode.icon
                        : ViewMode.list),
                    iconColor,
                    iconSize: 20),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _loadDirectory(String dirPath) async {
    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    try {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        if (!_isMultiSelectMode) _selectedFiles.clear();
      });

      String normalizedPath = _normalizePath(dirPath);
      final list = await _sftpClient.listdir(normalizedPath);

      final filteredList = list.where((item) {
        final filename = item.filename.toString();
        return filename != '.' && filename != '..';
      }).toList();

      filteredList.sort((a, b) {
        final aIsDir = a.attr?.isDirectory ?? false;
        final bIsDir = b.attr?.isDirectory ?? false;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        final aFilename = a.filename?.toString() ?? '';
        final bFilename = b.filename?.toString() ?? '';
        return aFilename.compareTo(bFilename);
      });

      if (mounted) {
        setState(() {
          _fileList = filteredList;
          _currentPath = normalizedPath;
          _isLoading = false;
        });
      }
    } catch (e) {
      // 如果操作失敗，檢查連線狀態
      if (!await _checkConnection()) return;

      if (mounted) setState(() => _isLoading = false);
      _showErrorDialog('讀取目錄失敗', '路徑: $dirPath\n錯誤: $e');
    }
  }

  String _normalizePath(String rawPath) {
    String normalized =
        rawPath.replaceAll('\\', '/').replaceAll(RegExp(r'/+'), '/');
    if (!normalized.startsWith('/')) normalized = '/$normalized';
    if (normalized != '/' && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  String _joinPath(String part1, String part2) {
    if (part1.endsWith('/')) part1 = part1.substring(0, part1.length - 1);
    if (part2.startsWith('/')) part2 = part2.substring(1);
    return '$part1/$part2';
  }

  void _toggleFileSelection(String filename) {
    if (!mounted || !_isMultiSelectMode) return;

    setState(() {
      if (_selectedFiles.contains(filename)) {
        _selectedFiles.remove(filename);
        if (_selectedFiles.isEmpty) _isMultiSelectMode = false;
      } else {
        _selectedFiles.add(filename);
      }
    });
  }

  void _toggleMultiSelectMode() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
    });
  }

  void _selectAllFiles() {
    setState(() {
      _isMultiSelectMode = !_isMultiSelectMode;
      _selectedFiles.clear();
      if (_isMultiSelectMode) {
        for (var item in _fileList) {
          _selectedFiles.add(item.filename.toString());
        }
      }
    });
  }

  void _clearSelectionAndExitMultiSelect() {
    if (!mounted) return;
    setState(() {
      _selectedFiles.clear();
      _isMultiSelectMode = false;
    });
  }

  //重新命名
  Future<void> _renameFile() async {
    if (_selectedFiles.length != 1) {
      _showErrorDialog('重新命名失敗', '請選擇一個檔案或資料夾進行重新命名');
      return;
    }

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    final oldName = _selectedFiles.first;
    final oldPath = _joinPath(_currentPath, oldName);

    final textController = TextEditingController(text: oldName);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('重新命名'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '新名稱',
            hintText: '輸入新的檔案/資料夾名稱',
          ),
          autofocus: true,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              final newName = textController.text.trim();
              if (newName.isEmpty) {
                _showErrorDialog('重新命名失敗', '名稱不能為空');
                return;
              }
              if (newName == oldName) {
                Navigator.of(context).pop();
                return;
              }
              Navigator.of(context).pop();
              await _renameFileAction(oldPath, oldName, newName);
            },
            child: const Text('重新命名'),
          ),
        ],
      ),
    );
  }

  Future<void> _renameFileAction(
      String oldPath, String oldName, String newName) async {
    try {
      final newPath = _joinPath(_currentPath, newName);

      // 檢查新名稱是否已存在
      try {
        await _sftpClient.stat(newPath);
        _showErrorDialog('重新命名失敗', '名稱 "$newName" 已存在');
        return;
      } catch (e) {}

      await _sftpClient.rename(oldPath, newPath);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重新命名成功: $oldName → $newName')),
        );
        _clearSelectionAndExitMultiSelect();
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('重新命名失敗', e.toString());
    }
  }

  Future<void> _uploadFile() async {
    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    try {
      // 使用 file_selector 替代 file_picker
      const XTypeGroup typeGroup =
          XTypeGroup(label: 'files', extensions: <String>[]);
      final XFile? file =
          await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);

      if (file == null || !mounted) return;

      _showProgressDialog('上傳檔案', showCancel: true);
      _cancelOperation = false;

      int successCount = 0;
      int totalCount = 1;
      int skippedCount = 0;

      // 在每個檔案上傳前檢查連線狀態
      if (!await _checkConnection()) return;
      if (_cancelOperation) return;

      final localFile = File(file.path);
      final remotePath = _joinPath(_currentPath, file.name);
      if (!await localFile.exists()) return;

      bool fileExists = false;
      try {
        await _sftpClient.stat(remotePath);
        fileExists = true;
      } catch (e) {
        fileExists = false;
      }

      if (fileExists) {
        if (mounted) {
          Navigator.of(context).pop();
          final shouldOverwrite = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('檔案已存在'),
              content: Text('檔案 "${file.name}" 已存在，是否覆蓋？'),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('跳過'),
                ),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('覆蓋', style: TextStyle(color: Colors.red)),
                ),
              ],
            ),
          );
          _showProgressDialog('上傳檔案', showCancel: true);
          if (shouldOverwrite == false) {
            skippedCount++;
            return;
          }
        }
      }

      final fileSize = await localFile.length();
      setState(() {
        _currentOperation = '正在上傳: ${file.name} (1 / 1)';
        _uploadProgress = 0.0;
      });

      final remote = await _sftpClient.open(
        remotePath,
        mode: SftpFileOpenMode.create |
            SftpFileOpenMode.write |
            SftpFileOpenMode.truncate,
      );
      _currentUploader = remote;

      int offset = 0;
      await for (final chunk in localFile.openRead()) {
        // 在每次寫入前檢查連線狀態
        if (!await _checkConnection()) break;
        if (_cancelOperation) break;

        await remote.writeBytes(chunk, offset: offset);
        offset += chunk.length;
        if (mounted) {
          setState(() {
            _uploadProgress = fileSize > 0 ? offset / fileSize : 0.0;
          });
        }
      }

      try {
        await remote.close();
      } catch (e) {}
      _currentUploader = null;
      if (!_cancelOperation) successCount++;

      if (mounted) Navigator.of(context).pop();
      if (!_cancelOperation && mounted) {
        String message = '上傳完成: $successCount / $totalCount 個檔案';
        if (skippedCount > 0) message += ' (跳過 $skippedCount 個檔案)';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(message)));
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        _showErrorDialog('上傳失敗', e.toString());
      }
    } finally {
      _currentUploader = null;
      _uploadProgress = 0;
      _currentOperation = '';
    }
  }

  Future<void> _deleteSelectedFilesAction() async {
    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    try {
      int successCount = 0;
      int totalCount = _selectedFiles.length;

      _showProgressDialog('刪除檔案', showCancel: true);
      _cancelOperation = false;

      for (int i = 0; i < totalCount; i++) {
        // 在刪除每個檔案前檢查連線狀態
        if (!await _checkConnection()) break;
        if (_cancelOperation) break;

        final filename = _selectedFiles.elementAt(i);
        final itemPath = _joinPath(_currentPath, filename);

        setState(() {
          _currentOperation = '正在刪除: $filename (${i + 1} / $totalCount)';
        });

        try {
          final stat = await _sftpClient.stat(itemPath);
          if (stat.isDirectory) {
            // 使用SSH命令刪除目錄，支援非空目錄
            final session = await _sshClient!
                .execute('rm -rf "${_escapeShellArgument(itemPath)}"');
            await session.done;
            if (session.exitCode == 0) {
              successCount++;
            } else {
              final error = await session.stderr.join();
              debugPrint('刪除目錄失敗: $error');
            }
          } else {
            await _sftpClient.remove(itemPath);
            successCount++;
          }
        } catch (e) {
          debugPrint('刪除 $filename 失敗: $e');
        }
      }

      if (mounted) Navigator.of(context).pop();
      if (!_cancelOperation && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('刪除完成: $successCount/${_selectedFiles.length}')),
        );
        _clearSelectionAndExitMultiSelect();
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      if (mounted) {
        try {
          Navigator.of(context).pop();
        } catch (_) {}
        _showErrorDialog('刪除失敗', e.toString());
      }
    } finally {
      _currentOperation = '';
    }
  }

  // 轉義Shell參數中的特殊字符
  String _escapeShellArgument(String argument) {
    return argument.replaceAll("'", "'\\''");
  }

  Future<void> _downloadSelectedFiles() async {
    if (_selectedFiles.isEmpty) {
      debugPrint('沒有選中任何檔案，跳過下載');
      return;
    }

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    List<String> directories = [];
    for (String filename in _selectedFiles) {
      try {
        final fileItem = _fileList
            .firstWhere((item) => item.filename.toString() == filename);
        if (fileItem.attr?.isDirectory == true) directories.add(filename);
      } catch (e) {
        debugPrint('找不到檔案: $filename');
      }
    }

    if (directories.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('錯誤: 不能下載目錄: ${directories.join(', ')}'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    String? saveDir = _appSettings.defaultDownloadPath?.isNotEmpty == true
        ? _appSettings.defaultDownloadPath
        : await _getDownloadDirectory();

    if (saveDir == null && Platform.isAndroid) {
      saveDir = await _getAndroidDownloadDirectory();
    }

    try {
      final dir = Directory(saveDir!);
      if (!await dir.exists()) await dir.create(recursive: true);
    } catch (e) {
      if (mounted) {
        if (saveDir == null || saveDir.isEmpty) {
          debugPrint('沒有可用的下載目錄，下載操作已取消');
        } else {
          _showErrorDialog('下載失敗', '無法創建保存目錄: $e');
        }
      }
      return;
    }

    _showProgressDialog('下載檔案', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int total = _selectedFiles.length;

    for (int i = 0; i < total; i++) {
      // 在下載每個檔案前檢查連線狀態
      if (!await _checkConnection()) break;
      if (_cancelOperation) break;

      final filename = _selectedFiles.elementAt(i);
      final remotePath = _joinPath(_currentPath, filename);
      final safeFilename = _getSafeFileName(filename);
      final localFilePath = '$saveDir/$safeFilename';

      setState(() {
        _currentOperation = '正在下載: $filename (${i + 1} / $total)';
        _downloadProgress = 0.0;
      });

      await _downloadSingleFile(remotePath, localFilePath, filename, i, total);
      if (!_cancelOperation && await File(localFilePath).exists())
        successCount++;
    }

    if (mounted) {
      try {
        Navigator.of(context).pop();
      } catch (_) {}
      if (!_cancelOperation) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下載完成: $successCount / $total 個檔案')),
        );
        _clearSelectionAndExitMultiSelect();
      }
    }

    _downloadProgress = 0;
    _currentDownloadFile = null;
    _currentOperation = '';
  }

  Future<String?> _getDownloadDirectory() async {
    // 使用 file_selector 替代 file_picker
    if (Platform.isWindows) {
      final firstSelectedFile = _selectedFiles.first;
      final String? result = (await getSaveLocation(
        suggestedName:
            _selectedFiles.length == 1 ? firstSelectedFile : 'download',
      )) as String?;
      return result?.substring(0, result.lastIndexOf(Platform.pathSeparator));
    } else {
      if (Platform.isOhos) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('HarmonyOS暫不支援檔案下載')));
        //for 2in1,tablet only
        //return await PathProviderPlatform.instance.getDownloadsPath();
      } else {
        return await getDirectoryPath();
      }
    }
    return null;
  }

  Future<String?> _getAndroidDownloadDirectory() async {
    return _appSettings.defaultDownloadPath?.isNotEmpty == true
        ? _appSettings.defaultDownloadPath
        : await SettingsService.getPlatformDefaultDownloadPath();
  }

  Future<void> _downloadSingleFile(String remotePath, String localFilePath,
      String filename, int index, int total) async {
    IOSink? sink;
    dynamic remote;

    try {
      final stat = await _sftpClient.stat(remotePath);
      final int fileSize = (stat.size ?? 0).toInt();
      if (fileSize <= 0) {
        debugPrint('檔案大小為0或無效: $filename');
        return;
      }

      remote = await _sftpClient.open(remotePath);
      _currentDownloadFile = remote;
      final localFile = File(localFilePath);
      sink = localFile.openWrite();

      num offset = 0;
      const int chunkSize = 32 * 1024;

      while (offset < fileSize && !_cancelOperation) {
        // 在每次讀取前檢查連線狀態
        if (!await _checkConnection()) break;

        final bytesToRead =
            fileSize - offset > chunkSize ? chunkSize : fileSize - offset;
        final chunk =
            await remote.readBytes(offset: offset, length: bytesToRead);
        if (chunk.isEmpty) {
          debugPrint('讀取到空數據塊，檔案可能已損壞: $filename');
          break;
        }
        sink.add(chunk);
        offset += chunk.length;
        if (mounted) {
          setState(() =>
              _downloadProgress = fileSize > 0 ? (offset / fileSize) : 0.0);
        }
      }

      await sink.flush();
      await sink.close();
      await remote.close();
      _currentDownloadFile = null;
    } catch (e) {
      debugPrint('下載檔案 $filename 失敗: $e');
      try {
        await sink?.close();
      } catch (_) {}
      try {
        await remote?.close();
      } catch (_) {}
      _currentDownloadFile = null;
      try {
        final incompleteFile = File(localFilePath);
        if (await incompleteFile.exists()) await incompleteFile.delete();
      } catch (deleteError) {
        debugPrint('刪除不完整檔案失敗: $deleteError');
      }
      rethrow;
    }
  }

  String _getSafeFileName(String filename) {
    return filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  }

  Future<void> _cancelCurrentOperation() async {
    _cancelOperation = true;
    try {
      await _currentUploader?.close();
    } catch (e) {
      debugPrint('關閉 uploader 出錯: $e');
    }
    try {
      await _currentDownloadFile?.close();
    } catch (e) {
      debugPrint('關閉 download file 出錯: $e');
    }
    _currentUploader = null;
    _currentDownloadFile = null;

    if (mounted) {
      setState(() {
        _uploadProgress = 0.0;
        _downloadProgress = 0.0;
        _currentOperation = '';
      });

      // 安全關閉對話框
      if (_isProgressDialogOpen && Navigator.canPop(context)) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('操作已取消')));
      }
    }
  }

  Future<void> _deleteSelectedFiles() async {
    if (_selectedFiles.isEmpty) return;

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('刪除檔案'),
        content: Text('確定要刪除選中的 ${_selectedFiles.length} 個檔案/資料夾嗎？'),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteSelectedFilesAction();
            },
            child: const Text('刪除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  Future<void> _showFileDetails() async {
    if (_selectedFiles.length != 1) return;

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    final filename = _selectedFiles.first;
    final filePath = _joinPath(_currentPath, filename);

    try {
      final stat = await _sftpClient.stat(filePath);
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('屬性 - $filename'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildDetailItem('檔案名', filename),
                  _buildDetailItem('路徑', filePath),
                  _buildDetailItem('類型', _getFileType(stat)),
                  _buildDetailItem('大小', _formatFileSize(stat.size ?? 0)),
                  _buildDetailItem('權限', _getPermissions(stat)),
                  _buildDetailItem('修改時間', _formatDate(stat.modifyTime)),
                  _buildDetailItem('訪問時間', _formatDate(stat.accessTime)),
                ],
              ),
            ),
            actions: [
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('關閉'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showErrorDialog('獲取屬性失敗', e.toString());
    }
  }

  Widget _buildListView() {
    return ListView.builder(
      itemCount: _fileList.length,
      itemBuilder: _buildFileItem,
    );
  }

  Widget _buildGridView() {
    final screenWidth = MediaQuery.of(context).size.width;
    int crossAxisCount = _getCrossAxisCount(screenWidth);

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 4),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 0.95,
      ),
      itemCount: _fileList.length,
      itemBuilder: (context, index) {
        final item = _fileList[index];
        final isDirectory = item.attr?.isDirectory == true;
        final filename = item.filename.toString();
        final isSelected = _selectedFiles.contains(filename);

        return GestureDetector(
          onTap: () {
            if (_isMultiSelectMode) {
              _toggleFileSelection(filename);
            } else if (isDirectory) {
              _loadDirectory(_joinPath(_currentPath, filename));
            }
          },
          onLongPress: () {
            if (!_isMultiSelectMode) _toggleMultiSelectMode();
            _toggleFileSelection(filename);
          },
          child: Container(
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.12) : null,
              borderRadius: BorderRadius.circular(5),
              border: isSelected
                  ? Border.all(color: Colors.blueAccent, width: 1.3)
                  : null,
            ),
            padding: const EdgeInsets.all(4),
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Container(
                        alignment: Alignment.center,
                        child: Icon(
                          isDirectory ? Icons.folder : Icons.insert_drive_file,
                          size: 50,
                          color: isDirectory ? Colors.blueAccent : Colors.grey,
                        ),
                      ),
                    ),
                    Container(
                      height: constraints.maxHeight * 0.3,
                      alignment: Alignment.topCenter,
                      child: Text(
                        filename,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth >= 1600) return 10;
    if (screenWidth >= 1300) return 8;
    if (screenWidth >= 1000) return 7;
    if (screenWidth >= 800) return 6;
    if (screenWidth >= 600) return 5;
    if (screenWidth >= 400) return 4;
    return 3;
  }

  Widget _buildFileItem(BuildContext context, int index) {
    final item = _fileList[index];
    final isDirectory = item.attr?.isDirectory == true;
    final filename = item.filename.toString();
    final size = item.attr?.size ?? 0;
    final isSelected = _selectedFiles.contains(filename);

    return ListTile(
      leading: Icon(
        isDirectory ? Icons.folder : Icons.insert_drive_file,
        color: isDirectory ? Colors.blueAccent : Colors.grey,
      ),
      title: Text(filename),
      subtitle: Text(isDirectory ? '資料夾' : _formatFileSize(size)),
      onTap: () {
        if (_isMultiSelectMode) {
          _toggleFileSelection(filename);
        } else if (isDirectory) {
          _loadDirectory(_joinPath(_currentPath, filename));
        }
      },
      onLongPress: () {
        if (!_isMultiSelectMode) _toggleMultiSelectMode();
        _toggleFileSelection(filename);
      },
      tileColor: isSelected ? Colors.blue.withOpacity(0.3) : null,
    );
  }

  Widget _buildDetailItem(String label, String value) {
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 80,
              child: Text('$label:',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            Expanded(child: Text(value.isEmpty ? '未知' : value)),
          ],
        ));
  }

  String _getFileType(dynamic stat) {
    if (stat.isDirectory) return '目錄';
    if (stat.isSymbolicLink) return '符號鏈接';
    if (stat.isSocket) return '套接字';
    if (stat.isBlockDevice) return '塊設備';
    if (stat.isCharacterDevice) return '字符設備';

    try {
      final type = stat.type?.toString().toLowerCase() ?? '';
      if (type.contains('directory')) return '目錄';
      if (type.contains('symlink') || type.contains('link')) return '符號鏈接';
      if (type.contains('socket')) return '套接字';
      if (type.contains('block')) return '塊設備';
      if (type.contains('character')) return '字符設備';
      if (type.contains('fifo') || type.contains('pipe')) return 'FIFO';
      if (type.contains('regular') || type.contains('file')) return '普通檔案';
    } catch (e) {}
    return '普通檔案';
  }

  String _getPermissions(dynamic stat) {
    try {
      final mode = stat.mode;
      if (mode == null) return '---------';
      if (mode is String) {
        final match = RegExp(r'\((\d+)\)').firstMatch(mode);
        if (match != null) {
          final octalString = match.group(1);
          if (octalString != null && octalString.length >= 3) {
            final lastDigits = octalString.length > 3
                ? octalString.substring(octalString.length - 3)
                : octalString;
            return _octalToPermissionString(lastDigits);
          }
        }
        if (mode.length >= 3) {
          final lastDigits =
              mode.length > 3 ? mode.substring(mode.length - 3) : mode;
          if (RegExp(r'^\d+$').hasMatch(lastDigits))
            return _octalToPermissionString(lastDigits);
        }
        return '---------';
      }
      if (mode is int) return _intToPermissionString(mode);

      final modeStr = mode.toString();
      final digitMatch = RegExp(r'(\d{3,4})').firstMatch(modeStr);
      if (digitMatch != null) {
        final digits = digitMatch.group(1)!;
        final lastThree =
            digits.length > 3 ? digits.substring(digits.length - 3) : digits;
        return _octalToPermissionString(lastThree);
      }
      if (modeStr.length >= 9 && RegExp(r'^[rwsxt-]{9,}$').hasMatch(modeStr)) {
        return modeStr.length > 9
            ? modeStr.substring(modeStr.length - 9)
            : modeStr;
      }
      return '---------';
    } catch (e) {
      debugPrint('獲取權限失敗: $e');
      return '---------';
    }
  }

  String _octalToPermissionString(String octalString) {
    if (octalString.length != 3) return '---------';
    final permissions = StringBuffer();
    for (int i = 0; i < 3; i++) {
      final digit = int.tryParse(octalString[i]);
      if (digit == null) return '---------';
      permissions.write((digit & 4) != 0 ? 'r' : '-');
      permissions.write((digit & 2) != 0 ? 'w' : '-');
      permissions.write((digit & 1) != 0 ? 'x' : '-');
    }
    return permissions.toString();
  }

  String _intToPermissionString(int mode) {
    final permissions = StringBuffer();
    permissions.write((mode & 0x100) != 0 ? 'r' : '-');
    permissions.write((mode & 0x80) != 0 ? 'w' : '-');
    permissions.write((mode & 0x40) != 0 ? 'x' : '-');
    permissions.write((mode & 0x20) != 0 ? 'r' : '-');
    permissions.write((mode & 0x10) != 0 ? 'w' : '-');
    permissions.write((mode & 0x8) != 0 ? 'x' : '-');
    permissions.write((mode & 0x4) != 0 ? 'r' : '-');
    permissions.write((mode & 0x2) != 0 ? 'w' : '-');
    permissions.write((mode & 0x1) != 0 ? 'x' : '-');
    return permissions.toString();
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return '未知';
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _createDirectory() async {
    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    final textController = TextEditingController();
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新增資料夾'),
        content: TextField(
          controller: textController,
          decoration: const InputDecoration(
            labelText: '資料夾名稱',
            hintText: '輸入新資料夾名稱',
          ),
          autofocus: true,
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () async {
              if (textController.text.trim().isNotEmpty) {
                Navigator.of(context).pop();
                await _createDirectoryAction(textController.text.trim());
              }
            },
            child: const Text('創建'),
          ),
        ],
      ),
    );
  }

  Future<void> _createDirectoryAction(String dirName) async {
    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    try {
      final newDirPath = _joinPath(_currentPath, dirName);
      await _sftpClient.mkdir(newDirPath);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('資料夾創建成功')));
        await _loadDirectory(_currentPath);
      }
    } catch (e) {
      _showErrorDialog('創建資料夾失敗', e.toString());
    }
  }

  // 修改為支持批量複製
  Future<void> _copySelected() async {
    if (_selectedFiles.isEmpty) return;

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    final newClipboardItems = <ClipboardItem>[];

    for (final name in _selectedFiles) {
      final remotePath = _joinPath(_currentPath, name);

      try {
        final stat = await _sftpClient.stat(remotePath);
        if (!_hasReadPermission(stat)) {
          _showErrorDialog('複製失敗', '沒有讀取 $name 的權限');
          return;
        }
        newClipboardItems.add(ClipboardItem(
          path: remotePath,
          isDirectory: stat.isDirectory,
          name: name,
        ));
      } catch (e) {
        _showErrorDialog('複製失敗', '無法訪問 $name: $e');
        return;
      }
    }

    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(newClipboardItems);
      _clipboardIsCut = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已複製 ${_selectedFiles.length} 個項目')),
      );
      _clearSelectionAndExitMultiSelect();
    }
  }

  // 修改為支持批量剪下
  Future<void> _cutSelected() async {
    if (_selectedFiles.isEmpty) return;

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    final newClipboardItems = <ClipboardItem>[];

    for (final name in _selectedFiles) {
      final remotePath = _joinPath(_currentPath, name);

      try {
        final stat = await _sftpClient.stat(remotePath);
        if (!_hasReadPermission(stat)) {
          _showErrorDialog('剪下失敗', '沒有修改 $name 的權限');
          return;
        }
        newClipboardItems.add(ClipboardItem(
          path: remotePath,
          isDirectory: stat.isDirectory,
          name: name,
        ));
      } catch (e) {
        _showErrorDialog('剪下失敗', '無法訪問 $name: $e');
        return;
      }
    }

    setState(() {
      _clipboardItems.clear();
      _clipboardItems.addAll(newClipboardItems);
      _clipboardIsCut = true;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已剪下 ${_selectedFiles.length} 個項目')),
      );
    }
  }

  bool _hasReadPermission(dynamic stat) {
    try {
      final permissions = _getPermissions(stat);
      return permissions.length >= 9 && permissions[6] == 'r';
    } catch (e) {
      debugPrint('檢查讀取權限失敗: $e');
      return true;
    }
  }

  Future<void> _showProgressDialog(String title,
      {required bool showCancel}) async {
    if (_isProgressDialogOpen) return;

    _isProgressDialogOpen = true;

    await showDialog(
      context: context,
      barrierDismissible: false,
      useRootNavigator: true,
      builder: (context) {
        return StreamBuilder<int>(
          stream: Stream.periodic(const Duration(milliseconds: 200), (i) => i),
          builder: (context, snapshot) {
            final progress =
                _uploadProgress > 0 ? _uploadProgress : _downloadProgress;
            final displayedText =
                _currentOperation.isEmpty ? '處理中...' : _currentOperation;
            return AlertDialog(
              title: Text(title),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(displayedText),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: progress),
                  const SizedBox(height: 8),
                  Text('${(progress * 100).toStringAsFixed(1)}%'),
                ],
              ),
              actions: showCancel
                  ? [
                      OutlinedButton(
                          onPressed: _cancelCurrentOperation,
                          child: const Text('取消'))
                    ]
                  : null,
            );
          },
        );
      },
    ).then((_) {
      _isProgressDialogOpen = false;
    });
  }

  // 修改為支持批量貼上，添加權限檢查
  Future<void> _pasteFile() async {
    if (_clipboardItems.isEmpty) return;

    // 在操作前檢查連線狀態
    if (!await _checkConnection()) return;

    _showProgressDialog('貼上檔案', showCancel: true);
    _cancelOperation = false;

    int successCount = 0;
    int totalCount = _clipboardItems.length;

    for (int i = 0; i < totalCount; i++) {
      if (_cancelOperation) break;
      if (!await _checkConnection()) break;

      final item = _clipboardItems[i];
      final newPath = _joinPath(_currentPath, item.name);

      setState(() {
        _currentOperation = '正在貼上: ${item.name} (${i + 1} / $totalCount)';
      });

      try {
        if (_clipboardIsCut) {
          // 剪下操作：移動檔案/目錄
          await _sftpClient.rename(item.path, newPath);
          successCount++;
        } else {
          // 複製操作：使用SSH命令複製
          final cmd = item.isDirectory
              ? 'cp -r "${_escapeShellArgument(item.path)}" "${_escapeShellArgument(newPath)}"'
              : 'cp "${_escapeShellArgument(item.path)}" "${_escapeShellArgument(newPath)}"';

          final session = await _sshClient!.execute(cmd);
          await session.done;

          if (session.exitCode == 0) {
            successCount++;
          } else {
            final stderr = await session.stderr.join();
            debugPrint('複製失敗: $stderr');
          }
        }
      } catch (e) {
        debugPrint('貼上 ${item.name} 失敗: $e');
      }
    }

    if (mounted) Navigator.of(context).pop();

    if (!_cancelOperation && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('貼上完成: $successCount / $totalCount 個項目')),
      );

      // 如果是剪下操作，清空剪貼板
      if (_clipboardIsCut) {
        setState(() {
          _clipboardItems.clear();
          _clipboardIsCut = false;
        });
      }

      await _loadDirectory(_currentPath);
    }

    _currentOperation = '';
  }

  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(child: Text(message)),
        actions: [
          OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('確定'))
        ],
      ),
    );
  }

  String _formatFileSize(int size) {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  void _goToParentDirectory() {
    setState(() {
      _isMultiSelectMode = false;
      _selectedFiles.clear();
    });
    if (_currentPath != '/') {
      String parentPath = _normalizePath(_currentPath);
      if (parentPath.endsWith('/') && parentPath != '/') {
        parentPath = parentPath.substring(0, parentPath.length - 1);
      }
      final lastSlashIndex = parentPath.lastIndexOf('/');
      parentPath =
          lastSlashIndex > 0 ? parentPath.substring(0, lastSlashIndex) : '/';
      _loadDirectory(_normalizePath(parentPath));
    }
  }

  void _exitApp() => Navigator.of(context).pop();

  @override
  void dispose() {
    _cancelCurrentOperation();
    try {
      _sftpClient?.close();
    } catch (_) {}
    try {
      _sshClient?.close();
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedFiles.isNotEmpty;
    final singleSelection = _selectedFiles.length == 1;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWideScreen = screenWidth >= 800;
    final iconColor = _getIconColor(context);
    final disabledIconColor = _getDisabledIconColor(context);
    final displayTitle = 'SFTP-${widget.connection.name}';

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (_currentPath != '/') {
          _goToParentDirectory();
          return;
        }

        final now = DateTime.now();
        final bool shouldExit = _lastBackPressedTime == null ||
            now.difference(_lastBackPressedTime!) > const Duration(seconds: 2);

        if (shouldExit) {
          _lastBackPressedTime = now;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '再按一次退出',
              ),
              duration: const Duration(seconds: 1),
            ),
          );

          Future.delayed(const Duration(seconds: 3), () {});
        } else {
          // 允許退出
          if (mounted) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          toolbarHeight: 40,
          backgroundColor: _getAppBarColor(),
          foregroundColor: Colors.white,
          titleSpacing: 0,
          automaticallyImplyLeading: false, // 完全禁用預設的返回按鈕
          leading: _ismobile
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back, size: 20),
                  padding: const EdgeInsets.all(8),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          title: Container(
            width: double.infinity,
            child: Padding(
              padding: EdgeInsets.only(left: _ismobile ? 18.0 : 0), // 添加左邊距
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    displayTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _isConnected ? Icons.circle : Icons.circle_outlined,
                        color: Colors.white,
                        size: 8,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _status,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'refresh':
                    _loadDirectory(_currentPath);
                    break;
                  case 'reconnect':
                    _connectSftp();
                    break;
                  case 'exit':
                    _exitApp();
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(children: [Text('刷新')]),
                ),
                const PopupMenuItem(
                  value: 'reconnect',
                  child: Row(children: [Text('重新連線')]),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'exit',
                  child: Row(children: [Text('退出')]),
                ),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text(
                    _currentPath,
                    style:
                        const TextStyle(fontFamily: 'hmossans', fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              height: screenWidth < 600 ? 80 : 40,
              child: screenWidth < 600
                  ? _buildDoubleRowToolbar(iconColor, disabledIconColor,
                      hasSelection, singleSelection)
                  : _buildSingleRowToolbar(iconColor, disabledIconColor,
                      hasSelection, singleSelection, isWideScreen),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: Text('正在加載'))
                  : _fileList.isEmpty
                      ? const Center(child: Text('目錄為空'))
                      : _viewMode == ViewMode.list
                          ? _buildListView()
                          : _buildGridView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconButton(
      IconData icon, String tooltip, VoidCallback? onPressed, Color color,
      {double iconSize = 24}) {
    return IconButton(
      icon: Icon(icon, size: iconSize),
      onPressed: onPressed,
      tooltip: tooltip,
      color: color,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
