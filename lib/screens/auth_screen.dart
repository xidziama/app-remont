import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../utils/auth_debug.dart';

/// AuthScreen — экран входа и регистрации по Email/Password.
///
/// Экран не вызывает FirebaseAuth напрямую. Он только:
/// - читает email и пароль из полей;
/// - валидирует ввод на клиенте, чтобы дать быструю подсказку;
/// - вызывает методы AuthService;
/// - показывает ошибки через SnackBar.
///
/// После успешного входа или регистрации здесь нет Navigator.push. Firebase
/// обновит authStateChanges, а StreamBuilder в main.dart автоматически заменит
/// AuthScreen на ProjectListScreen. Это проще и надежнее, чем ручная навигация
/// из формы авторизации.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  /// FormState нужен для запуска validator'ов всех полей одной командой.
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Контроллер email хранит текст из поля ввода.
  ///
  /// Контроллер нужен, потому что один и тот же email используется и для входа,
  /// и для регистрации.
  final TextEditingController _emailController = TextEditingController();

  /// Контроллер пароля хранит введенный пароль.
  ///
  /// Пароль не сохраняется в локальное состояние приложения и не пишется в
  /// Firestore. Он передается только в Firebase Auth во время операции.
  final TextEditingController _passwordController = TextEditingController();

  /// Loading блокирует кнопки и поля во время запроса к Firebase.
  ///
  /// Это защищает от двойных нажатий: например, пользователь не сможет дважды
  /// отправить регистрацию и случайно получить странную ошибку.
  bool _loading = false;

  /// Управляет видимостью пароля.
  ///
  /// По умолчанию пароль скрыт. Пользователь может открыть его через иконку,
  /// чтобы проверить ввод на мобильной клавиатуре.
  bool _obscurePassword = true;

  /// Email без случайных пробелов по краям.
  String get _email => _emailController.text.trim();

  /// Пароль берем как есть, но обрезаем пробелы по краям.
  ///
  /// Для MVP это практично: случайный пробел после вставки пароля не ломает
  /// вход. Если в будущем понадобится поддерживать пароли с пробелами по краям,
  /// эту строку можно заменить на _passwordController.text.
  String get _password => _passwordController.text.trim();

  @override
  void dispose() {
    // Контроллеры нужно освобождать вручную, чтобы Flutter не держал ресурсы
    // после закрытия экрана.
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Проверяет email.
  ///
  /// Это базовая клиентская проверка для UX. Финальную проверку все равно
  /// выполняет Firebase Auth на сервере или в Auth Emulator.
  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';

    if (email.isEmpty) {
      return 'Введите email.';
    }

    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    if (!emailRegex.hasMatch(email)) {
      return 'Введите корректный email.';
    }

    return null;
  }

  /// Проверяет пароль.
  ///
  /// Firebase Email/Password требует минимум 6 символов. Держим такое же
  /// правило в UI, чтобы пользователь видел ошибку до сетевого запроса.
  String? _validatePassword(String? value) {
    final password = value?.trim() ?? '';

    if (password.isEmpty) {
      return 'Введите пароль.';
    }

    if (password.length < 6) {
      return 'Пароль должен быть не короче 6 символов.';
    }

    return null;
  }

  /// Показывает ошибку Firebase в дружелюбном виде.
  ///
  /// FirebaseAuthException.code стабилен и удобен для маппинга, а message может
  /// быть слишком техническим или английским. Поэтому для частых ошибок даем
  /// короткие русские сообщения, а для редких оставляем fallback.
  void _showAuthError(FirebaseAuthException error) {
    final message = switch (error.code) {
      'invalid-email' => 'Email введен некорректно.',
      'user-disabled' => 'Этот аккаунт отключен.',
      'user-not-found' => 'Пользователь с таким email не найден.',
      'wrong-password' => 'Неверный пароль.',
      'invalid-credential' => 'Неверный email или пароль.',
      'email-already-in-use' => 'Пользователь с таким email уже зарегистрирован.',
      'weak-password' => 'Пароль слишком простой. Используйте минимум 6 символов.',
      'network-request-failed' => 'Нет соединения с Firebase. Проверьте интернет или emulator.',
      _ => error.message?.trim().isNotEmpty == true
          ? error.message!.trim()
          : 'Ошибка авторизации: ${error.code}',
    };

    _showMessage(message);
  }

  /// Показывает SnackBar.
  ///
  /// Через один метод все сообщения выглядят одинаково, а старый SnackBar
  /// скрывается перед показом нового.
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

  /// Запускает вход или регистрацию.
  ///
  /// Параметр action нужен, чтобы не дублировать одинаковые шаги:
  /// - валидация формы;
  /// - скрытие клавиатуры;
  /// - включение loading;
  /// - try/catch;
  /// - выключение loading при ошибке.
  Future<void> _submit(_AuthAction action) async {
    if (_loading) {
      return;
    }

    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    // Скрываем клавиатуру перед сетевым запросом, чтобы пользователь видел
    // loader и disabled state кнопок.
    FocusScope.of(context).unfocus();

    setState(() => _loading = true);

    try {
      switch (action) {
        case _AuthAction.signIn:
          await AuthService.instance.signInWithEmail(
            email: _email,
            password: _password,
          );
        case _AuthAction.register:
          await AuthService.instance.registerWithEmail(
            email: _email,
            password: _password,
          );
      }

      debugPrint(
        '[AuthScreen._submit] ${action.name} completed. '
        'currentUser=${AuthDebug.describeUser(AuthService.instance.currentUser)}',
      );
    } on FirebaseAuthException catch (error) {
      _showAuthError(error);

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (error) {
      _showMessage('Не удалось выполнить авторизацию: $error');

      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: GestureDetector(
          // Тап по свободному месту скрывает клавиатуру на телефоне.
          onTap: () => FocusScope.of(context).unfocus(),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 40,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Icon(
                                  Icons.lock_person_outlined,
                                  size: 44,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Мои объекты',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.headlineMedium?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Войдите или зарегистрируйтесь, чтобы управлять объектами ремонта.',
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 28),
                                _EmailField(
                                  controller: _emailController,
                                  enabled: !_loading,
                                  validator: _validateEmail,
                                  onSubmitted: (_) => _submit(_AuthAction.signIn),
                                ),
                                const SizedBox(height: 14),
                                _PasswordField(
                                  controller: _passwordController,
                                  enabled: !_loading,
                                  obscureText: _obscurePassword,
                                  validator: _validatePassword,
                                  onSubmitted: (_) => _submit(_AuthAction.signIn),
                                  onToggleVisibility: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                ),
                                const SizedBox(height: 22),
                                FilledButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () => _submit(_AuthAction.signIn),
                                  icon: _loading
                                      ? const _ButtonLoader()
                                      : const Icon(Icons.login),
                                  label: const Text('Войти'),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  onPressed: _loading
                                      ? null
                                      : () => _submit(_AuthAction.register),
                                  icon: const Icon(Icons.person_add_alt_1),
                                  label: const Text('Регистрация'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Возможные действия формы.
///
/// enum делает код понятнее, чем bool вроде `isRegister`.
enum _AuthAction {
  signIn,
  register,
}

/// Поле email вынесено отдельно, чтобы основной build оставался коротким.
class _EmailField extends StatelessWidget {
  const _EmailField({
    required this.controller,
    required this.enabled,
    required this.validator,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final bool enabled;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      autofillHints: const [AutofillHints.email],
      autocorrect: false,
      textCapitalization: TextCapitalization.none,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: const InputDecoration(
        labelText: 'Email',
        hintText: 'name@example.com',
        prefixIcon: Icon(Icons.email_outlined),
      ),
    );
  }
}

/// Поле пароля с переключателем видимости.
class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.enabled,
    required this.obscureText,
    required this.validator,
    required this.onSubmitted,
    required this.onToggleVisibility,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool obscureText;
  final FormFieldValidator<String> validator;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: TextInputAction.done,
      autofillHints: const [AutofillHints.password],
      autocorrect: false,
      enableSuggestions: false,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      decoration: InputDecoration(
        labelText: 'Password',
        hintText: 'Минимум 6 символов',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: obscureText ? 'Показать пароль' : 'Скрыть пароль',
          onPressed: enabled ? onToggleVisibility : null,
          icon: Icon(
            obscureText ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
        ),
      ),
    );
  }
}

/// Маленький loader для кнопок.
class _ButtonLoader extends StatelessWidget {
  const _ButtonLoader();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
  }
}
