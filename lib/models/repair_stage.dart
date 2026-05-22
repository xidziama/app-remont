import '../utils/firestore_field_reader.dart';

/// RepairStage — отдельная сущность этапа работ.
///
/// Почему этап вынесен в отдельную модель, а не хранится строкой в фото:
/// - этап можно переименовать один раз, и все фото автоматически покажут
///   новое название, потому что фото ссылаются на stageId;
/// - у этапа могут быть собственные цвет, иконка и порядок сортировки;
/// - фильтрация и группировка становятся стабильнее: stageId не меняется,
///   даже если название этапа отредактировали;
/// - такая структура проще масштабируется под аналитику, отчеты и права.
class RepairStage {
  const RepairStage({
    required this.id,
    required this.name,
    required this.color,
    required this.icon,
    required this.sortOrder,
    required this.createdAt,
  });

  /// ID документа этапа в Firestore.
  final String id;

  /// Название этапа, например "Электрика" или "Плитка".
  final String name;

  /// Цвет этапа как ARGB int.
  ///
  /// В модели не используем Flutter Color напрямую, чтобы модель оставалась
  /// простой структурой данных и легко сохранялась в Firestore.
  final int color;

  /// Имя иконки.
  ///
  /// Храним строку, потому что Firestore не умеет хранить IconData.
  /// UI потом преобразует это имя в конкретную Material icon.
  final String icon;

  /// Порядок сортировки этапов в списках и группировке фото.
  final int sortOrder;

  /// Дата создания этапа.
  final DateTime createdAt;

  /// Создает копию этапа с измененными полями.
  ///
  /// Это удобно для формы редактирования: меняем только name/color/icon,
  /// а id и createdAt остаются прежними.
  RepairStage copyWith({
    String? name,
    int? color,
    String? icon,
    int? sortOrder,
    DateTime? createdAt,
  }) {
    return RepairStage(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// Превращает модель в Map для Firestore.
  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'color': color,
      'icon': icon,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  /// Безопасно читает этап из Firestore.
  ///
  /// Если какие-то поля отсутствуют, используем fallback-значения, чтобы UI
  /// не падал из-за неполных данных в Emulator UI.
  factory RepairStage.fromMap(String id, Map<String, dynamic> map) {
    return RepairStage(
      id: id,
      name: FirestoreFieldReader.string(
        map,
        'name',
        fallback: 'Без названия',
      ),
      color: FirestoreFieldReader.intValue(
        map,
        'color',
        fallback: 0xFF64748B,
      ),
      icon: FirestoreFieldReader.string(
        map,
        'icon',
        fallback: 'construction',
      ),
      sortOrder: FirestoreFieldReader.intValue(map, 'sortOrder'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );
  }
}
