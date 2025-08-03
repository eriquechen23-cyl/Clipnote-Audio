/// 日誌工具骨架
class Logger {
  static void log(String message) {
    final now = DateTime.now().toIso8601String();
    print('[LOG] \$now: \$message');
  }
}
