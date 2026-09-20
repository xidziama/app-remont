import 'dart:typed_data';

import 'package:aws_common/aws_common.dart';
import 'package:aws_signature_v4/aws_signature_v4.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../core/app_config.dart';

/// Result of an S3 upload.
///
/// `downloadUrl` is a presigned GET URL used by the UI to display the image.
/// `storagePath` is the raw S3 object key, used by repositories to delete or
/// re-sign the exact file without parsing a URL.
class StorageUploadResult {
  const StorageUploadResult({
    required this.downloadUrl,
    required this.storagePath,
    required this.sizeBytes,
  });

  final String downloadUrl;
  final String storagePath;
  final int sizeBytes;
}

/// Small wrapper around Yandex Object Storage (S3-совместимое хранилище).
///
/// Firestore и Auth остаются на Firebase. Только бинарные данные фото
/// (этапы, чеки, чат) хранятся в Yandex Object Storage, чтобы не зависеть от
/// Firebase Storage и его тарифов/регионов.
///
/// Бакет приватный («доступ с авторизацией»), поэтому показ фото в
/// приложении и сама загрузка идут через presigned URL — временную ссылку,
/// подписанную ключом доступа, без публичного ACL на объекты.
///
/// ВАЖНО — безопасность (dev/test only):
/// Access Key ID и Secret Access Key сейчас передаются в это мобильное
/// приложение через --dart-define (см. AppConfig.s3AccessKey/s3SecretKey) и
/// поэтому попадают в скомпилированный APK/IPA. Это приемлемо ТОЛЬКО для
/// разработки и тестов. В публичном релизе secret key не должен оказаться на
/// устройстве — кто угодно может извлечь его из сборки и получить прямой
/// доступ к бакету с правами этого ключа.
///
/// TODO(production): перенести подпись запросов на backend (тот же backend/,
/// что уже есть в проекте). Правильная схема: приложение просит у своего
/// backend presigned URL на конкретную операцию (upload/delete/получить
/// ссылку), backend подписывает запрос секретом, который хранится только на
/// сервере, и отдает клиенту одноразовую ссылку. Сама эта серверная схема
/// сейчас НЕ реализована — secret key продолжает жить в --dart-define.
class StorageService {
  StorageService._();

  static final StorageService instance = StorageService._();

  final Uuid _uuid = const Uuid();

  /// Подписывающий клиент. Credentials — константы из AppConfig, поэтому сам
  /// signer можно сделать compile-time constant.
  static const AWSSigV4Signer _signer = AWSSigV4Signer(
    credentialsProvider: AWSCredentialsProvider(
      AWSCredentials(AppConfig.s3AccessKey, AppConfig.s3SecretKey),
    ),
  );

  /// Срок жизни presigned-ссылок на запись/удаление.
  ///
  /// Эти ссылки используются сразу после генерации, поэтому короткий срок
  /// жизни безопаснее: если ссылка где-то осядет в логах, она быстро
  /// перестанет работать.
  static const Duration _writeUrlTtl = Duration(minutes: 15);

  /// Срок жизни presigned-ссылок на чтение (показ фото в приложении).
  ///
  /// 7 дней — максимум, разрешенный протоколом SigV4 для presigned URL.
  /// ВАЖНО: ссылка, сохраненная в Firestore (photo.imageUrl), перестанет
  /// открываться после истечения этого срока. Если фото нужно показывать
  /// дольше, вызывающий код должен перевыпустить ссылку через
  /// [presignDownloadUrl] по сохраненному storagePath.
  static const Duration _downloadUrlTtl = Duration(days: 7);

  AWSCredentialScope get _scope => AWSCredentialScope(
        region: AppConfig.s3Region,
        service: AWSService.s3,
      );

  Uri _objectUri(String key) => Uri.https(AppConfig.s3Endpoint, '/${AppConfig.s3Bucket}/$key');

  /// Fails fast with a clear message instead of silently signing requests
  /// with an empty Access Key ID.
  ///
  /// _signer is a single `static const` shared by upload/download/delete, so
  /// if the app was launched without `--dart-define=S3_ACCESS_KEY=...
  /// S3_SECRET_KEY=...` (e.g. a plain `flutter run` instead of
  /// run_local.ps1/build_release.secrets.ps1), AppConfig.s3AccessKey compiles
  /// to '' and EVERY S3 operation in this build signs with an empty key —
  /// not just the one that happens to be called first. Yandex then rejects
  /// the request with a cryptic
  /// "AuthorizationQueryParametersError: ... Credential is malformed"
  /// (visibly an empty AKID before the first '/' in X-Amz-Credential). This
  /// check turns that into an immediately actionable error at the call site.
  void _assertCredentialsConfigured() {
    if (AppConfig.s3AccessKey.isEmpty || AppConfig.s3SecretKey.isEmpty) {
      throw StateError(
        'S3 credentials are not configured (AppConfig.s3AccessKey/'
        's3SecretKey are empty). Run with '
        '--dart-define=S3_ACCESS_KEY=... --dart-define=S3_SECRET_KEY=... '
        '(see run_local.ps1 / build_release.secrets.ps1) — without them '
        'every S3 request signs with an empty Access Key ID and Yandex '
        'rejects it.',
      );
    }
  }

