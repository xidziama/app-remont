import 'package:cloud_firestore/cloud_firestore.dart';

/// FirestoreFieldReader — маленький набор безопасных функций чтения полей.
///
/// Зачем он нужен:
/// - Firestore хранит данные как `Map<String, dynamic>`.
/// - Старые документы, ручные записи из Emulator UI или ошибки миграций могут
///   оставить поле null, строкой вместо числа или вообще без нужного ключа.
/// - Небезопасный cast вроде `data['members'] as List` ломает приложение,
///   особенно во Flutter Web, где runtime type errors сразу падают в UI.
/// - Эти функции возвращают fallback-значения и позволяют экрану продолжить
///   работу даже с неполными dev-данными.
///
/// Это не заменяет валидацию данных на запись. Это защитный слой чтения,
/// чтобы приложение было стабильнее во время разработки и миграций.
class FirestoreFieldReader {
  /// Безопасно читает строку.
  ///
  /// Если Firestore вернул null или значение другого типа, возвращаем fallback.
  static String string(
    Map<String, dynamic> data,
    String key, {
    String fallback = '',
  }) {
    final value = data[key];

    if (value is String) {
      return value;
    }

    return fallback;
  }

  /// Безопасно читает необязательную строку.
  ///
  /// Используется для полей вроде комментария или URL, где null допустим.
  static String? nullableString(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is String && value.isNotEmpty) {
      return value;
    }

    return null;
  }

  /// Безопасно читает список строк.
  ///
  /// Это прямое исправление класса ошибок "Null value error for list" и
  /// runtime cast ошибок. Мы сначала проверяем `value is List`, и только потом
  /// аккуратно выбираем из него строковые элементы.
  static List<String> stringList(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value is! List) {
      return <String>[];
    }

    return value.whereType<String>().toList();
  }

  /// Безопасно читает boolean.
  ///
  /// Firestore обычно возвращает bool, но в dev-данных поле может отсутствовать
  /// или быть создано вручную как строка. В таком случае возвращаем fallback,
  /// чтобы один некорректный документ не ломал весь экран.
  static bool boolValue(
    Map<String, dynamic> data,
    String key, {
    bool fallback = false,
  }) {
    final value = data[key];

    if (value is bool) {
      return value;
    }

    return fallback;
  }

  /// Безопасно читает число как double.
  ///
  /// Firestore может вернуть int или double, оба типа реализуют num.
  static double doubleValue(
    Map<String, dynamic> data,
    String key, {
    double fallback = 0,
  }) {
    final value = data[key];

    if (value is num) {
      return value.toDouble();
    }

    return fallback;
  }

  /// Безопасно читает число как int.
  ///
  /// Firestore может вернуть int или double. Для цвета и порядка сортировки
  /// нам нужен int, поэтому любое num аккуратно приводим через toInt().
  static int intValue(
    Map<String, dynamic> data,
    String key, {
    int fallback = 0,
  }) {
    final value = data[key];

    if (value is num) {
      return value.toInt();
    }

    return fallback;
  }

  /// Безопасно читает дату.
  ///
  /// Сейчас приложение пишет дату как ISO-строку, но Firestore часто хранит
  /// даты как Timestamp. Поддерживаем оба варианта, чтобы будущая миграция на
  /// Timestamp не сломала старые экраны.
  static DateTime dateTime(
    Map<String, dynamic> data,
    String key, {
    DateTime? fallback,
  }) {
    final value = data[key];

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value) ?? fallback ?? DateTime.now();
    }

    return fallback ?? DateTime.now();
  }

  /// Безопасно читает необязательную дату.
  ///
  /// Отличается от dateTime тем, что возвращает null, если поля нет.
  /// Это удобно для профиля пользователя, где createdAt пока может не писаться.
  static DateTime? nullableDateTime(Map<String, dynamic> data, String key) {
    final value = data[key];

    if (value == null) {
      return null;
    }

    if (value is Timestamp) {
      return value.toDate();
    }

    if (value is DateTime) {
      return value;
    }

    if (value is String) {
      return DateTime.tryParse(value);
    }

    return null;
  }
}
