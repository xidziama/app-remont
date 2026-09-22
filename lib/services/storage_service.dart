import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'photos_api_client.dart';

/// Result of an upload.
///
/// `storagePath` — ключ объекта в S3, единственное, что теперь хранится в
/// Firestore для показа/удаления файла. Presigned-ссылка на чтение больше не
/// возвращается отсюда и не сохраняется — она запрашивается заново при
/// показе через [PhotoUrlResolver] (см. lib/services/photo_url_resolver.dart).
class StorageUploadResult {
  const StorageUploadResult({
    required this.storagePath,
    required this.sizeBytes,
  });

  final String storagePath;
  final int sizeBytes;
}

/// Загрузка/удаление фото через backend photos-api (Yandex Cloud Function).
///
/// Раньше этот класс сам подписывал запросы к Yandex Object Storage ключом,
/// зашитым в приложение через --dart-define — и этот ключ извлекался прямым
/// анализом собранного APK. Теперь клиент только просит backend подписать
/// presigned URL на конкретную операцию (он же проверяет права по логике
/// firestore.rules) и грузит/удаляет файл по этой одноразовой ссылке.
/// Секрет S3 теперь существует только на сервере.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  final PhotosApiClient _api = PhotosApiClient();
  final http.Client _http = http.Client();

  /// Uploads a photo or receipt for a concrete production stage.
  ///
  /// `photoId`/`stageId` формируют ключ:
  /// `projects/{projectId}/stages/{stageId}/photos/{photoId}.jpg`.
  /// `kind` — подсказка backend для метаданных объекта (`'photo'` для
  /// обычного фото прогресса, `'receipt'` для чека этапа); по одному пути
  /// backend не может различить эти два случая (см. photos-api/src/endpoints
  /// /putUrl.js), поэтому вызывающий код обязан передать его явно для чеков.
  Future<StorageUploadResult> uploadStagePhoto({
    required String projectId,
    required String stageId,
    required Uint8List bytes,
    required String photoId,
    String contentType = 'image/jpeg',
    String kind = 'photo',
  }) async {
    final key = 'projects/$projectId/stages/$stageId/photos/$photoId.jpg';
    return _putObject(key: key, bytes: bytes, contentType: contentType, kind: kind);
  }

  /// Uploads a receipt attached directly to the project (no stage — "Иное").
  ///
  /// `id` ДОЛЖЕН быть тем же id, что и у документа `expenses/{id}` в
  /// Firestore (см. ProjectRepository.createExpenseId) — backend определяет
  /// автора и статус оплаты чека именно по этому совпадению id при удалении.
  Future<StorageUploadResult> uploadProjectReceipt({
    required String projectId,
    required String id,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final key = 'projects/$projectId/receipts/$id.jpg';
    return _putObject(key: key, bytes: bytes, contentType: contentType, kind: 'receipt');
  }

  /// Uploads an image attached to the project chat.
  ///
  /// `messageId` — id уже созданного (или ещё не отправленного) документа
  /// `projects/{projectId}/messages/{messageId}`, формирует ключ
  /// `projects/{projectId}/chat/{messageId}.jpg`.
  Future<StorageUploadResult> uploadChatImage({
    required String projectId,
    required String messageId,
    required Uint8List bytes,
    String contentType = 'image/jpeg',
  }) async {
    final safeMessageId = messageId.trim();
    if (safeMessageId.isEmpty) {
      throw ArgumentError('messageId must not be empty');
    }

    final key = 'projects/$projectId/chat/$safeMessageId.jpg';
    return _putObject(key: key, bytes: bytes, contentType: contentType, kind: 'photo');
  }

  /// Deletes a file by direct storage key (`storagePath`).
  ///
  /// `kind` обязателен и должен совпадать с реальной природой файла:
  /// `'photo'` — обычное фото этапа (удалить может только owner/manager);
  /// `'receipt'` — чек, с этапом или без (удалить может owner/manager или
  /// автор своего чека, и НИКТО — если чек уже оплачен: backend вернёт 403
  /// независимо от роли, см. PhotosApiException.message).
  Future<void> deleteByPath(String storagePath, {required String kind}) async {
    if (storagePath.isEmpty) {
      return;
    }

    await _api.delete(storagePath: storagePath, kind: kind);
  }

  Future<StorageUploadResult> _putObject({
    required String key,
    required Uint8List bytes,
    required String contentType,
    required String kind,
  }) async {
    final signed = await _api.putUrl(
      storagePath: key,
      contentType: contentType,
      kind: kind,
    );

    final response = await _http.put(
      Uri.parse(signed.uploadUrl),
      // Заголовки должны БУКВАЛЬНО совпадать с тем, что вернул backend — они
      // входят в подпись presigned URL (см. PutUrlResult.headers).
      headers: signed.headers,
      body: bytes,
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PhotosApiException(
        statusCode: response.statusCode,
        code: 'storage_error',
        message: 'Не удалось загрузить файл в хранилище '
            '(код ${response.statusCode}). Попробуйте ещё раз.',
      );
    }

    return StorageUploadResult(
      storagePath: signed.storagePath,
      sizeBytes: bytes.length,
    );
  }
}
