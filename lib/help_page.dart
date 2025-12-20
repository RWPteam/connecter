import 'package:flutter/material.dart';

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('帮助'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'connssh 帮助',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'connssh 是一个便捷的SSH和SFTP连接管理工具',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              _buildHelpSection(
                title: '快速连接',
                content: '使用快速连接来进行SSH/SFTP的连接操作。您连接过的主机也会自动添加到最近连接中',
              ),
              _buildHelpSection(
                title: '管理连接和凭证',
                content: '在"管理认证凭证"和"管理连接"页面，可以管理您的连接和凭证信息',
              ),
              _buildHelpSection(
                title: 'SSH/SFTP',
                content: '终端支持同时开启两个会话；SFTP通过顶部工具栏进行操作，支持侧滑返回上级',
              ),
              _buildHelpSection(
                  title: '数据面板（Beta）',
                  content: '此功能可以监控大部分Linux服务器的系统运行数据，但对于部分服务器不起作用'),
              _buildHelpSection(
                title: '反馈',
                content: '如有问题或建议，请发送邮件至samuioto@outlook.com',
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () {
                  showAboutDialog(
                    context: context,
                    applicationName: 'connssh',
                    applicationVersion: '1.2.0',
                    children: [
                      const Text(
                        '此版本更新内容：',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '新增功能：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text('新增数据面板功能，可实时监控服务器运行情况（Beta）'),
                      const Text('支持同时开启两个终端会话，支持一键切换（Beta）'),
                      const Text('新增密钥和证书信息读取功能，可从密钥和证书文件解析相关信息'),
                      const Text('可将已保存的连接一键保存为其他类型，方便连接'),
                      const SizedBox(height: 16),
                      const Text(
                        '问题改进：',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      const Text('修复SSH页面焦点不正确获取的情况'),
                      const Text('修复SFTP返回二次确认提示消失的问题'),
                      const Text('最近连接支持去重，避免重复显示'),
                      const Text('工具栏采用了新的设计，降低误触率'),
                      const Text('修正部分样式设计和文字说明'),
                      const SizedBox(height: 4),
                    ],
                  );
                },
                child: const Text('关于'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelpSection({required String title, required String content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
