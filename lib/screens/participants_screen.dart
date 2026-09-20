import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../models/project.dart';
import '../models/stage.dart';
import '../repositories/project_repository.dart';
import '../widgets/empty_state.dart';

String _inviteRoleTitle(CompanyRole role) {
  if (role.isClient) {
    return 'Заказчик объекта';
  }

  if (role.isWorker) {
    return 'Подрядчик';
  }

  return role.label;
}

class ParticipantsScreen extends StatelessWidget {
  const ParticipantsScreen({
    super.key,
    required this.project,
    required this.company,
  });

  final Project project;
  final CompanyMember company;

  bool get _canManageParticipants {
    return company.role.isOwner || company.role.isManager;
  }

  Future<void> _invite(
    BuildContext context,
    CompanyRole role,
    List<Stage> stages,
  ) async {
    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteProjectMemberDialog(
        company: company,
        project: project,
        role: role,
        stages: stages,
      ),
    );

    if (!context.mounted || created != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Приглашение создано')),
    );
  }

  Future<void> _editWorkerStages(
    BuildContext context,
    CompanyMember worker,
    List<Stage> stages,
  ) async {
    final selectedStages = await showDialog<List<Stage>>(
      context: context,
      builder: (_) => _WorkerStagesDialog(worker: worker, stages: stages),
    );

    if (!context.mounted || selectedStages == null) {
      return;
    }

    final repository = context.read<ProjectRepository>();
    final currentlyAssigned = stages
        .where((stage) => stage.assignedUserIds.contains(worker.uid))
        .toList(growable: false);
    final selectedIds = selectedStages.map((stage) => stage.id).toSet();
    final currentIds = currentlyAssigned.map((stage) => stage.id).toSet();
    final toAdd = selectedStages
        .where((stage) => !currentIds.contains(stage.id))
        .toList(growable: false);
    final toRemove = currentlyAssigned
        .where((stage) => !selectedIds.contains(stage.id))
        .toList(growable: false);

    try {
      if (toAdd.isNotEmpty) {
        await repository.assignWorkerToProjectStages(
          project: project,
          worker: worker,
          stages: toAdd,
        );
      }
      if (toRemove.isNotEmpty) {
        await repository.removeWorkerFromProjectStages(
          project: project,
          worker: worker,
          stages: toRemove,
        );
      }

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Назначения обновлены')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось обновить назначения: $error')),
      );
    }
  }

  Future<void> _removeParticipant(
    BuildContext context,
    CompanyMember member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить участника с объекта?'),
        content: Text(
          '${member.displayName}\n\n'
          'Аккаунт и созданные данные не будут удалены.',
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
      await context.read<ProjectRepository>().removeProjectParticipant(
            actor: company,
            project: project,
            member: member,
          );

      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Участник удален с объекта')),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось удалить участника: $error')),
      );
    }
  }

  bool _canRemove(CompanyMember member) {
    if (!_canManageParticipants || member.role.isOwner) {
      return false;
    }

    if (member.role.isManager) {
      return company.role.isOwner;
    }

    return member.role.isWorker || member.role.isClient;
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Участники')),
      body: StreamBuilder<List<Stage>>(
        stream: repository.watchProductionStages(project.id),
        builder: (context, stageSnapshot) {
          final stages = stageSnapshot.data ?? const <Stage>[];

          return StreamBuilder<List<CompanyMember>>(
            stream: repository.watchProjectMembers(project),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return EmptyState(
                  icon: Icons.error_outline,
                  title: 'Не удалось загрузить участников',
                  subtitle: snapshot.error.toString(),
                );
              }

              final members = snapshot.data ?? const <CompanyMember>[];
              final managers =
                  members.where((member) => member.role.isManager).toList();
              final workers =
                  members.where((member) => member.role.isWorker).toList();
              final clients =
                  members.where((member) => member.role.isClient).toList();

              return ListView(
                key: PageStorageKey<String>('project_members_${project.id}'),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                children: [
                  _MemberGroup(
                    title: 'Прорабы',
                    members: managers,
                    stages: stages,
                    canManage: _canManageParticipants,
                    canRemove: _canRemove,
                    onEditStages: _editWorkerStages,
                    onRemove: _removeParticipant,
                  ),
                  _MemberGroup(
                    title: 'Подрядчики',
                    members: workers,
                    stages: stages,
                    canManage: _canManageParticipants,
                    canRemove: _canRemove,
                    onEditStages: _editWorkerStages,
                    onRemove: _removeParticipant,
                  ),
                  _MemberGroup(
                    title: 'Заказчики',
                    members: clients,
                    stages: stages,
                    canManage: _canManageParticipants,
                    canRemove: _canRemove,
                    onEditStages: _editWorkerStages,
                    onRemove: _removeParticipant,
                  ),
                  if (members.isEmpty)
                    const EmptyState(
                      icon: Icons.groups_outlined,
                      title: 'Участников пока нет',
                      subtitle: 'Пригласите подрядчика или заказчика.',
                    ),
                  if (_canManageParticipants) ...[
                    const SizedBox(height: 16),
                    _PendingInvitationsSection(
                      company: company,
                      project: project,
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
      floatingActionButton: !_canManageParticipants
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showInviteMenu(context),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Пригласить'),
            ),
    );
  }

  Future<void> _showInviteMenu(BuildContext context) async {
    final role = await showModalBottomSheet<CompanyRole>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.handyman_outlined),
              title: const Text('Подрядчика'),
              onTap: () => Navigator.of(sheetContext).pop(CompanyRole.worker),
            ),
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text(
                'Заказчик объекта',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              onTap: () => Navigator.of(sheetContext).pop(CompanyRole.client),
            ),
          ],
        ),
      ),
    );

    if (!context.mounted || role == null) {
      return;
    }

    final stages = await context.read<ProjectRepository>().getProductionStages(
          project.id,
        );

    if (!context.mounted) {
      return;
    }

    await _invite(context, role, stages);
  }
}

