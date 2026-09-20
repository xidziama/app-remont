import '../utils/firestore_field_reader.dart';

/// Тип внутреннего уведомления.
///
/// Значения намеренно похожи на TimelineEventType. Так проще позже подключить
/// FCM: Cloud Function сможет читать timeline event, выбирать такой же тип
/// уведомления и отправлять push без переписывания UI.
enum AppNotificationType {
  joinRequestCreated('join_request_created'),
  projectSentToDirectorReview('project_sent_to_director_review'),
  projectSentToClientReview('project_sent_to_client_review'),
  projectClosed('project_closed'),
  invitationAccepted('invitation_accepted'),
  stageSentToReview('stage_sent_to_review'),
  stageApproved('stage_approved'),
  stageReturned('stage_returned'),
  workerAssignedToStage('worker_assigned_to_stage'),
  receiptUploaded('receipt_uploaded');

  const AppNotificationType(this.firestoreValue);

  final String firestoreValue;

  static AppNotificationType fromFirestore(String value) {
    return AppNotificationType.values.firstWhere(
      (type) => type.firestoreValue == value,
      orElse: () => AppNotificationType.stageSentToReview,
    );
  }
}

/// Уведомление конкретного пользователя внутри приложения.
///
/// Документы хранятся по пути:
/// users/{uid}/notifications/{notificationId}
///
/// Такая структура дает быстрый badge и быстрый список уведомлений без тяжелых
/// collectionGroup-запросов по всем проектам. Timeline остается историей
/// проекта, а Notification является персональной "доставкой" события
/// конкретному пользователю.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.userId,
    required this.type,
    required this.title,
    required this.message,
    required this.isRead,
    required this.createdAt,
    this.projectId,
    this.projectTitle,
    this.stageId,
    this.stageTitle,
    this.companyId,
    this.sourceEventId,
  });

  final String id;
  final String userId;
  final AppNotificationType type;
  final String title;
  final String message;
  final bool isRead;
  final DateTime createdAt;
  final String? projectId;
  final String? projectTitle;
  final String? stageId;
  final String? stageTitle;
  final String? companyId;
  final String? sourceEventId;

  bool get hasProject => projectId != null && projectId!.isNotEmpty;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'type': type.firestoreValue,
      'title': title,
      'message': message,
      'isRead': isRead,
      'createdAt': createdAt,
      'projectId': projectId,
      'projectTitle': projectTitle,
      'stageId': stageId,
      'stageTitle': stageTitle,
      'companyId': companyId,
      'sourceEventId': sourceEventId,
    };
  }

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: FirestoreFieldReader.string(map, 'userId'),
      type: AppNotificationType.fromFirestore(
        FirestoreFieldReader.string(map, 'type'),
      ),
      title: FirestoreFieldReader.string(map, 'title'),
      message: FirestoreFieldReader.string(map, 'message'),
      isRead: FirestoreFieldReader.boolValue(map, 'isRead'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      projectId: FirestoreFieldReader.nullableString(map, 'projectId'),
      projectTitle: FirestoreFieldReader.nullableString(map, 'projectTitle'),
      stageId: FirestoreFieldReader.nullableString(map, 'stageId'),
      stageTitle: FirestoreFieldReader.nullableString(map, 'stageTitle'),
      companyId: FirestoreFieldReader.nullableString(map, 'companyId'),
      sourceEventId: FirestoreFieldReader.nullableString(map, 'sourceEventId'),
    );
  }

  AppNotification copyWith({
    bool? isRead,
  }) {
    return AppNotification(
      id: id,
      userId: userId,
      type: type,
      title: title,
      message: message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt,
      projectId: projectId,
      projectTitle: projectTitle,
      stageId: stageId,
      stageTitle: stageTitle,
      companyId: companyId,
      sourceEventId: sourceEventId,
    );
  }
}
