import '../utils/firestore_field_reader.dart';

/// Internal role of a user inside a company.
///
/// The app stores technical values in Firestore, but UI must show the readable
/// Russian labels from [label].
enum CompanyRole {
  owner('owner'),
  manager('manager'),
  worker('worker'),
  client('client'),
  user('user');

  const CompanyRole(this.firestoreValue);

  final String firestoreValue;

  String get label {
    switch (this) {
      case CompanyRole.owner:
        return 'Директор';
      case CompanyRole.manager:
        return 'Прораб';
      case CompanyRole.worker:
        return 'Подрядчик';
      case CompanyRole.client:
        return 'Заказчик';
      case CompanyRole.user:
        return 'Без доступа';
    }
  }

  bool get isOwner => this == CompanyRole.owner;
  bool get isManager => this == CompanyRole.manager;
  bool get isWorker => this == CompanyRole.worker;
  bool get isClient => this == CompanyRole.client;

  static CompanyRole fromFirestore(String value) {
    return CompanyRole.values.firstWhere(
      (role) => role.firestoreValue == value,
      orElse: () => CompanyRole.user,
    );
  }
}

enum CompanyStatus {
  active('active'),
  deleted('deleted');

  const CompanyStatus(this.firestoreValue);

  final String firestoreValue;

  static CompanyStatus fromFirestore(String value) {
    return CompanyStatus.values.firstWhere(
      (status) => status.firestoreValue == value,
      orElse: () => CompanyStatus.active,
    );
  }
}

enum InvitationStatus {
  pending('pending'),
  accepted('accepted'),
  declined('declined'),
  expired('expired'),
  revoked('revoked');

  const InvitationStatus(this.firestoreValue);

  final String firestoreValue;

  static InvitationStatus fromFirestore(String value) {
    return InvitationStatus.values.firstWhere(
      (status) => status.firestoreValue == value,
      orElse: () => InvitationStatus.pending,
    );
  }
}

enum JoinRequestStatus {
  pending('pending'),
  approved('approved'),
  declined('declined');

  const JoinRequestStatus(this.firestoreValue);

  final String firestoreValue;

  static JoinRequestStatus fromFirestore(String value) {
    return JoinRequestStatus.values.firstWhere(
      (status) => status.firestoreValue == value,
      orElse: () => JoinRequestStatus.pending,
    );
  }
}

