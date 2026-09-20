import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';

/// FirebaseBootstrap отвечает только за техническую настройку Firebase SDK.
///
/// Важно держать это отдельно от экранов:
/// - UI не должен знать порты Auth/Firestore emulator;
/// - UI не должен решать, какой host нужен Android, Web или desktop;
/// - вся настройка локальной инфраструктуры живет в одном понятном месте.
///
/// Storage здесь больше не настраивается: фото хранятся в Yandex Object
/// Storage (см. storage_service.dart), которое не зависит от Firebase
/// Emulator Suite и одинаково работает в dev и prod режимах.
class FirebaseBootstrap {
  static bool _connected = false;
  static bool _authEmulatorEnabled = false;
  static bool _firestoreEmulatorEnabled = false;

  static bool get authEmulatorEnabled => _authEmulatorEnabled;
  static bool get firestoreEmulatorEnabled => _firestoreEmulatorEnabled;

  static bool get emulatorStateIsConsistent {
    final enabledCount = [
      _authEmulatorEnabled,
      _firestoreEmulatorEnabled,
    ].where((enabled) => enabled).length;

    return enabledCount == 0 || enabledCount == 2;
  }

  /// Prints whether Firebase services use emulator endpoints.
  ///
  /// INVALID_REFRESH_TOKEN is often caused by switching between Auth Emulator
  /// and production Auth while a local session is still stored on the device.
  /// These logs make it obvious whether Auth and Firestore are both in the
  /// same environment.
  static void logEmulatorState(String source) {
    debugPrint(
      '[FirebaseBootstrap][$source] Auth emulator enabled = '
      '$_authEmulatorEnabled',
    );
    debugPrint(
      '[FirebaseBootstrap][$source] Firestore emulator enabled = '
      '$_firestoreEmulatorEnabled',
    );
    debugPrint(
      '[FirebaseBootstrap][$source] Emulator state consistent = '
      '$emulatorStateIsConsistent',
    );
  }

  /// Подключает Firebase SDK к локальным эмуляторам в debug/profile режиме.
  ///
  /// В release метод ничего не делает, чтобы production-сборка случайно не
  /// пошла в локальный emulator вместо настоящего Firebase проекта.
  static Future<void> connectToEmulators() async {
    // Firebase SDK не любит повторное подключение к emulator endpoints в рамках
    // одного запуска приложения. Флаг защищает от повторного вызова при hot
    // restart или повторной инициализации верхнего уровня.
    if (_connected) {
      debugPrint(
        '[FirebaseBootstrap] Firebase emulators are already connected.',
      );
      logEmulatorState('connectToEmulators already connected');
      return;
    }

    if (kReleaseMode) {
      debugPrint(
        '[FirebaseBootstrap] Release mode detected. Emulator connection is '
        'skipped so production builds use the real Firebase project.',
      );
      logEmulatorState('connectToEmulators release skipped');
      return;
    }

    // Android emulator обращается к компьютеру разработчика через 10.0.2.2.
    //
    // Flutter Web, iOS simulator и desktop используют 127.0.0.1.
    // Это стабильнее, чем localhost, когда Firebase emulators запущены в Docker:
    // 127.0.0.1 явно указывает на IPv4 loopback, а localhost иногда резолвится
    // иначе и может приводить к firebase_auth/network-request-failed.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? AppConfig.androidEmulatorHost
        : AppConfig.loopbackHost;

    debugPrint('[FirebaseBootstrap] CONNECTING TO FIREBASE EMULATORS');
    debugPrint(
      '[FirebaseBootstrap] Platform: $defaultTargetPlatform. '
      'This decides which emulator host is safe for the current runtime.',
    );
    debugPrint(
      '[FirebaseBootstrap] Auth emulator host=$host port=${AppConfig.authPort}',
    );
    debugPrint(
      '[FirebaseBootstrap] Firestore emulator host=$host '
      'port=${AppConfig.firestorePort}',
    );

    // Подключаем Firebase Auth SDK к Auth emulator.
    //
    // Email/Password Auth тоже должен идти через emulator в локальной разработке,
    // если флаг USE_FIREBASE_EMULATORS включен. Иначе приложение обратится к
    // настоящему Firebase Auth и создаст/проверит пользователя в production.
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authPort);
    _authEmulatorEnabled = true;
    debugPrint('[FirebaseBootstrap] Auth emulator connected.');

    // Подключаем Cloud Firestore SDK к Firestore emulator.
    //
    // Объекты ремонта, участники, чат, расходы, этапы и фото-метаданные в dev
    // режиме сохраняются локально, а не в production Firebase project.
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppConfig.firestorePort,
    );
    _firestoreEmulatorEnabled = true;
    debugPrint('[FirebaseBootstrap] Firestore emulator connected.');

    // Помечаем, что SDK уже переключены на эмуляторы.
    _connected = true;
    debugPrint(
      '[FirebaseBootstrap] Firebase emulators connected successfully.',
    );
    logEmulatorState('connectToEmulators completed');
  }
}
