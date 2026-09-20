import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../widgets/project_stages_section.dart';
import '../widgets/status_chip.dart';
import 'chat_screen.dart';
import 'expenses_screen.dart';
import 'participants_screen.dart';
import 'photos_screen.dart';

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({
    super.key,
    required this.project,
    required this.company,
  });

  final Project project;
  final CompanyMember company;

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  final Set<String> _selectedStageIds = <String>{};
  bool _stageSelectionMode = false;
  bool _deletingStages = false;

  // Стрим создается один раз за жизнь State, а не на каждый build().
  // Иначе StreamBuilder видит "новый" Stream-объект при каждой пересборке
  // экрана (например, во время интерактивного жеста "назад") и сбрасывает
  // snapshot в ConnectionState.waiting, хотя данные уже были загружены.
  late Stream<Project?> _projectStream;

  @override
  void initState() {
    super.initState();
    _projectStream =
        context.read<ProjectRepository>().watchProject(widget.project.id);
  }

  @override
  void didUpdateWidget(ProjectDetailScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    // На практике widget.project.id не меняется за время жизни этого экрана
    // (новый объект открывается через новый push с новым State). Эта проверка
    // защищает от теоретического случая, когда родитель переиспользует тот же
    // State для другого id.
    if (widget.project.id != oldWidget.project.id) {
      _projectStream =
          context.read<ProjectRepository>().watchProject(widget.project.id);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _enableStageSelectionMode() {
    setState(() {
      _stageSelectionMode = true;
      _selectedStageIds.clear();
    });
  }

  void _cancelStageSelectionMode() {
    setState(() {
      _stageSelectionMode = false;
      _selectedStageIds.clear();
    });
  }

  void _toggleStageSelection(Stage stage, bool selected) {
    setState(() {
      if (selected) {
        _selectedStageIds.add(stage.id);
      } else {
        _selectedStageIds.remove(stage.id);
      }
    });
  }

  Future<bool> _confirmForcedCompletion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Не все этапы работ завершены.'),
        content: const Text(
          'Вы можете вернуться и завершить этапы или завершить объект '
          'принудительно.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Завершить принудительно'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  Future<void> _updateProjectStatus({
    required BuildContext sheetContext,
    required Project project,
    required ProjectStatus status,
  }) async {
    final repository = context.read<ProjectRepository>();

    try {
      if (status == ProjectStatus.closed) {
        final hasIncompleteStages =
            await repository.hasIncompleteProductionStages(project.id);

        if (hasIncompleteStages) {
          if (!mounted) {
            return;
          }

          final forceComplete = await _confirmForcedCompletion();
          if (!forceComplete) {
            return;
          }
        }
      }

      await repository.updateProjectStatus(
        projectId: project.id,
        status: status,
      );

      if (sheetContext.mounted) {
        Navigator.of(sheetContext).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Не удалось изменить статус: $error');
    }
  }

  Future<void> _openStatusSheet(Project currentProject) async {
    final statuses = _availableStatuses(currentProject);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Изменить статус',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ),
              for (final status in statuses)
                ListTile(
                  leading: Icon(
                    status == currentProject.status
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  title: Text(status.label),
                  selected: status == currentProject.status,
                  onTap: () => _updateProjectStatus(
                    sheetContext: sheetContext,
                    project: currentProject,
                    status: status,
                  ),
                ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  List<ProjectStatus> _availableStatuses(Project project) {
    if (widget.company.role.isManager) {
      return const [
        ProjectStatus.inProgress,
        ProjectStatus.paused,
        ProjectStatus.directorReview,
      ];
    }

    if (widget.company.role.isOwner) {
      return const [
        ProjectStatus.inProgress,
        ProjectStatus.paused,
        ProjectStatus.clientReview,
        ProjectStatus.closed,
      ];
    }

    if (widget.company.role.isClient &&
        project.status == ProjectStatus.clientReview) {
      return const [ProjectStatus.closed];
    }

    return const [ProjectStatus.inProgress, ProjectStatus.paused];
  }

  Future<void> _deleteSelectedStages(Project project) async {
    if (_selectedStageIds.isEmpty) {
      _showMessage('Выберите хотя бы один этап.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить выбранные этапы?'),
        content: const Text(
          'Фотографии, чеки и события timeline, связанные с этими этапами, '
          'также могут быть удалены.',
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

    setState(() => _deletingStages = true);

    try {
      await context.read<ProjectRepository>().deleteProductionStages(
            projectId: project.id,
            stageIds: _selectedStageIds,
          );

      if (!mounted) {
        return;
      }

      setState(() {
        _stageSelectionMode = false;
        _selectedStageIds.clear();
      });
      _showMessage('Этапы удалены.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Не удалось удалить этапы: $error');
    } finally {
      if (mounted) {
        setState(() => _deletingStages = false);
      }
    }
  }

  void _handleMenuAction(_ProjectMenuAction action, Project project) {
    switch (action) {
      case _ProjectMenuAction.editDetails:
        _openEditDetailsSheet(project);
      case _ProjectMenuAction.changeStatus:
        _openStatusSheet(project);
      case _ProjectMenuAction.selectStages:
        _enableStageSelectionMode();
    }
  }

  Future<void> _openEditDetailsSheet(Project project) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _EditProjectDetailsSheet(project: project),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Project?>(
      stream: _projectStream,
      builder: (context, snapshot) {
        final currentProject = snapshot.data ?? widget.project;
        final sections = [
          _ProjectSection(
            title: 'Участники',
            subtitle: 'Прорабы, подрядчики и заказчики объекта',
            icon: Icons.groups,
            builder: (_) => ParticipantsScreen(
              project: currentProject,
              company: widget.company,
            ),
          ),
          _ProjectSection(
            title: 'Чат',
            subtitle: 'Обсуждение объекта между участниками',
            icon: Icons.chat_bubble_outline,
            builder: (_) => ChatScreen(
              project: currentProject,
              company: widget.company,
            ),
          ),
          _ProjectSection(
            title: 'Чеки и расходы',
            subtitle: 'Фото чеков, суммы, категории и даты',
            icon: Icons.receipt_long,
            builder: (_) => ExpensesScreen(
              project: currentProject,
              company: widget.company,
            ),
          ),
          _ProjectSection(
            title: 'Фото',
            subtitle: 'Фото объекта и этапов работ',
            icon: Icons.photo_library_outlined,
            builder: (_) => PhotosScreen(
              project: currentProject,
              company: widget.company,
            ),
          ),
        ];

        return Scaffold(
          appBar: AppBar(
            leading: _stageSelectionMode
                ? IconButton(
                    tooltip: 'Выйти из режима выбора',
                    onPressed:
                        _deletingStages ? null : _cancelStageSelectionMode,
                    icon: const Icon(Icons.close),
                  )
                : null,
            title: Text(
              _stageSelectionMode
                  ? 'Выбрано: ${_selectedStageIds.length}'
                  : currentProject.title,
            ),
            actions: [
              if (_stageSelectionMode)
                IconButton(
                  tooltip: 'Удалить выбранные этапы',
                  onPressed: _deletingStages || _selectedStageIds.isEmpty
                      ? null
                      : () => _deleteSelectedStages(currentProject),
                  icon: _deletingStages
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                )
              else if (widget.company.role.isOwner ||
                  widget.company.role.isManager ||
                  (widget.company.role.isClient &&
                      currentProject.status == ProjectStatus.clientReview))
                PopupMenuButton<_ProjectMenuAction>(
                  tooltip: 'Действия',
                  onSelected: (action) =>
                      _handleMenuAction(action, currentProject),
                  itemBuilder: (context) => [
                    if (widget.company.role.isOwner ||
                        widget.company.role.isManager)
                      const PopupMenuItem(
                        value: _ProjectMenuAction.editDetails,
                        child: ListTile(
                          leading: Icon(Icons.edit_outlined),
                          title: Text('Редактировать объект'),
                        ),
                      ),
                    const PopupMenuItem(
                      value: _ProjectMenuAction.changeStatus,
                      child: ListTile(
                        leading: Icon(Icons.tune),
                        title: Text('Изменить статус'),
                      ),
                    ),
                    if (widget.company.role.isOwner ||
                        widget.company.role.isManager)
                      const PopupMenuItem(
                        value: _ProjectMenuAction.selectStages,
                        child: ListTile(
                          leading: Icon(Icons.checklist),
                          title: Text('Выбрать этапы'),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          body: ListView(
            key: PageStorageKey<String>(
              'project_detail_${currentProject.id}',
            ),
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              currentProject.title,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 12),
                          StatusChip(status: currentProject.status),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.place_outlined, size: 20),
                          const SizedBox(width: 8),
                          Expanded(child: Text(currentProject.address)),
                        ],
                      ),
                      if (currentProject.description.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(currentProject.description),
                      ],
                      const SizedBox(height: 16),
                      LinearProgressIndicator(
                        value: currentProject.progressValue,
                        minHeight: 8,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Завершено этапов: '
                        '${currentProject.completedStages} из '
                        '${currentProject.totalStages} '
                        '(${currentProject.progressPercent}%)',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              ProjectStagesSection(
                project: currentProject,
                company: widget.company,
                selectionMode: _stageSelectionMode,
                selectedStageIds: _selectedStageIds,
                onStageSelectionChanged: _toggleStageSelection,
              ),
              const SizedBox(height: 8),
              for (final section in sections)
                Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: Icon(section.icon),
                    title: Text(section.title),
                    subtitle: Text(section.subtitle),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: _stageSelectionMode
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(builder: section.builder),
                            ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

enum _ProjectMenuAction {
  editDetails,
  changeStatus,
  selectStages,
}

class _ProjectSection {
  const _ProjectSection({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.builder,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final WidgetBuilder builder;
}

/// Bottom sheet редактирования названия и адреса объекта.
///
/// Сохраняет только эти два поля через
/// [ProjectRepository.updateProjectDetails] — частичный .update(), а не
/// полная перезапись документа объекта.
class _EditProjectDetailsSheet extends StatefulWidget {
  const _EditProjectDetailsSheet({required this.project});

  final Project project;

  @override
  State<_EditProjectDetailsSheet> createState() =>
      _EditProjectDetailsSheetState();
}

class _EditProjectDetailsSheetState extends State<_EditProjectDetailsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleController;
  late final TextEditingController _addressController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.project.title);
    _addressController = TextEditingController(text: widget.project.address);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().updateProjectDetails(
            projectId: widget.project.id,
            title: _titleController.text.trim(),
            address: _addressController.text.trim(),
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось сохранить изменения: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Редактировать объект',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _titleController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Название объекта',
                    prefixIcon: Icon(Icons.home_work_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите название объекта';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Адрес',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Введите адрес объекта';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check),
                  label: Text(_saving ? 'Сохранение...' : 'Сохранить'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
