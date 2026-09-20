import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/app_config.dart';
import 'core/app_theme.dart';
import 'firebase_options.dart';
import 'repositories/project_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/home_router_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_bootstrap.dart';
import 'utils/auth_debug.dart';

Future<void> main() async {
  // debugPrint используется по всему приложению для диагностики (в том числе
  // печатает uid/email при разборе ошибок Auth/Firestore). Сам debugPrint не
  // отключается в release автоматически, поэтому в release-сборке глушим его
  // здесь централизованно, до любых других вызовов. В debug/profile режимах
  // поведение не меняется — отладочные логи продолжают работать как раньше.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Flutter должен подготовить binding до вызова Firebase.initializeApp().
  // Без этой строки Firebase и плагины могут быть недоступны на старте.
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('[main] WidgetsFlutterBinding initialized.');

  // Подключаем Firebase к приложению.
  //
  // Для Android значения должны совпадать с android/app/google-services.json.
  // Если здесь оставить demo-api-key, Firebase Auth на реальном устройстве
  // вернет ошибку "API key not valid".
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint(
    '[main] Firebase.initializeApp completed. '
    'projectId=${DefaultFirebaseOptions.currentPlatform.projectId}',
  );
  debugPrint(
    '[main] USE_FIREBASE_EMULATORS=${AppConfig.useFirebaseEmulators}',
  );

  // Firebase Emulator Suite включается только явно через dart-define.
  //
  // По умолчанию флаг выключен, чтобы Email/Password вход на Android Samsung
  // использовал production Firebase project `remont-76b60`.
  // Для локальной разработки с Docker emulators можно запускать так:
  // flutter run --dart-define=USE_FIREBASE_EMULATORS=true
  if (AppConfig.useFirebaseEmulators) {
    debugPrint(
      '[main] Calling FirebaseBootstrap.connectToEmulators() before runApp.',
    );
    await FirebaseBootstrap.connectToEmulators();
  } else {
    debugPrint(
      '[main] Firebase emulators are disabled. The app will use production '
      'Firebase. For local development pass '
      '--dart-define=USE_FIREBASE_EMULATORS=true.',
    );
  }
  FirebaseBootstrap.logEmulatorState('main after bootstrap');

  // At startup Firebase may restore a cached Auth user from disk. If that
  // cached refresh token belongs to a different environment, for example old
  // Auth Emulator data while the app now uses production Firebase, getIdToken()
  // can fail with INVALID_REFRESH_TOKEN. We detect that early and sign out.
  await AuthDebug.validateCurrentUserToken(
    source: 'main startup',
    forceRefresh: true,
  );

  debugPrint('[main] Starting Flutter app with runApp().');
  runApp(const RemontApp());
}

class RemontApp extends StatelessWidget {
  const RemontApp({super.key});

  @override
  Widget build(BuildContext context) {
    // MultiProvider держит зависимости на верхнем уровне приложения.
    // Так экраны получают AppState и репозитории через context, без глобального
    // хаоса и без сложных архитектурных фреймворков.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AppState()),
        Provider<ProjectRepository>(create: (_) => ProjectRepository()),
      ],
      child: MaterialApp(
        title: 'Мои объекты',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: StreamBuilder(
          // Поток авторизации автоматически сообщает, вошел пользователь или нет.
          stream: AuthService.instance.authStateChanges,
          builder: (context, snapshot) {
            // Пока Firebase проверяет сохраненную сессию, показываем loader.
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }

            // Если user есть — открываем приложение. Если нет — экран входа.
            return snapshot.hasData
                ? const HomeRouterScreen()
                : const AuthScreen();
          },
        ),
      ),
    );
  }
}
