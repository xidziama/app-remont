import '../utils/firestore_field_reader.dart';

/// Lifecycle status of a repair project.
///
/// `completed` from older MVP data is mapped to [ProjectStatus.closed] during
/// reading. New writes use the production lifecycle values below.
enum ProjectStatus {
  inProgress('in_progress'),
  paused('paused'),
  directorReview('director_review'),
  clientReview('client_review'),
  closed('closed');

  const ProjectStatus(this.firestoreValue);

  final String firestoreValue;

  String get label {
    switch (this) {
      case ProjectStatus.inProgress:
        return 'В работе';
      case ProjectStatus.paused:
        return 'Пауза';
      case ProjectStatus.directorReview:
        return 'На проверке директора';
      case ProjectStatus.clientReview:
        return 'На приёмке заказчика';
      case ProjectStatus.closed:
        return 'Закрыт';
    }
  }

  bool get canBeDeleted => this == ProjectStatus.closed;

  static ProjectStatus fromFirestore(String value) {
    switch (value) {
      case 'in_progress':
      case 'active':
      case 'planned':
        return ProjectStatus.inProgress;
      case 'paused':
        return ProjectStatus.paused;
      case 'director_review':
        return ProjectStatus.directorReview;
      case 'client_review':
        return ProjectStatus.clientReview;
      case 'closed':
      case 'completed':
        return ProjectStatus.closed;
      default:
        return ProjectStatus.inProgress;
    }
  }
}

/// Main Firestore document for a repair project.
///
/// Projects are stored in `projects/{projectId}` and connected to a company by
/// `companyId`. Access is intentionally represented by simple summary fields:
/// owner sees all company projects, managers are listed in `managerIds`, and
/// workers/clients can be included in `participantIds`.
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
    this.companyId,
    this.companyName,
    this.managerIds = const [],
    this.managerNames = const [],
    this.workerIds = const [],
    this.workerNames = const [],
    this.clientIds = const [],
    this.clientNames = const [],
    this.totalStages = 0,
    this.completedStages = 0,
    this.progressPercent = 0,
  });

  final String id;
  final String title;
  final String address;
  final String description;
  final ProjectStatus status;
  final String ownerId;
  final List<String> participantIds;
  final List<String> participantPhones;
  final DateTime createdAt;
  final String? companyId;
  final String? companyName;
  final List<String> managerIds;
  final List<String> managerNames;
  final List<String> workerIds;
  final List<String> workerNames;
  final List<String> clientIds;
  final List<String> clientNames;
  final int totalStages;
  final int completedStages;
  final int progressPercent;

  double get progressValue => progressPercent.clamp(0, 100).toDouble() / 100;

  String get managersLabel {
    if (managerNames.isEmpty) {
      return '';
    }

    return managerNames.length == 1
        ? 'Прораб: ${managerNames.first}'
        : 'Прорабы: ${managerNames.join(', ')}';
  }

  Project copyWith({
    String? id,
    String? title,
    String? address,
    String? description,
    ProjectStatus? status,
    String? ownerId,
    List<String>? participantIds,
    List<String>? participantPhones,
    DateTime? createdAt,
    String? companyId,
    String? companyName,
    List<String>? managerIds,
    List<String>? managerNames,
    List<String>? workerIds,
    List<String>? workerNames,
    List<String>? clientIds,
    List<String>? clientNames,
    int? totalStages,
    int? completedStages,
    int? progressPercent,
  }) {
    return Project(
      id: id ?? this.id,
      title: title ?? this.title,
      address: address ?? this.address,
      description: description ?? this.description,
      status: status ?? this.status,
      ownerId: ownerId ?? this.ownerId,
      participantIds: participantIds ?? this.participantIds,
      participantPhones: participantPhones ?? this.participantPhones,
      createdAt: createdAt ?? this.createdAt,
      companyId: companyId ?? this.companyId,
      companyName: companyName ?? this.companyName,
      managerIds: managerIds ?? this.managerIds,
      managerNames: managerNames ?? this.managerNames,
      workerIds: workerIds ?? this.workerIds,
      workerNames: workerNames ?? this.workerNames,
      clientIds: clientIds ?? this.clientIds,
      clientNames: clientNames ?? this.clientNames,
      totalStages: totalStages ?? this.totalStages,
      completedStages: completedStages ?? this.completedStages,
      progressPercent: progressPercent ?? this.progressPercent,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'address': address,
      'description': description,
      'status': status.firestoreValue,
      'ownerId': ownerId,
      'participantIds': participantIds,
      'participantPhones': participantPhones,
      'createdAt': createdAt.toIso8601String(),
      'companyId': companyId,
      'companyName': companyName,
      'managerIds': managerIds,
      'managerNames': managerNames,
      'workerIds': workerIds,
      'workerNames': workerNames,
      'clientIds': clientIds,
      'clientNames': clientNames,
      'totalStages': totalStages.clamp(0, 1000000),
      'completedStages': completedStages.clamp(0, 1000000),
      'progressPercent': progressPercent.clamp(0, 100),
    };
  }

  factory Project.fromMap(String id, Map<String, dynamic> map) {
    final totalStages = FirestoreFieldReader.intValue(map, 'totalStages');
    final completedStages = FirestoreFieldReader.intValue(
      map,
      'completedStages',
    );
    final progressPercent = FirestoreFieldReader.intValue(
      map,
      'progressPercent',
      fallback: _calculateProgressPercent(
        totalStages: totalStages,
        completedStages: completedStages,
      ),
    );

    return Project(
      id: id,
      title: FirestoreFieldReader.string(map, 'title'),
      address: FirestoreFieldReader.string(map, 'address'),
      description: FirestoreFieldReader.string(map, 'description'),
      status: ProjectStatus.fromFirestore(
        FirestoreFieldReader.string(map, 'status'),
      ),
      ownerId: FirestoreFieldReader.string(map, 'ownerId'),
      participantIds: FirestoreFieldReader.stringList(map, 'participantIds'),
      participantPhones:
          FirestoreFieldReader.stringList(map, 'participantPhones'),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      companyId: FirestoreFieldReader.nullableString(map, 'companyId'),
      companyName: FirestoreFieldReader.nullableString(map, 'companyName'),
      managerIds: FirestoreFieldReader.stringList(map, 'managerIds'),
      managerNames: FirestoreFieldReader.stringList(map, 'managerNames'),
      workerIds: FirestoreFieldReader.stringList(map, 'workerIds'),
      workerNames: FirestoreFieldReader.stringList(map, 'workerNames'),
      clientIds: FirestoreFieldReader.stringList(map, 'clientIds'),
      clientNames: FirestoreFieldReader.stringList(map, 'clientNames'),
      totalStages: totalStages,
      completedStages: completedStages,
      progressPercent: progressPercent.clamp(0, 100).toInt(),
    );
  }

  static int _calculateProgressPercent({
    required int totalStages,
    required int completedStages,
  }) {
    if (totalStages <= 0) {
      return 0;
    }

    return ((completedStages / totalStages) * 100)
        .round()
        .clamp(0, 100)
        .toInt();
  }
}
