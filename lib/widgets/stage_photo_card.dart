import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../models/photo.dart';
import 'storage_image.dart';

/// Grid card for a stage photo or receipt.
///
/// The image is loaded through CachedNetworkImage so scrolling the grid does
/// not redownload every thumbnail. Broken URLs render a small fallback icon
/// instead of breaking the whole screen.
class StagePhotoCard extends StatelessWidget {
  const StagePhotoCard({
    super.key,
    required this.photo,
    required this.onOpen,
    required this.onDelete,
    this.canDelete = true,
  });

  final Photo photo;
  final VoidCallback onOpen;
  final VoidCallback onDelete;
  final bool canDelete;

  String? _receiptCategoryLabel() {
    final categoryName = photo.receiptCategory;
    if (categoryName == null || categoryName.isEmpty) {
      return null;
    }

    final category = ExpenseCategory.values.firstWhere(
      (item) => item.name == categoryName,
      orElse: () => ExpenseCategory.other,
    );

    return category.label;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  StorageImage(
                    storagePath: photo.storagePath,
                    fit: BoxFit.cover,
                    memCacheWidth: 700,
                  ),
                  Positioned(
                    left: 8,
                    top: 8,
                    child: _TypePill(type: photo.type),
                  ),
                  if (canDelete)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black.withAlpha(102),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: PopupMenuButton<_PhotoCardAction>(
                          tooltip: 'Действия',
                          icon:
                              const Icon(Icons.more_vert, color: Colors.white),
                          onSelected: (action) {
                            switch (action) {
                              case _PhotoCardAction.delete:
                                onDelete();
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: _PhotoCardAction.delete,
                              child: ListTile(
                                leading: Icon(Icons.delete_outline),
                                title: Text('Удалить фото'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (photo.amount != null)
                    Text(
                      NumberFormat.currency(locale: 'ru_RU', symbol: '₽')
                          .format(photo.amount),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    )
                  else
                    Text(
                      DateFormat('dd.MM.yyyy').format(photo.createdAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (_receiptCategoryLabel() != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      _receiptCategoryLabel()!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (photo.receiptDate != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('dd.MM.yyyy').format(photo.receiptDate!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (photo.comment?.isNotEmpty == true) ...[
                    const SizedBox(height: 3),
                    Text(
                      photo.comment!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhotoCardAction {
  delete,
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final PhotoType type;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          type.label,
          style: const TextStyle(
            color: Color(0xFF1D4ED8),
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}
