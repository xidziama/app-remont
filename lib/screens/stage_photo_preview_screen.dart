import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/expense.dart';
import '../models/photo.dart';
import '../repositories/project_repository.dart';

class StagePhotoPreviewScreen extends StatelessWidget {
  const StagePhotoPreviewScreen({
    super.key,
    required this.photo,
    this.canDelete = true,
  });

  final Photo photo;
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

  Future<void> _deletePhoto(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text('Файл и запись будут удалены из этапа.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);

    try {
      await context.read<ProjectRepository>().deleteStagePhoto(photo);

      if (!context.mounted) {
        return;
      }

      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Фото удалено.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось удалить фото: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(photo.type.label),
        actions: [
          if (canDelete)
            PopupMenuButton<_PreviewAction>(
              tooltip: 'Действия',
              onSelected: (action) {
                switch (action) {
                  case _PreviewAction.delete:
                    _deletePhoto(context);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: _PreviewAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('Удалить фото'),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Center(
                child: CachedNetworkImage(
                  imageUrl: photo.downloadUrl,
                  fit: BoxFit.contain,
                  placeholder: (context, _) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                  errorWidget: (context, _, __) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (photo.comment?.isNotEmpty == true ||
              photo.amount != null ||
              photo.receiptCategory != null ||
              photo.receiptDate != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withAlpha(190),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (photo.amount != null)
                          Text(
                            NumberFormat.currency(
                              locale: 'ru_RU',
                              symbol: '₽',
                            ).format(photo.amount),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        if (_receiptCategoryLabel() != null) ...[
                          if (photo.amount != null) const SizedBox(height: 8),
                          Text(
                            _receiptCategoryLabel()!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                        if (photo.receiptDate != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            DateFormat('dd.MM.yyyy').format(photo.receiptDate!),
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                        if (photo.isPaid && photo.paidAt != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            'Оплачено: ${DateFormat('dd.MM.yyyy').format(photo.paidAt!)}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                        if (photo.comment?.isNotEmpty == true) ...[
                          const SizedBox(height: 8),
                          Text(
                            photo.comment!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

enum _PreviewAction {
  delete,
}