class _MemberGroup extends StatelessWidget {
  const _MemberGroup({
    required this.title,
    required this.members,
    required this.stages,
    required this.canManage,
    required this.canRemove,
    required this.onEditStages,
    required this.onRemove,
  });

  final String title;
  final List<CompanyMember> members;
  final List<Stage> stages;
  final bool canManage;
  final bool Function(CompanyMember member) canRemove;
  final Future<void> Function(
    BuildContext context,
    CompanyMember worker,
    List<Stage> stages,
  ) onEditStages;
  final Future<void> Function(BuildContext context, CompanyMember member)
      onRemove;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        for (final member in members)
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person)),
              title: Text(
                member.role.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                member.email.trim().isEmpty
                    ? 'Email не указан'
                    : member.email.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
              ),
              trailing: canManage
                  ? PopupMenuButton<_MemberAction>(
                      onSelected: (action) {
                        switch (action) {
                          case _MemberAction.editStages:
                            onEditStages(context, member, stages);
                          case _MemberAction.remove:
                            onRemove(context, member);
                        }
                      },
                      itemBuilder: (context) => [
                        if (member.role.isWorker)
                          const PopupMenuItem(
                            value: _MemberAction.editStages,
                            child: ListTile(
                              leading: Icon(Icons.flag_outlined),
                              title: Text('Назначить этапы'),
                            ),
                          ),
                        if (canRemove(member))
                          const PopupMenuItem(
                            value: _MemberAction.remove,
                            child: ListTile(
                              leading: Icon(Icons.person_remove_outlined),
                              title: Text('Удалить с объекта'),
                            ),
                          ),
                      ],
                    )
                  : null,
            ),
          ),
      ],
    );
  }
}

enum _MemberAction {
  editStages,
  remove,
}

class _InviteProjectMemberDialog extends StatefulWidget {
  const _InviteProjectMemberDialog({
    required this.company,
    required this.project,
    required this.role,
    required this.stages,
  });

  final CompanyMember company;
  final Project project;
  final CompanyRole role;
  final List<Stage> stages;

  @override
  State<_InviteProjectMemberDialog> createState() =>
      _InviteProjectMemberDialogState();
}

class _InviteProjectMemberDialogState
    extends State<_InviteProjectMemberDialog> {
  final _emailController = TextEditingController();
  final Set<String> _selectedStageIds = <String>{};
  bool _saving = false;
  String? _errorText;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _errorText = 'Введите email.');
      return;
    }

    if (widget.role.isWorker && _selectedStageIds.isEmpty) {
      setState(() => _errorText = 'Выберите этапы для подрядчика.');
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);
    final selectedStages = widget.stages
        .where((stage) => _selectedStageIds.contains(stage.id))
        .toList(growable: false);

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      await repository.createCompanyInvitation(
        inviter: widget.company,
        email: email,
        role: widget.role,
        project: widget.project,
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
        _errorText = 'Не удалось создать приглашение: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Пригласить: ${_inviteRoleTitle(widget.role)}',
        softWrap: true,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _emailController,
              enabled: !_saving,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            if (widget.role.isWorker) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Этапы',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              for (final stage in widget.stages)
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
              : const Text('Пригласить'),
        ),
      ],
    );
  }
}

class _WorkerStagesDialog extends StatefulWidget {
  const _WorkerStagesDialog({
    required this.worker,
    required this.stages,
  });

  final CompanyMember worker;
  final List<Stage> stages;

  @override
  State<_WorkerStagesDialog> createState() => _WorkerStagesDialogState();
}

class _WorkerStagesDialogState extends State<_WorkerStagesDialog> {
  late final Set<String> _selectedStageIds;

  @override
  void initState() {
    super.initState();
    _selectedStageIds = widget.stages
        .where((stage) => stage.assignedUserIds.contains(widget.worker.uid))
        .map((stage) => stage.id)
        .toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Этапы: ${widget.worker.displayName}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final stage in widget.stages)
              CheckboxListTile(
                value: _selectedStageIds.contains(stage.id),
                title: Text(stage.title),
                onChanged: (value) {
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
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final selected = widget.stages
                .where((stage) => _selectedStageIds.contains(stage.id))
                .toList(growable: false);
            Navigator.of(context).pop(selected);
          },
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}

class _PendingInvitationsSection extends StatelessWidget {
  const _PendingInvitationsSection({
    required this.company,
    required this.project,
  });

  final CompanyMember company;
  final Project project;

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return StreamBuilder<List<CompanyInvitation>>(
      stream: repository.watchPendingInvitations(
        companyId: company.companyId,
        projectId: project.id,
      ),
      builder: (context, snapshot) {
        final invitations = snapshot.data ?? const <CompanyInvitation>[];
        if (invitations.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Ожидают приглашения',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            for (final invitation in invitations)
              Card(
                child: ListTile(
                  title: Text(
                    invitation.email.trim().isEmpty
                        ? 'Email не указан'
                        : invitation.email.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                  subtitle: Text(
                    [
                      invitation.role.label,
                      if (invitation.stageTitles.isNotEmpty)
                        'Этапы: ${invitation.stageTitles.join(', ')}',
                    ].join('\n'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: TextButton(
                    onPressed: () async {
                      try {
                        await repository.revokeInvitation(
                          actor: company,
                          invitation: invitation,
                        );
                      } catch (error) {
                        if (!context.mounted) {
                          return;
                        }

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content:
                                Text('Не удалось отозвать приглашение: $error'),
                          ),
                        );
                      }
                    },
                    child: const Text('Отозвать'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
