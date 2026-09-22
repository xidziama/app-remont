import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';
import '../models/app_notification.dart';
import '../models/chat_message.dart';
import '../models/company.dart';
import '../models/expense.dart';
import '../models/participant.dart';
import '../models/photo.dart';
import '../models/project.dart';
import '../models/repair_stage.dart';
import '../models/stage.dart';
import '../models/timeline_event.dart';
import '../services/firebase_bootstrap.dart';
import '../services/storage_service.dart';
import '../utils/auth_debug.dart';
import '../utils/phone_utils.dart';

/// A small domain-level exception for the exact case where a Firestore write
/// should not even be attempted because Firebase Auth has no active user.
///
/// UI can catch this type and show a clean Russian message instead of exposing
/// a low-level Firebase/StateError string to the user.
class UserNotAuthenticatedException implements Exception {
  const UserNotAuthenticatedException();

  String get message => 'Пользователь не авторизован.';

  @override
  String toString() => message;
}

/// ProjectRepository — слой доступа к данным объектов ремонта.
///
/// Экраны не должны напрямую собирать пути Firestore вроде
/// `objects/{id}/messages`. Это быстро приводит к дублированию и ошибкам.
/// Репозиторий прячет структуру базы и дает экранам понятные методы:
/// createProject, watchProjects, sendMessage, addExpense и так далее.
class ProjectRepository {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final Uuid _uuid = const Uuid();

  ProjectRepository() {
    final emulatorHost = defaultTargetPlatform == TargetPlatform.android
        ? AppConfig.androidEmulatorHost
        : AppConfig.loopbackHost;
    debugPrint(
      '[ProjectRepository] Created. firestoreProjectId=${_db.app.options.projectId}',
    );
    debugPrint(
      '[ProjectRepository] USE_FIREBASE_EMULATORS=${AppConfig.useFirebaseEmulators}',
    );
    debugPrint(
      '[ProjectRepository] Expected Firestore emulator host=$emulatorHost '
      'port=${AppConfig.firestorePort}',
    );
  }

  /// Главная коллекция объектов ремонта в Firestore.
  ///
  /// В UI и Dart-коде модель пока называется Project, потому что это короткое
  /// и уже существующее имя в приложении. В базе данных используем более
  /// предметное название `objects`, чтобы структура совпадала с продуктовой
  /// терминологией:
  ///
  /// objects/{objectId}
  /// objects/{objectId}/stages/{stageId}
  /// objects/{objectId}/photos/{photoId}
  ///
  /// Одна константная точка доступа защищает от ошибок: если путь коллекции
  /// понадобится изменить, не придется искать строку по всему проекту.
  // Diagnostic helpers live below; Firestore collection accessors follow after them.
  /// Main Firestore collection for repair projects.
  CollectionReference<Map<String, dynamic>> get _projectsCollection {
    return _db.collection('projects');
  }

  /// Legacy alias.
  ///
  /// Большая часть старого репозитория писалась в терминах "objects". Чтобы не
  /// переписывать все существующие методы за один раз и не сломать старые
  /// экраны, alias теперь указывает на production collection `projects`.
  CollectionReference<Map<String, dynamic>> get _objectsCollection {
    return _projectsCollection;
  }

  CollectionReference<Map<String, dynamic>> _stagesCollection(
    String projectId,
  ) {
    return _projectsCollection.doc(projectId).collection('stages');
  }

  CollectionReference<Map<String, dynamic>> _stagePhotosCollection({
    required String projectId,
    required String stageId,
  }) {
    return _stagesCollection(projectId).doc(stageId).collection('photos');
  }

  CollectionReference<Map<String, dynamic>> _timelineCollection(
    String projectId,
  ) {
    return _projectsCollection.doc(projectId).collection('timeline');
  }

  CollectionReference<Map<String, dynamic>> get _companiesCollection {
    return _db.collection('companies');
  }

  CollectionReference<Map<String, dynamic>> _companyMembersCollection(
    String companyId,
  ) {
    return _companiesCollection.doc(companyId).collection('members');
  }

  CollectionReference<Map<String, dynamic>> _joinRequestsCollection(
    String companyId,
  ) {
    return _companiesCollection.doc(companyId).collection('joinRequests');
  }

  CollectionReference<Map<String, dynamic>> get _legacyInvitationsCollection {
    return _db.collection('companyInvitations');
  }

  CollectionReference<Map<String, dynamic>> _companyInvitationsCollection(
    String companyId,
  ) {
    return _companiesCollection.doc(companyId).collection('invitations');
  }

  CollectionReference<Map<String, dynamic>> get _usersCollection {
    return _db.collection('users');
  }

  CollectionReference<Map<String, dynamic>> _notificationsCollection(
    String userId,
  ) {
    return _usersCollection.doc(userId).collection('notifications');
  }

  /// Возвращает UID текущего пользователя.
  ///
  /// Вызов `!` безопасен для экранов внутри приложения, потому что main.dart
  /// показывает эти экраны только после успешной авторизации.
  String get _uid {
    final user = _auth.currentUser;
    AuthDebug.logUser('ProjectRepository._uid', user);

    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    return user.uid;
  }

  /// Возвращает телефон текущего пользователя в нормализованном виде.
  String get _phone {
    final user = _auth.currentUser;
    AuthDebug.logUser('ProjectRepository._phone', user);
    return PhoneUtils.normalize(user?.phoneNumber ?? '');
  }

  /// Возвращает понятное имя текущего пользователя для участника и чата.
  ///
  /// После перехода на Email/Password Auth основное отображаемое имя — email.
  /// Телефон оставлен только как fallback для старых аккаунтов или будущих
  /// сценариев, где у Firebase user может быть заполнен phoneNumber.
  String get _displayName {
    final user = _auth.currentUser;
    AuthDebug.logUser('ProjectRepository._displayName', user);
    final email = user?.email;
    final phone = user?.phoneNumber;

    if (email != null && email.isNotEmpty) {
      return email;
    }

    if (phone != null && phone.isNotEmpty) {
      return phone;
    }

    return 'Пользователь';
  }

  /// Публичное имя автора для UI-слоя.
  ///
  /// Экран добавления фото использует это значение как uploadedBy.
  /// В production здесь можно заменить fallback на профиль пользователя.
  String get currentAuthorName => _displayName;

  String get currentUserId => _uid;

  /// Дефолтные этапы ремонта.
  ///
  /// Они создаются внутри конкретного объекта. Это важно: разные объекты могут
  /// иметь свой порядок этапов, свои кастомные этапы и свои правки названий.
  List<RepairStage> get _defaultStages {
    final now = DateTime.now();

    return [
      RepairStage(
        id: 'demolition',
        name: 'Демонтаж',
        color: 0xFFEF4444,
        icon: 'construction',
        sortOrder: 10,
        createdAt: now,
      ),
      RepairStage(
        id: 'electricity',
        name: 'Электрика',
        color: 0xFFF59E0B,
        icon: 'electric_bolt',
        sortOrder: 20,
        createdAt: now,
      ),
      RepairStage(
        id: 'plumbing',
        name: 'Сантехника',
        color: 0xFF0EA5E9,
        icon: 'plumbing',
        sortOrder: 30,
        createdAt: now,
      ),
      RepairStage(
        id: 'plaster',
        name: 'Штукатурка',
        color: 0xFF8B5CF6,
        icon: 'texture',
        sortOrder: 40,
        createdAt: now,
      ),
      RepairStage(
        id: 'putty',
        name: 'Шпаклевка',
        color: 0xFF64748B,
        icon: 'format_paint',
        sortOrder: 50,
        createdAt: now,
      ),
      RepairStage(
        id: 'painting',
        name: 'Покраска',
        color: 0xFF22C55E,
        icon: 'format_color_fill',
        sortOrder: 60,
        createdAt: now,
      ),
      RepairStage(
        id: 'floors',
        name: 'Полы',
        color: 0xFFA16207,
        icon: 'floor',
        sortOrder: 70,
        createdAt: now,
      ),
      RepairStage(
        id: 'tile',
        name: 'Плитка',
        color: 0xFF14B8A6,
        icon: 'grid_view',
        sortOrder: 80,
        createdAt: now,
      ),
      RepairStage(
        id: 'ceiling',
        name: 'Натяжной потолок',
        color: 0xFF6366F1,
        icon: 'layers',
        sortOrder: 90,
        createdAt: now,
      ),
      RepairStage(
        id: 'final_cleaning',
        name: 'Финальная уборка',
        color: 0xFF10B981,
        icon: 'cleaning_services',
        sortOrder: 100,
        createdAt: now,
      ),
    ];
  }

  /// Production-шаблоны этапов.
  ///
  /// Метод создает полноценные Stage-документы с summary metadata. Эти поля
  /// позволяют списку этапов работать быстро: UI не читает все фото и чеки,
  /// чтобы показать счетчики, сумму и обложку.
  List<Stage> _defaultProductionStages(String projectId) {
    final now = DateTime.now();
    final definitions = <({String id, StageType type, String title})>[
      (id: 'demolition', type: StageType.demolition, title: 'Демонтаж'),
      (id: 'electricity', type: StageType.electricity, title: 'Электрика'),
      (id: 'plumbing', type: StageType.plumbing, title: 'Сантехника'),
      (id: 'plaster', type: StageType.plaster, title: 'Штукатурка'),
      (id: 'putty', type: StageType.putty, title: 'Шпаклевка'),
      (id: 'painting', type: StageType.painting, title: 'Покраска'),
      (id: 'floors', type: StageType.floors, title: 'Полы'),
      (id: 'tile', type: StageType.tile, title: 'Плитка'),
      (id: 'ceiling', type: StageType.ceiling, title: 'Натяжной потолок'),
      (
        id: 'final_cleaning',
        type: StageType.finalCleaning,
        title: 'Финальная уборка',
      ),
    ];

    return [
      for (var index = 0; index < definitions.length; index++)
        Stage(
          id: definitions[index].id,
          projectId: projectId,
          title: definitions[index].title,
          type: definitions[index].type,
          status: StageStatus.notStarted,
          progress: 0,
          assignedUserIds: const [],
          showExecutorsToClient: true,
          photosCount: 0,
          receiptsCount: 0,
          receiptsTotal: 0,
          coverPhotoUrl: null,
          completedAt: null,
          createdAt: now,
          updatedAt: now,
          createdBy: _uid,
          orderIndex: (index + 1) * 10,
        ),
    ];
  }

  /// Безопасно превращает Firestore documents в модели.
  ///
  /// Почему это важно:
  /// - Firestore Emulator часто используется вручную через Emulator UI;
  /// - один документ может быть создан с неправильной структурой;
  /// - без try/catch ошибка одного документа ломает весь StreamBuilder;
  /// - с defensive parsing мы пропускаем только битый документ, а остальные
  ///   объекты/участники/сообщения продолжают отображаться.
  List<T> _mapDocumentsSafely<T>(
    Iterable<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    T Function(String id, Map<String, dynamic> data) fromMap,
  ) {
    final result = <T>[];

    for (final doc in docs) {
      try {
        result.add(fromMap(doc.id, doc.data()));
      } catch (error) {
        // В production здесь лучше отправлять ошибку в Crashlytics/logging.
        // В MVP не бросаем исключение дальше, чтобы UI не падал из-за одного
        // испорченного dev-документа.
        debugPrint(
          'Пропущен некорректный Firestore document '
          '${doc.reference.path}: $error',
        );
      }
    }

    return result;
  }

  /// Следит за персональными уведомлениями текущего пользователя.
  ///
  /// Храним уведомления в `users/{uid}/notifications`, поэтому экрану не нужно
  /// сканировать все компании и все timeline-события. Это дешевле, быстрее и
  /// уже похоже на будущую push-архитектуру: событие создается один раз, а
  /// доставка раскладывается по нужным пользователям.
  Stream<List<AppNotification>> watchNotifications({int limit = 80}) {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<List<AppNotification>>.value(const []);
    }

