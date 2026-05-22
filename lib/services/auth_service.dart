import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// AuthService — тонкая обертка над Firebase Auth.
///
/// Сервис знает только о Firebase API. Бизнес-логика экранов остается в UI,
/// а работа с авторизацией собрана в одном месте.
class AuthService {
  AuthService._();

  /// Singleton удобен для маленького MVP: сервис без состояния и используется
  /// из разных экранов. При росте проекта его можно заменить DI-контейнером.
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  ConfirmationResult? _webConfirmationResult;

  /// Поток сообщает об изменениях авторизации: вход, выход, восстановление сессии.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// Текущий пользователь Firebase. Может быть null, если пользователь не вошел.
  User? get currentUser => _auth.currentUser;

  /// Временный тестовый вход для dev-режима.
  ///
  /// Почему используется anonymous auth:
  /// 1. Не нужен номер телефона.
  /// 2. Не нужен SMS-код.
  /// 3. Не нужно включать Phone provider в Firebase Console.
  /// 4. Firebase Auth emulator поддерживает anonymous users сразу.
  ///
  /// Важно:
  /// - этот метод предназначен только для разработки;
  /// - production-вход позже можно вернуть на phone auth;
  /// - после успешного входа `authStateChanges` в main.dart автоматически
  ///   переключит AuthScreen на ProjectListScreen.
  Future<void> signInAsTemporaryDevUser() async {
    // kDebugMode равен true при обычном запуске через `flutter run`.
    // В release-сборке временный вход блокируется, чтобы случайно не оставить
    // тестовую авторизацию в production-приложении.
    if (!kDebugMode) {
      throw FirebaseAuthException(
        code: 'dev-login-disabled',
        message: 'Тестовый вход доступен только в debug-режиме.',
      );
    }

    // Если пользователь уже вошел, повторный вход не нужен.
    // Это защищает от лишнего создания anonymous users в emulator.
    if (_auth.currentUser != null) {
      return;
    }

    // Firebase создаст временного anonymous user и вернет его UID.
    // Этот UID дальше используется как ownerId и participantId в Firestore.
    await _auth.signInAnonymously();
  }

  /// Запускает отправку SMS-кода.
  ///
  /// На iOS/Android используется verifyPhoneNumber.
  /// На web Firebase использует другой API — signInWithPhoneNumber.
  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(String verificationId) onCodeSent,
    required void Function(String message) onFailed,
  }) async {
    // Firebase Auth для web возвращает ConfirmationResult, а не verificationId.
    if (kIsWeb) {
      try {
        _webConfirmationResult = await _auth.signInWithPhoneNumber(phoneNumber);
        onCodeSent('web');
      } on FirebaseAuthException catch (error) {
        onFailed(error.message ?? error.code);
      }
      return;
    }

    // Мобильный сценарий: Firebase отправляет SMS и возвращает verificationId.
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      verificationCompleted: (credential) async {
        // Android иногда умеет автоматически прочитать SMS и сразу войти.
        await _auth.signInWithCredential(credential);
      },
      verificationFailed: (error) => onFailed(error.message ?? error.code),
      codeSent: (verificationId, _) => onCodeSent(verificationId),
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Подтверждает SMS-код и выполняет вход.
  Future<void> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    // На web подтверждаем код через сохраненный ConfirmationResult.
    if (kIsWeb && _webConfirmationResult != null) {
      await _webConfirmationResult!.confirm(smsCode);
      return;
    }

    // На мобильных платформах собираем credential из verificationId и SMS-кода.
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    await _auth.signInWithCredential(credential);
  }

  /// Завершает текущую Firebase-сессию.
  Future<void> signOut() => _auth.signOut();
}
