import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/photo.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';
import '../widgets/stage_photo_card.dart';
import '../widgets/stage_photo_upload_sheet.dart';
import 'stage_photo_preview_screen.dart';

/// Stage details screen.
///
/// The screen keeps the MVP scope focused: stage workflow, progress photos and
/// receipts. Stage chat and complex editing are intentionally outside this
/// screen.
class StageDetailScreen extends StatelessWidget {
  const StageDetailScreen({
    super.key,
    required this.project,
    required this.initialStage,
    required this.company,
  });

  final Project project;
  final Stage initialStage;
  final CompanyMember company;

  Future<void> _deleteStage(BuildContext context, Stage stage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить этап?'),
        content: const Text(
          'Фотографии и чеки этого этапа также будут удалены.',
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

    if (confirmed != true || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    try {
      await context.read<ProjectRepository>().deleteProductionStage(stage);

      if (!context.mounted) {
        return;
      }

      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('Этап удален.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось удалить этап: $error')),
      );
    }
  }

  Future<void> _renameStage(BuildContext context, Stage stage) async {
    final controller = TextEditingController(text: stage.title);

    final newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Переименовать этап'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название этапа'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              Navigator.of(dialogContext).pop(trimmed.isEmpty ? null : trimmed);
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (newTitle == null || newTitle == stage.title || !context.mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      await context.read<ProjectRepository>().renameProductionStage(
            projectId: stage.projectId,
            stageId: stage.id,
            title: newTitle,
          );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('Не удалось переименовать этап: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return StreamBuilder<Stage?>(
      stream: repository.watchProductionStage(project.id, initialStage.id),
      builder: (context, snapshot) {
        final stage = snapshot.data ?? initialStage;

        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: Text(stage.title),
              actions: [
                if (company.role.isOwner || company.role.isManager)
                  PopupMenuButton<_StageDetailMenuAction>(
                    tooltip: 'Действия',
                    onSelected: (action) {
                      switch (action) {
                        case _StageDetailMenuAction.renameStage:
                          _renameStage(context, stage);
                        case _StageDetailMenuAction.deleteStage:
                          _deleteStage(context, stage);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _StageDetailMenuAction.renameStage,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Переименовать этап'),
                        ),
                      ),
                      PopupMenuItem(
                        value: _StageDetailMenuAction.deleteStage,
                        child: ListTile(
                          leading: Icon(Icons.delete_outline),
                          title: Text('Удалить этап'),
                        ),
                      ),
                    ],
                  ),
              ],
              bottom: const TabBar(
                tabs: [
                  Tab(text: 'Прогресс'),
                  Tab(text: 'Чеки'),
                ],
              ),
            ),
            body: Column(
              children: [
                _StageHeader(stage: stage, company: company),
                Expanded(
                  child: TabBarView(
                    children: [
                      _StagePhotoTab(
                        stage: stage,
                        types: const [
                          PhotoType.before,
                          PhotoType.progress,
                          PhotoType.after,
                          PhotoType.problem,
                        ],
                        emptyTitle: 'Фото прогресса пока нет',
                        emptySubtitle:
                            'Добавьте фото до, в процессе, после или проблему.',
                        canUpload: _canEditStage(stage),
                        canDelete:
                            company.role.isOwner || company.role.isManager,
                      ),
                      _StageReceiptTab(stage: stage, company: company),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _canEditStage(Stage stage) {
    if (company.role.isOwner || company.role.isManager) {
      return true;
    }

    if (company.role.isWorker) {
      return stage.assignedUserIds.contains(company.uid);
    }

    return false;
  }
}

enum _StageDetailMenuAction {
  renameStage,
  deleteStage,
}

class _StageHeader extends StatelessWidget {
  const _StageHeader({required this.stage, required this.company});

  final Stage stage;
  final CompanyMember company;

  Future<void> _changeStatus(
    BuildContext context,
    StageStatus status,
  ) async {
    DateTime? completedAt;

    if (status == StageStatus.completed) {
      completedAt = await showDatePicker(
        context: context,
        initialDate: stage.completedAt ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now().add(const Duration(days: 365)),
      );

      if (completedAt == null || !context.mounted) {
        return;
      }
    }

    try {
      await context.read<ProjectRepository>().updateProductionStageStatus(
            stage: stage,
            status: status,
            completedAt: completedAt,
          );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось изменить статус: $error')),
      );
    }
  }

  List<_StageAction> _actions() {
    final isAssignedWorker =
        company.role.isWorker && stage.assignedUserIds.contains(company.uid);
    final canManage =
        company.role.isOwner || company.role.isManager || isAssignedWorker;

    if (!canManage || company.role.isClient) {
      return const [];
    }

    switch (stage.status) {
      case StageStatus.notStarted:
        return [
          _StageAction('Начать', Icons.play_arrow, StageStatus.inProgress),
        ];
      case StageStatus.inProgress:
        return [
          _StageAction(
            'На проверку',
            Icons.rate_review,
            StageStatus.review,
          ),
        ];
      case StageStatus.review:
        if (company.role.isWorker) {
          return const [];
        }

        return [
          _StageAction(
            'Завершить',
            Icons.check_circle,
            StageStatus.completed,
          ),
          _StageAction(
            'Проблема',
            Icons.report_problem,
            StageStatus.problem,
          ),
        ];
      case StageStatus.problem:
        if (company.role.isWorker) {
          return const [];
        }

        return [
          _StageAction(
            'Вернуть в работу',
            Icons.restart_alt,
            StageStatus.inProgress,
          ),
        ];
      case StageStatus.completed:
        return const [];
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions();

    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    stage.status.label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text('${stage.progress}%'),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: stage.progress.clamp(0, 100).toDouble() / 100,
            ),
            if (stage.isCompleted && stage.completedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                'Завершено: ${DateFormat('dd.MM.yyyy').format(stage.completedAt!)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in actions)
                    FilledButton.tonalIcon(
                      onPressed: () => _changeStatus(context, action.status),
                      icon: Icon(action.icon),
                      label: Text(action.label),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StageAction {
  const _StageAction(this.label, this.icon, this.status);

  final String label;
  final IconData icon;
  final StageStatus status;
}

class _StagePhotoTab extends StatelessWidget {
  const _StagePhotoTab({
    required this.stage,
    required this.types,
    required this.emptyTitle,
    required this.emptySubtitle,
    this.isPaid,
    this.showUpload = true,
    this.canUpload = true,
    this.canDelete = true,
    this.selectionMode = false,
    this.selectedPhotoIds = const <String>{},
    this.onSelectionChanged,
  });

  final Stage stage;
  final List<PhotoType> types;
  final String emptyTitle;
  final String emptySubtitle;
  final bool? isPaid;
  final bool showUpload;
  final bool canUpload;
  final bool canDelete;
  final bool selectionMode;
  final Set<String> selectedPhotoIds;
  final void Function(Photo photo, bool selected)? onSelectionChanged;

  Future<void> _openUpload(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StagePhotoUploadSheet(
        stage: stage,
        allowedTypes: types,
      ),
    );
  }

  Future<void> _deletePhoto(BuildContext context, Photo photo) async {
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

    try {
      await context.read<ProjectRepository>().deleteStagePhoto(photo);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Фото удалено.')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить фото: $error')),
      );
    }
  }

  void _openPreview(BuildContext context, Photo photo) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StagePhotoPreviewScreen(
          photo: photo,
          canDelete: canDelete,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();
    final isReceiptOnly = types.length == 1 && types.first == PhotoType.receipt;

    return Column(
      children: [
        if (showUpload && canUpload)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => _openUpload(context),
                icon: const Icon(Icons.add),
                label: Text(isReceiptOnly ? 'Добавить чек' : 'Добавить'),
              ),
            ),
          ),
        Expanded(
          child: StreamBuilder<List<Photo>>(
            stream: repository.watchStagePhotos(
              projectId: stage.projectId,
              stageId: stage.id,
              types: types,
              isPaid: isPaid,
            ),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить фото',
                  subtitle: snapshot.error.toString(),
                );
              }

              final photos = snapshot.data ?? <Photo>[];

              if (photos.isEmpty) {
                return EmptyState(
                  icon: Icons.photo_library_outlined,
                  title: emptyTitle,
                  subtitle: emptySubtitle,
                );
              }

              return GridView.builder(
                key: PageStorageKey<String>(
                  'stage_photos_${stage.projectId}_${stage.id}_${types.map((type) => type.firestoreValue).join('_')}',
                ),
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 220,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.78,
                ),
                itemCount: photos.length,
                itemBuilder: (context, index) {
                  final photo = photos[index];
                  final selected = selectedPhotoIds.contains(photo.id);
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: StagePhotoCard(
                          photo: photo,
                          canDelete: canDelete,
                          onOpen: selectionMode
                              ? () => onSelectionChanged?.call(
                                    photo,
                                    !selected,
                                  )
                              : () => _openPreview(context, photo),
                          onDelete: () => _deletePhoto(context, photo),
                        ),
                      ),
                      if (selectionMode)
                        Positioned(
                          left: 6,
                          top: 6,
                          child: Checkbox(
                            value: selected,
                            onChanged: (value) => onSelectionChanged?.call(
                              photo,
                              value ?? false,
                            ),
                          ),
                        ),
                    ],
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

class _StageReceiptTab extends StatefulWidget {
  const _StageReceiptTab({
    required this.stage,
    required this.company,
  });

  final Stage stage;
  final CompanyMember company;

  @override
  State<_StageReceiptTab> createState() => _StageReceiptTabState();
}

class _StageReceiptTabState extends State<_StageReceiptTab> {
  final Set<String> _selectedReceiptIds = <String>{};
  final Map<String, Photo> _selectedReceipts = <String, Photo>{};
  bool _showPaid = false;
  bool _selectionMode = false;
  bool _saving = false;

  void _toggleSelection(Photo photo, bool selected) {
    setState(() {
      if (selected) {
        _selectedReceiptIds.add(photo.id);
        _selectedReceipts[photo.id] = photo;
      } else {
        _selectedReceiptIds.remove(photo.id);
        _selectedReceipts.remove(photo.id);
      }
    });
  }

  void _cancelSelection() {
    setState(() {
      _selectionMode = false;
      _selectedReceiptIds.clear();
      _selectedReceipts.clear();
    });
  }

  Future<void> _markSelectedPaid() async {
    if (_selectedReceipts.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отметить выбранные чеки как оплаченные?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Оплачено'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().markStageReceiptsPaid(
            projectId: widget.stage.projectId,
            receipts: _selectedReceipts.values,
          );

      if (!mounted) {
        return;
      }

      _cancelSelection();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Чеки отмечены оплаченными')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отметить чеки: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Card(
            child: ListTile(
              title: Text(_showPaid ? 'Оплаченные чеки' : 'Общая сумма чеков'),
              leading: _selectionMode
                  ? IconButton(
                      onPressed: _saving ? null : _cancelSelection,
                      icon: const Icon(Icons.close),
                    )
                  : null,
              subtitle: _selectionMode
                  ? Text('Выбрано: ${_selectedReceiptIds.length}')
                  : null,
              onTap: _selectionMode || _showPaid ? null : null,
              isThreeLine: _selectionMode,
              contentPadding: const EdgeInsets.only(left: 12, right: 4),
              minLeadingWidth: 0,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _showPaid
                        ? 'Архив'
                        : NumberFormat.currency(
                            locale: 'ru_RU',
                            symbol: '₽',
                          ).format(widget.stage.receiptsTotal),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  PopupMenuButton<_ReceiptMenuAction>(
                    onSelected: (action) {
                      switch (action) {
                        case _ReceiptMenuAction.togglePaid:
                          setState(() {
                            _showPaid = !_showPaid;
                            _selectionMode = false;
                            _selectedReceiptIds.clear();
                            _selectedReceipts.clear();
                          });
                        case _ReceiptMenuAction.selectReceipts:
                          setState(() {
                            _showPaid = false;
                            _selectionMode = true;
                            _selectedReceiptIds.clear();
                            _selectedReceipts.clear();
                          });
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: _ReceiptMenuAction.togglePaid,
                        child: ListTile(
                          leading: const Icon(Icons.payments_outlined),
                          title: Text(
                            _showPaid ? 'Активные чеки' : 'Оплаченные чеки',
                          ),
                        ),
                      ),
                      if (!_showPaid &&
                          (widget.company.role.isOwner ||
                              widget.company.role.isManager))
                        const PopupMenuItem(
                          value: _ReceiptMenuAction.selectReceipts,
                          child: ListTile(
                            leading: Icon(Icons.checklist),
                            title: Text('Выбрать чеки'),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectionMode)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving || _selectedReceiptIds.isEmpty
                    ? null
                    : _markSelectedPaid,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.payments_outlined),
                label: const Text('Отметить оплаченными'),
              ),
            ),
          ),
        Expanded(
          child: _StagePhotoTab(
            stage: widget.stage,
            types: const [PhotoType.receipt],
            isPaid: _showPaid,
            showUpload: !_showPaid && !_selectionMode,
            canUpload: _canUploadReceipt(),
            canDelete:
                widget.company.role.isOwner || widget.company.role.isManager,
            selectionMode: _selectionMode,
            selectedPhotoIds: _selectedReceiptIds,
            onSelectionChanged: _toggleSelection,
            emptyTitle:
                _showPaid ? 'Оплаченных чеков пока нет' : 'Чеков пока нет',
            emptySubtitle: _showPaid
                ? 'Оплаченные чеки этого этапа появятся здесь.'
                : 'Добавьте фото чека и сумму расхода.',
          ),
        ),
      ],
    );
  }

  bool _canUploadReceipt() {
    if (widget.company.role.isOwner || widget.company.role.isManager) {
      return true;
    }

    if (widget.company.role.isWorker) {
      return widget.stage.assignedUserIds.contains(widget.company.uid);
    }

    return false;
  }
}

enum _ReceiptMenuAction {
  togglePaid,
  selectReceipts,
}