    return _notificationsCollection(user.uid)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              AppNotification.fromMap,
            ));
  }

  /// Следит только за количеством непрочитанных уведомлений.
  ///
  /// AppBar использует этот stream для badge. Мы не грузим полный список
  /// уведомлений на главный экран, потому что для badge нужен только count.
  Stream<int> watchUnreadNotificationCount() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream<int>.value(0);
    }

    return _notificationsCollection(user.uid)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.size);
  }

  /// Отмечает одно уведомление прочитанным.
  ///
  /// Метод проверяет владельца документа на клиенте для понятной ошибки, а
  /// Firestore Rules повторно защищают эту операцию на серверной стороне.
  Future<void> markNotificationRead(AppNotification notification) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    if (notification.userId != user.uid) {
      throw StateError('Нельзя изменить чужое уведомление.');
    }

    if (notification.isRead) {
      return;
    }

    await _notificationsCollection(user.uid).doc(notification.id).update({
      'isRead': true,
      'readAt': DateTime.now(),
    });
  }

  /// Отмечает все непрочитанные уведомления текущего пользователя прочитанными.
  ///
  /// Для MVP достаточно одного batch. При тысячах уведомлений здесь можно
  /// добавить постраничную обработку, но текущий центр уведомлений ограничивает
  /// список и не создает тяжелую нагрузку.
  Future<void> markAllNotificationsRead() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final snapshot = await _notificationsCollection(user.uid)
        .where('isRead', isEqualTo: false)
        .limit(400)
        .get();

    if (snapshot.docs.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final batch = _db.batch();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {
        'isRead': true,
        'readAt': now,
      });
    }
    await batch.commit();
  }

  Stream<List<CompanyMember>> watchCurrentUserCompanyMemberships() async* {
    final user = _auth.currentUser;
    AuthDebug.logUser('[ACCESS] watchCurrentUserCompanyMemberships user', user);

    if (user == null) {
      debugPrint('[ACCESS] No FirebaseAuth.currentUser. memberships=[]');
      yield const <CompanyMember>[];
      return;
    }

    final uid = user.uid;
    final email = user.email?.trim().toLowerCase() ?? '';
    debugPrint('[ACCESS] Loading memberships...');
    debugPrint('[ACCESS] Query: collectionGroup companies/*/members/*');
    debugPrint('[ACCESS] Filters: uid=$uid, active=true, email=$email');

    final query = _db
        .collectionGroup('members')
        .where('uid', isEqualTo: uid)
        .where('active', isEqualTo: true);

    try {
      await for (final snapshot in query.snapshots()) {
        debugPrint(
          '[ACCESS] Memberships snapshot received. docs=${snapshot.docs.length}',
        );
        for (final doc in snapshot.docs) {
          debugPrint('[ACCESS] Membership doc allowed: ${doc.reference.path}');
        }

        final memberships = _mapDocumentsSafely(
          snapshot.docs,
          CompanyMember.fromMap,
        ).where((member) => member.role != CompanyRole.user).toList();

        memberships.sort((a, b) => a.companyName.compareTo(b.companyName));
        yield memberships;
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[ACCESS ERROR]');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint('path=collectionGroup(members)');
      debugPrint('filters=uid == $uid, active == true');
      debugPrintStack(
        label: '[ACCESS ERROR] Membership stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint('[ACCESS ERROR]');
      debugPrint('code=unexpected');
      debugPrint('message=$error');
      debugPrint('path=collectionGroup(members)');
      debugPrint('filters=uid == $uid, active == true');
      debugPrintStack(
        label: '[ACCESS ERROR] Membership stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Stream<List<CompanyInvitation>> watchCurrentUserInvitations() async* {
    final user = _auth.currentUser;
    final email = user?.email?.trim().toLowerCase() ?? '';
    debugPrint('[ACCESS] Loading current user invitations...');
    debugPrint('[ACCESS] Query: collectionGroup companies/*/invitations/*');
    debugPrint('[ACCESS] Filters: email=$email, status=pending');

    if (email.isEmpty) {
      debugPrint('[ACCESS] No email. invitations=[]');
      yield const <CompanyInvitation>[];
      return;
    }

    final query = _db
        .collectionGroup('invitations')
        .where('email', isEqualTo: email)
        .where('status', isEqualTo: InvitationStatus.pending.firestoreValue);

    try {
      await for (final snapshot in query.snapshots()) {
        debugPrint(
          '[ACCESS] Invitations snapshot received. docs=${snapshot.docs.length}',
        );
        for (final doc in snapshot.docs) {
          debugPrint('[ACCESS] Invitation doc allowed: ${doc.reference.path}');
        }

        yield _mapDocumentsSafely(
          snapshot.docs,
          CompanyInvitation.fromMap,
        );
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[ACCESS ERROR]');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint('path=collectionGroup(invitations)');
      debugPrint('filters=email == $email, status == pending');
      debugPrintStack(
        label: '[ACCESS ERROR] Invitations stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint('[ACCESS ERROR]');
      debugPrint('code=unexpected');
      debugPrint('message=$error');
      debugPrint('path=collectionGroup(invitations)');
      debugPrint('filters=email == $email, status == pending');
      debugPrintStack(
        label: '[ACCESS ERROR] Invitations stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Watches the company document itself.
  ///
  /// Membership documents know the current user's role, but the public join
  /// code belongs to the company document. Keeping this read in the repository
  /// lets the settings screen stay UI-only and avoids direct Firestore calls
  /// from widgets.
  Stream<Company?> watchCompany(String companyId) {
    if (companyId.trim().isEmpty) {
      return Stream<Company?>.value(null);
    }

    return _companiesCollection.doc(companyId).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }

      return Company.fromMap(snapshot.id, data);
    });
  }

  /// Generates a short human-readable company code and checks it against both
  /// current (`companyCode`) and legacy (`code`) fields.
  ///
  /// Firestore document ids are already unique, but users should not have to
  /// copy a long document id. A compact code is easier to dictate in chat or by
  /// phone. The loop is intentionally small: collisions are very unlikely, and
  /// if they happen repeatedly it is better to fail loudly than create two
  /// companies with the same join code.
  Future<String> _generateUniqueCompanyCode() async {
    for (var attempt = 0; attempt < 8; attempt++) {
      final raw = _uuid.v4().replaceAll('-', '').toUpperCase();
      final code = 'REMONT-${raw.substring(0, 6)}';

      final byCompanyCode = await _companiesCollection
          .where('companyCode', isEqualTo: code)
          .limit(1)
          .get();
      final byLegacyCode = await _companiesCollection
          .where('code', isEqualTo: code)
          .limit(1)
          .get();

      if (byCompanyCode.docs.isEmpty && byLegacyCode.docs.isEmpty) {
        return code;
      }
    }

    throw Exception('Не удалось создать уникальный код компании.');
  }

  /// Finds a company by the public join code.
  ///
  /// The app now has two separate onboarding flows:
  /// - company code creates a join request for the director;
  /// - email invitation is accepted from the invitations list.
  ///
  /// For compatibility with old emulator data we still check the legacy `code`
  /// field, but we deliberately do not accept invitation ids here anymore.
  Future<Company?> _findCompanyByCode(String rawCode) async {
    final code = rawCode.trim().toUpperCase();
    if (code.isEmpty) {
      return null;
    }

    final byCompanyCode = await _companiesCollection
        .where('companyCode', isEqualTo: code)
        .limit(1)
        .get();
    if (byCompanyCode.docs.isNotEmpty) {
      final doc = byCompanyCode.docs.first;
      return Company.fromMap(doc.id, doc.data());
    }

    final byLegacyCode = await _companiesCollection
        .where('code', isEqualTo: code)
        .limit(1)
        .get();
    if (byLegacyCode.docs.isNotEmpty) {
      final doc = byLegacyCode.docs.first;
      return Company.fromMap(doc.id, doc.data());
    }

    return null;
  }

  Future<Company> createCompany(String name) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    debugPrint(
      '[DialogFlow] createCompany repository start uid=${user.uid} '
      'email=${user.email ?? ''}',
    );

    final now = DateTime.now();
    final companyRef = _companiesCollection.doc();
    final code = await _generateUniqueCompanyCode();
    final email = user.email?.trim().toLowerCase() ?? '';
    final displayName = user.displayName ?? email;
    final company = Company(
      id: companyRef.id,
      name: name.trim(),
      code: code,
      ownerId: user.uid,
      status: CompanyStatus.active,
      createdAt: now,
    );
    final owner = CompanyMember(
      id: user.uid,
      companyId: company.id,
      companyName: company.name,
      uid: user.uid,
      email: email,
      displayName: displayName,
      role: CompanyRole.owner,
      canCreateProjects: true,
      assignedProjectIds: const [],
      active: true,
      createdAt: now,
    );

    final batch = _db.batch();
    batch.set(companyRef, company.toMap());
    batch.set(
        _companyMembersCollection(company.id).doc(user.uid), owner.toMap());
    batch.set(
      _usersCollection.doc(user.uid),
      {
        'uid': user.uid,
        'email': email,
        'displayName': displayName,
        'baseRole': 'user',
        'updatedAt': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );
    await batch.commit();

    debugPrint('[DialogFlow] createCompany repository success ${company.id}');
    return company;
  }

  Future<void> requestJoinCompany(String companyCode) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final code = companyCode.trim().toUpperCase();
    debugPrint('[ACCESS] Request join company by code. uid=${user.uid}');
    debugPrint('[ACCESS] Query: companies where companyCode/code == $code');
    if (code.isEmpty) {
      throw ArgumentError('Введите код компании.');
    }

    final company = await _findCompanyByCode(code);
    if (company == null) {
      throw Exception('Компания с таким кодом не найдена.');
    }

    if (!company.isActive) {
      throw Exception('Компания недоступна.');
    }

    final now = DateTime.now();
    final request = CompanyJoinRequest(
      id: user.uid,
      companyId: company.id,
      companyName: company.name,
      uid: user.uid,
      email: user.email?.trim().toLowerCase() ?? '',
      displayName: user.displayName ?? user.email ?? 'Пользователь',
      status: JoinRequestStatus.pending,
      createdAt: now,
    );

    final requestRef = _joinRequestsCollection(company.id).doc(user.uid);
    debugPrint('[ACCESS] Writing join request: ${requestRef.path}');
    final batch = _db.batch();
    batch.set(
      requestRef,
      request.toMap(),
      SetOptions(merge: true),
    );
    _setNotification(
      batch: batch,
      recipientId: company.ownerId,
      type: AppNotificationType.joinRequestCreated,
      title: 'Новая заявка на вступление',
      message: '${request.displayName} хочет присоединиться к компании.',
      createdAt: now,
      companyId: company.id,
    );
    await batch.commit();
  }

  Future<void> acceptInvitation(String invitationId) async {
    final email = _auth.currentUser?.email?.trim().toLowerCase() ?? '';
    debugPrint('[ACCESS] Accept invitation by id.');
    debugPrint('[ACCESS] Path: companyInvitations/$invitationId');
    final legacySnapshot =
        await _legacyInvitationsCollection.doc(invitationId).get();
    final legacyData = legacySnapshot.data();
    if (legacySnapshot.exists && legacyData != null) {
      await _acceptInvitationFromSnapshot(legacySnapshot.id, legacyData);
      return;
    }

    debugPrint('[ACCESS] Query: collectionGroup companies/*/invitations/*');
    debugPrint(
      '[ACCESS] Filters: documentId=$invitationId, email=$email, status=pending',
    );

    QuerySnapshot<Map<String, dynamic>> nestedSnapshot;
    try {
      nestedSnapshot = await _db
          .collectionGroup('invitations')
          .where(FieldPath.documentId, isEqualTo: invitationId)
          .where('email', isEqualTo: email)
          .where('status', isEqualTo: InvitationStatus.pending.firestoreValue)
          .limit(1)
          .get();
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[ACCESS ERROR]');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint('path=collectionGroup(invitations)');
      debugPrint(
        'filters=documentId == $invitationId, email == $email, status == pending',
      );
      debugPrintStack(
        label: '[ACCESS ERROR] Accept invitation stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }

    if (nestedSnapshot.docs.isEmpty) {
      throw Exception('Приглашение не найдено.');
    }

    final doc = nestedSnapshot.docs.first;
    await _acceptCompanyInvitation(
        CompanyInvitation.fromMap(doc.id, doc.data()));
  }

  Future<void> _acceptInvitationFromSnapshot(
    String id,
    Map<String, dynamic> data,
  ) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final invitation = CompanyInvitation.fromMap(id, data);
    final userEmail = user.email?.trim().toLowerCase() ?? '';
    if (invitation.email.toLowerCase() != userEmail) {
      throw Exception('Приглашение создано для другого email.');
    }

    final now = DateTime.now();
    final member = CompanyMember(
      id: user.uid,
      companyId: invitation.companyId,
      companyName: invitation.companyName,
      uid: user.uid,
      email: userEmail,
      displayName: user.displayName ?? userEmail,
      role: invitation.role,
      canCreateProjects: false,
      assignedProjectIds: [
        if (invitation.projectId?.isNotEmpty == true) invitation.projectId!,
      ],
      active: true,
      createdAt: now,
    );

    final batch = _db.batch();
    batch.set(
      _companyMembersCollection(invitation.companyId).doc(user.uid),
      {
        ...member.toMap(),
        'acceptedLegacyInvitationId': id,
      },
    );
    batch.update(_legacyInvitationsCollection.doc(id), {
      'status': InvitationStatus.accepted.firestoreValue,
      'acceptedAt': FieldValue.serverTimestamp(),
      'acceptedBy': user.uid,
    });

    final projectId = invitation.projectId;
    if (projectId != null && projectId.isNotEmpty) {
      final projectRef = _objectsCollection.doc(projectId);
      if (invitation.role == CompanyRole.manager) {
        batch.update(projectRef, {
          'managerIds': FieldValue.arrayUnion([user.uid]),
          'managerNames': FieldValue.arrayUnion([member.displayName]),
          'participantIds': FieldValue.arrayUnion([user.uid]),
        });
      } else if (invitation.role == CompanyRole.worker) {
        batch.update(projectRef, {
          'workerIds': FieldValue.arrayUnion([user.uid]),
          'workerNames': FieldValue.arrayUnion([member.displayName]),
          'participantIds': FieldValue.arrayUnion([user.uid]),
        });
        _applyWorkerStageUpdates(
          batch: batch,
          projectId: projectId,
          stageIds: invitation.stageIds,
          userId: user.uid,
          userName: member.displayName,
        );
      } else if (invitation.role == CompanyRole.client) {
        batch.update(projectRef, {
          'clientIds': FieldValue.arrayUnion([user.uid]),
          'clientNames': FieldValue.arrayUnion([member.displayName]),
          'participantIds': FieldValue.arrayUnion([user.uid]),
        });
      } else {
        batch.update(projectRef, {
          'participantIds': FieldValue.arrayUnion([user.uid]),
        });
      }
    }

    debugPrint('[MEMBERSHIP ACCESS] Accepting legacy invitation.');
    debugPrint(
      '[MEMBERSHIP ACCESS] Write membership path='
      'companies/${invitation.companyId}/members/${user.uid}; '
      'role=${invitation.role.firestoreValue}; active=true; '
      'assignedProjectIds=${member.assignedProjectIds}',
    );

    try {
      await batch.commit();
      debugPrint(
        '[MEMBERSHIP ACCESS] Legacy invitation accepted. '
        'membership=companies/${invitation.companyId}/members/${user.uid}',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[MEMBERSHIP ACCESS ERROR]');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint(
          'membershipPath=companies/${invitation.companyId}/members/${user.uid}');
      debugPrint('legacyInvitationPath=companyInvitations/$id');
      debugPrint('projectId=${invitation.projectId}');
      debugPrintStack(
        label: '[MEMBERSHIP ACCESS ERROR] Legacy invitation accept stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<void> acceptCompanyInvitation(CompanyInvitation invitation) async {
    await _acceptCompanyInvitation(invitation);
  }

  Future<void> declineCompanyInvitation(CompanyInvitation invitation) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final email = user.email?.trim().toLowerCase() ?? '';
    if (invitation.email.toLowerCase() != email) {
      throw Exception('Приглашение создано для другого email.');
    }

    await _companyInvitationsCollection(invitation.companyId)
        .doc(invitation.id)
        .update({
      'status': InvitationStatus.declined.firestoreValue,
      'declinedAt': FieldValue.serverTimestamp(),
      'declinedBy': user.uid,
    });

    await _writeTimelineEvent(
      projectId: invitation.projectId,
      stageId: '',
      type: TimelineEventType.invitationDeclined,
      stageTitle: '',
      metadata: {
        'userId': user.uid,
        'userEmail': email,
        'role': invitation.role.firestoreValue,
        'projectId': invitation.projectId,
        'stageIds': invitation.stageIds,
        'stageTitles': invitation.stageTitles,
      },
    );
  }

  Future<void> _acceptCompanyInvitation(CompanyInvitation invitation) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    if (invitation.status != InvitationStatus.pending) {
      throw Exception('Приглашение уже обработано.');
    }

    final userEmail = user.email?.trim().toLowerCase() ?? '';
    if (invitation.email.toLowerCase() != userEmail) {
      throw Exception('Приглашение создано для другого email.');
    }

    final now = DateTime.now();
    final member = CompanyMember(
      id: user.uid,
      companyId: invitation.companyId,
      companyName: invitation.companyName,
      uid: user.uid,
      email: userEmail,
      displayName: user.displayName ?? userEmail,
      role: invitation.role,
      canCreateProjects: false,
      assignedProjectIds: [
        if (invitation.projectId?.isNotEmpty == true) invitation.projectId!,
      ],
      active: true,
      createdAt: now,
    );
    final companySnapshot =
        await _companiesCollection.doc(invitation.companyId).get();
    final companyOwnerId = companySnapshot.data()?['ownerId'];
    final ownerId = companyOwnerId is String ? companyOwnerId : '';

    final invitationRef =
        _companyInvitationsCollection(invitation.companyId).doc(invitation.id);
    final membershipRef =
        _companyMembersCollection(invitation.companyId).doc(user.uid);
    debugPrint('[MEMBERSHIP ACCESS] Accepting company invitation.');
    debugPrint(
      '[MEMBERSHIP ACCESS] Invitation path=${invitationRef.path}; '
      'role=${invitation.role.firestoreValue}; projectId=${invitation.projectId}; '
      'stageIds=${invitation.stageIds}',
    );
    debugPrint(
      '[MEMBERSHIP ACCESS] Write membership path=${membershipRef.path}; '
      'uid=${user.uid}; email=$userEmail; active=true; '
      'assignedProjectIds=${member.assignedProjectIds}',
    );

    final batch = _db.batch();
    batch.set(
      membershipRef,
      {
        ...member.toMap(),
        'acceptedInvitationId': invitation.id,
      },
      SetOptions(merge: true),
    );
    batch.update(invitationRef, {
      'status': InvitationStatus.accepted.firestoreValue,
      'acceptedAt': FieldValue.serverTimestamp(),
      'acceptedBy': user.uid,
    });

    _applyProjectAccessUpdates(
      batch: batch,
      projectId: invitation.projectId,
      role: invitation.role,
      userId: user.uid,
      userName: member.displayName,
    );

    _applyWorkerStageUpdates(
      batch: batch,
      projectId: invitation.projectId,
      stageIds: invitation.stageIds,
      userId: user.uid,
      userName: member.displayName,
    );

    final invitationAcceptedEventId = _setTimelineEvent(
      batch: batch,
      projectId: invitation.projectId,
      stageId: '',
      type: TimelineEventType.invitationAccepted,
      stageTitle: '',
      metadata: {
        'userId': user.uid,
        'userEmail': userEmail,
        'role': invitation.role.firestoreValue,
        'projectId': invitation.projectId,
        'stageIds': invitation.stageIds,
        'stageTitles': invitation.stageTitles,
      },
    );
    _setNotification(
      batch: batch,
      recipientId: ownerId,
      type: AppNotificationType.invitationAccepted,
      title: 'Пользователь принял приглашение',
      message: '${member.displayName} присоединился к компании.',
      createdAt: now,
      projectId: invitation.projectId,
      projectTitle: invitation.projectTitle,
      companyId: invitation.companyId,
      sourceEventId: invitationAcceptedEventId,
    );
    _setTimelineEvent(
      batch: batch,
      projectId: invitation.projectId,
      stageId: '',
      type: TimelineEventType.participantAdded,
      stageTitle: '',
      metadata: {
        'userId': user.uid,
        'userEmail': userEmail,
        'role': invitation.role.firestoreValue,
        'projectId': invitation.projectId,
        'stageIds': invitation.stageIds,
        'stageTitles': invitation.stageTitles,
      },
    );

    for (var index = 0; index < invitation.stageIds.length; index++) {
      final stageId = invitation.stageIds[index];
      _setTimelineEvent(
        batch: batch,
        projectId: invitation.projectId,
        stageId: stageId,
        type: TimelineEventType.workerAssignedToStage,
        stageTitle: index < invitation.stageTitles.length
            ? invitation.stageTitles[index]
            : '',
        metadata: {
          'userId': user.uid,
          'userEmail': userEmail,
          'role': invitation.role.firestoreValue,
          'projectId': invitation.projectId,
          'stageIds': invitation.stageIds,
          'stageTitles': invitation.stageTitles,
        },
      );
    }

    if (invitation.role.isWorker && invitation.stageIds.isNotEmpty) {
      final projectTitle = invitation.projectTitle ?? 'Без названия';
      _setNotification(
        batch: batch,
        recipientId: user.uid,
        type: AppNotificationType.workerAssignedToStage,
        title: 'Вам назначен новый этап',
        message:
            'Объект "$projectTitle": ${invitation.stageTitles.join(', ')}.',
        createdAt: now,
        projectId: invitation.projectId,
        projectTitle: invitation.projectTitle,
        companyId: invitation.companyId,
        includeCurrentUser: true,
      );
    }

    try {
      await batch.commit();
      debugPrint(
        '[MEMBERSHIP ACCESS] Company invitation accepted. '
        'membership=${membershipRef.path}; role=${invitation.role.firestoreValue}',
      );
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[MEMBERSHIP ACCESS ERROR]');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint('membershipPath=${membershipRef.path}');
      debugPrint('invitationPath=${invitationRef.path}');
      debugPrint('projectId=${invitation.projectId}');
      debugPrint('role=${invitation.role.firestoreValue}');
      debugPrintStack(
        label:
            '[MEMBERSHIP ACCESS ERROR] Company invitation accept stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Stream<List<CompanyMember>> watchCompanyManagers(String companyId) {
    return _companyMembersCollection(companyId)
        .where('role', isEqualTo: CompanyRole.manager.firestoreValue)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              CompanyMember.fromMap,
            ));
  }

  Future<void> addManagerByEmail({
    required CompanyMember company,
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Введите email прораба.');
    }

    debugPrint(
      '[DialogFlow] addManagerByEmail start company=${company.companyId} '
      'email=$normalizedEmail',
    );

    await createCompanyInvitation(
      inviter: company,
      email: normalizedEmail,
      role: CompanyRole.manager,
    );
    debugPrint('[DialogFlow] addManagerByEmail invitation created');
  }

  Future<void> setManagerCanCreateProjects({
    required CompanyMember owner,
    required CompanyMember manager,
    required bool value,
  }) async {
    _assertOwner(owner);
    await _companyMembersCollection(owner.companyId).doc(manager.uid).update({
      'canCreateProjects': value,
    });
  }

  Future<void> assignProjectsToManager({
    required CompanyMember owner,
    required CompanyMember manager,
    required List<Project> projects,
  }) async {
    _assertOwner(owner);
    final projectIds = projects.map((project) => project.id).toSet().toList();
    final managerName =
        manager.displayName.isNotEmpty ? manager.displayName : manager.email;

    final batch = _db.batch();
    batch.update(_companyMembersCollection(owner.companyId).doc(manager.uid), {
      'assignedProjectIds': projectIds,
    });

    final companyProjects = await _objectsCollection
        .where('companyId', isEqualTo: owner.companyId)
        .get();
    for (final doc in companyProjects.docs) {
      final assigned = projectIds.contains(doc.id);
      batch.update(doc.reference, {
        'managerIds': assigned
            ? FieldValue.arrayUnion([manager.uid])
            : FieldValue.arrayRemove([manager.uid]),
        'managerNames': assigned
            ? FieldValue.arrayUnion([managerName])
            : FieldValue.arrayRemove([managerName]),
        'participantIds': assigned
            ? FieldValue.arrayUnion([manager.uid])
            : FieldValue.arrayRemove([manager.uid]),
      });
    }

    await batch.commit();
  }

  Future<void> removeManagerFromCompany({
    required CompanyMember owner,
    required CompanyMember manager,
  }) async {
    _assertOwner(owner);
    final batch = _db.batch();
    batch.update(_companyMembersCollection(owner.companyId).doc(manager.uid), {
      'active': false,
      'assignedProjectIds': <String>[],
    });

    final projects = await _objectsCollection
        .where('companyId', isEqualTo: owner.companyId)
        .where('managerIds', arrayContains: manager.uid)
        .get();
    for (final doc in projects.docs) {
      batch.update(doc.reference, {
        'managerIds': FieldValue.arrayRemove([manager.uid]),
        'managerNames': FieldValue.arrayRemove([manager.displayName]),
        'participantIds': FieldValue.arrayRemove([manager.uid]),
      });
    }

    await batch.commit();
  }

  Future<void> softDeleteCompany(CompanyMember owner) async {
    _assertOwner(owner);
    final now = DateTime.now();
    final batch = _db.batch();
    batch.update(_companiesCollection.doc(owner.companyId), {
      'status': CompanyStatus.deleted.firestoreValue,
      'deletedAt': now.toIso8601String(),
      'deletedBy': owner.uid,
    });
    final members = await _companyMembersCollection(owner.companyId).get();
    for (final member in members.docs) {
      batch.update(member.reference, {'active': false});
    }
    await batch.commit();
  }

  void _assertOwner(CompanyMember member) {
    if (!member.role.isOwner) {
      throw Exception('Действие доступно только директору.');
    }
  }

  bool canInviteRole({
    required CompanyMember inviter,
    required CompanyRole role,
  }) {
    if (inviter.role.isOwner) {
      return role == CompanyRole.manager ||
          role == CompanyRole.worker ||
          role == CompanyRole.client;
    }

    if (inviter.role.isManager) {
      return role == CompanyRole.worker || role == CompanyRole.client;
    }

    return false;
  }

  void _assertCanInvite({
    required CompanyMember inviter,
    required CompanyRole role,
  }) {
    if (!canInviteRole(inviter: inviter, role: role)) {
      throw Exception('У вас нет прав создавать такое приглашение.');
    }
  }

  Future<CompanyInvitation> createCompanyInvitation({
    required CompanyMember inviter,
    required String email,
    required CompanyRole role,
    Project? project,
    List<Stage> stages = const [],
  }) async {
    _assertCanInvite(inviter: inviter, role: role);

    final normalizedEmail = email.trim().toLowerCase();
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('Введите email.');
    }

    if ((role.isWorker || role.isClient) && project == null) {
      throw ArgumentError('Выберите объект.');
    }

    if (role.isWorker && stages.isEmpty) {
      throw ArgumentError('Выберите хотя бы один этап для подрядчика.');
    }

    final now = DateTime.now();
    final invitationRef =
        _companyInvitationsCollection(inviter.companyId).doc();
    final invitation = CompanyInvitation(
      id: invitationRef.id,
      companyId: inviter.companyId,
      companyName: inviter.companyName,
      email: normalizedEmail,
      role: role,
      status: InvitationStatus.pending,
      createdAt: now,
      projectId: project?.id,
      projectTitle: project?.title,
      stageIds: stages.map((stage) => stage.id).toList(growable: false),
      stageTitles: stages.map((stage) => stage.title).toList(growable: false),
      createdBy: inviter.uid,
    );

    final batch = _db.batch();
    batch.set(invitationRef, invitation.toMap());
    _setTimelineEvent(
      batch: batch,
      projectId: project?.id,
      stageId: '',
      type: TimelineEventType.invitationCreated,
      stageTitle: '',
      metadata: {
        'userEmail': normalizedEmail,
        'role': role.firestoreValue,
        'projectId': project?.id,
        'stageIds': invitation.stageIds,
        'stageTitles': invitation.stageTitles,
      },
    );
    await batch.commit();

    return invitation;
  }

  Stream<List<CompanyInvitation>> watchPendingInvitations({
    required String companyId,
    String? projectId,
    CompanyRole? role,
  }) {
    Query<Map<String, dynamic>> query = _companyInvitationsCollection(companyId)
        .where('status', isEqualTo: InvitationStatus.pending.firestoreValue);

    if (projectId != null && projectId.isNotEmpty) {
      query = query.where('projectId', isEqualTo: projectId);
    }

    if (role != null) {
      query = query.where('role', isEqualTo: role.firestoreValue);
    }

    return query.snapshots().map((snapshot) {
      final invitations = _mapDocumentsSafely(
        snapshot.docs,
        CompanyInvitation.fromMap,
      );
      invitations.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return invitations;
    });
  }

  Future<void> revokeInvitation({
    required CompanyMember actor,
    required CompanyInvitation invitation,
  }) async {
    _assertCanInvite(inviter: actor, role: invitation.role);

    await _companyInvitationsCollection(invitation.companyId)
        .doc(invitation.id)
        .update({
      'status': InvitationStatus.revoked.firestoreValue,
      'revokedAt': FieldValue.serverTimestamp(),
      'revokedBy': actor.uid,
    });
  }

  Stream<List<CompanyJoinRequest>> watchPendingJoinRequests(
    CompanyMember owner,
  ) {
    _assertOwner(owner);
    debugPrint('[ACCESS] Loading join requests for owner=${owner.uid}');
    debugPrint(
      '[ACCESS] Query: companies/${owner.companyId}/joinRequests '
      'where status=pending',
    );

    return _joinRequestsCollection(owner.companyId)
        .where('status', isEqualTo: JoinRequestStatus.pending.firestoreValue)
        .snapshots()
        .map((snapshot) {
      debugPrint(
        '[ACCESS] Join requests snapshot received. '
        'docs=${snapshot.docs.length}',
      );
      for (final doc in snapshot.docs) {
        debugPrint('[ACCESS] Join request doc allowed: ${doc.reference.path}');
      }

      final requests = _mapDocumentsSafely(
        snapshot.docs,
        CompanyJoinRequest.fromMap,
      );
      requests.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return requests;
    }).handleError((Object error, StackTrace stackTrace) {
      debugPrint('[ACCESS ERROR]');
      if (error is FirebaseException) {
        debugPrint('code=${error.code}');
        debugPrint('message=${error.message}');
      } else {
        debugPrint('code=unexpected');
        debugPrint('message=$error');
      }
      debugPrint('path=companies/${owner.companyId}/joinRequests');
      debugPrint('filters=status == pending');
      debugPrintStack(
        label: '[ACCESS ERROR] Join requests stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    });
  }

  Future<void> approveJoinRequest({
    required CompanyMember owner,
    required CompanyJoinRequest request,
    required CompanyRole role,
    Project? project,
    List<Stage> stages = const [],
  }) async {
    _assertOwner(owner);

    if (role == CompanyRole.user || role == CompanyRole.owner) {
      throw ArgumentError('Выберите роль доступа.');
    }

    if ((role.isWorker || role.isClient) && project == null) {
      throw ArgumentError('Выберите объект.');
    }

    if (role.isWorker && stages.isEmpty) {
      throw ArgumentError('Выберите хотя бы один этап для подрядчика.');
    }

    final now = DateTime.now();
    final member = CompanyMember(
      id: request.uid,
      companyId: owner.companyId,
      companyName: owner.companyName,
      uid: request.uid,
      email: request.email,
      displayName: request.displayName,
      role: role,
      canCreateProjects: false,
      assignedProjectIds: [
        if (project != null) project.id,
      ],
      active: true,
      createdAt: now,
    );

    final batch = _db.batch();
    batch.set(
      _companyMembersCollection(owner.companyId).doc(request.uid),
      member.toMap(),
      SetOptions(merge: true),
    );
    batch.update(_joinRequestsCollection(owner.companyId).doc(request.id), {
      'status': JoinRequestStatus.approved.firestoreValue,
      'approvedAt': FieldValue.serverTimestamp(),
      'approvedBy': owner.uid,
      'approvedRole': role.firestoreValue,
      'projectId': project?.id,
      'projectTitle': project?.title,
      'stageIds': stages.map((stage) => stage.id).toList(growable: false),
      'stageTitles': stages.map((stage) => stage.title).toList(growable: false),
    });

    _applyProjectAccessUpdates(
      batch: batch,
      projectId: project?.id,
      role: role,
      userId: request.uid,
      userName: request.displayName,
    );

    _applyWorkerStageUpdates(
      batch: batch,
      projectId: project?.id,
      stageIds: stages.map((stage) => stage.id).toList(growable: false),
      userId: request.uid,
      userName: request.displayName,
    );

    _setTimelineEvent(
      batch: batch,
      projectId: project?.id,
      stageId: '',
      type: TimelineEventType.joinRequestApproved,
      stageTitle: '',
      metadata: {
        'userId': request.uid,
        'userEmail': request.email,
        'role': role.firestoreValue,
        'projectId': project?.id,
        'stageIds': stages.map((stage) => stage.id).toList(growable: false),
        'stageTitles':
            stages.map((stage) => stage.title).toList(growable: false),
      },
    );
    _setTimelineEvent(
      batch: batch,
      projectId: project?.id,
      stageId: '',
      type: TimelineEventType.participantAdded,
      stageTitle: '',
      metadata: {
        'userId': request.uid,
        'userEmail': request.email,
        'role': role.firestoreValue,
        'projectId': project?.id,
        'stageIds': stages.map((stage) => stage.id).toList(growable: false),
        'stageTitles':
            stages.map((stage) => stage.title).toList(growable: false),
      },
    );

    if (role.isWorker && project != null && stages.isNotEmpty) {
      final stageTitles = stages.map((stage) => stage.title).join(', ');
      _setNotification(
        batch: batch,
        recipientId: request.uid,
        type: AppNotificationType.workerAssignedToStage,
        title: 'Вам назначен новый этап',
        message: 'Объект "${project.title}": $stageTitles.',
        createdAt: now,
        projectId: project.id,
        projectTitle: project.title,
        companyId: project.companyId,
        includeCurrentUser: true,
      );
    }

    await batch.commit();
  }

  Future<void> declineJoinRequest({
    required CompanyMember owner,
    required CompanyJoinRequest request,
  }) async {
    _assertOwner(owner);
    await _joinRequestsCollection(owner.companyId).doc(request.id).update({
      'status': JoinRequestStatus.declined.firestoreValue,
      'declinedAt': FieldValue.serverTimestamp(),
      'declinedBy': owner.uid,
    });
  }

  void _applyProjectAccessUpdates({
    required WriteBatch batch,
    required String? projectId,
    required CompanyRole role,
    required String userId,
    required String userName,
  }) {
    if (projectId == null || projectId.isEmpty) {
      debugPrint(
        '[PROJECT ACCESS] No project access grant. '
        'role=${role.firestoreValue}; uid=$userId; reason=empty projectId',
      );
      return;
    }

    final projectRef = _objectsCollection.doc(projectId);
    debugPrint(
      '[PROJECT ACCESS] Grant project access path=${projectRef.path}; '
      'role=${role.firestoreValue}; uid=$userId; userName=$userName',
    );

    if (role.isManager) {
      debugPrint(
        '[PROJECT ACCESS] Updating managerIds + managerNames + participantIds.',
      );
      batch.update(projectRef, {
        'managerIds': FieldValue.arrayUnion([userId]),
        'managerNames': FieldValue.arrayUnion([userName]),
        'participantIds': FieldValue.arrayUnion([userId]),
      });
    } else if (role.isWorker) {
      debugPrint(
        '[PROJECT ACCESS] Updating workerIds + workerNames + participantIds.',
      );
      batch.update(projectRef, {
        'workerIds': FieldValue.arrayUnion([userId]),
        'workerNames': FieldValue.arrayUnion([userName]),
        'participantIds': FieldValue.arrayUnion([userId]),
      });
    } else if (role.isClient) {
      debugPrint(
        '[PROJECT ACCESS] Updating clientIds + clientNames + participantIds.',
      );
      batch.update(projectRef, {
        'clientIds': FieldValue.arrayUnion([userId]),
        'clientNames': FieldValue.arrayUnion([userName]),
        'participantIds': FieldValue.arrayUnion([userId]),
      });
    }
  }

  void _removeProjectAccessUpdates({
    required WriteBatch batch,
    required Project project,
    required CompanyRole role,
    required CompanyMember member,
  }) {
    final projectRef = _objectsCollection.doc(project.id);
    if (role.isManager) {
      batch.update(projectRef, {
        'managerIds': FieldValue.arrayRemove([member.uid]),
        'managerNames': FieldValue.arrayRemove([member.displayName]),
        'participantIds': FieldValue.arrayRemove([member.uid]),
      });
    } else if (role.isWorker) {
      batch.update(projectRef, {
        'workerIds': FieldValue.arrayRemove([member.uid]),
        'workerNames': FieldValue.arrayRemove([member.displayName]),
        'participantIds': FieldValue.arrayRemove([member.uid]),
      });
    } else if (role.isClient) {
      batch.update(projectRef, {
        'clientIds': FieldValue.arrayRemove([member.uid]),
        'clientNames': FieldValue.arrayRemove([member.displayName]),
        'participantIds': FieldValue.arrayRemove([member.uid]),
      });
    }
  }

  void _applyWorkerStageUpdates({
    required WriteBatch batch,
    required String? projectId,
    required List<String> stageIds,
    required String userId,
    required String userName,
  }) {
    if (projectId == null || projectId.isEmpty) {
      return;
    }

    for (final stageId in stageIds.where((id) => id.trim().isNotEmpty)) {
      batch.update(_stagesCollection(projectId).doc(stageId), {
        'assignedUserIds': FieldValue.arrayUnion([userId]),
        'assignedUserNames': FieldValue.arrayUnion([userName]),
        'updatedAt': DateTime.now(),
      });
    }
  }

  void _removeWorkerStageUpdates({
    required WriteBatch batch,
    required String projectId,
    required Iterable<String> stageIds,
    required CompanyMember worker,
  }) {
    for (final stageId in stageIds.where((id) => id.trim().isNotEmpty)) {
      batch.update(_stagesCollection(projectId).doc(stageId), {
        'assignedUserIds': FieldValue.arrayRemove([worker.uid]),
        'assignedUserNames': FieldValue.arrayRemove([worker.displayName]),
        'updatedAt': DateTime.now(),
      });
    }
  }

  String? _setTimelineEvent({
    required WriteBatch batch,
    required String? projectId,
    required String stageId,
    required TimelineEventType type,
    required String stageTitle,
    required Map<String, dynamic> metadata,
  }) {
    if (projectId == null || projectId.isEmpty) {
      return null;
    }

    final eventRef = _timelineCollection(projectId).doc();
    batch.set(
      eventRef,
      TimelineEvent(
        id: eventRef.id,
        type: type,
        projectId: projectId,
        stageId: stageId,
        createdAt: DateTime.now(),
        createdBy: _uid,
        actorName: _displayName,
        stageTitle: stageTitle,
        metadata: metadata,
      ).toMap(),
    );
    return eventRef.id;
  }

  /// Добавляет персональное уведомление в batch.
  ///
  /// Важно: уведомление создается вместе с основным изменением и timeline event.
  /// Если batch не пройдет правила безопасности или сеть оборвется, не появится
  /// "висящее" уведомление без реального события.
  void _setNotification({
    required WriteBatch batch,
    required String recipientId,
    required AppNotificationType type,
    required String title,
    required String message,
    required DateTime createdAt,
    String? projectId,
    String? projectTitle,
    String? stageId,
    String? stageTitle,
    String? companyId,
    String? sourceEventId,
    bool includeCurrentUser = false,
  }) {
    final safeRecipientId = recipientId.trim();
    if (safeRecipientId.isEmpty) {
      return;
    }

    final currentUserId = _auth.currentUser?.uid;
    if (!includeCurrentUser && currentUserId == safeRecipientId) {
      return;
    }

    final notificationRef = _notificationsCollection(safeRecipientId).doc();
    final notification = AppNotification(
      id: notificationRef.id,
      userId: safeRecipientId,
      type: type,
      title: title,
      message: message,
      isRead: false,
      createdAt: createdAt,
      projectId: projectId,
      projectTitle: projectTitle,
      stageId: stageId,
      stageTitle: stageTitle,
      companyId: companyId,
      sourceEventId: sourceEventId,
    );

    batch.set(notificationRef, notification.toMap());
  }

  /// Создает одинаковое уведомление для нескольких пользователей.
  ///
  /// Set защищает от дублей, например если один пользователь случайно попал и
  /// в managerIds, и в participantIds.
  void _setNotificationsForRecipients({
    required WriteBatch batch,
    required Iterable<String> recipientIds,
    required AppNotificationType type,
    required String title,
    required String message,
    required DateTime createdAt,
    String? projectId,
    String? projectTitle,
    String? stageId,
    String? stageTitle,
    String? companyId,
    String? sourceEventId,
    bool includeCurrentUser = false,
  }) {
    final seenRecipientIds = <String>{};
    for (final recipientId in recipientIds) {
      final safeRecipientId = recipientId.trim();
      if (safeRecipientId.isEmpty || !seenRecipientIds.add(safeRecipientId)) {
        continue;
      }

      _setNotification(
        batch: batch,
        recipientId: safeRecipientId,
        type: type,
        title: title,
        message: message,
        createdAt: createdAt,
        projectId: projectId,
        projectTitle: projectTitle,
        stageId: stageId,
        stageTitle: stageTitle,
        companyId: companyId,
        sourceEventId: sourceEventId,
        includeCurrentUser: includeCurrentUser,
      );
    }
  }

  Future<void> _writeTimelineEvent({
    required String? projectId,
    required String stageId,
    required TimelineEventType type,
    required String stageTitle,
    required Map<String, dynamic> metadata,
  }) async {
    if (projectId == null || projectId.isEmpty) {
      return;
    }

    final batch = _db.batch();
    _setTimelineEvent(
      batch: batch,
      projectId: projectId,
      stageId: stageId,
      type: type,
      stageTitle: stageTitle,
      metadata: metadata,
    );
    await batch.commit();
  }

  /// Поток объектов ремонта, доступных текущему пользователю.
  ///
  /// В Email/Password Auth основной доступ идет по Firebase UID в `participantIds`.
  ///
  /// В проекте также остается `participantPhones`, потому что исполнителей
  /// по-прежнему добавляют из телефонной книги. Это уже не способ входа,
  /// а бизнес-данные участника объекта.
  Stream<List<Project>> watchProjects({CompanyMember? company}) {
    if (company != null) {
      return _watchCompanyProjects(company);
    }

    final phone = _phone;
    final hasPhone = phone.isNotEmpty;

    // У email/password пользователя телефона обычно нет, поэтому используется
    // participantIds. Ветка participantPhones оставлена для старых данных и
    // будущих сценариев, где phoneNumber может быть заполнен.
    final field = hasPhone ? 'participantPhones' : 'participantIds';
    final value = hasPhone ? phone : _uid;

    return _objectsCollection
        .where(field, arrayContains: value)
        .snapshots()
        .map((snapshot) {
      // Каждый документ Firestore превращаем в модель Project.
      // Если один документ поврежден, _mapDocumentsSafely пропустит его,
      // а список объектов продолжит загружаться.
      final projects = _mapDocumentsSafely(snapshot.docs, Project.fromMap);

      // Сортировка на клиенте оставляет запрос простым и не требует индекса.
      projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return projects;
    });
  }

  Stream<List<Project>> _watchCompanyProjects(CompanyMember company) async* {
    AuthDebug.logUser(
        '[ROLE CHECK] watchProjects currentUser', _auth.currentUser);
    debugPrint(
      '[ROLE CHECK] companyId=${company.companyId}, role=${company.role.firestoreValue}, '
      'uid=${company.uid}, assignedProjectIds=${company.assignedProjectIds}',
    );

    Query<Map<String, dynamic>> query;
    String queryDescription;

    if (company.role.isOwner) {
      query =
          _objectsCollection.where('companyId', isEqualTo: company.companyId);
      queryDescription = 'projects where companyId == ${company.companyId}';
    } else {
      query = _objectsCollection.where(
        'participantIds',
        arrayContains: company.uid,
      );
      queryDescription =
          'projects where participantIds array-contains ${company.uid}; '
          'client-side company filter == ${company.companyId}';
    }

    debugPrint('[PROJECT ACCESS] Loading projects...');
    debugPrint('[PROJECT ACCESS] Query: $queryDescription');
    debugPrint(
      '[PROJECT ACCESS] Rules path: projects/{projectId}; allow read via '
      'ownerId/company owner or participantIds/managerIds/workerIds/clientIds.',
    );

    try {
      await for (final snapshot in query.snapshots()) {
        debugPrint(
          '[PROJECT ACCESS] Projects snapshot received. rawDocs=${snapshot.docs.length}',
        );
        for (final doc in snapshot.docs) {
          final data = doc.data();
          debugPrint(
            '[PROJECT ACCESS] Doc allowed: ${doc.reference.path}; '
            'companyId=${data['companyId']}; '
            'managerIds=${data['managerIds']}; '
            'workerIds=${data['workerIds']}; '
            'clientIds=${data['clientIds']}; '
            'participantIds=${data['participantIds']}',
          );
        }

        final projects = _mapDocumentsSafely(snapshot.docs, Project.fromMap)
            .where((project) {
          if (company.role.isOwner) {
            return true;
          }

          return project.companyId == company.companyId;
        }).toList();

        projects.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        debugPrint(
          '[PROJECT ACCESS] Projects after role/company filter=${projects.length}',
        );
        yield projects;
      }
    } on FirebaseException catch (error, stackTrace) {
      debugPrint('[PROJECT ACCESS ERROR]');
      debugPrint('role=${company.role.firestoreValue}');
      debugPrint('uid=${company.uid}');
      debugPrint('companyId=${company.companyId}');
      debugPrint('code=${error.code}');
      debugPrint('message=${error.message}');
      debugPrint('query=$queryDescription');
      debugPrintStack(
        label: '[PROJECT ACCESS ERROR] Project list stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    } catch (error, stackTrace) {
      debugPrint('[PROJECT ACCESS ERROR]');
      debugPrint('role=${company.role.firestoreValue}');
      debugPrint('uid=${company.uid}');
      debugPrint('companyId=${company.companyId}');
      debugPrint('code=unexpected');
      debugPrint('message=$error');
      debugPrint('query=$queryDescription');
      debugPrintStack(
        label: '[PROJECT ACCESS ERROR] Project list stack trace',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Создает новый объект ремонта и сразу добавляет владельца в участники.
  Future<Project> createProject({
    required String title,
    required String address,
    required String description,
    required ProjectStatus status,
    CompanyMember? company,
  }) async {
    final user = _auth.currentUser;
    final firebaseAuthUser = FirebaseAuth.instance.currentUser;
    final emulatorHost = defaultTargetPlatform == TargetPlatform.android
        ? AppConfig.androidEmulatorHost
        : AppConfig.loopbackHost;

    debugPrint('[ProjectRepository.createProject] Start.');
    debugPrint(
      '[ProjectRepository.createProject] USE_FIREBASE_EMULATORS='
      '${AppConfig.useFirebaseEmulators}',
    );
    debugPrint(
      '[ProjectRepository.createProject] Firestore app projectId='
      '${_db.app.options.projectId}',
    );
    debugPrint(
      '[ProjectRepository.createProject] Expected Firestore emulator '
      'host=$emulatorHost port=${AppConfig.firestorePort}',
    );
    FirebaseBootstrap.logEmulatorState('ProjectRepository.createProject');
    debugPrint(
      '[ProjectRepository.createProject] _auth.currentUser='
      '${AuthDebug.describeUser(user)}',
    );
    debugPrint(
      '[ProjectRepository.createProject] FirebaseAuth.instance.currentUser='
      '${AuthDebug.describeUser(firebaseAuthUser)}',
    );

    if (user == null) {
      debugPrint(
        '[ProjectRepository.createProject] Abort: FirebaseAuth.currentUser is null.',
      );
      throw const UserNotAuthenticatedException();
    }

    final ownerId = user.uid;
    final ownerName = _displayName;
    final projectRef = _objectsCollection.doc();
    final now = DateTime.now();
    final ownerPhone = _phone;
    debugPrint(
      '[ProjectRepository.createProject] Firestore write path=${projectRef.path}',
    );

    // При Email/Password Auth ownerPhone обычно пустой. Это нормально: доступ
    // владельца работает через UID в participantIds.
    if (company != null && !company.canCreateProject) {
      throw Exception('У вас нет прав на создание объектов в этой компании.');
    }

    final managerIds = <String>[
      if (company?.role.isManager == true) user.uid,
    ];
    final managerNames = <String>[
      if (company?.role.isManager == true) ownerName,
    ];
    final project = Project(
      id: projectRef.id,
      title: title,
      address: address,
      description: description,
      status: status,
      ownerId: ownerId,
      participantIds: [
        ...{
          ownerId,
          ...managerIds,
        },
      ],
      participantPhones: [
        if (ownerPhone.isNotEmpty) ownerPhone,
      ],
      createdAt: now,
      companyId: company?.companyId,
      companyName: company?.companyName,
      managerIds: managerIds,
      managerNames: managerNames,
    );

    // Transaction гарантирует, что объект и участник-владелец создаются вместе.
    // Если одна операция упадет, Firestore откатит весь набор изменений.
    try {
      final validatedUser = await AuthDebug.validateCurrentUserToken(
        source: 'ProjectRepository.createProject',
        forceRefresh: true,
      );

      if (validatedUser == null) {
        debugPrint(
          '[ProjectRepository.createProject] Abort: Firebase user token is not valid.',
        );
        throw const UserNotAuthenticatedException();
      }

      if (validatedUser.uid != ownerId) {
        debugPrint(
          '[ProjectRepository.createProject] Auth user changed during token '
          'validation. originalUid=$ownerId validatedUid=${validatedUser.uid}',
        );
      }

      debugPrint(
        '[ProjectRepository.createProject] Running transaction for project '
        'and owner participant.',
      );
      await _db.runTransaction((transaction) async {
        transaction.set(projectRef, project.toMap());
        transaction.set(projectRef.collection('participants').doc(ownerId), {
          'name': ownerName,
          'phoneNumber': ownerPhone,
          'role': company?.role.firestoreValue ?? 'owner',
        });
        if (company?.role.isManager == true) {
          transaction.update(
            _companyMembersCollection(company!.companyId).doc(company.uid),
            {
              'assignedProjectIds': FieldValue.arrayUnion([projectRef.id]),
            },
          );
        }
      });
      debugPrint(
        '[ProjectRepository.createProject] Project document and owner '
        'participant saved.',
      );

      debugPrint(
        '[ProjectRepository.createProject] Success. projectId=${project.id}',
      );
      return project;
    } on FirebaseException catch (error, stackTrace) {
      debugPrint(
        '[ProjectRepository.createProject] FirebaseException. '
        'plugin=${error.plugin} code=${error.code} message=${error.message}',
      );
      debugPrintStack(stackTrace: stackTrace);
      final signedOut = await AuthDebug.signOutIfInvalidRefreshToken(
        error,
        source: 'ProjectRepository.createProject',
      );
      if (signedOut || error.code == 'unauthenticated') {
        throw const UserNotAuthenticatedException();
      }
      rethrow;
    } catch (error, stackTrace) {
      debugPrint(
        '[ProjectRepository.createProject] Unexpected error: $error',
      );
      debugPrintStack(stackTrace: stackTrace);
      final signedOut = await AuthDebug.signOutIfInvalidRefreshToken(
        error,
        source: 'ProjectRepository.createProject',
      );
      if (signedOut) {
        throw const UserNotAuthenticatedException();
      }
      rethrow;
    }
  }

  /// Обновляет основные поля объекта ремонта.
  ///
  /// UI для редактирования можно добавить позже, но метод уже есть в
  /// репозитории: так update-операция централизована и не размазывается
  /// по экранам.
  Future<void> updateProject(Project project) async {
    try {
      await _objectsCollection.doc(project.id).update(project.toMap());
    } catch (error) {
      throw Exception('Не удалось обновить объект ${project.id}: $error');
    }
  }

  /// Обновляет только название и адрес объекта.
  ///
  /// В отличие от [updateProject] (который перезаписывает весь документ
  /// целиком из объекта Project в памяти экрана), здесь уходит частичный
  /// .update() только с изменёнными полями. Это важно: пока пользователь
  /// редактирует форму, кто-то другой может параллельно изменить
  /// managerIds/participantIds объекта, и полная перезапись случайно
  /// затёрла бы эти изменения устаревшими данными.
  Future<void> updateProjectDetails({
    required String projectId,
    required String title,
    required String address,
  }) async {
    try {
      await _objectsCollection.doc(projectId).update({
        'title': title,
        'address': address,
      });
    } catch (error) {
      throw Exception('Не удалось обновить объект $projectId: $error');
    }
  }

  /// Следит за одним объектом ремонта.
  ///
  /// Экран карточки использует этот stream, чтобы статус и summary-прогресс
  /// обновлялись сразу после действий пользователя, без ручной навигации назад.
  Stream<Project?> watchProject(String projectId) {
    return _objectsCollection.doc(projectId).snapshots().map((doc) {
      final data = doc.data();
      if (!doc.exists || data == null) {
        return null;
      }

      return Project.fromMap(doc.id, data);
    });
  }

  /// Одноразово читает объект ремонта по id.
  ///
  /// Экран уведомлений использует этот метод при переходе из уведомления:
  /// сначала отмечаем уведомление прочитанным, затем читаем актуальный Project
  /// и открываем уже существующий ProjectDetailScreen.
  Future<Project?> getProjectById(String projectId) async {
    final safeProjectId = projectId.trim();
    if (safeProjectId.isEmpty) {
      return null;
    }

    final doc = await _objectsCollection.doc(safeProjectId).get();
    final data = doc.data();
    if (!doc.exists || data == null) {
      return null;
    }

    return Project.fromMap(doc.id, data);
  }

  /// Меняет статус всего объекта ремонта.
  ///
  /// Это не статус этапа. Прораб может вручную поставить объект на паузу,
  /// вернуть в работу или отметить как завершенный.
  Future<void> updateProjectStatus({
    required String projectId,
    required ProjectStatus status,
  }) async {
    try {
      final project = await getProjectById(projectId);
      if (project == null) {
        throw Exception('Объект не найден.');
      }

      final now = DateTime.now();
      final projectRef = _objectsCollection.doc(projectId);
      final batch = _db.batch();
      batch.update(projectRef, {
        'status': status.firestoreValue,
      });

      final timelineType = switch (status) {
        ProjectStatus.directorReview =>
          TimelineEventType.projectSentToDirectorReview,
        ProjectStatus.clientReview =>
          TimelineEventType.projectSentToClientReview,
        ProjectStatus.closed => TimelineEventType.projectClosed,
        ProjectStatus.inProgress || ProjectStatus.paused => null,
      };

      String? eventId;
      if (timelineType != null) {
        eventId = _setTimelineEvent(
          batch: batch,
          projectId: project.id,
          stageId: '',
          type: timelineType,
          stageTitle: '',
          metadata: {
            'oldStatus': project.status.firestoreValue,
            'newStatus': status.firestoreValue,
            'projectTitle': project.title,
          },
        );
      }

      if (status == ProjectStatus.directorReview) {
        _setNotification(
          batch: batch,
          recipientId: project.ownerId,
          type: AppNotificationType.projectSentToDirectorReview,
          title: 'Объект отправлен на проверку',
          message: 'Объект "${project.title}" ожидает проверки директора.',
          createdAt: now,
          projectId: project.id,
          projectTitle: project.title,
          companyId: project.companyId,
          sourceEventId: eventId,
        );
      } else if (status == ProjectStatus.clientReview) {
        _setNotificationsForRecipients(
          batch: batch,
          recipientIds: project.clientIds,
          type: AppNotificationType.projectSentToClientReview,
          title: 'Объект готов к приёмке',
          message: 'Объект "${project.title}" отправлен заказчику на приёмку.',
          createdAt: now,
          projectId: project.id,
          projectTitle: project.title,
          companyId: project.companyId,
          sourceEventId: eventId,
        );
      } else if (status == ProjectStatus.closed) {
        _setNotificationsForRecipients(
          batch: batch,
          recipientIds: project.clientIds,
          type: AppNotificationType.projectClosed,
          title: 'Объект успешно завершён',
          message: 'Объект "${project.title}" закрыт.',
          createdAt: now,
          projectId: project.id,
          projectTitle: project.title,
          companyId: project.companyId,
          sourceEventId: eventId,
          includeCurrentUser: true,
        );
      }

      await batch.commit();
    } catch (error) {
      throw Exception('Не удалось изменить статус объекта $projectId: $error');
    }
  }

  /// Удаляет объект ремонта.
  ///
  /// Важно: Firestore не удаляет subcollections автоматически. Для MVP метод
  /// удаляет только основной документ. При росте проекта лучше добавить Cloud
  /// Function или backend job для каскадного удаления участников, сообщений,
  /// расходов, фото и файлов Storage.
  Future<void> deleteProject(Project project) async {
    if (!project.status.canBeDeleted) {
      throw StateError(
        'Удалять можно только завершенные объекты. '
        'Сначала измените статус объекта на "Завершен".',
      );
    }

    try {
      await _deleteProjectTree(project.id);
    } catch (error) {
      throw Exception('Не удалось удалить объект ${project.id}: $error');
    }
  }

  /// Удаляет несколько завершенных объектов подряд.
  Future<void> deleteProjects(List<Project> projects) async {
    final blockedProjects = projects
        .where((project) => !project.status.canBeDeleted)
        .map((project) => project.title)
        .toList();

    if (blockedProjects.isNotEmpty) {
      throw StateError(
        'Нельзя удалить объект в работе или на паузе: '
        '${blockedProjects.join(', ')}',
      );
    }

    for (final project in projects) {
      await _deleteProjectTree(project.id);
    }
  }

  /// Удаляет документ проекта и известные подколлекции.
  ///
  /// Firestore не удаляет subcollections автоматически. Для MVP чистим
  /// известные коллекции клиента: stages, timeline, participants, messages,
  /// expenses и legacy photos. Файлы Storage лучше удалять отдельной backend
  /// задачей, потому что клиент не должен долго обходить все storage paths.
  Future<void> _deleteProjectTree(String projectId) async {
    final projectRef = _objectsCollection.doc(projectId);
    final stagesSnapshot = await projectRef.collection('stages').get();

    for (final stageDoc in stagesSnapshot.docs) {
      await _deleteCollection(stageDoc.reference.collection('photos'));
    }

    await _deleteCollection(projectRef.collection('stages'));
    await _deleteCollection(projectRef.collection('timeline'));
    await _deleteCollection(projectRef.collection('participants'));
    await _deleteCollection(projectRef.collection('messages'));
    await _deleteCollection(projectRef.collection('expenses'));
    await _deleteCollection(projectRef.collection('photos'));
    await projectRef.delete();
  }

  /// Удаляет документы коллекции небольшими пачками.
  ///
  /// Ограничение в 400 документов оставляет запас до лимита batch write 500.
  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    const batchSize = 400;

    while (true) {
      final snapshot = await collection.limit(batchSize).get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = _db.batch();

      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }

      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        return;
      }
    }
  }

  /// Следит за этапами конкретного объекта.
  ///
  /// Сортировку делаем на клиенте. Так экран продолжит работать, даже если
  /// какой-то dev-документ этапа был создан без sortOrder.
  Stream<List<RepairStage>> watchStages(String projectId) {
    return _objectsCollection
        .doc(projectId)
        .collection('stages')
        .snapshots()
        .map((snapshot) {
      final stages = _mapDocumentsSafely(snapshot.docs, RepairStage.fromMap);
      stages.sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) {
          return byOrder;
        }
        return a.name.compareTo(b.name);
      });
      return stages;
    });
  }

  /// Создает дефолтные этапы, если у объекта пока нет ни одного этапа.
  ///
  /// Метод безопасно вызывать при каждом открытии экрана фото:
  /// - если этапы уже есть, он ничего не меняет;
  /// - если этапов нет, batch-запись создаст базовый набор одним запросом.
  Future<void> ensureDefaultStages(String projectId) async {
    final stagesRef = _objectsCollection.doc(projectId).collection('stages');
    final existing = await stagesRef.limit(1).get();

    if (existing.docs.isNotEmpty) {
      return;
    }

    final batch = _db.batch();

    for (final stage in _defaultStages) {
      batch.set(stagesRef.doc(stage.id), stage.toMap());
    }

    await batch.commit();
  }

  /// Создает пользовательский этап вручную.
  ///
  /// UI передает только бизнес-поля. Репозиторий сам выбирает document id,
  /// дату создания и порядок сортировки.
  Future<RepairStage> createStage({
    required String projectId,
    required String name,
    required int color,
    required String icon,
  }) async {
    final stagesRef = _objectsCollection.doc(projectId).collection('stages');
    final stageRef = stagesRef.doc();
    final snapshot = await stagesRef.get();
    final stages = _mapDocumentsSafely(snapshot.docs, RepairStage.fromMap);

    final maxSortOrder = stages
        .map((stage) => stage.sortOrder)
        .fold<int>(0, (max, value) => value > max ? value : max);

    final stage = RepairStage(
      id: stageRef.id,
      name: name,
      color: color,
      icon: icon,
      sortOrder: maxSortOrder + 10,
      createdAt: DateTime.now(),
    );

    await stageRef.set(stage.toMap());
    await _recalculateProjectProgressSummary(projectId);
    return stage;
  }

  /// Редактирует существующий этап.
  ///
  /// Фото не нужно обновлять: они хранят stageId, поэтому после изменения
  /// названия/цвета/иконки все карточки автоматически покажут новый этап.
  Future<void> updateStage(String projectId, RepairStage stage) async {
    await _objectsCollection
        .doc(projectId)
        .collection('stages')
        .doc(stage.id)
        .update(stage.toMap());
    await _recalculateProjectProgressSummary(projectId);
  }

  /// Удаляет этап.
  ///
  /// Если у фото останется stageId удаленного этапа, UI покажет fallback
  /// "Этап удален". Так мы не теряем фотографии и не делаем опасное каскадное
  /// удаление без явного подтверждения пользователя.
  Future<void> deleteStage(String projectId, String stageId) async {
    await deleteProductionStages(projectId: projectId, stageIds: [stageId]);
  }

  /// Пересчитывает summary-прогресс объекта по production-этапам.
  ///
  /// Этот метод вызывается только при изменении этапов: создании этапа,
  /// изменении статуса или массовом bootstrap. Карточка объекта потом читает
  /// уже готовые поля из Project и не делает тяжелый запрос в stages.
  Future<void> _recalculateProjectProgressSummary(String projectId) async {
    final snapshot = await _stagesCollection(projectId).get();
    final stages = _mapDocumentsSafely(snapshot.docs, Stage.fromMap);
    final totalStages = stages.length;
    final completedStages =
        stages.where((stage) => stage.status == StageStatus.completed).length;
    final progressPercent = _calculateProjectProgressPercent(
      totalStages: totalStages,
      completedStages: completedStages,
    );

    await _projectsCollection.doc(projectId).update({
      'totalStages': totalStages,
      'completedStages': completedStages,
      'progressPercent': progressPercent,
    });
  }

  int _calculateProjectProgressPercent({
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

  /// Следит за production-этапами проекта.
  ///
  /// Firestore-путь:
  /// projects/{projectId}/stages/{stageId}
  ///
  /// Сортируем на клиенте, чтобы не требовать отдельный индекс для MVP.
  Stream<List<Stage>> watchProductionStages(String projectId) {
    return _stagesCollection(projectId).snapshots().map((snapshot) {
      final stages = _mapDocumentsSafely(snapshot.docs, Stage.fromMap);
      stages.sort((a, b) {
        final byOrder = a.orderIndex.compareTo(b.orderIndex);
        if (byOrder != 0) {
          return byOrder;
        }
        return a.title.compareTo(b.title);
      });
      return stages;
    });
  }

  /// One-time read of project stages for business checks.
  ///
  /// UI uses this before setting the whole project to `completed`: if at least
  /// one stage is not completed, the user must explicitly confirm forced
  /// completion. Empty projects are considered safe to complete.
  Future<List<Stage>> getProductionStages(String projectId) async {
    final snapshot = await _stagesCollection(projectId).get();
    final stages = _mapDocumentsSafely(snapshot.docs, Stage.fromMap);
    stages.sort((a, b) {
      final byOrder = a.orderIndex.compareTo(b.orderIndex);
      if (byOrder != 0) {
        return byOrder;
      }
      return a.title.compareTo(b.title);
    });
    return stages;
  }

  /// Returns true when the project still has at least one unfinished stage.
  ///
  /// If there are zero stages, the method returns false: there is nothing to
  /// block, and the object can be completed without division or empty-list
  /// errors.
  Future<bool> hasIncompleteProductionStages(String projectId) async {
    final stages = await getProductionStages(projectId);
    return stages.any((stage) => stage.status != StageStatus.completed);
  }

  /// Следит за одним production-этапом.
  ///
  /// Экран деталей использует этот stream, чтобы счетчики чеков/фото и статус
  /// обновлялись сразу после batch-записей.
  Stream<Stage?> watchProductionStage(String projectId, String stageId) {
    return _stagesCollection(projectId).doc(stageId).snapshots().map((doc) {
      if (!doc.exists) {
        return null;
      }

      final data = doc.data();
      if (data == null) {
        return null;
      }

      return Stage.fromMap(doc.id, data);
    });
  }

  /// Создает production-шаблон этапов, если у проекта еще нет этапов.
  Future<void> ensureDefaultProductionStages(String projectId) async {
    final stagesRef = _stagesCollection(projectId);
    debugPrint(
      '[ProjectRepository.ensureDefaultProductionStages] Checking path=${stagesRef.path}',
    );
    final existing = await stagesRef.limit(1).get();
    debugPrint(
      '[ProjectRepository.ensureDefaultProductionStages] Existing stage count preview=${existing.docs.length}',
    );

    if (existing.docs.isNotEmpty) {
      debugPrint(
        '[ProjectRepository.ensureDefaultProductionStages] Stages already exist. Skip bootstrap.',
      );
      return;
    }

    final batch = _db.batch();
    final defaultStages = _defaultProductionStages(projectId);

    for (final stage in defaultStages) {
      batch.set(stagesRef.doc(stage.id), stage.toMap());
    }

    debugPrint(
      '[ProjectRepository.ensureDefaultProductionStages] Creating ${defaultStages.length} default stages.',
    );
    await batch.commit();
    await _recalculateProjectProgressSummary(projectId);
    debugPrint(
      '[ProjectRepository.ensureDefaultProductionStages] Default stages created.',
    );
  }

  /// Создает пользовательский production-этап.
  Future<Stage> createProductionStage({
    required String projectId,
    required String title,
    StageType type = StageType.custom,
  }) async {
    final stagesRef = _stagesCollection(projectId);
    final stageRef = stagesRef.doc();
    final snapshot = await stagesRef.get();
    final stages = _mapDocumentsSafely(snapshot.docs, Stage.fromMap);
    final now = DateTime.now();

    final maxOrderIndex = stages
        .map((stage) => stage.orderIndex)
        .fold<int>(0, (max, value) => value > max ? value : max);

    final stage = Stage(
      id: stageRef.id,
      projectId: projectId,
      title: title,
      type: type,
      status: StageStatus.notStarted,
      progress: 0,
      assignedUserIds: const [],
      showExecutorsToClient: true,
      photosCount: 0,
      receiptsCount: 0,
      receiptsTotal: 0,
      coverPhotoUrl: null,
      completedAt: null,
      createdAt: now,
      updatedAt: now,
      createdBy: _uid,
      orderIndex: maxOrderIndex + 10,
    );

    await stageRef.set(stage.toMap());
    await _recalculateProjectProgressSummary(projectId);
    return stage;
  }

  /// Обновляет business-поля production-этапа.
  Future<void> updateProductionStage(Stage stage) async {
    await _stagesCollection(stage.projectId).doc(stage.id).update({
      ...stage.toMap(),
      'updatedAt': DateTime.now(),
    });
    await _recalculateProjectProgressSummary(stage.projectId);
  }

  /// Переименовывает production-этап.
  ///
  /// В отличие от [updateProductionStage] (полная перезапись документа +
  /// пересчёт прогресса объекта), здесь только частичный .update() с полем
  /// title — простое переименование не влияет на прогресс, поэтому
  /// пересчитывать его незачем.
  Future<void> renameProductionStage({
    required String projectId,
    required String stageId,
    required String title,
  }) async {
    await _stagesCollection(projectId).doc(stageId).update({
      'title': title,
      'updatedAt': DateTime.now(),
    });
  }

  /// Меняет статус этапа и автоматически пишет TimelineEvent.
  ///
  /// Важно: completedAt передается вручную из UI. Мы не ставим DateTime.now()
  /// автоматически, потому что пользователь может завершать этап задним числом.
  Future<void> updateProductionStageStatus({
    required Stage stage,
    required StageStatus status,
    DateTime? completedAt,
  }) async {
    if (status == StageStatus.completed && completedAt == null) {
      throw ArgumentError('Для завершения этапа нужно выбрать дату.');
    }

    final now = DateTime.now();
    final stageRef = _stagesCollection(stage.projectId).doc(stage.id);
    final eventRef = _timelineCollection(stage.projectId).doc();
    final oldStatus = stage.status;
    final project = await getProjectById(stage.projectId);

    final updateData = <String, dynamic>{
      'status': status.firestoreValue,
      'progress': _progressForStatus(status),
      'updatedAt': now,
    };

    if (status == StageStatus.completed) {
      updateData['completedAt'] = completedAt;
    } else {
      updateData['completedAt'] = FieldValue.delete();
    }

    final event = TimelineEvent(
      id: eventRef.id,
      type: _timelineTypeForStatus(status),
      projectId: stage.projectId,
      stageId: stage.id,
      createdAt: now,
      createdBy: _uid,
      actorName: _displayName,
      stageTitle: stage.title,
      metadata: {
        'oldStatus': oldStatus.firestoreValue,
        'newStatus': status.firestoreValue,
        if (completedAt != null) 'completedAt': completedAt.toIso8601String(),
      },
    );

    final batch = _db.batch();
    batch.update(stageRef, updateData);
    batch.set(eventRef, event.toMap());

    if (status == StageStatus.review && project != null) {
      _setNotificationsForRecipients(
        batch: batch,
        recipientIds: project.managerIds,
        type: AppNotificationType.stageSentToReview,
        title: 'Этап "${stage.title}" отправлен на проверку',
        message: 'Объект: ${project.title}',
        createdAt: now,
        projectId: project.id,
        projectTitle: project.title,
        stageId: stage.id,
        stageTitle: stage.title,
        companyId: project.companyId,
        sourceEventId: eventRef.id,
      );
    } else if (status == StageStatus.completed) {
      _setNotificationsForRecipients(
        batch: batch,
        recipientIds: stage.assignedUserIds,
        type: AppNotificationType.stageApproved,
        title: 'Этап принят',
        message: 'Этап "${stage.title}" принят.',
        createdAt: now,
        projectId: stage.projectId,
        projectTitle: project?.title,
        stageId: stage.id,
        stageTitle: stage.title,
        companyId: project?.companyId,
        sourceEventId: eventRef.id,
      );
    } else if (status == StageStatus.problem) {
      _setNotificationsForRecipients(
        batch: batch,
        recipientIds: stage.assignedUserIds,
        type: AppNotificationType.stageReturned,
        title: 'Этап возвращён на доработку',
        message: 'Этап "${stage.title}" требует исправлений.',
        createdAt: now,
        projectId: stage.projectId,
        projectTitle: project?.title,
        stageId: stage.id,
        stageTitle: stage.title,
        companyId: project?.companyId,
        sourceEventId: eventRef.id,
      );
    }
    await batch.commit();
    await _recalculateProjectProgressSummary(stage.projectId);
  }

  /// Deletes one production stage with its nested data.
  ///
  /// This method is used by StageDetailScreen. It delegates to the bulk method
  /// so single and multi-delete always follow the same rules.
  Future<void> deleteProductionStage(Stage stage) async {
    await deleteProductionStages(
      projectId: stage.projectId,
      stageIds: [stage.id],
    );
  }

  /// Deletes several production stages and recalculates project progress once.
  ///
  /// Firestore does not delete subcollections automatically. For every stage we
  /// therefore remove:
  /// - Storage files referenced by Photo.storagePath;
  /// - documents in `projects/{projectId}/stages/{stageId}/photos`;
  /// - old timeline events that point to this stage;
  /// - the stage document itself.
  ///
  /// After cleanup we create a fresh `stage_deleted` timeline event. Keeping a
  /// deletion event is useful for future push notifications and audit history,
  /// while removing older stage events avoids dangling timeline records for a
  /// stage that no longer exists.
  Future<void> deleteProductionStages({
    required String projectId,
    required Iterable<String> stageIds,
  }) async {
    final uniqueStageIds =
        stageIds.where((stageId) => stageId.trim().isNotEmpty).toSet().toList();

    if (uniqueStageIds.isEmpty) {
      return;
    }

    for (final stageId in uniqueStageIds) {
      await _deleteProductionStageTree(
        projectId: projectId,
        stageId: stageId,
      );
    }

    await _recalculateProjectProgressSummary(projectId);
  }

  Future<void> _deleteProductionStageTree({
    required String projectId,
    required String stageId,
  }) async {
    final stageRef = _stagesCollection(projectId).doc(stageId);
    final stageSnapshot = await stageRef.get();
    final stageData = stageSnapshot.data();

    if (!stageSnapshot.exists || stageData == null) {
      return;
    }

    final stage = Stage.fromMap(stageSnapshot.id, stageData);
    final photosCollection = stageRef.collection('photos');
    final photosSnapshot = await photosCollection.get();

    for (final photoDoc in photosSnapshot.docs) {
      try {
        final photo = Photo.fromMap(photoDoc.id, photoDoc.data());
        await StorageService.instance.deleteByPath(
          photo.storagePath,
          kind: photo.isReceipt ? 'receipt' : 'photo',
        );
      } catch (error) {
        throw Exception(
          'Не удалось удалить файл Storage для ${photoDoc.reference.path}: '
          '$error',
        );
      }
    }

    await _deleteCollection(photosCollection);
    await _deleteTimelineEventsForStage(projectId: projectId, stageId: stageId);

    final now = DateTime.now();
    final eventRef = _timelineCollection(projectId).doc();
    final event = TimelineEvent(
      id: eventRef.id,
      type: TimelineEventType.stageDeleted,
      projectId: projectId,
      stageId: stage.id,
      createdAt: now,
      createdBy: _uid,
      actorName: _displayName,
      stageTitle: stage.title,
      metadata: {
        'deletedStageStatus': stage.status.firestoreValue,
        'photosDeleted': photosSnapshot.docs.length,
        'receiptsCount': stage.receiptsCount,
        'receiptsTotal': stage.receiptsTotal,
      },
    );

    final batch = _db.batch();
    batch.delete(stageRef);
    batch.set(eventRef, event.toMap());
    await batch.commit();
  }

  Future<void> _deleteTimelineEventsForStage({
    required String projectId,
    required String stageId,
  }) async {
    const batchSize = 400;
    final collection = _timelineCollection(projectId);

    while (true) {
      final snapshot = await collection
          .where('stageId', isEqualTo: stageId)
          .limit(batchSize)
          .get();

      if (snapshot.docs.isEmpty) {
        return;
      }

      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      if (snapshot.docs.length < batchSize) {
        return;
      }
    }
  }

  /// Назначает исполнителя на этап и пишет событие worker_assigned.
  Future<void> assignWorkerToStage({
    required Stage stage,
    required String workerUserId,
  }) async {
    final now = DateTime.now();
    final stageRef = _stagesCollection(stage.projectId).doc(stage.id);
    final eventRef = _timelineCollection(stage.projectId).doc();
    final project = await getProjectById(stage.projectId);

    final event = TimelineEvent(
      id: eventRef.id,
      type: TimelineEventType.workerAssigned,
      projectId: stage.projectId,
      stageId: stage.id,
      createdAt: now,
      createdBy: _uid,
      actorName: _displayName,
      stageTitle: stage.title,
      metadata: {'workerUserId': workerUserId},
    );

    final batch = _db.batch();
    batch.update(stageRef, {
      'assignedUserIds': FieldValue.arrayUnion([workerUserId]),
      'updatedAt': now,
    });
    batch.set(eventRef, event.toMap());
    if (project != null) {
      _setNotificationsForRecipients(
        batch: batch,
        recipientIds: project.managerIds,
        type: AppNotificationType.workerAssignedToStage,
        title: 'Назначен новый подрядчик',
        message: 'На этап "${stage.title}" назначен подрядчик.',
        createdAt: now,
        projectId: project.id,
        projectTitle: project.title,
        stageId: stage.id,
        stageTitle: stage.title,
        companyId: project.companyId,
        sourceEventId: eventRef.id,
      );
      _setNotification(
        batch: batch,
        recipientId: workerUserId,
        type: AppNotificationType.workerAssignedToStage,
        title: 'Вам назначен новый этап',
        message: 'Этап "${stage.title}" в объекте "${project.title}".',
        createdAt: now,
        projectId: project.id,
        projectTitle: project.title,
        stageId: stage.id,
        stageTitle: stage.title,
        companyId: project.companyId,
        sourceEventId: eventRef.id,
        includeCurrentUser: true,
      );
    }
    await batch.commit();
  }

  /// Убирает исполнителя с этапа и пишет событие worker_removed.
  Future<void> removeWorkerFromStage({
    required Stage stage,
    required String workerUserId,
  }) async {
    final now = DateTime.now();
    final stageRef = _stagesCollection(stage.projectId).doc(stage.id);
    final eventRef = _timelineCollection(stage.projectId).doc();

    final event = TimelineEvent(
      id: eventRef.id,
      type: TimelineEventType.workerRemoved,
      projectId: stage.projectId,
      stageId: stage.id,
      createdAt: now,
      createdBy: _uid,
      actorName: _displayName,
      stageTitle: stage.title,
      metadata: {'workerUserId': workerUserId},
    );

    final batch = _db.batch();
    batch.update(stageRef, {
      'assignedUserIds': FieldValue.arrayRemove([workerUserId]),
      'updatedAt': now,
    });
    batch.set(eventRef, event.toMap());
    await batch.commit();
  }

  Stream<List<CompanyMember>> watchProjectMembers(Project project) {
    final companyId = project.companyId;
    if (companyId == null || companyId.isEmpty) {
      return Stream<List<CompanyMember>>.value(const []);
    }

    return _companyMembersCollection(companyId)
        .where('active', isEqualTo: true)
        .snapshots()
        .map((snapshot) {
      final members = _mapDocumentsSafely(
        snapshot.docs,
        CompanyMember.fromMap,
      ).where((member) {
        if (member.uid == project.ownerId) {
          return true;
        }
        if (member.role.isManager) {
          return project.managerIds.contains(member.uid);
        }
        if (member.role.isWorker) {
          return project.workerIds.contains(member.uid) ||
              project.participantIds.contains(member.uid);
        }
        if (member.role.isClient) {
          return project.clientIds.contains(member.uid) ||
              project.participantIds.contains(member.uid);
        }
        return false;
      }).toList();

      members.sort((a, b) {
        final byRole = a.role.index.compareTo(b.role.index);
        if (byRole != 0) {
          return byRole;
        }
        return a.displayName.compareTo(b.displayName);
      });
      return members;
    });
  }

  Future<void> assignWorkerToProjectStages({
    required Project project,
    required CompanyMember worker,
    required List<Stage> stages,
  }) async {
    if (!worker.role.isWorker) {
      throw ArgumentError('Назначать на этапы можно только подрядчика.');
    }

    if (stages.isEmpty) {
      throw ArgumentError('Выберите хотя бы один этап.');
    }

    final stageIds = stages.map((stage) => stage.id).toList(growable: false);
    final batch = _db.batch();
    _applyProjectAccessUpdates(
      batch: batch,
      projectId: project.id,
      role: CompanyRole.worker,
      userId: worker.uid,
      userName: worker.displayName,
    );
    _applyWorkerStageUpdates(
      batch: batch,
      projectId: project.id,
      stageIds: stageIds,
      userId: worker.uid,
      userName: worker.displayName,
    );

    final eventId = _setTimelineEvent(
      batch: batch,
      projectId: project.id,
      stageId: '',
      type: TimelineEventType.workerAssignedToStage,
      stageTitle: '',
      metadata: {
        'userId': worker.uid,
        'userEmail': worker.email,
        'role': worker.role.firestoreValue,
        'projectId': project.id,
        'stageIds': stageIds,
        'stageTitles': stages.map((stage) => stage.title).toList(),
      },
    );
    final stageTitles = stages.map((stage) => stage.title).join(', ');
    _setNotificationsForRecipients(
      batch: batch,
      recipientIds: project.managerIds,
      type: AppNotificationType.workerAssignedToStage,
      title: 'Назначен новый подрядчик',
      message: '${worker.displayName} назначен на этапы: $stageTitles.',
      createdAt: DateTime.now(),
      projectId: project.id,
      projectTitle: project.title,
      companyId: project.companyId,
      sourceEventId: eventId,
    );
    _setNotification(
      batch: batch,
      recipientId: worker.uid,
      type: AppNotificationType.workerAssignedToStage,
      title: 'Вам назначен новый этап',
      message: 'Объект "${project.title}": $stageTitles.',
      createdAt: DateTime.now(),
      projectId: project.id,
      projectTitle: project.title,
      companyId: project.companyId,
      sourceEventId: eventId,
      includeCurrentUser: true,
    );
    await batch.commit();
  }

  Future<void> removeWorkerFromProjectStages({
    required Project project,
    required CompanyMember worker,
    required List<Stage> stages,
  }) async {
    if (!worker.role.isWorker) {
      throw ArgumentError('С этапов можно снять только подрядчика.');
    }

    if (stages.isEmpty) {
      throw ArgumentError('Выберите хотя бы один этап.');
    }

    final stageIds = stages.map((stage) => stage.id).toList(growable: false);
    final batch = _db.batch();
    _removeWorkerStageUpdates(
      batch: batch,
      projectId: project.id,
      stageIds: stageIds,
      worker: worker,
    );

    _setTimelineEvent(
      batch: batch,
      projectId: project.id,
      stageId: '',
      type: TimelineEventType.workerRemovedFromStage,
      stageTitle: '',
      metadata: {
        'userId': worker.uid,
        'userEmail': worker.email,
        'role': worker.role.firestoreValue,
        'projectId': project.id,
        'stageIds': stageIds,
        'stageTitles': stages.map((stage) => stage.title).toList(),
      },
    );
    await batch.commit();
  }

  Future<void> removeProjectParticipant({
    required CompanyMember actor,
    required Project project,
    required CompanyMember member,
  }) async {
    if (!actor.role.isOwner && !actor.role.isManager) {
      throw Exception('У вас нет прав удалять участников объекта.');
    }

    if (member.role.isOwner) {
      throw Exception('Директора нельзя удалить из объекта.');
    }

    if (member.role.isManager && !actor.role.isOwner) {
      throw Exception('Только директор может снять прораба с объекта.');
    }

    final stages = await getProductionStages(project.id);
    final batch = _db.batch();
    _removeProjectAccessUpdates(
      batch: batch,
      project: project,
      role: member.role,
      member: member,
    );

    if (member.role.isWorker) {
      _removeWorkerStageUpdates(
        batch: batch,
        projectId: project.id,
        stageIds: stages.map((stage) => stage.id),
        worker: member,
      );
    }

    _setTimelineEvent(
      batch: batch,
      projectId: project.id,
      stageId: '',
      type: TimelineEventType.participantRemoved,
      stageTitle: '',
      metadata: {
        'userId': member.uid,
        'userEmail': member.email,
        'role': member.role.firestoreValue,
        'projectId': project.id,
      },
    );
    await batch.commit();
  }

  /// Следит за фотографиями конкретного этапа.
  ///
  /// limit защищает экран от загрузки всей истории сразу. Для MVP используем
  /// простую lazy-friendly схему: читаем ограниченную порцию и сортируем на
  /// клиенте. При росте проекта сюда можно добавить пагинацию startAfterDocument.
  Stream<List<Photo>> watchStagePhotos({
    required String projectId,
    required String stageId,
    required List<PhotoType> types,
    bool? isPaid,
    int limit = 60,
  }) {
    Query<Map<String, dynamic>> query = _stagePhotosCollection(
      projectId: projectId,
      stageId: stageId,
    );

    if (types.length == 1) {
      query = query.where('type', isEqualTo: types.first.firestoreValue);
    } else if (types.isNotEmpty) {
      query = query.where(
        'type',
        whereIn: types.map((type) => type.firestoreValue).toList(),
      );
    }

    return query
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final photos = _mapDocumentsSafely(snapshot.docs, Photo.fromMap)
          .where((photo) => isPaid == null || photo.isPaid == isPaid)
          .toList();
      photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return photos;
    });
  }

  /// Creates a stable Firestore document id before the image is uploaded.
  ///
  /// The UI passes this same id to StorageService, so the Storage path and the
  /// Firestore photo document stay easy to correlate:
  /// projects/{projectId}/stages/{stageId}/photos/{photoId}.jpg
  String createStagePhotoId({
    required String projectId,
    required String stageId,
  }) {
    return _stagePhotosCollection(
      projectId: projectId,
      stageId: stageId,
    ).doc().id;
  }

  /// Добавляет фото/чек в этап и атомарно обновляет summary-поля Stage.
  Future<void> addStagePhoto(Photo photo) async {
    final stageRef = _stagesCollection(photo.projectId).doc(photo.stageId);
    final stageSnapshot = await stageRef.get();
    final stage = stageSnapshot.data() == null
        ? null
        : Stage.fromMap(stageSnapshot.id, stageSnapshot.data()!);
    final project = await getProjectById(photo.projectId);
    final collection = _stagePhotosCollection(
      projectId: photo.projectId,
      stageId: photo.stageId,
    );
    final photoId = photo.id.trim().isEmpty ? collection.doc().id : photo.id;
    final photoRef = collection.doc(photoId);
    final eventRef = _timelineCollection(photo.projectId).doc();
    final now = DateTime.now();

    final stageUpdates = <String, dynamic>{
      'updatedAt': now,
    };

    if (photo.isReceipt && !photo.isPaid) {
      stageUpdates['receiptsCount'] = FieldValue.increment(1);
      stageUpdates['receiptsTotal'] = FieldValue.increment(photo.amount ?? 0);
    } else if (photo.isReceipt) {
      // Paid receipt photos are kept for archive/history and should not affect
      // active unpaid receipt counters.
    } else {
      stageUpdates['photosCount'] = FieldValue.increment(1);
      final coverPhotoUrl = stage?.coverPhotoUrl;
      if (coverPhotoUrl == null || coverPhotoUrl.isEmpty) {
        // D6/D7: coverPhotoUrl хранит storagePath, а не presigned-ссылку —
        // это поле сейчас нигде не отображается в UI, но должно оставаться
        // самосогласованным (сравнение ниже, в deleteStagePhoto).
        stageUpdates['coverPhotoUrl'] = photo.storagePath;
      }
    }

    final event = TimelineEvent(
      id: eventRef.id,
      type: photo.isReceipt
          ? TimelineEventType.receiptUploaded
          : TimelineEventType.photoUploaded,
      projectId: photo.projectId,
      stageId: photo.stageId,
      createdAt: now,
      createdBy: _uid,
      actorName: _displayName,
      stageTitle: stage?.title ?? '',
      metadata: {
        'photoId': photoId,
        'photoType': photo.type.firestoreValue,
        if (photo.amount != null) 'amount': photo.amount,
        if (photo.receiptCategory?.isNotEmpty == true)
          'receiptCategory': photo.receiptCategory,
        if (photo.receiptDate != null)
          'receiptDate': photo.receiptDate!.toIso8601String(),
        if (photo.comment?.isNotEmpty == true) 'comment': photo.comment,
      },
    );

    final batch = _db.batch();
    batch.set(photoRef, {
      ...photo.toMap(),
      'id': photoId,
    });
    batch.update(stageRef, stageUpdates);
    batch.set(eventRef, event.toMap());
    if (photo.isReceipt && project != null) {
      final stageTitle = stage?.title ?? 'Иное';
      _setNotificationsForRecipients(
        batch: batch,
        recipientIds: project.managerIds,
        type: AppNotificationType.receiptUploaded,
        title: 'Добавлен новый чек',
        message: 'Чек по этапу "$stageTitle"'
            '${photo.amount == null ? '' : ' на ${photo.amount} ₽'}.',
        createdAt: now,
        projectId: project.id,
        projectTitle: project.title,
        stageId: photo.stageId,
        stageTitle: stageTitle,
        companyId: project.companyId,
        sourceEventId: eventRef.id,
      );
    }
    await batch.commit();
  }

  /// Удаляет metadata фото этапа и корректирует summary-счетчики.
  ///
  /// Storage-файл удаляет вызывающий UI через StorageService. Разделение нужно,
  /// чтобы пользовательский сценарий не падал полностью, если файл уже удален.
  Future<void> deleteStagePhoto(Photo photo) async {
    await StorageService.instance.deleteByPath(
      photo.storagePath,
      kind: photo.isReceipt ? 'receipt' : 'photo',
    );

    final stageRef = _stagesCollection(photo.projectId).doc(photo.stageId);
    final stageSnapshot = await stageRef.get();
    final stage = stageSnapshot.data() == null
        ? null
        : Stage.fromMap(stageSnapshot.id, stageSnapshot.data()!);
    final photoRef = _stagePhotosCollection(
      projectId: photo.projectId,
      stageId: photo.stageId,
    ).doc(photo.id);

    final updates = <String, dynamic>{
      'updatedAt': DateTime.now(),
    };

    if (photo.isReceipt && !photo.isPaid) {
      updates['receiptsCount'] = FieldValue.increment(-1);
      updates['receiptsTotal'] = FieldValue.increment(-(photo.amount ?? 0));
    } else if (photo.isReceipt) {
      // Paid receipt deletion does not change active unpaid stage counters.
    } else {
      updates['photosCount'] = FieldValue.increment(-1);

      if (stage?.coverPhotoUrl == photo.storagePath) {
        final replacementCover = await _findReplacementCoverPhotoUrl(photo);
        updates['coverPhotoUrl'] = replacementCover;
      }
    }

    final batch = _db.batch();
    batch.delete(photoRef);
    if (photo.isReceipt) {
      final expenseId = photo.expenseId ?? photo.id;
      batch.delete(
        _objectsCollection
            .doc(photo.projectId)
            .collection('expenses')
            .doc(expenseId),
      );
    }
    batch.update(stageRef, updates);
    await batch.commit();
  }

  /// Возвращает storagePath (не presigned-ссылку, см. D6/D7) кандидата на
  /// новую обложку этапа.
  Future<String?> _findReplacementCoverPhotoUrl(Photo deletedPhoto) async {
    final snapshot = await _stagePhotosCollection(
      projectId: deletedPhoto.projectId,
      stageId: deletedPhoto.stageId,
    ).get();

    final candidates = _mapDocumentsSafely(snapshot.docs, Photo.fromMap)
        .where((photo) => photo.id != deletedPhoto.id)
        .where((photo) => !photo.isReceipt)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    if (candidates.isEmpty) {
      return null;
    }

    return candidates.first.storagePath;
  }

  /// Следит за timeline проекта.
  ///
  /// Пока timeline не показан отдельным экраном, но репозиторий уже готов для
  /// будущей истории изменений и push notifications.
  Stream<List<TimelineEvent>> watchTimeline(String projectId,
      {int limit = 50}) {
    return _timelineCollection(projectId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              TimelineEvent.fromMap,
            ));
  }

  int _progressForStatus(StageStatus status) {
    switch (status) {
      case StageStatus.notStarted:
        return 0;
      case StageStatus.inProgress:
        return 35;
      case StageStatus.review:
        return 90;
      case StageStatus.completed:
        return 100;
      case StageStatus.problem:
        return 80;
    }
  }

  TimelineEventType _timelineTypeForStatus(StageStatus status) {
    switch (status) {
      case StageStatus.inProgress:
        return TimelineEventType.stageStarted;
      case StageStatus.review:
        return TimelineEventType.stageSentToReview;
      case StageStatus.completed:
        return TimelineEventType.stageCompleted;
      case StageStatus.problem:
        return TimelineEventType.stageRejected;
      case StageStatus.notStarted:
        return TimelineEventType.stageRejected;
    }
  }

  /// Следит за участниками конкретного объекта.
  Stream<List<Participant>> watchParticipants(String projectId) {
    return _objectsCollection
        .doc(projectId)
        .collection('participants')
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              Participant.fromMap,
            ));
  }

  /// Добавляет исполнителя из телефонной книги.
  ///
  /// Мы сохраняем участника в subcollection `participants`, а телефон добавляем
  /// в массив `participantPhones` основного документа проекта. Благодаря этому
  /// исполнитель увидит объект после входа по этому номеру телефона.
  Future<void> addParticipantFromContact({
    required String projectId,
    required String name,
    required String phoneNumber,
  }) async {
    final normalizedPhone = PhoneUtils.normalize(phoneNumber);
    final participantId = _uuid.v4();
    final projectRef = _objectsCollection.doc(projectId);

    await _db.runTransaction((transaction) async {
      transaction.set(
        projectRef.collection('participants').doc(participantId),
        {
          'name': name,
          'phoneNumber': normalizedPhone,
          'role': 'executor',
        },
      );

      transaction.update(projectRef, {
        'participantPhones': FieldValue.arrayUnion([normalizedPhone]),
      });
    });
  }

  /// Следит за сообщениями чата конкретного объекта.
  Stream<List<ChatMessage>> watchMessages(String projectId) {
    return _objectsCollection
        .doc(projectId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              ChatMessage.fromMap,
            ));
  }

  /// Creates a stable chat message id before image upload.
  ///
  /// The same id is used in Firestore and in Firebase Storage:
  /// `projects/{projectId}/chat/{messageId}.jpg`.
  String createChatMessageId(String projectId) {
    return _objectsCollection.doc(projectId).collection('messages').doc().id;
  }

  /// Отправляет новое сообщение в чат объекта.
  Future<void> sendMessage(String projectId, String text) async {
    final user = _auth.currentUser;
    AuthDebug.logUser('ProjectRepository.sendMessage', user);

    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final message = ChatMessage(
      id: '',
      senderId: user.uid,
      senderName: _displayName,
      text: text,
      type: ChatMessageType.text,
      createdAt: DateTime.now(),
    );

    await _objectsCollection
        .doc(projectId)
        .collection('messages')
        .add(message.toMap());
  }

  /// Saves an image message after Firebase Storage upload succeeds.
  ///
  /// The UI uploads the file first. If upload fails, this method is not called,
  /// so the chat never receives a broken Firestore message without a real file.
  Future<void> sendImageMessage({
    required String projectId,
    required String messageId,
    required String storagePath,
    String text = '',
  }) async {
    final user = _auth.currentUser;
    AuthDebug.logUser('ProjectRepository.sendImageMessage', user);

    if (user == null) {
      throw const UserNotAuthenticatedException();
    }

    final safeMessageId = messageId.trim();
    if (safeMessageId.isEmpty) {
      throw ArgumentError('messageId must not be empty');
    }

    final message = ChatMessage(
      id: safeMessageId,
      senderId: user.uid,
      senderName: _displayName,
      text: text.trim(),
      type: ChatMessageType.image,
      createdAt: DateTime.now(),
      storagePath: storagePath,
    );

    await _objectsCollection
        .doc(projectId)
        .collection('messages')
        .doc(safeMessageId)
        .set(message.toMap());
  }

  String createExpenseId(String projectId) {
    return _objectsCollection.doc(projectId).collection('expenses').doc().id;
  }

  /// Следит за расходами объекта, начиная с самых новых.
  Stream<List<Expense>> watchExpenses(String projectId) {
    return _objectsCollection
        .doc(projectId)
        .collection('expenses')
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => _mapDocumentsSafely(
              snapshot.docs,
              Expense.fromMap,
            ));
  }

  /// Adds a receipt/expense.
  ///
  /// If the expense is linked to a stage, the same receipt is also represented
  /// as `Photo(type: receipt)` in the stage photos subcollection. This keeps the
  /// existing StageDetailScreen architecture working while the general expenses
  /// section remains the source of truth for payment state.
  Future<void> addExpense(String projectId, Expense expense) async {
    final expenseCollection =
        _objectsCollection.doc(projectId).collection('expenses');
    final expenseId = expense.id.trim().isEmpty
        ? expenseCollection.doc().id
        : expense.id.trim();
    final expenseRef = expenseCollection.doc(expenseId);
    final now = DateTime.now();
    final batch = _db.batch();
    final project = await getProjectById(projectId);

    batch.set(expenseRef, {
      ...expense.toMap(),
      'id': expenseId,
      'projectId': projectId,
      'createdAt': expense.createdAt.toIso8601String(),
      'isPaid': expense.isPaid,
    });

    final stageId = expense.stageId;
    if (stageId != null && stageId.isNotEmpty) {
      final stageRef = _stagesCollection(projectId).doc(stageId);
      final photoRef = _stagePhotosCollection(
        projectId: projectId,
        stageId: stageId,
      ).doc(expenseId);
      final eventRef = _timelineCollection(projectId).doc();
      final stageTitle = expense.stageTitle ?? 'Иное';

      batch.set(photoRef, {
        'id': expenseId,
        'projectId': projectId,
        'stageId': stageId,
        'type': PhotoType.receipt.firestoreValue,
        'downloadUrl': expense.receiptUrl ?? '',
        'storagePath': expense.receiptStoragePath ?? '',
        'comment': expense.comment,
        'amount': expense.amount,
        'expenseId': expenseId,
        'receiptCategory': expense.category.name,
        'receiptDate': expense.date.toIso8601String(),
        'uploadedBy': _displayName,
        'createdAt': expense.createdAt.toIso8601String(),
        'width': 0,
        'height': 0,
        'sizeBytes': 0,
        'isFavorite': false,
        'isPaid': expense.isPaid,
        'paidAt': expense.paidAt?.toIso8601String(),
        'paidBy': expense.paidBy,
      });

      if (!expense.isPaid) {
        batch.update(stageRef, {
          'receiptsCount': FieldValue.increment(1),
          'receiptsTotal': FieldValue.increment(expense.amount),
          'updatedAt': now,
        });
      }

      batch.set(
        eventRef,
        TimelineEvent(
          id: eventRef.id,
          type: TimelineEventType.receiptUploaded,
          projectId: projectId,
          stageId: stageId,
          createdAt: now,
          createdBy: _uid,
          actorName: _displayName,
          stageTitle: stageTitle,
          metadata: {
            'receiptId': expenseId,
            'amount': expense.amount,
            'stageId': stageId,
            'stageTitle': stageTitle,
          },
        ).toMap(),
      );
      if (project != null) {
        _setNotificationsForRecipients(
          batch: batch,
          recipientIds: project.managerIds,
          type: AppNotificationType.receiptUploaded,
          title: 'Добавлен новый чек',
          message: 'Чек по этапу "$stageTitle" на ${expense.amount} ₽.',
          createdAt: now,
          projectId: project.id,
          projectTitle: project.title,
          stageId: stageId,
          stageTitle: stageTitle,
          companyId: project.companyId,
          sourceEventId: eventRef.id,
        );
      }
    } else {
      final eventRef = _timelineCollection(projectId).doc();
      batch.set(
        eventRef,
        TimelineEvent(
          id: eventRef.id,
          type: TimelineEventType.receiptUploaded,
          projectId: projectId,
          stageId: '',
          createdAt: now,
          createdBy: _uid,
          actorName: _displayName,
          stageTitle: 'Иное',
          metadata: {
            'receiptId': expenseId,
            'amount': expense.amount,
            'stageId': null,
            'stageTitle': 'Иное',
          },
        ).toMap(),
      );
      if (project != null) {
        _setNotificationsForRecipients(
          batch: batch,
          recipientIds: project.managerIds,
          type: AppNotificationType.receiptUploaded,
          title: 'Добавлен новый чек',
          message: 'Чек по объекту "${project.title}" на ${expense.amount} ₽.',
          createdAt: now,
          projectId: project.id,
          projectTitle: project.title,
          companyId: project.companyId,
          sourceEventId: eventRef.id,
        );
      }
    }

    await batch.commit();
  }

  /// Редактирует сумму/категорию/комментарий неоплаченного чека.
  ///
  /// Оплаченный чек редактировать нельзя никому (см. firestore.rules:
  /// resource.data.isPaid == false проверяется раньше роли) — это финансовый
  /// факт, зафиксированный задним числом. Проверка здесь дублирует правило,
  /// чтобы пользователь увидел понятную ошибку в приложении, а не только
  /// PERMISSION_DENIED от Firestore.
  ///
  /// Если чек привязан к этапу, зеркальная запись в
  /// stages/{stageId}/photos/{expenseId} и денормализованная
  /// stage.receiptsTotal обновляются в этом же batch, чтобы суммы не
  /// разъехались между документами.
  Future<void> updateExpense({
    required String projectId,
    required Expense original,
    required double amount,
    required ExpenseCategory category,
    String? comment,
  }) async {
    if (original.isPaid) {
      throw StateError('Оплаченный чек нельзя редактировать.');
    }

    final expenseRef = _objectsCollection
        .doc(projectId)
        .collection('expenses')
        .doc(original.id);

    final batch = _db.batch();
    final now = DateTime.now();

    batch.update(expenseRef, {
      'amount': amount,
      'category': category.name,
      'comment': comment,
    });

    final stageId = original.stageId;
    if (stageId != null && stageId.isNotEmpty) {
      final photoRef = _stagePhotosCollection(
        projectId: projectId,
        stageId: stageId,
      ).doc(original.id);
      batch.update(photoRef, {
        'amount': amount,
        'comment': comment,
        'receiptCategory': category.name,
        'updatedAt': now,
      });

      final delta = amount - original.amount;
      if (delta != 0) {
        final stageRef = _stagesCollection(projectId).doc(stageId);
        batch.update(stageRef, {
          'receiptsTotal': FieldValue.increment(delta),
          'updatedAt': now,
        });
      }
    }

    try {
      await batch.commit();
    } catch (error) {
      throw Exception('Не удалось обновить чек ${original.id}: $error');
    }
  }

  /// Удаляет неоплаченный чек: файл в Yandex Object Storage (если есть),
  /// зеркальную запись в stages/{stageId}/photos (если чек привязан к
  /// этапу) и сам документ expenses/{id}.
  ///
  /// Оплаченный чек удалить нельзя никому — та же гарантия, что и в
  /// [updateExpense]. Firestore-документы удаляются одним batch, чтобы
  /// stage.receiptsCount/receiptsTotal не разъехались с реальным списком
  /// чеков, если что-то прервётся на середине.
  ///
  /// Порядок: сначала файл в S3 (через backend), потом Firestore batch.
  /// Раньше (когда S3 подписывался прямо на клиенте) порядок был обратным —
  /// это защищало от локально неверно настроенных S3-credentials. Теперь
  /// подпись и авторизация удаления файла идут через backend photos-api,
  /// который для чека БЕЗ прав canManageProject проверяет авторство именно
  /// по документу expenses/{id} (совпадение uid с createdBy) — то есть этот
  /// документ должен ещё существовать в момент запроса на удаление файла.
  /// Если удалить сначала Firestore, а потом файл, backend для
  /// автора-подрядчика (не owner/manager) больше не найдёт документ и
  /// откажет 403 — то есть свой же неоплаченный чек стало бы невозможно
  /// удалить целиком. Поэтому файл удаляется первым: если backend отказал
  /// (сеть, права, чек внезапно оказался оплачен) — Firestore не трогаем
  /// вообще, ничего не остаётся в рассинхроне.
  Future<void> deleteExpense(Expense expense) async {
    if (expense.isPaid) {
      throw StateError('Оплаченный чек нельзя удалить.');
    }

    final storagePath = expense.receiptStoragePath;
    if (storagePath != null && storagePath.isNotEmpty) {
      await StorageService.instance.deleteByPath(storagePath, kind: 'receipt');
    }

    final expenseRef = _objectsCollection
        .doc(expense.projectId)
        .collection('expenses')
        .doc(expense.id);

    final batch = _db.batch();
    batch.delete(expenseRef);

    final stageId = expense.stageId;
    if (stageId != null && stageId.isNotEmpty) {
      final photoRef = _stagePhotosCollection(
        projectId: expense.projectId,
        stageId: stageId,
      ).doc(expense.id);
      batch.delete(photoRef);

      final stageRef = _stagesCollection(expense.projectId).doc(stageId);
      batch.update(stageRef, {
        'receiptsCount': FieldValue.increment(-1),
        'receiptsTotal': FieldValue.increment(-expense.amount),
        'updatedAt': DateTime.now(),
      });
    }

    try {
      await batch.commit();
    } catch (error) {
      throw Exception(
        'Файл чека удалён, но не удалось удалить запись ${expense.id} из '
        'Firestore: $error',
      );
    }
  }

  Future<void> markExpensesPaid({
    required String projectId,
    required Iterable<Expense> expenses,
  }) async {
    final selected = expenses.where((expense) => !expense.isPaid).toList();
    if (selected.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final paidBy = _uid;
    final batch = _db.batch();

    for (final expense in selected) {
      final expenseRef = _objectsCollection
          .doc(projectId)
          .collection('expenses')
          .doc(expense.id);
      batch.update(expenseRef, {
        'isPaid': true,
        'paidAt': now.toIso8601String(),
        'paidBy': paidBy,
      });

      final stageId = expense.stageId;
      if (stageId != null && stageId.isNotEmpty) {
        final stageRef = _stagesCollection(projectId).doc(stageId);
        final photoRef = _stagePhotosCollection(
          projectId: projectId,
          stageId: stageId,
        ).doc(expense.id);
        batch.update(photoRef, {
          'isPaid': true,
          'paidAt': now.toIso8601String(),
          'paidBy': paidBy,
        });
        batch.update(stageRef, {
          'receiptsCount': FieldValue.increment(-1),
          'receiptsTotal': FieldValue.increment(-expense.amount),
          'updatedAt': now,
        });
      }
    }

    final eventRef = _timelineCollection(projectId).doc();
    final total = selected.fold<double>(
      0,
      (runningTotal, expense) => runningTotal + expense.amount,
    );
    batch.set(
      eventRef,
      TimelineEvent(
        id: eventRef.id,
        type: TimelineEventType.receiptPaid,
        projectId: projectId,
        stageId: selected.length == 1 ? selected.first.stageId ?? '' : '',
        createdAt: now,
        createdBy: paidBy,
        actorName: _displayName,
        stageTitle:
            selected.length == 1 ? selected.first.displayStageTitle : 'Разное',
        metadata: {
          'receiptIds': selected.map((expense) => expense.id).toList(),
          'amount': total,
          if (selected.length == 1) 'stageId': selected.first.stageId,
          if (selected.length == 1)
            'stageTitle': selected.first.displayStageTitle,
        },
      ).toMap(),
    );

    await batch.commit();
  }

  Future<void> markStageReceiptsPaid({
    required String projectId,
    required Iterable<Photo> receipts,
  }) async {
    final expenses = <Expense>[];
    for (final receipt in receipts.where((photo) => !photo.isPaid)) {
      final expenseId = receipt.expenseId ?? receipt.id;
      final expenseDoc = await _objectsCollection
          .doc(projectId)
          .collection('expenses')
          .doc(expenseId)
          .get();
      final data = expenseDoc.data();
      if (data != null) {
        expenses.add(Expense.fromMap(expenseDoc.id, data));
      }
    }

    await markExpensesPaid(projectId: projectId, expenses: expenses);
  }

  /// Следит за фотографиями объекта во всех его этапах.
  ///
  /// Фото хранятся только в `projects/{projectId}/stages/{stageId}/photos`
  /// (см. [addStagePhoto]/[watchStagePhotos]) — отдельной коллекции фото на
  /// уровне объекта не существует. Общая галерея собирает их через
  /// collectionGroup('photos') с фильтром по projectId, чтобы показать фото
  /// сразу всех этапов в одном списке.
  ///
  /// Чеки (PhotoType.receipt) сюда не попадают — они показываются в экране
  /// расходов, а не в общей галерее фото.
  Stream<List<Photo>> watchProjectPhotosAcrossStages(String projectId) {
    return _db
        .collectionGroup('photos')
        .where('projectId', isEqualTo: projectId)
        .snapshots()
        .map((snapshot) {
      final photos = _mapDocumentsSafely(snapshot.docs, Photo.fromMap)
          .where((photo) => !photo.isReceipt)
          .toList();
      photos.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return photos;
    });
  }
}
