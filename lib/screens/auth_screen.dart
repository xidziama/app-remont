import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';

/// AuthScreen отвечает за первый экран приложения.
///
/// Важно для текущего dev-режима:
/// - Phone Auth отключен в debug UI.
/// - Разработчик входит одной кнопкой через anonymous Firebase Auth.
/// - После входа main.dart получает новое состояние из authStateChanges
///   и автоматически показывает ProjectListScreen.
///
/// Почему экран все еще содержит production phone auth:
/// - это полезная заготовка для будущего MVP production;
/// - в debug она не используется;
/// - при release-сборке можно включить настоящий телефонный вход.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  /// Контроллер номера нужен только для release phone auth.
  ///
  /// В debug-режиме поле не показывается, потому что пользователь попросил
  /// отключить phone auth для разработки.
  final _phoneController = TextEditingController(text: '+15555550100');

  /// Контроллер SMS-кода тоже нужен только для release phone auth.
  final _codeController = TextEditingController();

  /// verificationId приходит от Firebase после отправки SMS.
  ///
  /// Если значение null — код еще не запрошен.
  /// Если значение не null — можно показывать поле SMS-кода.
  String? _verificationId;

  /// Локальный флаг загрузки блокирует кнопки во время запросов к Firebase.
  bool _loading = false;

  @override
  void dispose() {
    // Контроллеры нужно освобождать, чтобы Flutter не держал лишние ресурсы
    // после закрытия экрана.
    _phoneController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  /// Выполняет временный вход для разработки.
  ///
  /// Здесь нет ручной навигации на список объектов. После signInAnonymously()
  /// Firebase Auth обновит authStateChanges, а main.dart сам заменит экран.
  Future<void> _signInAsTemporaryDevUser() async {
    setState(() => _loading = true);

    try {
      await AuthService.instance.signInAsTemporaryDevUser();
    } catch (error) {
      if (!mounted) {
        return;
      }

      // SnackBar нужен, чтобы разработчик сразу увидел причину ошибки входа:
      // например, если emulator не запущен или anonymous auth недоступен.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка тестового входа: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Запрашивает SMS-код для production phone auth.
  ///
  /// В debug этот метод не вызывается, потому что phone auth в dev отключен.
  Future<void> _sendCode() async {
    setState(() => _loading = true);

    await AuthService.instance.verifyPhoneNumber(
      phoneNumber: _phoneController.text.trim(),
      onCodeSent: (verificationId) {
        // Firebase вернул verificationId — значит, можно показать поле SMS-кода.
        setState(() {
          _verificationId = verificationId;
          _loading = false;
        });
      },
      onFailed: (message) {
        // Если Firebase вернул ошибку, выключаем loader и показываем сообщение.
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message)),
        );
      },
    );
  }

  /// Подтверждает SMS-код для production phone auth.
  Future<void> _confirmCode() async {
    final verificationId = _verificationId;

    // Без verificationId Firebase не сможет проверить SMS-код.
    if (verificationId == null) {
      return;
    }

    setState(() => _loading = true);

    try {
      await AuthService.instance.signInWithSmsCode(
        verificationId: verificationId,
        smsCode: _codeController.text.trim(),
      );
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // kDebugMode — главный переключатель текущего требования.
    // В debug показываем временный вход и не показываем phone auth вообще.
    if (kDebugMode) {
      return _buildDevLogin(context);
    }

    // В release показываем phone auth UI.
    return _buildPhoneLogin(context);
  }

  /// UI временного dev-входа.
  Widget _buildDevLogin(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'APP Remont',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Dev-режим: вход без телефона и SMS.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Нажмите кнопку ниже. Firebase Auth emulator создаст '
                    'временного тестового пользователя, а приложение сразу '
                    'откроет список объектов.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _loading ? null : _signInAsTemporaryDevUser,
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.person),
                    label: Text(
                      _loading
                          ? 'Вход...'
                          : 'Войти как тестовый пользователь',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// UI production phone auth.
  Widget _buildPhoneLogin(BuildContext context) {
    final codeSent = _verificationId != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'APP Remont',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Вход по номеру телефона.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Номер телефона',
                    ),
                  ),
                  if (codeSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _codeController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'SMS-код',
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _loading
                        ? null
                        : codeSent
                            ? _confirmCode
                            : _sendCode,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(codeSent ? 'Войти' : 'Получить код'),
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
