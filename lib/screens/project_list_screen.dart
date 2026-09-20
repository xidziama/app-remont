import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/app_state.dart';
import '../models/company.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';
import '../utils/auth_debug.dart';
import '../widgets/empty_state.dart';
import '../widgets/project_card.dart';
import 'create_project_screen.dart';
import 'company_settings_screen.dart';
import 'join_requests_screen.dart';
import 'manager_management_screen.dart';
import 'notifications_screen.dart';
import 'project_detail_screen.dart';
import 'support_screen.dart';

class ProjectListScreen extends StatefulWidget {
  const ProjectListScreen({super.key, required this.company});

  final CompanyMember company;

  @override
  State<ProjectListScreen> createState() => _ProjectListScreenState();
}

class _ProjectListScreenState extends State<ProjectListScreen> {
  final Set<String> _selectedProjectIds = <String>{};
  List<Project> _latestProjects = <Project>[];
  bool _selectionMode = false;
  bool _deleting = false;

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  void _openCreateProject() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateProjectScreen(company: widget.company),
      ),
    );
  }

  void _openNotifications() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NotificationsScreen(company: widget.company),
      ),
    );
  }

  void _openProject(Project project) {
    context.read<AppState>().selectProject(project);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProjectDetailScreen(
          project: project,
          company: widget.company,
        ),
      ),
    );
  }

  void _enableSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedProjectIds.clear();
    });
  }

  void _cancelSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedProjectIds.clear();
    });
  }

  void _toggleProjectSelection(Project project, bool selected) {
    if (!project.status.canBeDeleted) {
      _showMessage('Удалять можно только завершенные объекты.');
      return;
    }

    setState(() {
      if (selected) {
        _selectedProjectIds.add(project.id);
      } else {
        _selectedProjectIds.remove(project.id);
      }
    });
  }

  String _deleteTitle(int count) {
    return 'Удалить $count ${count == 1 ? 'объект' : 'объекта'}?';
  }

  Future<void> _deleteSelectedProjects(List<Project> projects) async {
    final selectedProjects = projects
        .where((project) => _selectedProjectIds.contains(project.id))
        .toList();

    if (selectedProjects.isEmpty) {
      _showMessage('Выберите хотя бы один завершенный объект.');
      return;
    }

    final hasBlockedProject = selectedProjects.any(
      (project) => !project.status.canBeDeleted,
    );
    if (hasBlockedProject) {
      _showMessage('Удалять можно только завершенные объекты.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_deleteTitle(selectedProjects.length)),
        content: const Text('Это действие нельзя отменить.'),
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

    setState(() => _deleting = true);

    try {
      await context.read<ProjectRepository>().deleteProjects(selectedProjects);

      if (!mounted) {
        return;
      }

      setState(() {
        _selectionMode = false;
        _selectedProjectIds.clear();
      });
      _showMessage('Объекты удалены.');
    } catch (error) {
      if (!mounted) {
        return;
      }

      _showMessage('Не удалось удалить объекты: $error');
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _handleMenuAction(_ProjectListMenuAction action) async {
    switch (action) {
      case _ProjectListMenuAction.selectProjects:
        _enableSelectionMode();
      case _ProjectListMenuAction.manageManagers:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ManagerManagementScreen(company: widget.company),
          ),
        );
      case _ProjectListMenuAction.joinRequests:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => JoinRequestsScreen(company: widget.company),
          ),
        );
      case _ProjectListMenuAction.companySettings:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => CompanySettingsScreen(company: widget.company),
          ),
        );
      case _ProjectListMenuAction.support:
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SupportScreen()),
        );
      case _ProjectListMenuAction.signOut:
        await AuthService.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();
    final authUser = AuthService.instance.currentUser;
    AuthDebug.logUser('ProjectListScreen.build', authUser);

    return Scaffold(
      appBar: AppBar(
        leading: _selectionMode
            ? IconButton(
                tooltip: 'Выйти из режима выбора',
                onPressed: _deleting ? null : _cancelSelectionMode,
                icon: const Icon(Icons.close),
              )
            : null,
        title: Text(
          _selectionMode
              ? 'Выбрано: ${_selectedProjectIds.length}'
              : widget.company.companyName,
        ),
        actions: [
          if (_selectionMode)
            IconButton(
              tooltip: 'Удалить выбранные объекты',
              onPressed: _deleting || _selectedProjectIds.isEmpty
                  ? null
                  : () => _deleteSelectedProjects(_latestProjects),
              icon: _deleting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.delete_outline),
            )
          else ...[
            _NotificationBell(
              repository: repository,
              onPressed: _openNotifications,
            ),
            PopupMenuButton<_ProjectListMenuAction>(
              tooltip: 'Меню',
              onSelected: _handleMenuAction,
              itemBuilder: (context) => [
                if (widget.company.role.isOwner) ...[
                  const PopupMenuItem(
                    value: _ProjectListMenuAction.selectProjects,
                    child: ListTile(
                      leading: Icon(Icons.checklist),
                      title: Text('Выбрать объекты'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ProjectListMenuAction.manageManagers,
                    child: ListTile(
                      leading: Icon(Icons.engineering_outlined),
                      title: Text('Управление прорабами'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ProjectListMenuAction.joinRequests,
                    child: ListTile(
                      leading: Icon(Icons.how_to_reg_outlined),
                      title: Text('Заявки на вступление'),
                    ),
                  ),
                  const PopupMenuItem(
                    value: _ProjectListMenuAction.companySettings,
                    child: ListTile(
                      leading: Icon(Icons.settings_outlined),
                      title: Text('Настройки компании'),
                    ),
                  ),
                  const PopupMenuDivider(),
                ],
                const PopupMenuItem(
                  value: _ProjectListMenuAction.support,
                  child: ListTile(
                    leading: Icon(Icons.support_agent_outlined),
                    title: Text('Поддержка'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ProjectListMenuAction.signOut,
                  child: ListTile(
                    leading: Icon(Icons.logout),
                    title: Text('Выйти'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
      body: StreamBuilder<List<Project>>(
        stream: repository.watchProjects(company: widget.company),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return EmptyState(
              icon: Icons.error_outline,
              title: 'Не удалось загрузить объекты',
              subtitle: snapshot.error.toString(),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final projects = snapshot.data ?? <Project>[];
          _latestProjects = projects;

          if (projects.isEmpty) {
            final subtitle = widget.company.role.isManager
                ? 'У вас пока нет назначенных объектов.\nДиректор должен назначить вам объект.'
                : widget.company.role.isWorker || widget.company.role.isClient
                    ? 'У вас нет активных объектов. Ожидайте назначения или используйте приглашение.'
                    : 'Создайте первый объект ремонта или назначьте объект прорабу.';
            return EmptyState(
              icon: Icons.apartment,
              title: 'Пока нет объектов',
              subtitle: subtitle,
            );
          }

          return ListView.builder(
            key: const PageStorageKey<String>('project_list_scroll'),
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: projects.length,
            itemBuilder: (context, index) {
              final project = projects[index];
              return ProjectCard(
                key: ValueKey(project.id),
                project: project,
                selectionMode: _selectionMode,
                selected: _selectedProjectIds.contains(project.id),
                onSelectionChanged: (selected) {
                  _toggleProjectSelection(project, selected);
                },
                onTap: () => _openProject(project),
              );
            },
          );
        },
      ),
      floatingActionButton: _selectionMode || !widget.company.canCreateProject
          ? null
          : FloatingActionButton(
              tooltip: 'Добавить объект',
              onPressed: _deleting ? null : _openCreateProject,
              child: const Icon(Icons.add),
            ),
    );
  }
}

enum _ProjectListMenuAction {
  selectProjects,
  manageManagers,
  joinRequests,
  companySettings,
  support,
  signOut,
}

class _NotificationBell extends StatelessWidget {
  const _NotificationBell({
    required this.repository,
    required this.onPressed,
  });

  final ProjectRepository repository;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: repository.watchUnreadNotificationCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final hasUnread = count > 0;

        return IconButton(
          tooltip: 'Уведомления',
          onPressed: onPressed,
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none),
              if (hasUnread)
                Positioned(
                  right: -8,
                  top: -8,
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.error,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      count > 99 ? '99+' : count.toString(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onError,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
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
