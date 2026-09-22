import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../core/app_config.dart';

/// Ошибка запроса к photos-api backend.
///
/// `message` — уже человекочитаемый текст на русском, без стектрейсов и
/// внутренних деталей: его можно показывать пользователю напрямую (в
/// частности, `catch (error) { showMessage('...: $error') }` — [toString]
/// возвращает ровно [message], поэтому существующие места обработки ошибок
/// в экранах не нужно менять отдельно.
class PhotosApiException implements Exception {
  PhotosApiException({
    required this.statusCode,
    required this.code,
    required this.message,
  });

  /// HTTP-статус ответа backend (0 — если ответа не было вовсе, см.
  /// [PhotosApiException.network]).
  final int statusCode;

  /// Машиночитаемый код ошибки backend (`unauthenticated`,
  /// `permission_denied`, `invalid_argument`, `already_exists`,
  /// `storage_error`, `internal`) или `network`/`unknown`.
  final String code;

  final String message;

  factory PhotosApiException.network(Object cause) {
    return PhotosApiException(
      statusCode: 0,
      code: 'network',
      message: 'Нет соединения с сервером фото. Проверьте интернет и '
          'попробуйте снова.',
    );
  }

  factory PhotosApiException.fromResponse(http.Response response) {
    String? backendCode;
    String? backendMessage;

    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        backendCode = decoded['error'] as String?;
        backendMessage = decoded['message'] as String?;
      }
    } catch (_) {
      // Ответ не JSON (например, HTML-страница ошибки шлюза) — ниже
      // подставится обобщённое сообщение по статусу.
    }

    return PhotosApiException(
      statusCode: response.statusCode,
      code: backendCode ?? 'unknown',
      message: _friendlyMessage(response.statusCode, backendMessage),
    );
  }

  /// Backend уже отвечает готовыми русскими сообщениями для 400/403/404/409
  /// (см. backend/photos-api) — их и показываем как есть. Только для 401 (где
  /// backend-текст технический и на английском) и 5xx (где сообщение
  /// backend слишком общее) подставляем более уместный для пользователя текст.
  static String _friendlyMessage(int statusCode, String? backendMessage) {
    switch (statusCode) {
      case 401:
        return 'Сессия истекла. Войдите в приложение заново.';
      case 502:
        return 'Хранилище фото временно недоступно. Попробуйте позже.';
      case 500:
        return 'Сервер фото временно недоступен. Попробуйте позже.';
      default:
        if (backendMessage != null && backendMessage.trim().isNotEmpty) {
          return backendMessage;
        }
        if (statusCode >= 500) {
          return 'Сервер фото временно недоступен. Попробуйте позже.';
        }
        return 'Не удалось выполнить запрос к серверу фото '
            '(код $statusCode).';
    }
  }

  @override
  String toString() => message;
}

/// Результат `POST /put-url`.
class PutUrlResult {
  const PutUrlResult({
    required this.uploadUrl,
    required this.storagePath,
    required this.headers,
  });

  /// Presigned PUT URL — файл грузится сюда обычным HTTP PUT.
  final String uploadUrl;

  final String storagePath;

  /// Заголовки, с которыми backend подписал ссылку. Они ВХОДЯТ в подпись
  /// (X-Amz-SignedHeaders), поэтому PUT-запрос обязан отправить их
  /// БЕЗ ИЗМЕНЕНИЙ — другое значение (или отсутствие заголовка) даст
  /// SignatureDoesNotMatch на стороне Yandex.
  final Map<String, String> headers;

  factory PutUrlResult.fromJson(Map<String, dynamic> json) {
    return PutUrlResult(
      uploadUrl: json['uploadUrl'] as String,
      storagePath: json['storagePath'] as String,
      headers: (json['headers'] as Map<String, dynamic>? ?? const {})
          .map((key, value) => MapEntry(key, value.toString())),
    );
  }
}

