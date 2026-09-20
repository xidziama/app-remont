import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';

class CompanyOnboardingScreen extends StatelessWidget {
  const CompanyOnboardingScreen({super.key});

  Future<void> _createCompany(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _CreateCompanyDialog(),
    );
  }

  Future<void> _joinCompany(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _JoinCompanyDialog(),
    );
  }

  Future<void> _showInvitations(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _InvitationSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Мои объекты'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: AuthService.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Настройте доступ',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'После регистрации у пользователя нет роли и объектов. Создайте '
              'компанию, отправьте запрос на вступление или примите приглашение.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            _OnboardingAction(
              icon: Icons.business_outlined,
              title: 'Создать компанию',
              subtitle: 'Вы станете директором и получите полный доступ.',
              onTap: () => _createCompany(context),
            ),
            _OnboardingAction(
              icon: Icons.group_add_outlined,
              title: 'Присоединиться к компании',
              subtitle: 'Введите код компании, который выдал директор.',
              onTap: () => _joinCompany(context),
            ),
            _OnboardingAction(
              icon: Icons.mail_outline,
              title: 'У меня есть приглашение',
              subtitle: 'Показать email-приглашения для вашего аккаунта.',
              onTap: () => _showInvitations(context),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCompanyDialog extends StatefulWidget {
  const _CreateCompanyDialog();

  @override
  State<_CreateCompanyDialog> createState() => _CreateCompanyDialogState();
}

class _CreateCompanyDialogState extends State<_CreateCompanyDialog> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showError('Введите название компании.');
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);

    debugPrint('[DialogFlow] createCompany started name=$name');
    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await repository.createCompany(name);

      debugPrint('[DialogFlow] createCompany success');
      debugPrint('[DialogFlow] context mounted = $mounted');

      if (!mounted) {
        return;
      }

      debugPrint('[DialogFlow] closing createCompany dialog');
      navigator.pop();
    } catch (error) {
      debugPrint('[DialogFlow] createCompany error: $error');

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      _showError('Не удалось создать компанию: $error');
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorText = message;
    });

    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Создать компанию'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _nameController,
            autofocus: true,
            enabled: !_isLoading,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Название компании',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
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
              : const Text('Создать'),
        ),
      ],
    );
  }
}

class _JoinCompanyDialog extends StatefulWidget {
  const _JoinCompanyDialog();

  @override
  State<_JoinCompanyDialog> createState() => _JoinCompanyDialogState();
}

class _JoinCompanyDialogState extends State<_JoinCompanyDialog> {
  final TextEditingController _codeController = TextEditingController();
  bool _isLoading = false;
  String? _errorText;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isLoading) {
      return;
    }

    final code = _codeController.text.trim();
    if (code.isEmpty) {
      _showError('Введите код компании.');
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() {
      _isLoading = true;
      _errorText = null;
    });

    try {
      await repository.requestJoinCompany(code);

      if (!mounted) {
        return;
      }

      navigator.pop();
      messenger
        ?..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Заявка отправлена директору')),
        );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = false;
      });
      _showError(_friendlyError(error));
    }
  }

  String _friendlyError(Object error) {
    final message = error
        .toString()
        .replaceFirst('Exception: ', '')
        .replaceFirst('Invalid argument(s): ', '')
        .trim();

    if (message.isEmpty) {
      return 'Не удалось отправить заявку.';
    }

    return message;
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _errorText = message;
    });

    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Присоединиться к компании'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Код компании выдаёт директор.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _codeController,
            autofocus: true,
            enabled: !_isLoading,
            textCapitalization: TextCapitalization.characters,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: 'Код компании',
              hintText: 'Введите код компании',
              errorText: _errorText,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
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
              : const Text('Отправить'),
        ),
      ],
    );
  }
}

class _OnboardingAction extends StatelessWidget {
  const _OnboardingAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        minVerticalPadding: 18,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _InvitationSheet extends StatefulWidget {
  const _InvitationSheet();

  @override
  State<_InvitationSheet> createState() => _InvitationSheetState();
}

class _InvitationSheetState extends State<_InvitationSheet> {
  String? _acceptingInvitationId;
  String? _decliningInvitationId;

  Future<void> _accept(
    BuildContext context,
    CompanyInvitation invitation,
  ) async {
    if (_acceptingInvitationId != null || _decliningInvitationId != null) {
      return;
    }

    final repository = context.read<ProjectRepository>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() {
      _acceptingInvitationId = invitation.id;
    });

    try {
      await repository.acceptCompanyInvitation(invitation);

      if (!mounted) {
        return;
      }

      navigator.pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Приглашение принято')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _acceptingInvitationId = null;
      });
      messenger?.showSnackBar(
        SnackBar(content: Text('Не удалось принять приглашение: $error')),
      );
    }
  }

  Future<void> _decline(
    BuildContext context,
    CompanyInvitation invitation,
  ) async {
    if (_acceptingInvitationId != null || _decliningInvitationId != null) {
      return;
    }

    final repository = context.read<ProjectRepository>();
    final messenger = ScaffoldMessenger.maybeOf(context);

    setState(() {
      _decliningInvitationId = invitation.id;
    });

    try {
      await repository.declineCompanyInvitation(invitation);

      if (!mounted) {
        return;
      }

      setState(() {
        _decliningInvitationId = null;
      });
      messenger?.showSnackBar(
        const SnackBar(content: Text('Приглашение отклонено')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _decliningInvitationId = null;
      });
      messenger?.showSnackBar(
        SnackBar(content: Text('Не удалось отклонить приглашение: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return SafeArea(
      child: StreamBuilder<List<CompanyInvitation>>(
        stream: repository.watchCurrentUserInvitations(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              height: 220,
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final invitations = snapshot.data ?? const <CompanyInvitation>[];
          if (invitations.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Активных приглашений нет'),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            shrinkWrap: true,
            children: [
              Text(
                'Приглашения',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 12),
              for (final invitation in invitations)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          invitation.companyName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          [
                            'Роль: ${invitation.role.label}',
                            if (invitation.projectTitle?.isNotEmpty == true)
                              'Объект: ${invitation.projectTitle}',
                            if (invitation.stageTitles.isNotEmpty)
                              'Этапы: ${invitation.stageTitles.join(', ')}',
                          ].join('\n'),
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 12),
                        OverflowBar(
                          alignment: MainAxisAlignment.end,
                          spacing: 8,
                          overflowSpacing: 8,
                          children: [
                            OutlinedButton(
                              onPressed: _acceptingInvitationId == null &&
                                      _decliningInvitationId == null
                                  ? () => _decline(context, invitation)
                                  : null,
                              child: _decliningInvitationId == invitation.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Отклонить'),
                            ),
                            FilledButton(
                              onPressed: _acceptingInvitationId == null &&
                                      _decliningInvitationId == null
                                  ? () => _accept(context, invitation)
                                  : null,
                              child: _acceptingInvitationId == invitation.id
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Text('Принять'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
