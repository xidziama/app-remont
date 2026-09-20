import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';

class JoinRequestsScreen extends StatelessWidget {
  const JoinRequestsScreen({super.key, required this.company});

  final CompanyMember company;

  String _requestRoleLabel() {
    // Join request is created before the director chooses the final role.
    // Until user profiles and requested roles are implemented, the safest UI
    // label is the neutral fallback from the product requirement.
    return 'Пользователь';
  }

  String _safeEmail(CompanyJoinRequest request) {
    final email = request.email.trim();
    return email.isEmpty ? 'Email не указан' : email;
  }

  Future<void> _approve(
    BuildContext context,
    CompanyJoinRequest request,
    List<Project> projects,
  ) async {
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApproveJoinRequestDialog(
        company: company,
        request: request,
        projects: projects,
      ),
    );

    if (!context.mounted || approved != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Заявка одобрена')),
    );
  }

  Future<void> _decline(
    BuildContext context,
    CompanyJoinRequest request,
  ) async {
    final repository = context.read<ProjectRepository>();

    try {
      await repository.declineJoinRequest(owner: company, request: request);

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Заявка отклонена')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось отклонить заявку: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Заявки на вступление')),
      body: StreamBuilder<List<Project>>(
        stream: repository.watchProjects(company: company),
        builder: (context, projectSnapshot) {
          final projects = projectSnapshot.data ?? const <Project>[];

          return StreamBuilder<List<CompanyJoinRequest>>(
            stream: repository.watchPendingJoinRequests(company),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить заявки',
                  subtitle: snapshot.error.toString(),
                );
              }

              final requests = snapshot.data ?? const <CompanyJoinRequest>[];
              if (requests.isEmpty) {
                return const EmptyState(
                  icon: Icons.how_to_reg_outlined,
                  title: 'Заявок пока нет',
                  subtitle: 'Новые пользователи появятся здесь после запроса.',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: requests.length,
                itemBuilder: (context, index) {
                  final request = requests[index];
                  return Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              const CircleAvatar(child: Icon(Icons.person)),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _requestRoleLabel(),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _safeEmail(request),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Хочет присоединиться к компании',
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          OverflowBar(
                            alignment: MainAxisAlignment.end,
                            spacing: 8,
                            overflowSpacing: 8,
                            children: [
                              OutlinedButton(
                                onPressed: () => _decline(context, request),
                                child: const Text('Отклонить'),
                              ),
                              FilledButton(
                                onPressed: () =>
                                    _approve(context, request, projects),
                                child: const Text('Одобрить'),
                              ),
                            ],
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

class _ApproveJoinRequestDialog extends StatefulWidget {
  const _ApproveJoinRequestDialog({
    required this.company,
    required this.request,
    required this.projects,
  });

  final CompanyMember company;
  final CompanyJoinRequest request;
  final List<Project> projects;

  @override
  State<_ApproveJoinRequestDialog> createState() =>
      _ApproveJoinRequestDialogState();
}

class _ApproveJoinRequestDialogState extends State<_ApproveJoinRequestDialog> {
  CompanyRole _role = CompanyRole.manager;
  Project? _project;
  List<Stage> _stages = const [];
  final Set<String> _selectedStageIds = <String>{};
  bool _loadingStages = false;
  bool _saving = false;
  String? _errorText;

  Future<void> _loadStages(Project? project) async {
    setState(() {
      _project = project;
      _stages = const [];
      _selectedStageIds.clear();
      _loadingStages = project != null;
      _errorText = null;
    });

    if (project == null) {
      return;
    }

    try {
      final stages = await context
          .read<ProjectRepository>()
          .getProductionStages(project.id);

      if (!mounted) {
        return;
      }

      setState(() {
        _stages = stages;
        _loadingStages = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _loadingStages = false;
        _errorText = 'Не удалось загрузить этапы: $error';
      });
    }
  }

  Future<void> _submit() async {
    if (_saving) {
      return;
    }

    if ((_role.isWorker || _role.isClient) && _project == null) {
      setState(() => _errorText = 'Выберите объект.');
      return;
    }

    if (_role.isWorker && _selectedStageIds.isEmpty) {
      setState(() => _errorText = 'Выберите этапы для подрядчика.');
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);
    final selectedStages = _stages
        .where((stage) => _selectedStageIds.contains(stage.id))
        .toList(growable: false);

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await repository.approveJoinRequest(
        owner: widget.company,
        request: widget.request,
        role: _role,
        project: _project,
        stages: selectedStages,
      );

      if (!mounted) {
        return;
      }

      navigator.pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _saving = false;
        _errorText = 'Не удалось одобрить заявку: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final needsProject = _role.isWorker || _role.isClient;
    final needsStages = _role.isWorker;

    return AlertDialog(
      title: const Text('Одобрить заявку'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<CompanyRole>(
              initialValue: _role,
              decoration: const InputDecoration(labelText: 'Роль'),
              items: const [
                CompanyRole.manager,
                CompanyRole.worker,
                CompanyRole.client,
              ]
                  .map(
                    (role) => DropdownMenuItem(
                      value: role,
                      child: Text(role.label),
                    ),
                  )
                  .toList(),
              onChanged: _saving
                  ? null
                  : (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _role = value;
                        _errorText = null;
                      });
                      if (!value.isWorker && !value.isClient) {
                        _loadStages(null);
                      }
                    },
            ),
            if (needsProject) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<Project>(
                initialValue: _project,
                decoration: const InputDecoration(labelText: 'Объект'),
                items: [
                  for (final project in widget.projects)
                    DropdownMenuItem(
                      value: project,
                      child: Text(project.title),
                    ),
                ],
                onChanged: _saving ? null : _loadStages,
              ),
            ],
            if (needsStages) ...[
              const SizedBox(height: 12),
              if (_loadingStages)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(),
                )
              else
                for (final stage in _stages)
                  CheckboxListTile(
                    value: _selectedStageIds.contains(stage.id),
                    title: Text(stage.title),
                    onChanged: _saving
                        ? null
                        : (value) {
                            setState(() {
                              if (value == true) {
                                _selectedStageIds.add(stage.id);
                              } else {
                                _selectedStageIds.remove(stage.id);
                              }
                            });
                          },
                  ),
            ],
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Одобрить'),
        ),
      ],
    );
  }
}
