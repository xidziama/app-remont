import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../utils/auth_debug.dart';
import 'photo_url_resolver.dart';

/// AuthService — тонкая обертка над Firebase Authentication.
///
/// Важная идея архитектуры:
/// - экран авторизации отвечает только за форму, loading state и SnackBar;
/// - сервис отвечает за реальные Firebase вызовы;
/// - main.dart слушает authStateChanges и сам переключает AuthScreen на
///   ProjectListScreen после успешного входа.
///
/// Благодаря этому UI не знает, как именно Firebase создает пользователя или
/// проверяет пароль. Если позже появятся Google/Apple auth или восстановление
/// пароля, их можно будет добавить здесь, не размазывая Firebase API по экранам.
class AuthService {
  AuthService._();

  /// Singleton подходит для текущего MVP: сервис не хранит сложное состояние,
  /// а только делегирует операции Firebase SDK.
  static final AuthService instance = AuthService._();

  /// Основной клиент Firebase Auth.
  ///
  /// Он уже настроен в main.dart после Firebase.initializeApp().
  /// Если включены эмуляторы, FirebaseBootstrap переключит этот же instance на
  /// локальный Auth Emulator до первого запроса авторизации.
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Поток состояния авторизации.
  ///
  /// StreamBuilder в main.dart использует этот поток как единственный источник
  /// правды:
  /// - User == null: показываем AuthScreen;
  /// - User != null: показываем ProjectListScreen.
  Stream<User?> get authStateChanges {
    return _auth.authStateChanges().map((user) {
      if (user == null) {
        debugPrint('[AuthService.authStateChanges] SIGNED OUT');
      } else {
        debugPrint(
          '[AuthService.authStateChanges] SIGNED IN uid=${user.uid}, '
          'email=${user.email ?? ''}, isAnonymous=${user.isAnonymous}, '
          'providerData=${AuthDebug.describeProviderData(user)}',
        );
      }

      return user;
    });
  }

  /// Текущий Firebase-пользователь.
  ///
  /// Может быть null, если пользователь еще не вошел или уже вышел.
  User? get currentUser => _auth.currentUser;

  /// Выполняет вход по email и паролю.
  ///
  /// UI передает уже обрезанные строки. Firebase сам проверит существование
  /// пользователя, корректность пароля, блокировки и прочие серверные правила.
  /// Ошибки FirebaseAuthException не скрываем: экран поймает их и покажет
  /// понятное сообщение пользователю.
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthService.signInWithEmail] Start email=$email');

    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    AuthDebug.logUser(
      'AuthService.signInWithEmail credential.user',
      credential.user,
    );
    AuthDebug.logUser(
      'AuthService.signInWithEmail currentUser',
      _auth.currentUser,
    );

    await _ensureUserProfile(credential.user);
  }

  /// Регистрирует нового пользователя по email и паролю.
  ///
  /// После успешной регистрации Firebase автоматически считает пользователя
  /// авторизованным. Поэтому отдельный вход после createUserWithEmailAndPassword
  /// не нужен: authStateChanges сам переведет приложение на ProjectListScreen.
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    debugPrint('[AuthService.registerWithEmail] Start email=$email');

    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    AuthDebug.logUser(
      'AuthService.registerWithEmail credential.user',
      credential.user,
    );
    AuthDebug.logUser(
      'AuthService.registerWithEmail currentUser',
      _auth.currentUser,
    );

    await _ensureUserProfile(credential.user);

    if (credential.user != null && !credential.user!.emailVerified) {
      debugPrint(
        '[AuthService.registerWithEmail] Sending email verification to '
        '${credential.user!.email}.',
      );
      await credential.user!.sendEmailVerification();
    }
  }

  /// Текущий (закэшированный SDK) статус подтверждения почты.
  ///
  /// Это значение могло устареть, если пользователь подтвердил почту по
  /// ссылке из письма в этой же сессии. Для свежего статуса используйте
  /// [reloadAndCheckEmailVerified].
  bool get isEmailVerified => _auth.currentUser?.emailVerified ?? false;

  /// Повторно отправляет письмо подтверждения текущему пользователю.
  ///
  /// На Firebase Auth Emulator письмо не уходит на реальный почтовый ящик.
  /// Чтобы подтвердить почту в dev-режиме, откройте Emulator UI
  /// (http://127.0.0.1:4000/auth, либо http://10.0.2.2:4000/auth с телефона
  /// на Android emulator), найдите пользователя и либо откройте ссылку
  /// подтверждения из карточки письма, либо переключите "Email verified"
  /// вручную в интерфейсе эмулятора.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw Exception('Пользователь не авторизован.');
    }

    await user.sendEmailVerification();
  }

  /// Перезагружает данные пользователя с сервера и возвращает свежий
  /// emailVerified.
  ///
  /// `User.emailVerified` — закэшированное поле, которое не обновляется
  /// автоматически после перехода по ссылке из письма. reload() запрашивает
  /// актуальные данные у Firebase Auth.
  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) {
      return false;
    }

    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
  }

  Future<void> _ensureUserProfile(User? user) async {
    if (user == null) {
      return;
    }

    final now = DateTime.now();
    final email = user.email?.trim().toLowerCase() ?? '';
    final userPath = 'users/${user.uid}';
    debugPrint('[ACCESS] Ensuring user profile...');
    debugPrint('[ACCESS] Writing $userPath email=$email');

    await _db.collection('users').doc(user.uid).set(
      {
        'uid': user.uid,
        'email': email,
        'displayName': user.displayName ?? email,
        'baseRole': 'user',
        'updatedAt': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  /// Завершает текущую Firebase-сессию.
  ///
  /// После signOut поток authStateChanges вернет null, и main.dart автоматически
  /// покажет AuthScreen.
  Future<void> signOut() async {
    AuthDebug.logUser('AuthService.signOut before', _auth.currentUser);
    await _auth.signOut();
    // Presigned-ссылки в кэше резолвера не тянут за собой чужие данные (они
    // просто перестанут работать без валидного токена), но на общем
    // устройстве не должны переживать смену пользователя.
    PhotoUrlResolver.instance.clearCache();
    AuthDebug.logUser('AuthService.signOut after', _auth.currentUser);
  }
}
