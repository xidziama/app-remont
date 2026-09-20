/// Роли пользователя внутри проекта.
///
/// Полная security-модель будет жить в Firestore/Storage rules и, возможно,
/// backend/Cloud Functions. Сейчас enum нужен, чтобы данные и UI уже говорили
/// одним словарем ролей.
enum ProjectRole {
  owner,
  manager,
  worker,
  client;

  String get label {
    switch (this) {
      case ProjectRole.owner:
        return 'Владелец';
      case ProjectRole.manager:
        return 'Прораб';
      case ProjectRole.worker:
        return 'Исполнитель';
      case ProjectRole.client:
        return 'Клиент';
    }
  }
}
