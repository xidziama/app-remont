import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/photo_url_resolver.dart';

/// Показывает фото по его `storagePath`, запрашивая свежую presigned-ссылку
/// через [PhotoUrlResolver] (backend photos-api) при каждом построении.
///
/// Раньше все места показа фото брали готовую ссылку из Firestore
/// (`photo.downloadUrl`/`message.imageUrl`/`expense.receiptUrl`) — эта ссылка
/// протухала через 7 дней и не перевыпускалась (см. TODO-историю
/// storage_service.dart). Теперь Firestore хранит только `storagePath`
/// (D6), а сама ссылка на чтение всегда свежая (backend подписывает её на
/// 60 минут при каждом запросе).
///
/// `cacheKey` для [CachedNetworkImage] — это [storagePath], а НЕ сама ссылка:
/// ссылка каждый раз новая (другая подпись/токен в query), и если кэшировать
/// по url, диск-кэш промахивался бы при каждом повторном показе одного и
/// того же файла, перекачивая его заново.
class StorageImage extends StatelessWidget {
  const StorageImage({
    super.key,
    required this.storagePath,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.memCacheWidth,
    this.fadeInDuration = const Duration(milliseconds: 180),
    this.placeholder,
    this.errorWidget,
  });

  /// Ключ объекта в S3. `null`/пустая строка трактуются как «фото нет» —
  /// сразу показывается [errorWidget] без обращения к резолверу.
  final String? storagePath;

  final BoxFit fit;
  final double? width;
  final double? height;
  final int? memCacheWidth;
  final Duration fadeInDuration;

  /// Если не задано — используется небольшой спиннер по центру.
  final WidgetBuilder? placeholder;

  /// Если не задано — используется серый фон со значком «битой» картинки.
  /// Показывается и когда файла нет, и когда ссылку не удалось получить
  /// (нет прав, файл удалён, сеть недоступна) — с точки зрения пользователя
  /// это один и тот же случай «фото недоступно».
  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    final path = storagePath;
    if (path == null || path.isEmpty) {
      return _buildError(context);
    }

    return FutureBuilder<String?>(
      // Виджет может пересобираться чаще, чем меняется storagePath (родитель
      // перестраивается по другой причине) — резолвер сам кэширует результат
      // на ~50 минут и дедуплицирует параллельные запросы одного пути, так
      // что повторный вызов resolve() здесь не порождает лишних запросов.
      future: PhotoUrlResolver.instance.resolve(path),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _buildPlaceholder(context);
        }

        final url = snapshot.data;
        if (url == null) {
          return _buildError(context);
        }

        return CachedNetworkImage(
          imageUrl: url,
          cacheKey: path,
          fit: fit,
          width: width,
          height: height,
          memCacheWidth: memCacheWidth,
          fadeInDuration: fadeInDuration,
          placeholder: (context, _) => _buildPlaceholder(context),
          errorWidget: (context, _, __) => _buildError(context),
        );
      },
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (placeholder != null) {
      return placeholder!(context);
    }

    return SizedBox(
      width: width,
      height: height,
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }

  Widget _buildError(BuildContext context) {
    if (errorWidget != null) {
      return errorWidget!(context);
    }

    return SizedBox(
      width: width,
      height: height,
      child: const ColoredBox(
        color: Color(0xFFE5E7EB),
        child: Center(child: Icon(Icons.broken_image_outlined)),
      ),
    );
  }
}
