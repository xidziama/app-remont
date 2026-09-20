import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Экран обратной связи: контакты для сообщений об ошибках, идей и
/// добровольной поддержки проекта.
class SupportScreen extends StatelessWidget {
  const SupportScreen({super.key});

  static const _supportEmail = 'ghjcnjghjc@gmail.com';

  Future<void> _sendEmail(BuildContext context) async {
    final emailUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {'subject': 'APP_Remont — обратная связь'},
    );

    final launched = await launchUrl(emailUri);

    if (!context.mounted || launched) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Не удалось открыть почтовый клиент. Адрес: $_supportEmail',
          ),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Поддержка')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Нашли ошибку или есть идея, как сделать приложение '
                    'удобнее? Буду признателен за любое сообщение — это '
                    'правда помогает. Если хотите поддержать проект, '
                    'напишите на почту, и мы пришлём реквизиты.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () => _sendEmail(context),
                    icon: const Icon(Icons.email_outlined),
                    label: const Text('Написать на почту'),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: SelectableText(
                      _supportEmail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
