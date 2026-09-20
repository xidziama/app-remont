import '../utils/firestore_field_reader.dart';

/// Возможные статусы этапа работ.
///
/// В Dart используем удобные camelCase имена, а в Firestore сохраняем значения
/// в snake_case. Так база остается простой для чтения в Firebase Console,
/// backend jobs и будущих Cloud Functions.
enum StageStatus {
  notStarted('not_started'),
  inProgress('in_progress'),
  review('review'),
  completed('completed'),
  problem('problem');

  const StageStatus(this.firestoreValue);

  final String firestoreValue;

  String get label {
    switch (this) {
      case StageStatus.notStarted:
        return 'Не начато';
      case StageStatus.inProgress:
        return 'В работе';
      case StageStatus.review:
        return 'На проверке';
      case StageStatus.completed:
        return 'Завершено';
      case StageStatus.problem:
        return 'Проблема';
    }
  }

  static StageStatus fromFirestore(String value) {
    return StageStatus.values.firstWhere(
      (status) => status.firestoreValue == value,
      orElse: () => StageStatus.notStarted,
    );
  }
}

/// Тип этапа работ.
///
/// Тип не является пользовательским названием. Он нужен для аналитики, иконок,
/// шаблонов, правил доступа и будущих автоматических уведомлений.
enum StageType {
  demolition('demolition'),
  electricity('electricity'),
  plumbing('plumbing'),
  plaster('plaster'),
  putty('putty'),
  painting('painting'),
  floors('floors'),
  tile('tile'),
  ceiling('ceiling'),
  finalCleaning('final_cleaning'),
  custom('custom');

  const StageType(this.firestoreValue);

  final String firestoreValue;

  String get label {
    switch (this) {
      case StageType.demolition:
        return 'Демонтаж';
      case StageType.electricity:
        return 'Электрика';
      case StageType.plumbing:
        return 'Сантехника';
      case StageType.plaster:
        return 'Штукатурка';
      case StageType.putty:
        return 'Шпаклевка';
      case StageType.painting:
        return 'Покраска';
      case StageType.floors:
        return 'Полы';
      case StageType.tile:
        return 'Плитка';
      case StageType.ceiling:
        return 'Натяжной потолок';
      case StageType.finalCleaning:
        return 'Финальная уборка';
      case StageType.custom:
        return 'Свой этап';
    }
  }

  static StageType fromFirestore(String value) {
    return StageType.values.firstWhere(
      (type) => type.firestoreValue == value,
      orElse: () => StageType.custom,
    );
  }
}

/// Production-модель этапа работ.
///
/// Документ хранится по пути:
/// projects/{projectId}/stages/{stageId}
///
/// Этап содержит summary metadata: счетчики фото/чеков, сумму чеков и обложку.
/// Благодаря этому список этапов не загружает все фотографии и чеки, а читает
/// только легкий документ этапа.
class Stage {
  const Stage({
    required this.id,
    required this.projectId,
    required this.title,
    required this.type,
    required this.status,
    required this.progress,
    required this.assignedUserIds,
    this.assignedUserNames = const [],
    required this.showExecutorsToClient,
    required this.photosCount,
    required this.receiptsCount,
    required this.receiptsTotal,
    required this.coverPhotoUrl,
    required this.completedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    required this.orderIndex,
  });

  final String id;
  final String projectId;
  final String title;
  final StageType type;
  final StageStatus status;
  final int progress;
  final List<String> assignedUserIds;
  final List<String> assignedUserNames;
  final bool showExecutorsToClient;
  final int photosCount;
  final int receiptsCount;
  final double receiptsTotal;
  final String? coverPhotoUrl;
  final DateTime? completedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String createdBy;
  final int orderIndex;

  bool get isCompleted => status == StageStatus.completed;

  Stage copyWith({
    String? id,
    String? projectId,
    String? title,
    StageType? type,
    StageStatus? status,
    int? progress,
    List<String>? assignedUserIds,
    List<String>? assignedUserNames,
    bool? showExecutorsToClient,
    int? photosCount,
    int? receiptsCount,
    double? receiptsTotal,
    String? coverPhotoUrl,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? createdBy,
    int? orderIndex,
  }) {
    return Stage(
      id: id ?? this.id,
      projectId: projectId ?? this.projectId,
      title: title ?? this.title,
      type: type ?? this.type,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      assignedUserIds: assignedUserIds ?? this.assignedUserIds,
      assignedUserNames: assignedUserNames ?? this.assignedUserNames,
      showExecutorsToClient:
          showExecutorsToClient ?? this.showExecutorsToClient,
      photosCount: photosCount ?? this.photosCount,
      receiptsCount: receiptsCount ?? this.receiptsCount,
      receiptsTotal: receiptsTotal ?? this.receiptsTotal,
      coverPhotoUrl: coverPhotoUrl ?? this.coverPhotoUrl,
      completedAt: clearCompletedAt ? null : completedAt ?? this.completedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      createdBy: createdBy ?? this.createdBy,
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'title': title,
      'type': type.firestoreValue,
      'status': status.firestoreValue,
      'progress': progress.clamp(0, 100),
      'assignedUserIds': assignedUserIds,
      'assignedUserNames': assignedUserNames,
      'showExecutorsToClient': showExecutorsToClient,
      'photosCount': photosCount,
      'receiptsCount': receiptsCount,
      'receiptsTotal': receiptsTotal,
      'coverPhotoUrl': coverPhotoUrl,
      'completedAt': completedAt,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
      'createdBy': createdBy,
      'orderIndex': orderIndex,

      // Legacy-compatible поля позволяют старому разделу "Фото" читать новые
      // этапы через модель RepairStage, пока проект постепенно мигрирует.
      'name': title,
      'sortOrder': orderIndex,
    };
  }

  factory Stage.fromMap(String id, Map<String, dynamic> map) {
    final type = StageType.fromFirestore(
      FirestoreFieldReader.string(map, 'type', fallback: 'custom'),
    );

    return Stage(
      id: id,
      projectId: FirestoreFieldReader.string(map, 'projectId'),
      title: FirestoreFieldReader.string(
        map,
        'title',
        fallback: FirestoreFieldReader.string(
          map,
          'name',
          fallback: type.label,
        ),
      ),
      type: type,
      status: StageStatus.fromFirestore(
        FirestoreFieldReader.string(map, 'status', fallback: 'not_started'),
      ),
      progress:
          FirestoreFieldReader.intValue(map, 'progress').clamp(0, 100).toInt(),
      assignedUserIds: FirestoreFieldReader.stringList(map, 'assignedUserIds'),
      assignedUserNames:
          FirestoreFieldReader.stringList(map, 'assignedUserNames'),
      showExecutorsToClient:
          FirestoreFieldReader.boolValue(map, 'showExecutorsToClient'),
      photosCount: FirestoreFieldReader.intValue(map, 'photosCount'),
      receiptsCount: FirestoreFieldReader.intValue(map, 'receiptsCount'),
      receiptsTotal: FirestoreFieldReader.doubleValue(map, 'receiptsTotal'),
      coverPhotoUrl: FirestoreFieldReader.nullableString(map, 'coverPhotoUrl'),
      completedAt: FirestoreFieldReader.nullableDateTime(map, 'completedAt'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      updatedAt: FirestoreFieldReader.dateTime(map, 'updatedAt'),
      createdBy: FirestoreFieldReader.string(map, 'createdBy'),
      orderIndex: FirestoreFieldReader.intValue(
        map,
        'orderIndex',
        fallback: FirestoreFieldReader.intValue(map, 'sortOrder'),
      ),
    );
  }
}
