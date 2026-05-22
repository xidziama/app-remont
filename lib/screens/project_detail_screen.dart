import 'package:flutter/material.dart';

import '../models/project.dart';
import '../widgets/status_chip.dart';
import 'chat_screen.dart';
import 'expenses_screen.dart';
import 'participants_screen.dart';
import 'photos_screen.dart';

class ProjectDetailScreen extends StatelessWidget {
  const ProjectDetailScreen({super.key, required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    final sections = [
      _ProjectSection(
        title: 'Исполнители',
        subtitle: 'Участники объекта из телефонной книги',
        icon: Icons.groups,
        builder: (_) => ParticipantsScreen(project: project),
      ),
      _ProjectSection(
        title: 'Чат',
        subtitle: 'Обсуждение объекта между участниками',
        icon: Icons.chat_bubble_outline,
        builder: (_) => ChatScreen(project: project),
      ),
      _ProjectSection(
        title: 'Чеки и расходы',
        subtitle: 'Фото чеков, суммы, категории и даты',
        icon: Icons.receipt_long,
        builder: (_) => ExpensesScreen(project: project),
      ),
      _ProjectSection(
        title: 'Фото',
        subtitle: 'Фото объекта и этапов работ',
        icon: Icons.photo_library_outlined,
        builder: (_) => PhotosScreen(project: project),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text(project.title)),
      body: ListView(
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
                          project.title,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 12),
                      StatusChip(status: project.status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(child: Text(project.address)),
                    ],
                  ),
                  if (project.description.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(project.description),
                  ],
                ],
              ),
            ),
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
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: section.builder),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
