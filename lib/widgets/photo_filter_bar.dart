import 'package:flutter/material.dart';

import '../models/repair_stage.dart';
import 'repair_stage_chip.dart';

/// Панель поиска и фильтрации фото.
///
/// Она не знает о Firestore и не хранит данные сама. Родительский экран
/// передает текущие значения и получает изменения через callbacks.
class PhotoFilterBar extends StatelessWidget {
  const PhotoFilterBar({
    super.key,
    required this.stages,
    required this.searchQuery,
    required this.selectedStageId,
    required this.onSearchChanged,
    required this.onStageChanged,
  });

  final List<RepairStage> stages;
  final String searchQuery;
  final String? selectedStageId;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String?> onStageChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Поиск по фото',
                hintText: 'Этап, описание, автор',
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: stages.length + 1,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  if (index == 0) {
                    final selected = selectedStageId == null;
                    return ActionChip(
                      onPressed: () => onStageChanged(null),
                      backgroundColor: selected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.white,
                      side: BorderSide(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      avatar: Icon(
                        Icons.all_inclusive,
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary,
                      ),
                      label: const Text('Все'),
                      labelStyle: TextStyle(
                        color: selected
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    );
                  }

                  final stage = stages[index - 1];
                  return RepairStageChip(
                    stage: stage,
                    selected: selectedStageId == stage.id,
                    onTap: () => onStageChanged(stage.id),
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
