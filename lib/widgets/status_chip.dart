import 'package:flutter/material.dart';

import '../models/project.dart';

/// Маленький бейдж статуса объекта.
///
/// Вынос в отдельный виджет помогает одинаково показывать статус в списке
/// и на экране карточки объекта.
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.status});

  /// Статус модели Project.
  final ProjectStatus status;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(status.label),
      visualDensity: VisualDensity.compact,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      side: BorderSide.none,
    );
  }
}
