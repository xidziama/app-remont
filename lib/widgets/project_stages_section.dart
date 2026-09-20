import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../screens/stage_detail_screen.dart';
import 'empty_state.dart';
import 'stage_card.dart';

/// Section with work stages on the project detail screen.
///
/// Stages are not auto-created: every repair object can have its own work set,
/// so the foreman manually adds only the stages that are actually needed.
class ProjectStagesSection extends StatefulWidget {
  const ProjectStagesSection({
    super.key,
    required this.project,
    required this.company,
    this.selectionMode = false,
    this.selectedStageIds = const <String>{},
    this.onStageSelectionChanged,
  });

  final Project project;
  final CompanyMember company;
  final bool selectionMode;
  final Set<String> selectedStageIds;
  final void Function(Stage stage, bool selected)? onStageSelectionChanged;

  @override
  State<ProjectStagesSection> createState() => _ProjectStagesSectionState();
}

class _ProjectStagesSectionState extends State<ProjectStagesSection> {
  // Стрим создается один раз за жизнь State, а не на каждый build() — иначе
  // StreamBuilder видит "новый" Stream-объект при каждой пересборке секции
  // (например, во время интерактивного жеста "назад" на экране объекта) и
  // сбрасывает snapshot в ConnectionState.waiting, хотя этапы уже загружены.
  late Stream<List<Stage>> _stagesStream;

  @override
  void initState() {
    super.initState();
    _stagesStream = context
        .read<ProjectRepository>()
        .watchProductionStages(widget.project.id);
  }

  @override
  void didUpdateWidget(ProjectStagesSection oldWidget) {
    super.didUpdateWidget(oldWidget);

    // На практике widget.project.id не меняется за время жизни этой секции.
    // Защита на случай, если родитель когда-нибудь переиспользует тот же
    // State для другого объекта.
    if (widget.project.id != oldWidget.project.id) {
      _stagesStream = context
          .read<ProjectRepository>()
          .watchProductionStages(widget.project.id);
    }
  }

  Future<void> _createStage() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CreateStageSheet(projectId: widget.project.id),
    );
  }

  void _openStage(Stage stage) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StageDetailScreen(
          project: widget.project,
          initialStage: stage,
          company: widget.company,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Stage>>(
      stream: _stagesStream,
      builder: (context, snapshot) {
        final stages = snapshot.data ?? <Stage>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Этапы работ',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (!widget.selectionMode &&
                    (widget.company.role.isOwner ||
                        widget.company.role.isManager))
                  IconButton.filledTonal(
                    tooltip: 'Создать этап',
                    onPressed: _createStage,
                    icon: const Icon(Icons.add),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (snapshot.connectionState == ConnectionState.waiting &&
                !snapshot.hasData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (snapshot.hasError)
              EmptyState(
                icon: Icons.error_outline,
                title: 'Не удалось загрузить этапы',
                subtitle: snapshot.error.toString(),
              )
            else if (stages.isEmpty)
              const EmptyState(
                icon: Icons.flag_outlined,
                title: 'Этапов пока нет',
                subtitle: 'Создайте первый этап работ для этого объекта.',
              )
            else
              ListView.builder(
                key: PageStorageKey<String>(
                  'project_stages_${widget.project.id}',
                ),
                shrinkWrap: true,
                primary: false,
                itemCount: stages.length,
                itemBuilder: (context, index) {
                  final stage = stages[index];
                  final selected = widget.selectedStageIds.contains(stage.id);

                  return StageCard(
                    key: ValueKey(stage.id),
                    stage: stage,
                    selectionMode: widget.selectionMode,
                    selected: selected,
                    onSelectionChanged: (value) {
                      widget.onStageSelectionChanged?.call(stage, value);
                    },
                    onTap: () => _openStage(stage),
                  );
                },
              ),
          ],
        );
      },
    );
  }
}

class _CreateStageSheet extends StatefulWidget {
  const _CreateStageSheet({required this.projectId});

  final String projectId;

  @override
  State<_CreateStageSheet> createState() => _CreateStageSheetState();
}

class _CreateStageSheetState extends State<_CreateStageSheet> {
  final _customTitleController = TextEditingController();
  StageType? _selectedType;
  bool _saving = false;

  static const List<StageType> _availableTypes = [
    StageType.demolition,
    StageType.electricity,
    StageType.plumbing,
    StageType.plaster,
    StageType.tile,
    StageType.painting,
    StageType.custom,
  ];

  @override
  void dispose() {
    _customTitleController.dispose();
    super.dispose();
  }

  bool get _isCustomStage => _selectedType == StageType.custom;

  bool get _canCreate {
    if (_saving || _selectedType == null) {
      return false;
    }

    if (_isCustomStage) {
      return _customTitleController.text.trim().isNotEmpty;
    }

    return true;
  }

  String _stageTitleForSave(StageType type) {
    if (type == StageType.custom) {
      return _customTitleController.text.trim();
    }

    return type.label;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save() async {
    final type = _selectedType;

    if (type == null) {
      _showMessage('Выберите тип этапа.');
      return;
    }

    final title = _stageTitleForSave(type);
    if (title.isEmpty) {
      _showMessage('Введите название этапа.');
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);

    try {
      await context.read<ProjectRepository>().createProductionStage(
            projectId: widget.projectId,
            title: title,
            type: type,
          );

      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Не удалось создать этап: $error');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final selectedType = _selectedType;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              selectedType == null ? 'Выберите тип этапа' : 'Новый этап',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 12),
            if (selectedType == null)
              ..._availableTypes.map(
                (type) => _StageTypeTile(
                  type: type,
                  onTap: () => setState(() => _selectedType = type),
                ),
              )
            else ...[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(_iconForStageType(selectedType)),
                title: Text(selectedType.label),
                subtitle: Text(
                  _isCustomStage
                      ? 'Введите свое название этапа.'
                      : 'Название будет заполнено автоматически.',
                ),
              ),
              if (_isCustomStage) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customTitleController,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Название этапа',
                    hintText: 'Например: фасадные работы',
                    prefixIcon: Icon(Icons.edit_outlined),
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) {
                    if (_canCreate) {
                      _save();
                    }
                  },
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => setState(() => _selectedType = null),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Назад'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _canCreate ? _save : null,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: Text(_saving ? 'Создание...' : 'Создать'),
                    ),
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

class _StageTypeTile extends StatelessWidget {
  const _StageTypeTile({
    required this.type,
    required this.onTap,
  });

  final StageType type;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconForStageType(type)),
        title: Text(type.label),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

IconData _iconForStageType(StageType type) {
  switch (type) {
    case StageType.demolition:
      return Icons.construction;
    case StageType.electricity:
      return Icons.electrical_services;
    case StageType.plumbing:
      return Icons.plumbing;
    case StageType.plaster:
      return Icons.format_paint;
    case StageType.tile:
      return Icons.grid_view;
    case StageType.painting:
      return Icons.format_color_fill;
    case StageType.custom:
      return Icons.add_circle_outline;
    case StageType.putty:
    case StageType.floors:
    case StageType.ceiling:
    case StageType.finalCleaning:
      return Icons.flag_outlined;
  }
}
