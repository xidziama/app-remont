import '../utils/firestore_field_reader.dart';

/// Тип события в timeline проекта.
///
/// Timeline — это event-driven слой. Сейчас он нужен для истории, а позже эти
/// же события можно слушать Cloud Functions и отправлять push notifications.
enum TimelineEventType {
  stageStarted('stage_started'),
  stageSentToReview('stage_sent_to_review'),
  stageCompleted('stage_completed'),
  stageRejected('stage_rejected'),
  stageDeleted('stage_deleted'),
  photoUploaded('photo_uploaded'),
  receiptUploaded('receipt_uploaded'),
  receiptPaid('receipt_paid'),
  workerAssigned('worker_assigned'),
  workerRemoved('worker_removed'),
  invitationCreated('invitation_created'),
  invitationAccepted('invitation_accepted'),
  invitationDeclined('invitation_declined'),
  joinRequestCreated('join_request_created'),
  joinRequestApproved('join_request_approved'),
  joinRequestDeclined('join_request_declined'),
  projectSentToDirectorReview('project_sent_to_director_review'),
  projectSentToClientReview('project_sent_to_client_review'),
  projectClosed('project_closed'),
  participantAdded('participant_added'),
  participantRemoved('participant_removed'),
  workerAssignedToStage('worker_assigned_to_stage'),
  workerRemovedFromStage('worker_removed_from_stage');

  const TimelineEventType(this.firestoreValue);

  final String firestoreValue;

  static TimelineEventType fromFirestore(String value) {
    return TimelineEventType.values.firstWhere(
      (type) => type.firestoreValue == value,
      orElse: () => TimelineEventType.photoUploaded,
    );
  }
}

/// Событие timeline проекта.
///
/// Документ хранится по пути:
/// projects/{projectId}/timeline/{eventId}
class TimelineEvent {
  const TimelineEvent({
    required this.id,
    required this.type,
    required this.projectId,
    required this.stageId,
    required this.createdAt,
    required this.createdBy,
    required this.actorName,
    required this.stageTitle,
    required this.metadata,
  });

  final String id;
  final TimelineEventType type;
  final String projectId;
  final String stageId;
  final DateTime createdAt;
  final String createdBy;
  final String actorName;
  final String stageTitle;
  final Map<String, dynamic> metadata;

  Map<String, dynamic> toMap() {
    return {
      'type': type.firestoreValue,
      'projectId': projectId,
      'stageId': stageId,
      'createdAt': createdAt,
      'createdBy': createdBy,
      'actorName': actorName,
      'stageTitle': stageTitle,
      'metadata': metadata,
    };
  }

  factory TimelineEvent.fromMap(String id, Map<String, dynamic> map) {
    final rawMetadata = map['metadata'];
    final metadata = rawMetadata is Map
        ? rawMetadata.map((key, value) => MapEntry(key.toString(), value))
        : <String, dynamic>{};

    return TimelineEvent(
      id: id,
      type: TimelineEventType.fromFirestore(
        FirestoreFieldReader.string(map, 'type'),
      ),
      projectId: FirestoreFieldReader.string(map, 'projectId'),
      stageId: FirestoreFieldReader.string(map, 'stageId'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      createdBy: FirestoreFieldReader.string(map, 'createdBy'),
      actorName: FirestoreFieldReader.string(map, 'actorName'),
      stageTitle: FirestoreFieldReader.string(map, 'stageTitle'),
      metadata: metadata,
    );
  }
}
