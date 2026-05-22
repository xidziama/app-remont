import 'package:flutter/foundation.dart';

import '../models/project.dart';

/// AppState — самый простой слой state management на Provider.
///
/// В MVP большая часть данных приходит потоками из Firestore, поэтому нам
/// не нужен сложный state management. Этот класс хранит только состояние UI,
/// которое не обязано жить в базе данных: выбранный объект и общий флаг загрузки.
class AppState extends ChangeNotifier {
  Project? _selectedProject;
  bool _busy = false;

  /// Текущий объект, который пользователь открыл на экране карточки.
  Project? get selectedProject => _selectedProject;

  /// Общий флаг для операций, где экрану нужно показать загрузку.
  bool get busy => _busy;

  /// Сохраняет выбранный объект и уведомляет виджеты, которые слушают AppState.
  void selectProject(Project project) {
    _selectedProject = project;
    notifyListeners();
  }

  /// Меняет флаг загрузки. Это полезно для кнопок и форм.
  void setBusy(bool value) {
    _busy = value;
    notifyListeners();
  }
}
