import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';

class ManagerManagementScreen extends StatelessWidget {
  const ManagerManagementScreen({super.key, required this.company});

  final CompanyMember company;

  Future<void> _addManager(BuildContext context) async {
    debugPrint('[DialogFlow] addManager dialog open');
    final added = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddManagerDialog(company: company),
    );

    if (!context.mounted || added != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приглашение прорабу создано')),
    );
  }

  Future<void> _assignProjects(
    BuildContext context,
    CompanyMember manager,
    List<Project> projects,
  ) async {
    final selected = manager.assignedProjectIds.toSet();
    final result = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Объекты: ${manager.displayName}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final project in projects)
                  CheckboxListTile(
                    value: selected.contains(project.id),
                    title: Text(project.title),
                    subtitle: Text(project.address),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          selected.add(project.id);
                        } else {
                          selected.remove(project.id);
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(selected),
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    if (result == null || !context.mounted) {
      return;
    }

    final selectedProjects = projects
        .where((project) => result.contains(project.id))
        .toList(growable: false);

    await _run(
      context,
      () => context.read<ProjectRepository>().assignProjectsToManager(
            owner: company,
            manager: manager,
            projects: selectedProjects,
          ),
      'Назначения обновлены',
    );
  }

  Future<void> _removeManager(
    BuildContext context,
    CompanyMember manager,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить прораба из компании?'),
        content: Text(manager.displayName),
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

    await _run(
      context,
      () => context.read<ProjectRepository>().removeManagerFromCompany(
            owner: company,
            manager: manager,
          ),
      'Прораб удалён из компании',
    );
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);

    try {
      await action();

      if (!context.mounted) {
        return;
      }

      messenger?.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger?.showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Управление прорабами'),
        actions: [
          IconButton(
            tooltip: 'Пригласить прораба',
            onPressed: () => _addManager(context),
            icon: const Icon(Icons.person_add_alt_1),
          ),
        ],
      ),
      body: StreamBuilder<List<Project>>(
        stream: repository.watchProjects(company: company),
        builder: (context, projectSnapshot) {
          final projects = projectSnapshot.data ?? const <Project>[];

          return StreamBuilder<List<CompanyMember>>(
            stream: repository.watchCompanyManagers(company.companyId),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              final managers = snapshot.data ?? const <CompanyMember>[];
              if (managers.isEmpty) {
                return const EmptyState(
                  icon: Icons.engineering_outlined,
                  title: 'Прорабов пока нет',
                  subtitle: 'Пригласите прораба по email.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: managers.length,
                itemBuilder: (context, index) {
                  final manager = managers[index];
                  final assignedCount = manager.assignedProjectIds.length;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text(
                              'Прораб',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  manager.email.trim().isEmpty
                                      ? 'Email не указан'
                                      : manager.email.trim(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  softWrap: false,
                                ),
                                Text(
                                  'Назначено объектов: $assignedCount',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            trailing: IconButton(
                              tooltip: 'Удалить прораба',
                              onPressed: () => _removeManager(context, manager),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: manager.canCreateProjects,
                            title: const Text('Может создавать объекты'),
                            onChanged: (value) => _run(
                              context,
                              () => repository.setManagerCanCreateProjects(
                                owner: company,
                                manager: manager,
                                value: value,
                              ),
                              'Права обновлены',
                            ),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                _assignProjects(context, manager, projects),
                            icon: const Icon(Icons.apartment_outlined),
                            label: const Text('Назначить объекты'),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

class _AddManagerDialog extends StatefulWidget {
  const _AddManagerDialog({required this.company});

  final CompanyMember company;

  @override
  State<_AddManagerDialog> createState() => _AddManagerDialogState();
}

class _AddManagerDialogState extends State<_AddManagerDialog> {
  final TextEditingController _emailController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }

    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      _showError('Введите email прораба.');
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    debugPrint('[DialogFlow] addManager started email=$email');
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await repository.addManagerByEmail(
        company: widget.company,
        email: email,
      );

      debugPrint('[DialogFlow] addManager success');
      debugPrint('[DialogFlow] context mounted = $mounted');

      if (!mounted) {
        return;
      }

      debugPrint('[DialogFlow] closing addManager dialog');
      navigator.pop(true);
    } catch (error) {
      debugPrint('[DialogFlow] addManager error: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      _showError(_messageForAddManagerError(error));
      messenger?.showSnackBar(
        SnackBar(content: Text(_messageForAddManagerError(error))),
      );
    }
  }

  String _messageForAddManagerError(Object error) {
    return 'Не удалось создать приглашение: $error';
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorText = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Пригласить прораба'),
      content: TextField(
        controller: _emailController,
        autofocus: true,
        enabled: !_isLoading,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'Email',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Пригласить'),
        ),
      ],
    );
  }
}
