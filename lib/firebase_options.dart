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
    apiKey: 'AIzaSyDbUZkJn_iLmoR-pN7N4IHj2gE3usT2wYw',
    appId: '1:866414790092:web:646ae9f1ec079243918969',
    messagingSenderId: '866414790092',
    projectId: 'remont-76b60',
    authDomain: 'remont-76b60.firebaseapp.com',
    storageBucket: 'remont-76b60.firebasestorage.app',
    measurementId: 'G-8L2G5JKEQF',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCAnSU02P3iOxmqzhrJv_oN6gIWb589OQA',
    appId: '1:866414790092:android:883477f0f1753bf6918969',
    messagingSenderId: '866414790092',
    projectId: 'remont-76b60',
    storageBucket: 'remont-76b60.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDHd8mlYt8vF_kzieSxLFTn7EPIWe6fFoM',
    appId: '1:866414790092:ios:241bc53335bdec76918969',
    messagingSenderId: '866414790092',
    projectId: 'remont-76b60',
    storageBucket: 'remont-76b60.firebasestorage.app',
    iosBundleId: 'com.remont.app',
  );

}