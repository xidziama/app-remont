import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:uuid/uuid.dart';

/// StorageService отвечает только за загрузку файлов в Firebase Storage.
///
/// Firestore хранит текстовые данные и ссылки, а сами изображения чеков/объекта
/// должны лежать в Storage. Так база остается легкой, а файлы можно кэшировать.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  final FirebaseStorage _storage = FirebaseStorage.instance;
  final Uuid _uuid = const Uuid();

  /// Загружает изображение в папку конкретного объекта.
  ///
  /// projectId нужен, чтобы файлы разных объектов не смешивались.
  /// folder разделяет типы файлов: например, `receipts` и `photos`.
  Future<String> uploadProjectImage({
    required String projectId,
    required Uint8List bytes,
    required String folder,
    String contentType = 'image/jpeg',
  }) async {
    // UUID защищает от конфликта имен файлов.
    final id = _uuid.v4();

    // Финальный путь выглядит так:
    // objects/<projectId>/<folder>/<uuid>.jpg
    final ref = _storage.ref('objects/$projectId/$folder/$id.jpg');

    // Metadata помогает Storage и браузерам понимать тип загруженного файла.
    await ref.putData(bytes, SettableMetadata(contentType: contentType));

    // Возвращаем download URL, чтобы сохранить его в Firestore.
    return ref.getDownloadURL();
  }

  /// Удаляет файл из Firebase Storage по download URL.
  ///
  /// Почему принимаем URL:
  /// - Firestore хранит именно download URL;
  /// - экран фото уже имеет imageUrl в ProjectPhoto;
  /// - Storage SDK умеет восстановить reference через refFromURL().
  ///
  /// Если URL пустой или файл уже удален, метод не должен ломать весь сценарий
  /// удаления фото. Поэтому вызывающий код может поймать ошибку и все равно
  /// удалить Firestore metadata, если это нужно для UX.
  Future<void> deleteByUrl(String imageUrl) async {
    if (imageUrl.isEmpty) {
      return;
    }

    final ref = _storage.refFromURL(imageUrl);
    await ref.delete();
  }
}
