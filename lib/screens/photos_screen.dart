import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/project.dart';
import '../models/project_photo.dart';
import '../models/repair_stage.dart';
import '../repositories/project_repository.dart';
import '../services/storage_service.dart';
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
  const PhotosScreen({super.key, required this.project});

  final Project project;

  @override
  State<PhotosScreen> createState() => _PhotosScreenState();
}

class _PhotosScreenState extends State<PhotosScreen> {
  String _searchQuery = '';
  String? _selectedStageId;
  bool _defaultStagesRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // didChangeDependencies безопасно имеет доступ к Provider.
    // Запрашиваем создание дефолтных этапов только один раз за жизнь экрана.
    if (!_defaultStagesRequested) {
      _defaultStagesRequested = true;
      _ensureDefaultStages();
    }
  }

  Future<void> _ensureDefaultStages() async {
    try {
      await context
          .read<ProjectRepository>()
          .ensureDefaultStages(widget.project.id);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось создать этапы по умолчанию: $error')),
      );
    }
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

  Future<void> _deletePhoto(ProjectPhoto photo) async {
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
      // Сначала пытаемся удалить файл из Storage.
      // Если файл уже удален или URL старый, metadata все равно удалим ниже.
      try {
        await StorageService.instance.deleteByUrl(photo.imageUrl);
      } catch (_) {
        // Storage cleanup не должен блокировать удаление карточки из UI.
      }

      await repository.deletePhoto(widget.project.id, photo.id);
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить фото: $error')),
      );
    }
  }

  List<ProjectPhoto> _filterPhotos(
    List<ProjectPhoto> photos,
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
        photo.description,
        photo.uploadedBy,
      ].join(' ').toLowerCase();

      return searchableText.contains(query);
    }).toList();
  }

  List<_PhotoFeedItem> _buildFeedItems({
    required List<ProjectPhoto> photos,
    required List<RepairStage> stages,
  }) {
    final stageById = {for (final stage in stages) stage.id: stage};
    final grouped = <String, List<ProjectPhoto>>{};

    for (final photo in photos) {
      final key = photo.stageId.isEmpty ? _missingStageId : photo.stageId;
      grouped.putIfAbsent(key, () => <ProjectPhoto>[]).add(photo);
    }

    final items = <_PhotoFeedItem>[];

    for (final stage in stages) {
      final stagePhotos = grouped[stage.id] ?? <ProjectPhoto>[];
      if (stagePhotos.isEmpty) {
        continue;
      }

      items.add(_PhotoFeedItem.header(stage: stage, count: stagePhotos.length));
      for (final photo in stagePhotos) {
        items.add(_PhotoFeedItem.photo(photo: photo, stage: stage));
      }
    }

    final missingPhotos = grouped[_missingStageId] ?? <ProjectPhoto>[];
    if (missingPhotos.isNotEmpty) {
      items.add(_PhotoFeedItem.header(stage: null, count: missingPhotos.length));
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
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openUploadSheet(stages),
            icon: const Icon(Icons.add_a_photo),
            label: const Text('Фото'),
          ),
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
          child: StreamBuilder<List<ProjectPhoto>>(
            stream: repository.watchPhotos(widget.project.id),
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

              final photos = photoSnapshot.data ?? <ProjectPhoto>[];
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
  final ProjectPhoto? photo;
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
