import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/project_card.dart';
import 'create_project_screen.dart';
import 'project_detail_screen.dart';

class ProjectListScreen extends StatelessWidget {
  const ProjectListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Получаем репозиторий из Provider. Это проще тестировать и расширять,
    // чем обращаться к глобальному singleton из каждого экрана.
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Объекты ремонта'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: AuthService.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: StreamBuilder<List<Project>>(
        // StreamBuilder сам перерисует список, когда Firestore пришлет изменения.
        stream: repository.watchProjects(),
        builder: (context, snapshot) {
          // Если Firestore emulator не запущен или правила безопасности
          // запрещают чтение, ошибка попадет сюда. Это сильно помогает новичку
          // понять, что проблема не в интерфейсе, а в подключении/правилах.
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Не удалось загрузить объекты',
              subtitle: snapshot.error.toString(),
            );
          }

          // Пока первый ответ из Firestore еще не пришел, показываем loader.
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          // Если данных нет, используем пустой список, чтобы UI не падал на null.
          final projects = snapshot.data ?? [];
          if (projects.isEmpty) {
            return const EmptyState(
              icon: Icons.apartment,
              title: 'Пока нет объектов',
              subtitle: 'Создайте первый объект ремонта и добавьте участников.',
            );
          }

          return ListView.builder(
            itemCount: projects.length,
            itemBuilder: (context, index) {
              // Берем конкретный объект из списка и передаем его в карточку.
              final project = projects[index];
              return ProjectCard(
                project: project,
                onTap: () {
                  // Сохраняем выбранный объект в AppState. Это простой пример
                  // state management на Provider без лишней сложности.
                  context.read<AppState>().selectProject(project);

                  // Навигация открывает карточку выбранного объекта.
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ProjectDetailScreen(project: project),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        // Кнопка открывает форму создания объекта.
        // Сама запись в Firestore происходит уже внутри CreateProjectScreen.
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateProjectScreen()),
        ),
        icon: const Icon(Icons.add),
        label: const Text('Объект'),
      ),
    );
  }
}
