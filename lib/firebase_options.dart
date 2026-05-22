import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return web;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:web:remont',
    messagingSenderId: '123456789',
    projectId: 'remont-local',
    authDomain: 'remont-local.firebaseapp.com',
    storageBucket: 'remont-local.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:android:remont',
    messagingSenderId: '123456789',
    projectId: 'remont-local',
    storageBucket: 'remont-local.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:123456789:ios:remont',
    messagingSenderId: '123456789',
    projectId: 'remont-local',
    iosBundleId: 'com.example.appRemont',
    storageBucket: 'remont-local.appspot.com',
  );
}
