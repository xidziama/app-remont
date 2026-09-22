import 'dart:async';

import 'photos_api_client.dart';

class _CacheEntry {
  _CacheEntry(this.url, this.fetchedAt);

  final String url;
  final DateTime fetchedAt;
}

/// Резолвит `storagePath` в свежую presigned GET-ссылку через backend
/// photos-api, с кэшем в памяти и микро-батчингом конкурентных запросов.
///
/// Presigned-ссылки больше не хранятся в Firestore (D6) — единственный
/// стабильный идентификатор фото это `storagePath`, а ссылку на чтение нужно
/// каждый раз получать заново (backend подписывает её на 60 минут). Экран с
/// сеткой из 20-30 фото строит 20-30 виджетов [StorageImage] в одном кадре;
/// без батчинга это было бы 20-30 отдельных HTTP-запросов вместо одного.
///
/// Использование: `PhotoUrlResolver.instance.resolve(photo.storagePath)`.
/// Экраны не создают собственные экземпляры — резолвер держит общий кэш на
/// всё приложение, как и [StorageService.instance].
class PhotoUrlResolver {
  PhotoUrlResolver({PhotosApiClient? client})
      : _client = client ?? PhotosApiClient();

  static final PhotoUrlResolver instance = PhotoUrlResolver();

  final PhotosApiClient _client;
  final Map<String, _CacheEntry> _cache = {};

  /// Пути, ожидающие следующего пакетного запроса, и те, кто на них подписан.
  final Set<String> _pendingPaths = {};
  final Map<String, Completer<String?>> _pendingCompleters = {};
  Timer? _flushTimer;

  /// Ссылка живёт на backend 60 минут (D8); держим кэш немного короче, чтобы
  /// у CachedNetworkImage всегда был запас времени докачать файл, даже если
  /// ссылка была получена почти час назад.
  static const _cacheTtl = Duration(minutes: 50);

  /// Небольшая задержка перед отправкой пакета: собирает все вызовы
  /// [resolve], сделанные в рамках одного кадра построения виджетов, в один
  /// HTTP-запрос вместо запроса на каждый виджет.
  static const _batchWindow = Duration(milliseconds: 20);

  /// Возвращает свежую ссылку на чтение файла по его `storagePath`, либо
  /// `null`, если ссылку получить не удалось (нет доступа, файл не найден,
  /// сеть недоступна) или сам `storagePath` пуст. Вызывающий виджет должен
  /// трактовать `null` так же, как битую ссылку — просто placeholder,
  /// без пробрасывания исключения дальше.
  Future<String?> resolve(String storagePath) {
    if (storagePath.isEmpty) {
      return Future.value(null);
    }

    final cached = _cache[storagePath];
    if (cached != null && DateTime.now().difference(cached.fetchedAt) < _cacheTtl) {
      return Future.value(cached.url);
    }

    final existing = _pendingCompleters[storagePath];
    if (existing != null) {
      return existing.future;
    }

    final completer = Completer<String?>();
    _pendingCompleters[storagePath] = completer;
    _pendingPaths.add(storagePath);

    _flushTimer ??= Timer(_batchWindow, _flush);

    return completer.future;
  }

  /// Пакетно резолвит несколько путей сразу — удобно перед показом целого
  /// экрана (например, вся сетка фото объекта), чтобы не ждать по одному.
  /// Возвращает то же самое, что вернул бы [resolve] для каждого пути.
  Future<Map<String, String?>> resolveAll(Iterable<String> storagePaths) async {
    final results = await Future.wait(
      storagePaths.map((path) async => MapEntry(path, await resolve(path))),
    );
    return Map.fromEntries(results);
  }

  Future<void> _flush() async {
    _flushTimer = null;
    final paths = _pendingPaths.toList();
    _pendingPaths.clear();

    if (paths.isEmpty) {
      return;
    }

    Map<String, String> urls;
    Object? failure;
    try {
      urls = await _client.getUrls(paths);
    } catch (error) {
      urls = const {};
      failure = error;
    }

    final now = DateTime.now();
    for (final path in paths) {
      final completer = _pendingCompleters.remove(path);
      if (completer == null || completer.isCompleted) {
        continue;
      }

      final url = urls[path];
      if (url != null) {
        _cache[path] = _CacheEntry(url, now);
        completer.complete(url);
      } else {
        // Путь недоступен (нет прав, не найден) либо весь пакет упал
        // (failure != null, например сеть). В обоих случаях экран должен
        // просто показать placeholder, а не падать — поэтому complete(null),
        // а не completeError.
        completer.complete(null);
      }
    }

    if (failure != null) {
      // Ничего не пробрасываем наверх (см. выше), но не проглатываем совсем —
      // это помогает при отладке в дебажной консоли.
      // ignore: avoid_print
      assert(() {
        // ignore: avoid_print
        print('[PhotoUrlResolver] batch get-urls failed: $failure');
        return true;
      }());
    }
  }

  /// Очищает кэш ссылок. Вызывается при выходе из аккаунта (см.
  /// AuthService.signOut), чтобы на том же устройстве другой пользователь не
  /// начинал сессию с чужими закэшированными ссылками (сами ссылки всё равно
  /// не работают без доступа, но это лишняя гигиена, а не мера защиты).
  void clearCache() {
    _cache.clear();
  }
}
