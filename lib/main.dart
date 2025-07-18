import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'permission_util.dart';
import 'server_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化前台任务
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'asr_server_foreground',
      channelName: 'ASR Server Foreground',
      channelDescription:
          'This notification appears when ASR server is running in the background.',
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(
      showNotification: true,
      playSound: false,
    ),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(5000),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );

  runApp(const ASRServerApp());
}

class ASRServerApp extends StatelessWidget {
  const ASRServerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => ServerController(),
      child: MaterialApp(
        title: 'ASR HTTP Server',
        // 亮色主题
        theme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.light,
        ),
        // 暗色主题
        darkTheme: ThemeData(
          useMaterial3: true,
          colorSchemeSeed: Colors.indigo,
          brightness: Brightness.dark,
        ),
        // 跟随系统主题
        themeMode: ThemeMode.system,
        home: const HomePage(),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? modelDir;
  final _portCtl = TextEditingController(text: '8000');
  static const String _modelDirKey = 'selected_model_directory';

  @override
  void initState() {
    super.initState();
    // 接收来自前台任务的数据
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
    // 加载保存的模型目录
    _loadSavedModelDir();
  }

  @override
  void dispose() {
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
    super.dispose();
  }

  // 加载保存的模型目录
  Future<void> _loadSavedModelDir() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedDir = prefs.getString(_modelDirKey);
      if (savedDir != null && mounted) {
        setState(() {
          modelDir = savedDir;
        });
      }
    } catch (e) {
      // 忽略加载错误
    }
  }

  // 保存模型目录
  Future<void> _saveModelDir(String dir) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modelDirKey, dir);
    } catch (e) {
      // 忽略保存错误
    }
  }

  void _onReceiveTaskData(Object data) {
    if (mounted && data is Map<String, dynamic>) {
      final controller = context.read<ServerController>();
      final message = data['message'] as String?;
      if (message != null) {
        controller.addLog(message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ServerController>();

    return Scaffold(
      appBar: AppBar(title: const Text('ASR Maid')),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            // 模型目录选择
            Row(
              children: [
                Expanded(
                  child: Text(
                    modelDir ?? '未选择模型目录',
                    style: TextStyle(
                      color: modelDir == null
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: controller.serverRunning
                      ? null
                      : () async {
                          final dir = await FilePicker.platform
                              .getDirectoryPath();
                          if (dir != null && mounted) {
                            setState(() => modelDir = dir);
                            await _saveModelDir(dir); // 保存选择的目录
                          }
                        },
                  icon: const Icon(Icons.folder_open),
                  label: const Text('选择模型目录'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // 端口
            TextField(
              controller: _portCtl,
              decoration: const InputDecoration(
                labelText: '端口号',
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.number,
              enabled: !controller.serverRunning,
            ),
            const SizedBox(height: 12),

            // 加载模型按钮
            FilledButton.icon(
              onPressed: () async {
                if (controller.modelLoaded) {
                  await controller.unloadModel();
                } else {
                  if (modelDir == null) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('请先选择模型目录'),
                          backgroundColor: Colors.orange,
                        ),
                      );
                    }
                    return;
                  }

                  // 在加载模型时申请权限
                  if (!await ensurePermissions()) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('权限被拒绝！请在系统设置中手动授予权限。'),
                          backgroundColor: Colors.red,
                          action: SnackBarAction(
                            label: '去设置',
                            onPressed: () => openAppSettings(),
                          ),
                          duration: const Duration(seconds: 5),
                        ),
                      );
                    }
                    return;
                  }

                  await controller.loadModel(modelDir!);
                }
              },
              icon: Icon(controller.modelLoaded ? Icons.clear : Icons.download),
              label: Text(controller.modelLoaded ? '卸载模型' : '加载模型'),
            ),
            const SizedBox(height: 8),

            // 启动/停止服务按钮
            FilledButton.icon(
              onPressed: controller.modelLoaded
                  ? () async {
                      if (controller.serverRunning) {
                        await controller.stopServer();
                      } else {
                        // 权限已在加载模型时申请过，这里直接启动服务
                        await controller.startServer(int.parse(_portCtl.text));
                      }
                    }
                  : null,
              icon: Icon(
                controller.serverRunning ? Icons.stop : Icons.play_arrow,
              ),
              label: Text(controller.serverRunning ? '停止服务' : '启动服务'),
            ),
            const Divider(height: 24),

            const Text('实时日志'),
            const SizedBox(height: 6),

            // 日志列表
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.3),
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: ListView.builder(
                  reverse: true,
                  itemCount: controller.logs.length,
                  itemBuilder: (_, i) => Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: Text(
                      controller.logs[i],
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
