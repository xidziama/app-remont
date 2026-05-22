import '../utils/firestore_field_reader.dart';

/// Participant описывает участника конкретного объекта.
///
/// Участники хранятся в subcollection:
/// `objects/{projectId}/participants/{participantId}`.
class Participant {
  const Participant({
    required this.id,
    required this.name,
    required this.phoneNumber,
    required this.role,
  });

  /// ID документа участника в Firestore.
  final String id;

  /// Имя из телефонной книги или номер владельца.
  final String name;

  /// Номер телефона, по которому исполнитель сможет увидеть объект.
  final String phoneNumber;

  /// Роль: owner или executor.
  final String role;

  /// Превращает модель в Map для Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phoneNumber': phoneNumber,
      'role': role,
    };
  }

  /// Собирает модель из данных Firestore.
  factory Participant.fromMap(String id, Map<String, dynamic> map) {
    // Читаем поля защитно: участник, созданный вручную в Emulator UI, может
    // не иметь name/phoneNumber/role, и экран не должен падать из-за этого.
    return Participant(
      id: id,
      name: FirestoreFieldReader.string(
        map,
        'name',
        fallback: 'Исполнитель',
      ),
      phoneNumber: FirestoreFieldReader.string(map, 'phoneNumber'),
      role: FirestoreFieldReader.string(map, 'role', fallback: 'executor'),
    );
  }
}
