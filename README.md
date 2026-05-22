# APP Remont

APP Remont — MVP мобильного приложения на Flutter + Firebase для управления ремонтными объектами.

Приложение позволяет:

- в dev-режиме входить временным тестовым пользователем без SMS;
- оставить phone auth как production-заготовку;
- создавать объекты ремонта;
- видеть только доступные пользователю объекты;
- добавлять исполнителей из телефонной книги;
- вести чат внутри объекта;
- добавлять чеки, расходы и фото чеков;
- хранить фото в Firebase Storage;
- хранить данные в Cloud Firestore.

## Архитектура

Flutter запускается локально через VS Code или Android Studio.

Docker используется только для инфраструктуры:

- `backend` — минимальный Node.js backend;
- `firebase-emulators` — Firebase Auth, Firestore, Storage и Emulator UI.

## Структура проекта

```text
lib/
  core/             общая конфигурация, тема, AppState на Provider
  models/           модели данных приложения
  services/         низкоуровневые сервисы Firebase/Auth/Storage
  repositories/     работа с данными Firestore для экранов
  screens/          экраны приложения
  widgets/          переиспользуемые UI-компоненты
  utils/            маленькие утилиты

backend/            минимальный backend на Express
docker/firebase/    Dockerfile для Firebase CLI
firebase.json       конфигурация Firebase emulators
firestore.rules     правила безопасности Firestore
storage.rules       правила безопасности Storage
docker-compose.yml  backend + Firebase emulators
```

## 1. Установка Flutter

1. Откройте официальный сайт Flutter: https://docs.flutter.dev/get-started/install
2. Выберите вашу ОС: Windows, macOS или Linux.
3. Скачайте Flutter SDK.
4. Добавьте папку `flutter/bin` в переменную `PATH`.
5. Проверьте установку:

```bash
flutter doctor
```

Если `flutter doctor` показывает предупреждения, исправьте их по подсказкам в терминале.

## 2. Установка Android Studio

1. Скачайте Android Studio: https://developer.android.com/studio
2. Установите Android Studio.
3. Откройте Android Studio.
4. Установите Android SDK.
5. Установите Android SDK Platform Tools.
6. Установите Android Emulator.
7. В Android Studio откройте `Device Manager`.
8. Создайте Android Virtual Device, например Pixel 7.

После установки снова выполните:

```bash
flutter doctor
```

## 3. Подготовка проекта Flutter

Если в проекте еще нет папок `android/` и `ios/`, создайте платформенные файлы:

```bash
flutter create --platforms=android,ios .
```

Затем установите зависимости:

```bash
flutter pub get
```

Для Android после генерации платформенных файлов проверьте, что в
`android/app/src/main/AndroidManifest.xml` есть разрешение на чтение контактов:

```xml
<uses-permission android:name="android.permission.READ_CONTACTS" />
```

Для iOS после генерации платформенных файлов добавьте описание доступа к
контактам в `ios/Runner/Info.plist`:

```xml
<key>NSContactsUsageDescription</key>
<string>Приложение использует контакты, чтобы добавлять исполнителей на объект.</string>
```

## 4. Запуск Firebase emulators и backend

Убедитесь, что Docker Desktop запущен.

Запустите инфраструктуру:

```bash
docker compose up --build
```

После запуска будут доступны:

- Firebase Emulator UI: http://127.0.0.1:4000
- Firestore emulator: `127.0.0.1:8080`
- Firebase Auth emulator: `127.0.0.1:9099`
- Firebase Storage emulator: `127.0.0.1:9199`
- Backend healthcheck: http://127.0.0.1:8081/health

Flutter в Docker не запускается. Это сделано специально: мобильное приложение удобнее запускать локально через IDE, эмулятор или реальное устройство.

## 5. Запуск Android emulator

Вариант через Android Studio:

1. Откройте Android Studio.
2. Откройте `Device Manager`.
3. Нажмите `Start` рядом с созданным устройством.

