// lib/permission_util.dart
import 'package:permission_handler/permission_handler.dart';

Future<bool> ensurePermissions() async {
  // 定义我们需要的所有权限
  final permissions = [
    Permission.manageExternalStorage, // 用于选择模型目录
    Permission.notification, // 用于前台服务通知 (Android 13+)
    Permission.ignoreBatteryOptimizations, // 用于后台保活
  ];

  // 一次性请求所有权限
  Map<Permission, PermissionStatus> statuses = await permissions.request();

  // 检查所有权限是否都已授予
  bool allGranted = true;
  statuses.forEach((permission, status) {
    if (!status.isGranted) {
      allGranted = false;
    }
  });

  return allGranted;
}

// 可选：提供一个打开应用设置的辅助函数
Future<void> openSettings() async {
  await openAppSettings();
}
