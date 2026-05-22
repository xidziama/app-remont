/// AppConfig хранит настройки приложения, которые нужны в разных местах.
///
/// Сейчас здесь лежат адреса Firebase Emulator Suite.
/// Когда проект пойдет в production, этот файл удобно расширить флагами
/// окружений: dev, stage, prod.
class AppConfig {
  /// ID локального Firebase project для эмуляторов.
  static const firebaseProjectId = 'remont-local';

  /// На Android emulator адрес `localhost` указывает на сам эмулятор Android,
  /// а не на компьютер разработчика.
  ///
  /// Чтобы Android-приложение достучалось до компьютера разработчика,
  /// используется специальный адрес `10.0.2.2`.
  static const androidEmulatorHost = '10.0.2.2';

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

  /// Storage emulator хранит изображения чеков и фотографии объектов.
  static const storagePort = 9199;
}
