import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_state.dart';
import 'core/app_theme.dart';
import 'firebase_options.dart';
import 'repositories/project_repository.dart';
import 'screens/auth_screen.dart';
import 'screens/project_list_screen.dart';
import 'services/auth_service.dart';
import 'services/firebase_bootstrap.dart';

Future<void> main() async {
  // Flutter должен подготовить binding до вызова Firebase.initializeApp().
  // Без этой строки Firebase и плагины могут быть недоступны на старте.
  WidgetsFlutterBinding.ensureInitialized();

  // Подключаем Firebase к приложению. В MVP используются demo options,
  // а для production их нужно заменить через FlutterFire CLI.
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // В debug-режиме подключаемся к Firebase emulators.
  //
  // Для Flutter Web это особенно важно: перед первым Auth/Firestore/Storage
  // запросом SDK должен знать, что нужно идти на 127.0.0.1:9099/8080/9199,
  // а не в настоящий Firebase backend.
  // В release-режиме метод ничего не делает, чтобы не ломать production.
  await FirebaseBootstrap.connectToEmulators();

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
        title: 'APP Remont',
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
                ? const ProjectListScreen()
                : const AuthScreen();
          },
        ),
      ),
    );
  }
}
