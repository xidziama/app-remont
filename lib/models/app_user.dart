import '../utils/firestore_field_reader.dart';

/// AppUser — модель профиля пользователя внутри Firestore.
///
/// Firebase Auth хранит учетную запись, а Firestore-профиль пригодится для
/// имени, роли, аватара и других данных приложения. В MVP используется частично.
class AppUser {
  const AppUser({
    required this.id,
    required this.phoneNumber,
    this.displayName,
    this.createdAt,
  });

  /// UID из Firebase Auth.
  final String id;

  /// Телефон пользователя.
  final String phoneNumber;

  /// Отображаемое имя, если пользователь заполнит профиль.
  final String? displayName;

  /// Дата создания профиля.
  final DateTime? createdAt;

  /// Превращает профиль в Map для Firestore.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  /// Создает профиль из Firestore data.
  factory AppUser.fromMap(Map<String, dynamic> map) {
    // UID обязателен логически, но в dev-данных поле может отсутствовать.
    // Вместо падения возвращаем пустую строку и позволяем UI решить, что делать.
    return AppUser(
      id: FirestoreFieldReader.string(map, 'id'),
      phoneNumber: FirestoreFieldReader.string(map, 'phoneNumber'),
      displayName: FirestoreFieldReader.nullableString(map, 'displayName'),
      createdAt: FirestoreFieldReader.nullableDateTime(map, 'createdAt'),
    );
  }
}
