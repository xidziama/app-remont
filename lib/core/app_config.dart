/// AppConfig хранит настройки приложения, которые нужны в разных местах.
///
/// Сейчас здесь лежат адреса Firebase Emulator Suite.
/// Когда проект пойдет в production, этот файл удобно расширить флагами
/// окружений: dev, stage, prod.
class AppConfig {
  /// Compile-time flag for local Firebase Emulator Suite.
  ///
  /// Default is false, because a real Android phone should normally talk to the
  /// real Firebase project from `google-services.json`.
  ///
  /// To use emulators intentionally, run:
  /// flutter run --dart-define=USE_FIREBASE_EMULATORS=true
  static const useFirebaseEmulators = bool.fromEnvironment(
    'USE_FIREBASE_EMULATORS',
    defaultValue: false,
  );

  /// На Android emulator адрес `localhost` указывает на сам эмулятор Android,
  /// а не на компьютер разработчика.
  ///
  /// Чтобы Android-приложение достучалось до компьютера разработчика,
  /// используется специальный адрес `10.0.2.2`.
  ///
  /// `10.0.2.2` is the special host address that the Android emulator uses to
  /// reach services running on the developer machine. This is safer than
  /// `localhost`, because `localhost` inside Android points back to Android
  /// itself, not to Docker on the computer.
  ///
  /// A physical Android phone is different: it cannot use `10.0.2.2` because it
  /// is not running inside the Android emulator. For a real device on the same
  /// Wi-Fi, pass the computer IP explicitly:
  ///
  /// flutter run --dart-define=USE_FIREBASE_EMULATORS=true \
  ///   --dart-define=FIREBASE_EMULATOR_HOST=192.168.0.100
  static const androidEmulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: '10.0.2.2',
  );

  /// Loopback-адрес компьютера разработчика для Flutter Web, iOS simulator
  /// и desktop.
  ///
  /// Почему именно `127.0.0.1`, а не `localhost`:
  /// - Flutter Web работает внутри браузера, а Firebase JS SDK делает обычные
  ///   HTTP-запросы к Auth/Firestore/Storage emulator.
  /// - Docker публикует порты эмуляторов на loopback-интерфейс хоста.
  /// - В некоторых окружениях `localhost` может резолвиться в IPv6 `::1`,
  ///   проксироваться браузером или иначе отличаться от ожидаемого IPv4.
  /// - `127.0.0.1` явно указывает браузеру идти на IPv4 loopback хоста,
  ///   поэтому Flutter Web + Docker обычно работает стабильнее.
  static const loopbackHost = '127.0.0.1';

  /// Порты должны совпадать с firebase.json и docker-compose.yml.
  ///
  /// Firestore emulator хранит документы объектов, участников, чата и расходов.
  static const firestorePort = 8080;

  /// Auth emulator принимает запросы Firebase Auth.
  static const authPort = 9099;

  // ---------------------------------------------------------------------
  // Yandex Object Storage (S3-совместимое хранилище фото).
  //
  // Firestore и Auth остаются на Firebase, но изображения (фото этапов,
  // чеки, фото в чате) хранятся в Yandex Object Storage. Подробности и
  // ограничения безопасности — в storage_service.dart.
  // ---------------------------------------------------------------------

  /// Имя бакета. Несекретный параметр, поэтому есть безопасный default.
  static const s3Bucket = String.fromEnvironment(
    'S3_BUCKET',
    defaultValue: 'app-remont-photos',
  );

  /// Endpoint Yandex Object Storage. Несекретный параметр.
  static const s3Endpoint = String.fromEnvironment(
    'S3_ENDPOINT',
    defaultValue: 'storage.yandexcloud.net',
  );

  /// Регион бакета. Несекретный параметр.
  static const s3Region = String.fromEnvironment(
    'S3_REGION',
    defaultValue: 'ru-central1',
  );

  /// Access Key ID. Секрет — default пустой, значение передается только через
  /// --dart-define и не должно попадать в git.
  static const s3AccessKey = String.fromEnvironment(
    'S3_ACCESS_KEY',
    defaultValue: '',
  );

  /// Secret Access Key. Секрет — default пустой, значение передается только
  /// через --dart-define и не должно попадать в git.
  static const s3SecretKey = String.fromEnvironment(
    'S3_SECRET_KEY',
    defaultValue: '',
  );
}
