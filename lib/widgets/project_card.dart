import 'package:flutter/material.dart';

import '../models/project.dart';
import 'status_chip.dart';

/// Карточка объекта в списке.
///
/// Виджет получает готовую модель Project и callback на нажатие.
/// Так список объектов остается простым, а UI карточки переиспользуемым.
class ProjectCard extends StatelessWidget {
  const ProjectCard({
    super.key,
    required this.project,
    required this.onTap,
  });

  /// Данные объекта ремонта.
  final Project project;

  /// Действие при нажатии. Обычно открывает ProjectDetailScreen.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Верхняя строка: название объекта слева, статус справа.
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      project.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  StatusChip(status: project.status),
                ],
              ),
              const SizedBox(height: 8),
              // Адрес всегда показываем, потому что это ключевая информация.
              Text(project.address),
              if (project.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                // Описание обрезается, чтобы длинный текст не ломал список.
                Text(
                  project.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Colors.black54,
                      ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
