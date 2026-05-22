import '../utils/firestore_field_reader.dart';

/// Возможные статусы ремонтного объекта.
///
/// Enum удобнее строки: меньше опечаток и проще показывать варианты в Dropdown.
enum ProjectStatus {
  planned,
  active,
  paused,
  completed;

  /// Человекочитаемое название статуса для интерфейса.
  String get label {
    switch (this) {
      case ProjectStatus.planned:
        return 'Планируется';
      case ProjectStatus.active:
        return 'В работе';
      case ProjectStatus.paused:
        return 'Пауза';
      case ProjectStatus.completed:
        return 'Завершен';
    }
  }
}

/// Project описывает основной документ в коллекции Firestore `objects`.
///
/// Модель нужна, чтобы приложение работало с понятными Dart-полями, а не с
/// сырым `Map<String, dynamic>` из Firestore на каждом экране.
class Project {
  const Project({
    required this.id,
    required this.title,
    required this.address,
    required this.description,
    required this.status,
    required this.ownerId,
    required this.participantIds,
    required this.participantPhones,
    required this.createdAt,
  });

  /// Firestore document id.
  final String id;

  /// Название объекта, например "Квартира на Светланской".
  final String title;

  /// Адрес объекта.
  final String address;

  /// Свободное описание работ.
  final String description;

  /// Текущий статус ремонта.
  final ProjectStatus status;

  /// UID пользователя, который создал объект.
  final String ownerId;

  /// UID участников, которые уже известны Firebase Auth.
  final List<String> participantIds;

  /// Телефоны участников. Это позволяет приглашать исполнителей из контактов.
  final List<String> participantPhones;

  /// Дата создания нужна для сортировки списка объектов.
  final DateTime createdAt;

  /// Превращает модель в Map для записи в Firestore.
  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'address': address,
      'description': description,
      'status': status.name,
      'ownerId': ownerId,
      'participantIds': participantIds,
      'participantPhones': participantPhones,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Создает модель Project из Firestore document id и document data.
  factory Project.fromMap(String id, Map<String, dynamic> map) {
    // Все поля читаются через FirestoreFieldReader.
    // Так приложение не падает, если в emulator лежит старый документ без
    // participantIds/participantPhones или с null вместо списка.
    final statusName = FirestoreFieldReader.string(map, 'status');

    return Project(
      id: id,
      title: FirestoreFieldReader.string(map, 'title'),
      address: FirestoreFieldReader.string(map, 'address'),
      description: FirestoreFieldReader.string(map, 'description'),
      status: ProjectStatus.values.firstWhere(
        (status) => status.name == statusName,
        orElse: () => ProjectStatus.planned,
      ),
      ownerId: FirestoreFieldReader.string(map, 'ownerId'),
      participantIds: FirestoreFieldReader.stringList(map, 'participantIds'),
      participantPhones:
          FirestoreFieldReader.stringList(map, 'participantPhones'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );
  }
}