  /// Backward-compatible project image upload.
  ///
  /// Older screens expect only a download URL. Internally we still use the
  /// detailed method so new code can keep the direct storage path as well.
  Future<String> uploadProjectImage({
    required String projectId,
    required Uint8List bytes,
    required String folder,
    String contentType = 'image/jpeg',
  }) async {
    final result = await uploadProjectImageDetailed(
      projectId: projectId,
      bytes: bytes,
      folder: folder,
      contentType: contentType,
    );

    return result.downloadUrl;
  }

  /// Uploads a project-level image and returns URL plus direct storage path.
  ///
  /// The folder is used for legacy project sections such as `receipts` and
  /// `photos`: `projects/{projectId}/{folder}/{uuid}.jpg`.
  Future<StorageUploadResult> uploadProjectImageDetailed({
    required String projectId,
    required Uint8List bytes,
    required String folder,
    String contentType = 'image/jpeg',
  }) async {
    final id = _uuid.v4();
    final key = 'projects/$projectId/$folder/$id.jpg';

    return _putObject(key: key, bytes: bytes, contentType: contentType);
  }

  /// Uploads a photo or receipt for a concrete production stage.
  ///
  /// The optional `photoId` lets the repository create a Firestore document id
  /// first and reuse the same id in storage:
  /// `projects/{projectId}/stages/{stageId}/photos/{photoId}.jpg`.
  Future<StorageUploadResult> uploadStagePhoto({
    required String projectId,
    required String stageId,
    required Uint8List bytes,
    String? photoId,
    String contentType = 'image/jpeg',
  }) async {
    final id =
        photoId?.trim().isNotEmpty == true ? photoId!.trim() : _uuid.v4();
    final key = 'projects/$projectId/stages/$stageId/photos/$id.jpg';

    return _putObject(key: key, bytes: bytes, contentType: contentType);
  }

  /// Uploads an image attached to the project chat.
  ///
  /// The UI asks ProjectRepository for a message id before upload. Reusing that
  /// id in storage keeps the file and Firestore message easy to match:
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

    return _putObject(key: key, bytes: bytes, contentType: contentType);
  }

  /// Deletes a file by direct storage key (`storagePath`).
  Future<void> deleteByPath(String storagePath) async {
    if (storagePath.isEmpty) {
      return;
    }

    await _deleteObject(storagePath);
  }

  /// Deletes a file by a previously issued presigned URL.
  ///
  /// Legacy project photos and expenses may have only URL metadata, so this
  /// method is kept for backward compatibility. The object key is recovered
  /// from the URL path (everything after `/{bucket}/`), the query string
  /// (signature, expiry) is ignored.
  Future<void> deleteByUrl(String imageUrl) async {
    if (imageUrl.isEmpty) {
      return;
    }

    final key = _keyFromUrl(imageUrl);
    if (key == null) {
      return;
    }

    await _deleteObject(key);
  }

  /// Re-signs a fresh download URL for an already uploaded file.
  ///
  /// Use this when a previously stored presigned URL (older than
  /// [_downloadUrlTtl]) has expired and the UI needs a working link again.
  Future<String> presignDownloadUrl(String storagePath) {
    return _presignGetUrl(storagePath);
  }

  Future<StorageUploadResult> _putObject({
    required String key,
    required Uint8List bytes,
    required String contentType,
  }) async {
    _assertCredentialsConfigured();
    final headers = {'content-type': contentType};
    final request = AWSHttpRequest.put(
      _objectUri(key),
      body: bytes,
      headers: headers,
    );

    final presignedUri = await _signer.presign(
      request,
      credentialScope: _scope,
      serviceConfiguration: S3ServiceConfiguration(),
      expiresIn: _writeUrlTtl,
    );

    final response = await http.put(presignedUri, body: bytes, headers: headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
        'S3 upload failed: HTTP ${response.statusCode} ${response.body}',
      );
    }

    return StorageUploadResult(
      downloadUrl: await _presignGetUrl(key),
      storagePath: key,
      sizeBytes: bytes.length,
    );
  }

  Future<String> _presignGetUrl(String key) async {
    _assertCredentialsConfigured();
    final request = AWSHttpRequest.get(_objectUri(key));
    final presignedUri = await _signer.presign(
      request,
      credentialScope: _scope,
      serviceConfiguration: S3ServiceConfiguration(),
      expiresIn: _downloadUrlTtl,
    );

    return presignedUri.toString();
  }

  Future<void> _deleteObject(String key) async {
    _assertCredentialsConfigured();
    final request = AWSHttpRequest.delete(_objectUri(key));
    final presignedUri = await _signer.presign(
      request,
      credentialScope: _scope,
      serviceConfiguration: S3ServiceConfiguration(),
      expiresIn: _writeUrlTtl,
    );

    final response = await http.delete(presignedUri);
    final isNotFound = response.statusCode == 404;
    final isOk = response.statusCode >= 200 && response.statusCode < 300;
    if (!isOk && !isNotFound) {
      throw Exception(
        'S3 delete failed: HTTP ${response.statusCode} ${response.body}',
      );
    }
  }

  /// Recovers the object key from a presigned URL produced by [_objectUri].
  String? _keyFromUrl(String imageUrl) {
    final uri = Uri.tryParse(imageUrl);
    if (uri == null) {
      return null;
    }

    final prefix = '/${AppConfig.s3Bucket}/';
    if (!uri.path.startsWith(prefix)) {
      return null;
    }

    return uri.path.substring(prefix.length);
  }
}