Вариант через терминал:

```bash
flutter emulators
flutter emulators --launch <emulator_id>
```

Проверьте, что Flutter видит устройство:

```bash
flutter devices
```

## 6. Запуск приложения

Сначала запустите Docker-инфраструктуру:

```bash
docker compose up --build
```

В другом терминале запустите Flutter:

```bash
flutter run
```

Или откройте проект в VS Code / Android Studio и нажмите Run.

## 7. Dev-вход без Phone Auth

В debug-режиме Phone Auth отключен.

На экране входа будет одна кнопка:

```text
Войти как тестовый пользователь
```

Что происходит после нажатия:

1. Приложение вызывает Firebase Auth anonymous sign-in.
2. Firebase Auth emulator создает временного пользователя.
3. `main.dart` получает новое состояние авторизации.
4. Экран входа автоматически заменяется на список объектов.
5. Созданные объекты сохраняются в Firestore emulator.

Это временное решение только для разработки. Оно нужно, чтобы быстро проверять
создание объектов без настройки SMS и Phone provider.

## 8. Создание объекта в Firestore emulator

1. Запустите инфраструктуру:

```bash
docker compose up --build
```

2. Запустите приложение:

```bash
flutter run
```

3. Нажмите `Войти как тестовый пользователь`.
4. Нажмите кнопку `Объект`.
5. Заполните название, адрес, описание и статус.
6. Нажмите `Создать объект`.
7. Откройте Firebase Emulator UI:

```text
http://127.0.0.1:4000
```

8. Перейдите в Firestore и проверьте коллекцию `objects`.

## 9. Этапы работ и фото

Фото объекта теперь привязаны к отдельной сущности этапа работ.

Структура внутри Firestore:

```text
objects/
  {objectId}/
    stages/
      {stageId}
    photos/
      {photoId}
```

Этап:

```text
id
name
color
icon
sortOrder
createdAt
```

Фото:

```text
id
objectId
stageId
imageUrl
description
uploadedBy
uploadedAt
```

Почему `stageId`, а не текст этапа внутри фото:

- этап можно переименовать без изменения всех фото;
- фото остается связано со стабильным ID;
- проще фильтровать и группировать фотографии;
- у этапа могут быть цвет, иконка и порядок сортировки.

В разделе `Фото` доступны:

- дефолтные этапы ремонта;
- создание своего этапа;
- редактирование этапа;
- удаление этапа;
- загрузка фото только после выбора этапа;
- поиск по этапу, описанию и автору;
- фильтр по этапу;
- группировка фото по этапам;
- удаление фото;
- кэширование изображений через `cached_network_image`.

## 10. Firestore rules в dev-режиме

Для локальной разработки `firestore.rules` временно разрешает чтение и запись
всем пользователям:

```text
allow read, write: if true;
```

Это сделано специально для Firebase Emulator, чтобы новичок мог быстро
проверить вход, список объектов и создание объекта без ошибок прав доступа.

Даже локальный Firestore Emulator применяет rules. Если rules написаны слишком
строго или проверяют null как list, Flutter получит `permission-denied`.

Перед production эти rules нужно заменить строгими правилами доступа.

## 11. Production Firebase

Для production нужно подключить настоящий Firebase project:

1. Создайте проект в Firebase Console.
2. Включите Firebase Auth Phone provider.
3. Создайте Android/iOS приложения в Firebase Console.
4. Выполните:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

5. Замените demo-настройки в `lib/firebase_options.dart`.
6. Задеплойте правила:

```bash
firebase deploy --only firestore:rules,storage
```

## 12. Полезные команды

Проверить Docker Compose:

```bash
docker compose config
```

Проверить Flutter-код:

```bash
flutter analyze
```

Запустить тесты:

```bash
flutter test
```

Очистить Flutter build:

```bash
flutter clean
flutter pub get
```
