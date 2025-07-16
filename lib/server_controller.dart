import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart' as shelf_router;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

class ServerController extends ChangeNotifier implements TaskHandler {
  bool _modelLoaded = false;
  bool _serverRunning = false;

  bool get modelLoaded => _modelLoaded;
  bool get serverRunning => _serverRunning;

  final List<String> _logs = [];
  List<String> get logs => List.unmodifiable(_logs);

  Timer? _logRefreshTimer;
  sherpa_onnx.OfflineRecognizer? _recognizer;
  final List<HttpServer> _servers = [];

  ServerController() {
    // 启动日志自动刷新
    _logRefreshTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) {
      notifyListeners();
    });
  }

  // 内部日志记录方法
  void _log(String message) {
    final timestamp = DateTime.now()
        .toIso8601String()
        .split('T')
        .last
        .substring(0, 12);
    final logMessage = '[$timestamp] $message';
    _logs.insert(0, logMessage);
    if (_logs.length > 500) {
      _logs.removeLast();
    }
    notifyListeners();

    // 如果前台任务正在运行，发送日志到前台任务
    if (_serverRunning) {
      FlutterForegroundTask.sendDataToTask({'message': logMessage});
    }
  }

  // 添加外部日志
  void addLog(String message) {
    _log(message);
  }

  // 加载模型
  Future<void> loadModel(String modelDir) async {
    if (_modelLoaded) return;

    final startTime = DateTime.now();
    _log('开始加载模型...');

    try {
      sherpa_onnx.initBindings();

      final modelPath = p.join(modelDir, 'model.int8.onnx');
      final tokensPath = p.join(modelDir, 'tokens.txt');

      // 检查文件是否存在
      if (!File(modelPath).existsSync()) {
        throw Exception('模型文件不存在: $modelPath');
      }
      if (!File(tokensPath).existsSync()) {
        throw Exception('词汇表文件不存在: $tokensPath');
      }

      final cfg = sherpa_onnx.OfflineRecognizerConfig(
        model: sherpa_onnx.OfflineModelConfig(
          senseVoice: sherpa_onnx.OfflineSenseVoiceModelConfig(
            model: modelPath,
            language: '',
            useInverseTextNormalization: true,
          ),
          tokens: tokensPath,
          debug: false,
          numThreads: 2,
        ),
      );

      _recognizer = sherpa_onnx.OfflineRecognizer(cfg);
      _modelLoaded = true;

      final loadTime = DateTime.now().difference(startTime).inMilliseconds;
      _log('模型加载成功！耗时: ${loadTime}ms');
    } catch (e) {
      _log('模型加载失败: $e');
      _modelLoaded = false;
    }
    notifyListeners();
  }

  // 卸载模型
  Future<void> unloadModel() async {
    if (_serverRunning) {
      await stopServer();
    }

    _recognizer?.free();
    _recognizer = null;
    _modelLoaded = false;
    _log('模型已卸载');
    notifyListeners();
  }

  // 获取所有本地IP地址
  Future<List<String>> _getLocalIPs() async {
    final List<String> ips = [];

    try {
      for (final interface in await NetworkInterface.list()) {
        for (final addr in interface.addresses) {
          if (!addr.isLoopback) {
            ips.add('${addr.address} (${interface.name})');
          }
        }
      }
    } catch (e) {
      _log('获取IP地址失败: $e');
    }

    return ips;
  }

  // 启动服务
  Future<void> startServer(int port) async {
    if (_serverRunning || !_modelLoaded) return;

    try {
      _log('正在启动HTTP服务...');

      // 启动前台任务（权限已在加载模型时申请过）
      await FlutterForegroundTask.startService(
        notificationTitle: 'ASR Server 运行中',
        notificationText: '端口: $port，点击返回应用',
        callback: startCallback,
      );

      final router = shelf_router.Router()
        ..get('/', _handleRoot)
        ..post('/asr', _handleAsr);

      // 启动IPv4服务器
      try {
        final server4 = await shelf_io.serve(
          router.call,
          InternetAddress.anyIPv4,
          port,
        );
        _servers.add(server4);
        _log('IPv4服务启动成功: ${server4.address.host}:${server4.port}');
      } catch (e) {
        _log('IPv4服务启动失败: $e');
      }

      // 启动IPv6服务器
      try {
        final server6 = await shelf_io.serve(
          router.call,
          InternetAddress.anyIPv6,
          port,
        );
        _servers.add(server6);
        _log('IPv6服务启动成功: [${server6.address.host}]:${server6.port}');
      } catch (e) {
        _log('IPv6服务启动失败: $e');
      }

      if (_servers.isNotEmpty) {
        _serverRunning = true;

        // 获取并打印所有本地IP
        final ips = await _getLocalIPs();
        _log('HTTP服务已启动，监听端口: $port');
        if (ips.isNotEmpty) {
          _log('本机IP地址:');
          for (final ip in ips) {
            _log('  - http://$ip:$port');
          }
        }
      } else {
        throw Exception('所有服务器启动失败');
      }
    } catch (e) {
      _log('启动服务失败: $e');
      await stopServer();
    }
    notifyListeners();
  }

  // 停止服务
  Future<void> stopServer() async {
    if (!_serverRunning) return;

    _log('正在停止服务...');

    // 关闭所有服务器
    for (final server in _servers) {
      await server.close(force: true);
    }
    _servers.clear();

    // 停止前台任务
    await FlutterForegroundTask.stopService();

    _serverRunning = false;
    _log('服务已停止');
    notifyListeners();
  }

  // 根路径处理器
  Response _handleRoot(Request req) {
    return Response.ok(
      jsonEncode({
        'status': 'ok',
        'model_loaded': _recognizer != null,
        'usage': 'POST 16kHz/16bit/mono wav to /asr',
        'time': DateTime.now().toIso8601String(),
      }),
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
      },
    );
  }

  // ASR 请求处理器
  Future<Response> _handleAsr(Request req) async {
    final startTime = DateTime.now();

    if (_recognizer == null) {
      const errorMessage = '错误：识别器未初始化';
      _log(errorMessage);
      return Response.internalServerError(
        body: jsonEncode({'status': 'error', 'message': errorMessage}),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }

    try {
      final bytes = Uint8List.fromList(
        await req.read().expand((e) => e).toList(),
      );

      final loadTime = DateTime.now().difference(startTime).inMilliseconds;
      _log('收到音频数据: ${bytes.length} bytes (接收耗时: ${loadTime}ms)');

      final tmpPath = p.join(
        Directory.systemTemp.path,
        'asr_${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(1 << 16)}.wav',
      );

      final tmpFile = File(tmpPath);
      await tmpFile.writeAsBytes(bytes);

      final wave = sherpa_onnx.readWave(tmpPath);
      await tmpFile.delete();

      if (wave.samples.isEmpty) {
        throw Exception('音频文件为空或格式不正确');
      }

      final recognizeStart = DateTime.now();
      final stream = _recognizer!.createStream();
      stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
      _recognizer!.decode(stream);
      final result = _recognizer!.getResult(stream).text;
      stream.free();

      final recognizeTime = DateTime.now()
          .difference(recognizeStart)
          .inMilliseconds;
      final totalTime = DateTime.now().difference(startTime).inMilliseconds;

      _log('识别完成: "$result" (识别耗时: ${recognizeTime}ms, 总耗时: ${totalTime}ms)');

      return Response.ok(
        jsonEncode({
          'status': 'success',
          'result': result,
          'processing_time_ms': totalTime,
          'recognition_time_ms': recognizeTime,
        }),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    } catch (e) {
      final errorTime = DateTime.now().difference(startTime).inMilliseconds;
      _log('识别错误: $e (耗时: ${errorTime}ms)');

      return Response.internalServerError(
        body: jsonEncode({
          'status': 'error',
          'message': e.toString(),
          'processing_time_ms': errorTime,
        }),
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
        },
      );
    }
  }

  // TaskHandler 实现 - 所有必需的抽象方法
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 前台任务启动时调用
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // 定期调用（每5秒）
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool killProcess) async {
    // 前台任务销毁时调用
  }

  @override
  void onButtonPressed(String id) {
    // 通知按钮按下时调用
  }

  @override
  void onNotificationPressed() {
    // 通知点击时调用
    FlutterForegroundTask.launchApp('/');
  }

  @override
  void onNotificationButtonPressed(String id) {
    // 通知按钮按下时调用
  }

  @override
  void onNotificationDismissed() {
    // 通知被关闭时调用
  }

  @override
  void onReceiveData(Object data) {
    // 接收数据时调用
  }

  @override
  void dispose() {
    _logRefreshTimer?.cancel();
    stopServer();
    unloadModel();
    super.dispose();
  }
}

// 前台任务回调函数
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(ServerController());
}
