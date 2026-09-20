import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/photo.dart';
import '../models/project.dart';
import '../models/repair_stage.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/photo_filter_bar.dart';
import '../widgets/photo_upload_sheet.dart';
import '../widgets/project_photo_card.dart';
import '../widgets/stage_manager_sheet.dart';

/// Экран фотографий объекта.
///
/// Здесь собраны пользовательские сценарии:
/// - создание дефолтных этапов;
/// - загрузка фото с выбором этапа;
/// - создание/редактирование/удаление этапов;
/// - поиск по фото;
/// - фильтрация по этапу;
/// - группировка фото по этапам;
/// - удаление фото.
class PhotosScreen extends StatefulWidget {
  const PhotosScreen({
    super.key,
    required this.project,
    required this.company,
  });

  final Project project;
  final CompanyMember company;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  String _searchQuery = '';
  String? _selectedStageId;

  // UX decision: этапы больше не создаются автоматически. Поле оставлено true,
  // чтобы старый bootstrap-код ниже не запускался и не ломал ручной сценарий.

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Этапы больше не создаются автоматически при открытии экрана фото.
    // Прораб сам добавляет нужные этапы под конкретный объект.
  }

  Future<void> _openUploadSheet(List<RepairStage> stages) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => PhotoUploadSheet(
        project: widget.project,
        stages: stages,
      ),
    );
  }

  Future<void> _openStageManager(List<RepairStage> stages) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StageManagerSheet(
        projectId: widget.project.id,
        stages: stages,
      ),
    );
  }

  Future<void> _deletePhoto(Photo photo) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить фото?'),
        content: const Text(
          'Фотография будет удалена из списка. Файл в Storage тоже будет '
          'удален, если он доступен.',
        ),
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

    if (confirmed != true || !mounted) {
      return;
    }

    final repository = context.read<ProjectRepository>();

    try {
      await repository.deleteStagePhoto(photo);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить фото: $error')),
      );
    }
  }

  List<Photo> _filterPhotos(
    List<Photo> photos,
    Map<String, RepairStage> stageById,
  ) {
    final query = _searchQuery.trim().toLowerCase();

    return photos.where((photo) {
      final stage = stageById[photo.stageId];
      final stageName = stage?.name ?? 'Этап удален';

      if (_selectedStageId != null && photo.stageId != _selectedStageId) {
        return false;
      }

      if (query.isEmpty) {
        return true;
      }

      final searchableText = [
        stageName,
        photo.comment ?? '',
        photo.uploadedBy,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

  List<_PhotoFeedItem> _buildFeedItems({
    required List<Photo> photos,
    required List<RepairStage> stages,
  }) {
    final grouped = <String, List<Photo>>{};

    for (final photo in photos) {
      final key = photo.stageId.isEmpty ? _missingStageId : photo.stageId;
      grouped.putIfAbsent(key, () => <Photo>[]).add(photo);
    }

    final items = <_PhotoFeedItem>[];

    for (final stage in stages) {
      final stagePhotos = grouped[stage.id] ?? <Photo>[];
      if (stagePhotos.isEmpty) {
        continue;
      }

      items.add(_PhotoFeedItem.header(stage: stage, count: stagePhotos.length));
      for (final photo in stagePhotos) {
        items.add(_PhotoFeedItem.photo(photo: photo, stage: stage));
      }
    }

    final missingPhotos = grouped[_missingStageId] ?? <Photo>[];
    if (missingPhotos.isNotEmpty) {
      items
          .add(_PhotoFeedItem.header(stage: null, count: missingPhotos.length));
      for (final photo in missingPhotos) {
        items.add(_PhotoFeedItem.photo(photo: photo, stage: null));
      }
    }

    return items;
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return StreamBuilder<List<RepairStage>>(
      stream: repository.watchStages(widget.project.id),
      builder: (context, stageSnapshot) {
        final stages = stageSnapshot.data ?? <RepairStage>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('Фото'),
            actions: [
              if (widget.company.role.isOwner || widget.company.role.isManager)
                IconButton(
                  tooltip: 'Этапы работ',
                  onPressed: () => _openStageManager(stages),
                  icon: const Icon(Icons.flag),
                ),
            ],
          ),
          body: _buildBody(
            context: context,
            stages: stages,
            stageSnapshot: stageSnapshot,
            repository: repository,
          ),
          floatingActionButton:
              widget.company.role.isOwner || widget.company.role.isManager
                  ? FloatingActionButton.extended(
                      onPressed: () => _openUploadSheet(stages),
                      icon: const Icon(Icons.add_a_photo),
                      label: const Text('Фото'),
                    )
                  : null,
        );
      },
    );
  }

  Widget _buildBody({
    required BuildContext context,
    required List<RepairStage> stages,
    required AsyncSnapshot<List<RepairStage>> stageSnapshot,
    required ProjectRepository repository,
  }) {
    if (stageSnapshot.hasError) {
      return EmptyState(
        icon: Icons.error_outline,
        title: 'Не удалось загрузить этапы',
        subtitle: stageSnapshot.error.toString(),
      );
    }

    if (stageSnapshot.connectionState == ConnectionState.waiting) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        PhotoFilterBar(
          stages: stages,
          searchQuery: _searchQuery,
          selectedStageId: _selectedStageId,
          onSearchChanged: (value) {
            setState(() => _searchQuery = value);
          },
          onStageChanged: (value) {
            setState(() => _selectedStageId = value);
          },
        ),
        Expanded(
          child: StreamBuilder<List<Photo>>(
            stream: repository.watchProjectPhotosAcrossStages(widget.project.id),
            builder: (context, photoSnapshot) {
              if (photoSnapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить фото',
                  subtitle: photoSnapshot.error.toString(),
                );
              }

              if (photoSnapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final photos = photoSnapshot.data ?? <Photo>[];
              final stageById = {for (final stage in stages) stage.id: stage};
              final filteredPhotos = _filterPhotos(photos, stageById);

              if (photos.isEmpty) {
                return const EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: 'Фото нет',
                  subtitle: 'Добавьте фото и привяжите его к этапу работ.',
                );
              }

              if (filteredPhotos.isEmpty) {
                return const EmptyState(
                  icon: Icons.search_off,
                  title: 'Ничего не найдено',
                  subtitle: 'Измените поиск или фильтр по этапу.',
                );
              }

              final items = _buildFeedItems(
                photos: filteredPhotos,
                stages: stages,
              );

              return ListView.builder(
                key: PageStorageKey<String>('photos_${widget.project.id}'),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[index];

                  if (item.header) {
                    return _StageHeader(
                      stage: item.stage,
                      count: item.count,
                    );
                  }

                  final photo = item.photo!;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ProjectPhotoCard(
                      photo: photo,
                      stage: item.stage,
                      onDelete: () => _deletePhoto(photo),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

const _missingStageId = '__missing_stage__';

class _PhotoFeedItem {
  const _PhotoFeedItem.header({
    required this.stage,
    required this.count,
  })  : header = true,
        photo = null;

  const _PhotoFeedItem.photo({
    required this.photo,
    required this.stage,
  })  : header = false,
        count = 0;

  final bool header;
  final RepairStage? stage;
  final int count;
  final Photo? photo;
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({
    required this.stage,
    required this.count,
  });

  final RepairStage? stage;
  final int count;

  @override
  Widget build(BuildContext context) {
    final title = stage?.name ?? 'Этап удален';

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Text(
            '$count фото',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                ),
          ),
        ],
      ),
    );
  }
}
