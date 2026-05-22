import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/project_photo.dart';
import '../models/repair_stage.dart';
import '../utils/stage_ui_utils.dart';

/// Карточка фотографии объекта.
///
/// Использует CachedNetworkImage, чтобы:
/// - не загружать изображение заново при каждом скролле;
/// - показать placeholder во время загрузки;
/// - аккуратно обработать ошибку битой ссылки.
class ProjectPhotoCard extends StatelessWidget {
  const ProjectPhotoCard({
    super.key,
    required this.photo,
    required this.stage,
    required this.onDelete,
  });

  final ProjectPhoto photo;
  final RepairStage? stage;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final stageColor = stage == null
        ? const Color(0xFF64748B)
        : StageUiUtils.colorFromInt(stage!.color);
    final stageName = stage?.name ?? 'Этап удален';
    final stageIcon = stage == null
        ? Icons.help_outline
        : StageUiUtils.iconFromName(stage!.icon);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 4 / 3,
            child: CachedNetworkImage(
              imageUrl: photo.imageUrl,
              fit: BoxFit.cover,
              memCacheWidth: 900,
              fadeInDuration: const Duration(milliseconds: 180),
              placeholder: (context, _) => const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              errorWidget: (context, _, __) => const ColoredBox(
                color: Color(0xFFE5E7EB),
                child: Center(child: Icon(Icons.broken_image_outlined)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: stageColor.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(stageIcon, size: 16, color: stageColor),
                          const SizedBox(width: 6),
                          Text(
                            stageName,
                            style: TextStyle(
                              color: stageColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      tooltip: 'Удалить фото',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  DateFormat('dd.MM.yyyy').format(photo.uploadedAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Автор: ${photo.uploadedBy.isEmpty ? 'Неизвестно' : photo.uploadedBy}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (photo.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(photo.description),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
