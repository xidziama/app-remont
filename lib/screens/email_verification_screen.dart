import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// Экран-заглушка между входом и приложением.
///
/// Показывается, когда у текущего пользователя `emailVerified == false`.
/// Пользователь не должен попасть дальше в приложение, пока не подтвердит
/// почту по ссылке из письма.
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key, required this.onVerified});

  /// Вызывается, когда повторная проверка показала emailVerified == true.
  final VoidCallback onVerified;

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _checking = false;
  bool _sending = false;

  Future<void> _checkVerified() async {
    if (_checking) {
      return;
    }

    setState(() => _checking = true);
    final verified = await AuthService.instance.reloadAndCheckEmailVerified();

    if (!mounted) {
      return;
    }

    setState(() => _checking = false);

    if (verified) {
      widget.onVerified();
    } else {
      _showMessage(
        'Почта пока не подтверждена. Перейдите по ссылке из письма и '
        'попробуйте снова.',
      );
    }
  }

  Future<void> _resend() async {
    if (_sending) {
      return;
    }

    setState(() => _sending = true);

    try {
      await AuthService.instance.sendEmailVerification();
      _showMessage('Письмо отправлено повторно.');
    } catch (error) {
      _showMessage('Не удалось отправить письмо: $error');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(message),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final email = AuthService.instance.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Подтверждение почты'),
        actions: [
          IconButton(
            tooltip: 'Выйти',
            onPressed: AuthService.instance.signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Подтвердите почту',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    email.isEmpty
                        ? 'Мы отправили письмо со ссылкой подтверждения. '
                            'Перейдите по ссылке из письма, затем нажмите '
                            '«Я подтвердил, обновить».'
                        : 'Мы отправили письмо со ссылкой подтверждения на '
                            '$email. Перейдите по ссылке из письма, затем '
                            'нажмите «Я подтвердил, обновить».',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _checking ? null : _checkVerified,
                    icon: _checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: const Text('Я подтвердил, обновить'),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _sending ? null : _resend,
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.mail_outline),
                    label: const Text('Отправить письмо повторно'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
