import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../core/app_config.dart';

/// FirebaseBootstrap отвечает только за техническую настройку Firebase.
///
/// Важно держать это отдельно от экранов: UI не должен знать, какие порты
/// у Firestore/Auth/Storage и чем Android emulator отличается от iOS simulator.
class FirebaseBootstrap {
  static bool _connected = false;

  static Future<void> connectToEmulators() async {
    // Не подключаемся повторно, если метод уже вызывался.
    // Firebase SDK не любит повторную настройку emulator endpoints в рамках
    // одного запуска приложения, поэтому защищаем метод флагом _connected.
    if (_connected || kReleaseMode) {
      return;
    }

    // Android emulator обращается к компьютеру разработчика через 10.0.2.2.
    //
    // Flutter Web, iOS simulator и desktop используют 127.0.0.1.
    // Это стабильнее, чем localhost, когда Firebase emulators запущены
    // в Docker и порты опубликованы на машину разработчика.
    //
    // Особенно важно для Flutter Web:
    // - браузер обращается к Firebase Auth emulator как к обычному HTTP API;
    // - localhost иногда резолвится не туда, куда опубликован Docker-порт;
    // - 127.0.0.1 явно ведет на IPv4 loopback хоста;
    // - это убирает частую ошибку firebase_auth/network-request-failed.
    final host = defaultTargetPlatform == TargetPlatform.android
        ? AppConfig.androidEmulatorHost
        : AppConfig.loopbackHost;

    // Подключаем Firebase Auth SDK к Auth emulator.
    //
    // Dev Login использует signInAnonymously(), но запрос все равно идет через
    // Firebase Auth. Поэтому без корректного Auth emulator endpoint кнопка
    // временного входа может падать с network-request-failed.
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authPort);

    // Подключаем Cloud Firestore SDK к Firestore emulator.
    //
    // Все объекты ремонта, участники, чат и расходы в dev-режиме сохраняются
    // в локальный emulator, а не в production Firebase project.
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppConfig.firestorePort,
    );

    // Подключаем Firebase Storage SDK к Storage emulator.
    //
    // Фото чеков и фотографии объектов в dev-режиме будут грузиться локально,
    // что безопаснее и дешевле на этапе разработки.
    FirebaseStorage.instance.useStorageEmulator(host, AppConfig.storagePort);

    // Помечаем, что SDK уже переключены на эмуляторы.
    _connected = true;
  }
}
