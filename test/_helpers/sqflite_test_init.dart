import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _initialized = false;

/// 跨平台测试用 SQLite 初始化。复用 `sqlite3` 包内置的二进制库，
/// 在 Windows / macOS / Linux 上都能直接跑 `flutter test`。
///
/// 使用 `databaseFactoryFfiNoIsolate` 是因为很多测试通过
/// [DatabaseHelper.injectDatabase] 在测试线程内共享一个 Database 实例，
/// 跨 Isolate 的工厂会让这种共享失效。
DatabaseFactory ensureSqfliteTestFactory() {
  if (!_initialized) {
    sqfliteFfiInit();
    _initialized = true;
  }
  databaseFactory = databaseFactoryFfiNoIsolate;
  return databaseFactoryFfiNoIsolate;
}
