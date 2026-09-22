import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/photo.dart';
import '../models/repair_stage.dart';
import '../utils/stage_ui_utils.dart';
import 'storage_image.dart';

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

  final Photo photo;
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
            child: StorageImage(
              storagePath: photo.storagePath,
              fit: BoxFit.cover,
              memCacheWidth: 900,
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
                        color: stageColor.withAlpha(26),
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
                  DateFormat('dd.MM.yyyy').format(photo.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.black54,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Автор: ${photo.uploadedBy.isEmpty ? 'Неизвестно' : photo.uploadedBy}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if ((photo.comment ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(photo.comment!),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
