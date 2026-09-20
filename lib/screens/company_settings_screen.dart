import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/company.dart';
import '../repositories/project_repository.dart';
import '../services/auth_service.dart';

class CompanySettingsScreen extends StatelessWidget {
  const CompanySettingsScreen({super.key, required this.company});

  final CompanyMember company;

  Future<void> _copyCompanyCode(BuildContext context, String code) async {
    final safeCode = code.trim();
    if (safeCode.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: safeCode));

    if (!context.mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Код компании скопирован')),
      );
  }

  Future<void> _deleteCompany(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить компанию?'),
        content: const Text(
          'Будут скрыты объекты, этапы, фото, чеки, чат, настройки компании '
          'и связи пользователей с компанией.\n\n'
          'В MVP выполняется безопасное soft delete: данные остаются в '
          'Firestore, но компания скрывается из интерфейса.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Удалить навсегда'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) {
      return;
    }

    final repository = context.read<ProjectRepository>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);

    try {
      await repository.softDeleteCompany(company);

      if (!context.mounted) {
        return;
      }

      navigator.pop();
      messenger?.showSnackBar(
        const SnackBar(content: Text('Компания скрыта из интерфейса')),
      );
      await AuthService.instance.signOut();
    } catch (error) {
      if (!context.mounted) {
        return;
      }

      messenger?.showSnackBar(
        SnackBar(content: Text('Не удалось удалить компанию: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final repository = context.read<ProjectRepository>();

    return Scaffold(
      appBar: AppBar(title: const Text('Настройки компании')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(company.companyName),
              subtitle: Text('Ваша роль: ${company.role.label}'),
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<Company?>(
            stream: repository.watchCompany(company.companyId),
            builder: (context, snapshot) {
              final companyDocument = snapshot.data;
              final code = companyDocument?.companyCode ?? '';
              final isLoading =
                  snapshot.connectionState == ConnectionState.waiting;

              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Код компании',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        isLoading
                            ? 'Загрузка...'
                            : code.isEmpty
                                ? 'Код не задан'
                                : code,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: code.isEmpty
                            ? null
                            : () => _copyCompanyCode(context, code),
                        icon: const Icon(Icons.copy_outlined),
                        label: const Text('Скопировать код'),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed:
                company.role.isOwner ? () => _deleteCompany(context) : null,
            icon: const Icon(Icons.delete_forever_outlined),
            label: const Text('Удалить компанию'),
          ),
        ],
      ),
    );
  }
}
