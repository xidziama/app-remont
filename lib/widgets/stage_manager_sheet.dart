import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/repair_stage.dart';
import '../repositories/project_repository.dart';
import '../utils/stage_ui_utils.dart';
import 'stage_form_sheet.dart';

/// Bottom sheet управления этапами.
///
/// Здесь пользователь может создать, отредактировать или удалить этап.
/// Экран фото остается чище: он только открывает этот sheet из AppBar.
class StageManagerSheet extends StatelessWidget {
  const StageManagerSheet({
    super.key,
    required this.projectId,
    required this.stages,
  });

  final String projectId;
  final List<RepairStage> stages;

  Future<void> _createStage(BuildContext context) async {
    await showModalBottomSheet<RepairStage>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StageFormSheet(projectId: projectId),
    );
  }

  Future<void> _editStage(BuildContext context, RepairStage stage) async {
    await showModalBottomSheet<RepairStage>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StageFormSheet(
        projectId: projectId,
        initialStage: stage,
      ),
    );
  }

  Future<void> _deleteStage(BuildContext context, RepairStage stage) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить этап?'),
        content: Text(
          'Фото не будут удалены, но для них будет показано "Этап удален". '
          'Это действие можно исправить только созданием нового этапа.',
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

    try {
      await context.read<ProjectRepository>().deleteStage(projectId, stage.id);
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить этап: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxListHeight = MediaQuery.of(context).size.height * 0.62;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Этапы работ',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Создать этап',
                  onPressed: () => _createStage(context),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxListHeight),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: stages.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final stage = stages[index];
                  final color = StageUiUtils.colorFromInt(stage.color);

                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: color.withOpacity(0.12),
                        child: Icon(
                          StageUiUtils.iconFromName(stage.icon),
                          color: color,
                        ),
                      ),
                      title: Text(stage.name),
                      subtitle: Text('Порядок: ${stage.sortOrder}'),
                      trailing: Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Редактировать',
                            onPressed: () => _editStage(context, stage),
                            icon: const Icon(Icons.edit),
                          ),
                          IconButton(
                            tooltip: 'Удалить',
                            onPressed: () => _deleteStage(context, stage),
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
