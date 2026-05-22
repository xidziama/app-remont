import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/expense.dart';
import '../models/participant.dart';
import '../models/project.dart';
import '../models/project_photo.dart';
import '../models/repair_stage.dart';
import '../utils/phone_utils.dart';

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
  CollectionReference<Map<String, dynamic>> get _objectsCollection {
    return _db.collection('objects');
  }

  /// Возвращает UID текущего пользователя.
  ///
  /// Вызов `!` безопасен для экранов внутри приложения, потому что main.dart
  /// показывает эти экраны только после успешной авторизации.
  String get _uid => _auth.currentUser!.uid;

  /// Возвращает телефон текущего пользователя в нормализованном виде.
  String get _phone {
    return PhoneUtils.normalize(_auth.currentUser?.phoneNumber ?? '');
  }

  /// Возвращает понятное имя текущего пользователя для участника и чата.
  ///
  /// При phone auth Firebase хранит номер телефона в user.phoneNumber.
  /// При temporary dev login пользователь anonymous, поэтому телефона нет.
  /// В этом случае используем стабильную подпись "Тестовый пользователь".
  String get _displayName {
    final user = _auth.currentUser;
    final phone = user?.phoneNumber;

    if (phone != null && phone.isNotEmpty) {
      return phone;
    }

    return 'Тестовый пользователь';
  }

  /// Публичное имя автора для UI-слоя.
  ///
  /// Экран добавления фото использует это значение как uploadedBy.
  /// В production здесь можно заменить fallback на профиль пользователя.
  String get currentAuthorName => _displayName;

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
        // ignore: avoid_print
        print(
          'Пропущен некорректный Firestore document '
          '${doc.reference.path}: $error',
        );
      }
    }

    return result;
  }

  /// Поток объектов ремонта, доступных текущему пользователю.
  ///
  /// Есть два режима:
  /// 1. Dev temporary login: у anonymous user нет телефона, поэтому ищем
  ///    проекты по `participantIds`, где хранится Firebase UID.
  /// 2. Phone auth: у пользователя есть номер телефона, поэтому ищем проекты
  ///    по `participantPhones`. Это позволяет исполнителю увидеть объект,
  ///    куда его добавили из телефонной книги еще до первого входа.
  Stream<List<Project>> watchProjects() {
    final phone = _phone;
    final hasPhone = phone.isNotEmpty;

    // Если телефон есть, используем participantPhones.
    // Если телефона нет, используем participantIds для anonymous dev user.
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

  /// Создает новый объект ремонта и сразу добавляет владельца в участники.
  Future<Project> createProject({
    required String title,
    required String address,
    required String description,
    required ProjectStatus status,
  }) async {
    final projectRef = _objectsCollection.doc();
    final now = DateTime.now();
    final ownerPhone = _phone;

    // В dev-режиме ownerPhone будет пустым, потому что anonymous user не имеет
    // номера телефона. Это нормально: доступ владельца работает через UID в
    // participantIds. В phone auth режиме дополнительно сохраняется телефон.
    final project = Project(
      id: projectRef.id,
      title: title,
      address: address,
      description: description,
      status: status,
      ownerId: _uid,
      participantIds: [_uid],
      participantPhones: [
        if (ownerPhone.isNotEmpty) ownerPhone,
      ],
      createdAt: now,
    );

    // Transaction гарантирует, что объект и участник-владелец создаются вместе.
    // Если одна операция упадет, Firestore откатит весь набор изменений.
    await _db.runTransaction((transaction) async {
      transaction.set(projectRef, project.toMap());
      transaction.set(projectRef.collection('participants').doc(_uid), {
        'name': _displayName,
        'phoneNumber': ownerPhone,
        'role': 'owner',
      });
    });

    return project;
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

  /// Удаляет объект ремонта.
  ///
  /// Важно: Firestore не удаляет subcollections автоматически. Для MVP метод
  /// удаляет только основной документ. При росте проекта лучше добавить Cloud
  /// Function или backend job для каскадного удаления участников, сообщений,
  /// расходов, фото и файлов Storage.
  Future<void> deleteProject(String projectId) async {
    try {
      await _objectsCollection.doc(projectId).delete();
    } catch (error) {
      throw Exception('Не удалось удалить объект $projectId: $error');
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
  }

  /// Удаляет этап.
  ///
  /// Если у фото останется stageId удаленного этапа, UI покажет fallback
  /// "Этап удален". Так мы не теряем фотографии и не делаем опасное каскадное
  /// удаление без явного подтверждения пользователя.
  Future<void> deleteStage(String projectId, String stageId) async {
    await _objectsCollection
        .doc(projectId)
        .collection('stages')
        .doc(stageId)
        .delete();
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

  /// Отправляет новое сообщение в чат объекта.
  Future<void> sendMessage(String projectId, String text) async {
    final user = _auth.currentUser!;

    final message = ChatMessage(
      id: '',
      senderId: user.uid,
      senderName: _displayName,
      text: text,
      createdAt: DateTime.now(),
    );

    await _objectsCollection
        .doc(projectId)
        .collection('messages')
        .add(message.toMap());
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

  /// Добавляет расход. Фото чека загружается отдельно в StorageService,
  /// а здесь сохраняется только ссылка на файл и данные расхода.
  Future<void> addExpense(String projectId, Expense expense) async {
    await _objectsCollection
        .doc(projectId)
        .collection('expenses')
        .add(expense.toMap());
  }

  /// Следит за фотографиями объекта.
  Stream<List<ProjectPhoto>> watchPhotos(String projectId) {
    return _objectsCollection
        .doc(projectId)
        .collection('photos')
        .snapshots()
        .map((snapshot) {
      final photos = _mapDocumentsSafely(snapshot.docs, ProjectPhoto.fromMap);
      photos.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      return photos;
    });
  }

  /// Добавляет запись о фото объекта после загрузки файла в Firebase Storage.
  Future<void> addPhoto(String projectId, ProjectPhoto photo) async {
    await _objectsCollection
        .doc(projectId)
        .collection('photos')
        .add(photo.toMap());
  }

  /// Удаляет метаданные фото из Firestore.
  ///
  /// Файл в Storage можно удалять отдельным методом StorageService по imageUrl.
  /// Разделение нужно, чтобы UI мог аккуратно обработать ошибку Storage и
  /// Firestore отдельно.
  Future<void> deletePhoto(String projectId, String photoId) async {
    await _objectsCollection
        .doc(projectId)
        .collection('photos')
        .doc(photoId)
        .delete();
  }
}