/// Тонкий HTTP-клиент к backend photos-api (Yandex Cloud Function за API
/// Gateway). Каждый запрос несёт `Authorization: Bearer <Firebase ID token>`
/// — сам backend проверяет токен и права по логике firestore.rules, клиент
/// здесь только формирует запросы и разбирает ответы.
///
/// StorageService и PhotoUrlResolver — единственные предполагаемые
/// потребители этого класса; экраны не должны обращаться к нему напрямую.
class PhotosApiClient {
  PhotosApiClient({String? baseUrl, http.Client? httpClient})
      : _baseUrl = baseUrl ?? AppConfig.storageApiBaseUrl,
        _http = httpClient ?? http.Client();

  final String _baseUrl;
  final http.Client _http;

  static const _requestTimeout = Duration(seconds: 20);

  Future<PutUrlResult> putUrl({
    required String storagePath,
    String contentType = 'image/jpeg',
    String? kind,
  }) async {
    final json = await _postJson('/put-url', {
      'storagePath': storagePath,
      'contentType': contentType,
      if (kind != null) 'kind': kind,
    });

    return PutUrlResult.fromJson(json);
  }

  /// Возвращает свежие GET-ссылки для переданных путей одним или несколькими
  /// пакетными запросами (backend принимает не более 50 путей за раз).
  ///
  /// Путь, на который у пользователя нет доступа (или который backend не
  /// смог разобрать), молча отсутствует в результате — это НЕ ошибка всего
  /// запроса, так задумано backend, чтобы не палить существование чужих
  /// файлов.
  Future<Map<String, String>> getUrls(List<String> storagePaths) async {
    final unique = storagePaths.toSet().where((path) => path.isNotEmpty).toList();
    if (unique.isEmpty) {
      return const {};
    }

    const batchSize = 50;
    final result = <String, String>{};

    for (var offset = 0; offset < unique.length; offset += batchSize) {
      final batch = unique.sublist(
        offset,
        offset + batchSize > unique.length ? unique.length : offset + batchSize,
      );

      final json = await _postJson('/get-urls', {'storagePaths': batch});
      final urls = json['urls'] as Map<String, dynamic>? ?? const {};
      urls.forEach((path, url) => result[path] = url as String);
    }

    return result;
  }

  /// Удаляет файл в S3. `kind` обязателен: `'photo'` для обычного фото
  /// этапа, `'receipt'` для чека (с этапом или без) — backend по-разному
  /// проверяет права и НИКОГДА не разрешает удалить файл ОПЛАЧЕННОГО чека,
  /// кем бы ни был вызывающий.
  Future<void> delete({
    required String storagePath,
    required String kind,
  }) async {
    await _postJson('/delete', {
      'storagePath': storagePath,
      'kind': kind,
    });
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final token = await _idToken();
    var response = await _send(path, body, token);

    // Токен мог протухнуть между чтением из кэша SDK и приходом ответа —
    // один раз пробуем принудительно обновить его и повторить запрos.
    if (response.statusCode == 401) {
      final freshToken = await _idToken(forceRefresh: true);
      if (freshToken != null && freshToken != token) {
        response = await _send(path, body, freshToken);
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PhotosApiException.fromResponse(response);
    }

    if (response.body.isEmpty) {
      return const {};
    }

    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (error) {
      throw PhotosApiException(
        statusCode: response.statusCode,
        code: 'invalid_response',
        message: 'Сервер фото вернул некорректный ответ. Попробуйте позже.',
      );
    }
  }

  Future<http.Response> _send(
    String path,
    Map<String, dynamic> body,
    String? token,
  ) async {
    if (token == null) {
      throw PhotosApiException(
        statusCode: 401,
        code: 'unauthenticated',
        message: 'Вы не авторизованы. Войдите в приложение заново.',
      );
    }

    try {
      return await _http
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {
              'Content-Type': 'application/json; charset=utf-8',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode(body),
          )
          .timeout(_requestTimeout);
    } on TimeoutException catch (error) {
      throw PhotosApiException.network(error);
    } on SocketException catch (error) {
      throw PhotosApiException.network(error);
    } on http.ClientException catch (error) {
      throw PhotosApiException.network(error);
    }
  }

  Future<String?> _idToken({bool forceRefresh = false}) {
    return FirebaseAuth.instance.currentUser?.getIdToken(forceRefresh) ??
        Future.value(null);
  }
}
