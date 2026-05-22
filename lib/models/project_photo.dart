import '../utils/firestore_field_reader.dart';

/// ProjectPhoto описывает фотографию ремонтного объекта.
///
/// Новая структура фото:
/// - фото не хранит название этапа текстом;
/// - фото хранит stageId и ссылается на RepairStage;
/// - сама картинка лежит в Firebase Storage;
/// - Firestore хранит только ссылку imageUrl и метаданные.
class ProjectPhoto {
  const ProjectPhoto({
    required this.id,
    required this.objectId,
    required this.stageId,
    required this.imageUrl,
    required this.description,
    required this.uploadedBy,
    required this.uploadedAt,
  });

  /// ID документа фото в Firestore.
  final String id;

  /// ID ремонтного объекта.
  ///
  /// В Firestore объект хранится в коллекции `objects`,
  /// поэтому objectId равен project.id. Название поля оставлено objectId,
  /// потому что это бизнес-термин: фото принадлежит объекту ремонта.
  final String objectId;

  /// ID этапа работ, к которому относится фото.
  ///
  /// Это ссылка на документ:
  /// objects/{objectId}/stages/{stageId}
  final String stageId;

  /// Download URL картинки из Firebase Storage.
  final String imageUrl;

  /// Опциональное описание фото.
  final String description;

  /// UID или понятное имя пользователя, который загрузил фото.
  final String uploadedBy;

  /// Дата загрузки или выбранная пользователем дата фото.
  final DateTime uploadedAt;

  /// Превращает модель в Map для Firestore.
  Map<String, dynamic> toMap() {
    return {
      'objectId': objectId,
      'stageId': stageId,
      'imageUrl': imageUrl,
      'description': description,
      'uploadedBy': uploadedBy,
      'uploadedAt': uploadedAt.toIso8601String(),
    };
  }

  /// Создает ProjectPhoto из Firestore document.
  ///
  /// Defensive parsing здесь особенно важен:
  /// - старые dev-фото могли иметь поля url/caption/createdBy/createdAt;
  /// - новые фото имеют imageUrl/description/uploadedBy/uploadedAt;
  /// - если сделать unsafe cast, Flutter Web упадет на runtime type error.
  factory ProjectPhoto.fromMap(String id, Map<String, dynamic> map) {
    final imageUrl = FirestoreFieldReader.string(
      map,
      'imageUrl',
      fallback: FirestoreFieldReader.string(map, 'url'),
    );

    final description = FirestoreFieldReader.string(
      map,
      'description',
      fallback: FirestoreFieldReader.string(map, 'caption'),
    );

    final uploadedBy = FirestoreFieldReader.string(
      map,
      'uploadedBy',
      fallback: FirestoreFieldReader.string(map, 'createdBy'),
    );

    final uploadedAt = FirestoreFieldReader.dateTime(
      map,
      'uploadedAt',
      fallback: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );

    return ProjectPhoto(
      id: id,
      objectId: FirestoreFieldReader.string(map, 'objectId'),
      stageId: FirestoreFieldReader.string(map, 'stageId'),
      imageUrl: imageUrl,
      description: description,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt,
    );
  }
}