class Company {
  const Company({
    required this.id,
    required this.name,
    required this.code,
    required this.ownerId,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String code;
  final String ownerId;
  final CompanyStatus status;
  final DateTime createdAt;

  bool get isActive => status == CompanyStatus.active;

  /// Public company join code used by the onboarding screen.
  ///
  /// Older MVP builds stored this value as `code`. Newer code also writes the
  /// clearer `companyCode` field to Firestore, but the Dart model keeps one
  /// source of truth so old and new documents behave the same in UI.
  String get companyCode => code;

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'code': code,
      'companyCode': code,
      'ownerId': ownerId,
      'status': status.firestoreValue,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory Company.fromMap(String id, Map<String, dynamic> map) {
    final companyCode = FirestoreFieldReader.string(
      map,
      'companyCode',
      fallback: FirestoreFieldReader.string(map, 'code'),
    );

    return Company(
      id: id,
      name: FirestoreFieldReader.string(map, 'name'),
      code: companyCode,
      ownerId: FirestoreFieldReader.string(map, 'ownerId'),
      status: CompanyStatus.fromFirestore(
        FirestoreFieldReader.string(map, 'status', fallback: 'active'),
      ),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );
  }
}

/// User membership in a company.
///
/// Stored at `companies/{companyId}/members/{uid}`. The document duplicates
/// company name and role labels intentionally: it lets the app decide routing
/// without an additional Firestore read during startup.
class CompanyMember {
  const CompanyMember({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.uid,
    required this.email,
    required this.displayName,
    required this.role,
    required this.canCreateProjects,
    required this.assignedProjectIds,
    required this.active,
    required this.createdAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String uid;
  final String email;
  final String displayName;
  final CompanyRole role;
  final bool canCreateProjects;
  final List<String> assignedProjectIds;
  final bool active;
  final DateTime createdAt;

  bool get canCreateProject {
    return role.isOwner || (role.isManager && canCreateProjects);
  }

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'companyName': companyName,
      'uid': uid,
      'email': email,
      'displayName': displayName,
      'role': role.firestoreValue,
      'canCreateProjects': canCreateProjects,
      'assignedProjectIds': assignedProjectIds,
      'active': active,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CompanyMember.fromMap(String id, Map<String, dynamic> map) {
    return CompanyMember(
      id: id,
      companyId: FirestoreFieldReader.string(map, 'companyId'),
      companyName: FirestoreFieldReader.string(map, 'companyName'),
      uid: FirestoreFieldReader.string(map, 'uid', fallback: id),
      email: FirestoreFieldReader.string(map, 'email'),
      displayName: FirestoreFieldReader.string(
        map,
        'displayName',
        fallback: FirestoreFieldReader.string(map, 'email'),
      ),
      role: CompanyRole.fromFirestore(
        FirestoreFieldReader.string(map, 'role', fallback: 'user'),
      ),
      canCreateProjects: FirestoreFieldReader.boolValue(
        map,
        'canCreateProjects',
      ),
      assignedProjectIds:
          FirestoreFieldReader.stringList(map, 'assignedProjectIds'),
      active: FirestoreFieldReader.boolValue(map, 'active', fallback: true),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
    );
  }
}

class CompanyInvitation {
  const CompanyInvitation({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.email,
    required this.role,
    required this.status,
    required this.createdAt,
    this.projectId,
    this.projectTitle,
    this.stageIds = const [],
    this.stageTitles = const [],
    this.createdBy,
    this.acceptedAt,
    this.declinedAt,
    this.revokedAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String email;
  final CompanyRole role;
  final InvitationStatus status;
  final DateTime createdAt;
  final String? projectId;
  final String? projectTitle;
  final List<String> stageIds;
  final List<String> stageTitles;
  final String? createdBy;
  final DateTime? acceptedAt;
  final DateTime? declinedAt;
  final DateTime? revokedAt;

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'companyName': companyName,
      'email': email.toLowerCase(),
      'role': role.firestoreValue,
      'status': status.firestoreValue,
      'createdAt': createdAt.toIso8601String(),
      'projectId': projectId,
      'projectTitle': projectTitle,
      'stageIds': stageIds,
      'stageTitles': stageTitles,
      'createdBy': createdBy,
      'acceptedAt': acceptedAt?.toIso8601String(),
      'declinedAt': declinedAt?.toIso8601String(),
      'revokedAt': revokedAt?.toIso8601String(),
    };
  }

  factory CompanyInvitation.fromMap(String id, Map<String, dynamic> map) {
    return CompanyInvitation(
      id: id,
      companyId: FirestoreFieldReader.string(map, 'companyId'),
      companyName: FirestoreFieldReader.string(map, 'companyName'),
      email: FirestoreFieldReader.string(map, 'email'),
      role: CompanyRole.fromFirestore(
        FirestoreFieldReader.string(map, 'role', fallback: 'user'),
      ),
      status: InvitationStatus.fromFirestore(
        FirestoreFieldReader.string(map, 'status', fallback: 'pending'),
      ),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      projectId: FirestoreFieldReader.nullableString(map, 'projectId'),
      projectTitle: FirestoreFieldReader.nullableString(map, 'projectTitle'),
      stageIds: FirestoreFieldReader.stringList(map, 'stageIds'),
      stageTitles: FirestoreFieldReader.stringList(map, 'stageTitles'),
      createdBy: FirestoreFieldReader.nullableString(map, 'createdBy'),
      acceptedAt: FirestoreFieldReader.nullableDateTime(map, 'acceptedAt'),
      declinedAt: FirestoreFieldReader.nullableDateTime(map, 'declinedAt'),
      revokedAt: FirestoreFieldReader.nullableDateTime(map, 'revokedAt'),
    );
  }
}

class CompanyJoinRequest {
  const CompanyJoinRequest({
    required this.id,
    required this.companyId,
    required this.companyName,
    required this.uid,
    required this.email,
    required this.displayName,
    required this.status,
    required this.createdAt,
    this.approvedAt,
    this.declinedAt,
  });

  final String id;
  final String companyId;
  final String companyName;
  final String uid;
  final String email;
  final String displayName;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? declinedAt;

  Map<String, dynamic> toMap() {
    return {
      'companyId': companyId,
      'companyName': companyName,
      'uid': uid,
      'userId': uid,
      'email': email.toLowerCase(),
      'userEmail': email.toLowerCase(),
      'displayName': displayName,
      'userName': displayName,
      'status': status.firestoreValue,
      'createdAt': createdAt.toIso8601String(),
      'approvedAt': approvedAt?.toIso8601String(),
      'declinedAt': declinedAt?.toIso8601String(),
    };
  }

  factory CompanyJoinRequest.fromMap(String id, Map<String, dynamic> map) {
    return CompanyJoinRequest(
      id: id,
      companyId: FirestoreFieldReader.string(map, 'companyId'),
      companyName: FirestoreFieldReader.string(map, 'companyName'),
      uid: FirestoreFieldReader.string(
        map,
        'uid',
        fallback: FirestoreFieldReader.string(map, 'userId'),
      ),
      email: FirestoreFieldReader.string(
        map,
        'email',
        fallback: FirestoreFieldReader.string(map, 'userEmail'),
      ),
      displayName: FirestoreFieldReader.string(
        map,
        'displayName',
        fallback: FirestoreFieldReader.string(map, 'userName'),
      ),
      status: JoinRequestStatus.fromFirestore(
        FirestoreFieldReader.string(map, 'status', fallback: 'pending'),
      ),
      createdAt: FirestoreFieldReader.dateTime(map, 'createdAt'),
      approvedAt: FirestoreFieldReader.nullableDateTime(map, 'approvedAt'),
      declinedAt: FirestoreFieldReader.nullableDateTime(map, 'declinedAt'),
    );
  }
}
