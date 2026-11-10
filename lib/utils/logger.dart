class Logger {
  Logger._();

  static const _blue = '\x1B[38;5;33m';
  static const _yellow = '\x1B[38;5;220m';
  static const _green = '\x1B[38;5;46m';
  static const _red = '\x1B[38;5;196m';
  static const _reset = '\x1B[0m';

  static void log(String screenName, Object? message) => _write(screenName, message, _blue);

  static void success(String screenName, Object? message) => _write(screenName, message, _green);

  static void warn(String screenName, Object? message) => _write(screenName, message, _yellow);

  static void error(String screenName, Object? message, {StackTrace? stackTrace}) {
    final fullMessage = stackTrace == null ? message : '$message\n$stackTrace';
    _write(screenName, fullMessage, _red);
  }

  static void _write(String screenName, Object? message, String color) {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final period = now.hour < 12 ? 'AM' : 'PM';
    final timestamp =
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.year} ${hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')} $period';

    // ignore: avoid_print
    print('$color$timestamp: $screenName:$_reset   $message');
  }
}
