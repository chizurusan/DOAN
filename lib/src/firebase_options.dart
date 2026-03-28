// File: lib/src/firebase_options.dart
//
// ⚠️  HƯỚNG DẪN THIẾT LẬP FIREBASE:
// ─────────────────────────────────
// 1. Tạo project trên https://console.firebase.google.com
// 2. Trong project, bật Authentication (Email/Password)
//    và Cloud Firestore (chế độ test để bắt đầu).
// 3. Cài FlutterFire CLI:
//      dart pub global activate flutterfire_cli
// 4. Chạy lệnh bên dưới tại thư mục gốc của project Flutter:
//      flutterfire configure
//    Lệnh này sẽ TỰ ĐỘNG tạo lại file này với các giá trị
//    thực từ Firebase project của bạn.
// 5. Sau khi file được tạo lại, xóa toàn bộ nội dung placeholder
//    ở đây và thay bằng nội dung mới được generate.
//
// Nếu chưa muốn dùng FlutterFire CLI, điền thủ công các giá trị
// lấy từ Firebase Console → Project Settings → My Apps → SDK setup:

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      case TargetPlatform.windows:
        return windows;
      default:
        throw UnsupportedError(
          'Platform hiện tại chưa được hỗ trợ. '
          'Chạy "flutterfire configure" để tạo lại file này.',
        );
    }
  }

  // ── Web ──────────────────────────────────────────────────────────
  // Lấy từ: Firebase Console → Project Settings → My Apps → Web App
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // ── Android ──────────────────────────────────────────────────────
  // Lấy từ: Firebase Console → Project Settings → My Apps → Android App
  // hoặc từ google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  // ── iOS ──────────────────────────────────────────────────────────
  // Lấy từ: Firebase Console → Project Settings → My Apps → iOS App
  // hoặc từ GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.roomifyMvp',
  );

  // ── Windows ──────────────────────────────────────────────────────
  // Sau khi chạy "flutterfire configure", giá trị Windows sẽ được tạo.
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'YOUR_WINDOWS_API_KEY',
    appId: 'YOUR_WINDOWS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );
}
