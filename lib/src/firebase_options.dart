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
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDOKqzUNDunOaYRbtwKRMRgOKFclc3q3_k',
    appId: '1:916069537337:web:18c694b8bfc1adb15a1fe8',
    messagingSenderId: '916069537337',
    projectId: 'doankn',
    authDomain: 'doankn.firebaseapp.com',
    storageBucket: 'doankn.firebasestorage.app',
    measurementId: 'G-R5LE8YW2WY',
  );

  // ── Android ──────────────────────────────────────────────────────
  // Cần thêm Android app trong Firebase Console + tải google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDOKqzUNDunOaYRbtwKRMRgOKFclc3q3_k',
    appId: 'YOUR_ANDROID_APP_ID',
    messagingSenderId: '916069537337',
    projectId: 'doankn',
    storageBucket: 'doankn.firebasestorage.app',
  );

  // ── iOS ──────────────────────────────────────────────────────────
  // Cần thêm iOS app trong Firebase Console
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDOKqzUNDunOaYRbtwKRMRgOKFclc3q3_k',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: '916069537337',
    projectId: 'doankn',
    storageBucket: 'doankn.firebasestorage.app',
    iosBundleId: 'com.example.roomifyMvp',
  );

  // ── Windows ──────────────────────────────────────────────────────
  // Dùng chung config Web cho Windows desktop
  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyDOKqzUNDunOaYRbtwKRMRgOKFclc3q3_k',
    appId: '1:916069537337:web:18c694b8bfc1adb15a1fe8',
    messagingSenderId: '916069537337',
    projectId: 'doankn',
    authDomain: 'doankn.firebaseapp.com',
    storageBucket: 'doankn.firebasestorage.app',
    measurementId: 'G-R5LE8YW2WY',
  );
}
