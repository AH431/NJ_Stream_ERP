import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// ── Background message handler（必須是 top-level 函式）─────────────────────────
// 在 App 未啟動或在背景時由系統喚醒執行，不可存取 UI。
@pragma('vm:entry-point')
Future<void> _fcmBackgroundHandler(RemoteMessage message) async {
  // 背景不顯示 UI；FCM 的 notification payload 由系統托盤自動顯示。
  debugPrint('[FCM] Background message: ${message.messageId}');
}

// ── 前景通知 channel（Android 8+）──────────────────────────────────────────────
const _androidChannel = AndroidNotificationChannel(
  'anomaly_alerts',
  '異常通知',
  description: 'NJ Stream ERP 系統異常告警',
  importance: Importance.high,
);

// ── FCM Service ────────────────────────────────────────────────────────────────
//
// 使用方式：
//   1. main() 中呼叫 FcmService.initialize()（background handler 需最早註冊）
//   2. Firebase.initializeApp() 之後呼叫 FcmService.setup(navigatorKey)
//   3. 登入後：FcmService.onUserLoggedIn(dio)
//   4. 登出前：FcmService.onUserLoggedOut(dio)

class FcmService {
  FcmService._();

  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static GlobalKey<NavigatorState>? _navigatorKey;

  // ── Step 1：main() 最早呼叫，註冊 background handler ─────────────────────
  static void initialize() {
    FirebaseMessaging.onBackgroundMessage(_fcmBackgroundHandler);
  }

  // ── Step 2：Firebase.initializeApp() 後呼叫 ──────────────────────────────
  static Future<void> setup(GlobalKey<NavigatorState> navigatorKey) async {
    _navigatorKey = navigatorKey;

    // 初始化本地通知（前景用）
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );

    // 建立 notification channel（Android 8+）
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);

    // Android 13+ 需明確請求通知權限
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    // 前景訊息 → 顯示本地通知（系統托盤不會自動顯示前景訊息）
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);

    // 背景點擊通知 → 導向通知頁
    FirebaseMessaging.onMessageOpenedApp.listen(_onNotificationOpened);

    // App 終止狀態下點擊通知啟動
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) _navigateToNotifications();
  }

  // ── 登入後：取得 token 並向後端註冊 ─────────────────────────────────────
  static Future<void> onUserLoggedIn(Dio dio) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await dio.post('/api/v1/notifications/token', data: {
        'token': token,
        'platform': 'android',
      });
      debugPrint('[FCM] Token registered');

      // token 輪換時自動重新註冊
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        try {
          await dio.post('/api/v1/notifications/token', data: {
            'token': newToken,
            'platform': 'android',
          });
          debugPrint('[FCM] Token refreshed and re-registered');
        } catch (e) {
          debugPrint('[FCM] Token refresh registration failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[FCM] onUserLoggedIn failed: $e');
    }
  }

  // ── 登出後：向後端移除 token ──────────────────────────────────────────────
  static Future<void> onUserLoggedOut(Dio dio) async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;

      await dio.delete('/api/v1/notifications/token', data: {'token': token});
      debugPrint('[FCM] Token unregistered');
    } catch (e) {
      debugPrint('[FCM] onUserLoggedOut failed: $e');
    }
  }

  // ── 前景收到訊息 → 顯示本地通知 ─────────────────────────────────────────
  static void _onForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _androidChannel.id,
          _androidChannel.name,
          channelDescription: _androidChannel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
      payload: message.data['screen'],
    );
  }

  // ── 點擊通知（前景本地通知）─────────────────────────────────────────────
  static void _onNotificationTap(NotificationResponse response) {
    if (response.payload == 'notifications') _navigateToNotifications();
  }

  // ── 點擊系統托盤通知（背景）────────────────────────────────────────────
  static void _onNotificationOpened(RemoteMessage message) {
    if (message.data['screen'] == 'notifications') _navigateToNotifications();
  }

  // ── 導向通知頁 ────────────────────────────────────────────────────────────
  static void _navigateToNotifications() {
    _navigatorKey?.currentState?.pushNamedAndRemoveUntil(
      '/notifications',
      (route) => route.isFirst,
    );
  }
}
