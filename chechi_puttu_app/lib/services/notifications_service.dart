import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:chechi_puttu_app/services/chechi_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationsService {
  NotificationsService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    FirebaseMessaging? messaging,
    FlutterLocalNotificationsPlugin? local,
    this.onDeepLink,
  })  : _db = firestore ?? chechiFirestore,
        _auth = auth ?? FirebaseAuth.instance,
        _messaging = messaging ?? FirebaseMessaging.instance,
        _local = local ?? FlutterLocalNotificationsPlugin();

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;
  final FirebaseMessaging _messaging;
  final FlutterLocalNotificationsPlugin _local;
  final void Function(Map<String, String> data)? onDeepLink;

  StreamSubscription<RemoteMessage>? _pushSub;
  StreamSubscription<RemoteMessage>? _pushOpenSub;

  static const _androidChannelId = 'order_updates';
  static const _androidChannelName = 'Order updates';
  static const _androidChannelDescription = 'Order status notifications';
  static const _birthdayChannelId = 'birthday_wishes';
  static const _birthdayChannelName = 'Birthday wishes';
  static const _birthdayChannelDescription = 'Birthday greetings from Chechi Puttu';

  bool get _supportsPush =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  Future<void> init() async {
    if (!_supportsPush) return;

    await _initLocalNotifications();

    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    try {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      // On iOS the FCM token is only available once the APNs token is set. If
      // APNs isn't ready yet, getToken can return null — retry once shortly.
      var token = await _messaging.getToken();
      if (token == null &&
          defaultTargetPlatform == TargetPlatform.iOS) {
        await Future<void>.delayed(const Duration(seconds: 2));
        token = await _messaging.getToken();
      }
      if (token != null) {
        await savePushTokenIfPresent(token);
      }
      _messaging.onTokenRefresh.listen(savePushTokenIfPresent);
      _pushSub?.cancel();
      _pushSub = FirebaseMessaging.onMessage.listen(_showForegroundPush);
      _pushOpenSub?.cancel();
      _pushOpenSub = FirebaseMessaging.onMessageOpenedApp.listen(
        _handleOpenedPush,
      );
      final initial = await FirebaseMessaging.instance.getInitialMessage();
      if (initial != null) _handleOpenedPush(initial);
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _pushSub?.cancel();
    await _pushOpenSub?.cancel();
  }

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // iOS: without Darwin settings the plugin never displays anything on iPhone.
    // Requesting the permissions here also covers foreground/local notifications.
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );
    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final parsed = jsonDecode(raw);
          if (parsed is! Map) return;
          final map = <String, String>{};
          parsed.forEach((k, v) {
            map[k.toString()] = v.toString();
          });
          onDeepLink?.call(map);
        } catch (_) {}
      },
    );

    const androidChannel = AndroidNotificationChannel(
      _androidChannelId,
      _androidChannelName,
      description: _androidChannelDescription,
      importance: Importance.high,
    );

    const birthdayChannel = AndroidNotificationChannel(
      _birthdayChannelId,
      _birthdayChannelName,
      description: _birthdayChannelDescription,
      importance: Importance.high,
    );

    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(androidChannel);
    await androidPlugin?.createNotificationChannel(birthdayChannel);
  }

  void _showForegroundPush(RemoteMessage m) {
    final title = m.notification?.title?.trim();
    final body = m.notification?.body?.trim();
    if (title == null || title.isEmpty || body == null || body.isEmpty) {
      return;
    }
    final isBirthday = m.data['type'] == 'birthday';
    _showLocal(
      title: title,
      body: body,
      payload: jsonEncode(m.data),
      birthday: isBirthday,
    );
  }

  void _showLocal({
    required String title,
    required String body,
    String? payload,
    bool birthday = false,
  }) {
    final android = birthday
        ? AndroidNotificationDetails(
            _birthdayChannelId,
            _birthdayChannelName,
            channelDescription: _birthdayChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          )
        : AndroidNotificationDetails(
            _androidChannelId,
            _androidChannelName,
            channelDescription: _androidChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          );
    _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: android,
        iOS: const DarwinNotificationDetails(),
      ),
      payload: payload,
    );
  }

  void _handleOpenedPush(RemoteMessage m) {
    final raw = m.data;
    if (raw.isEmpty) return;
    final map = <String, String>{};
    raw.forEach((k, v) => map[k] = v.toString());
    onDeepLink?.call(map);
  }

  Future<void> savePushTokenIfPresent(String token) async {
    final user = _auth.currentUser;
    if (user == null || token.isEmpty) return;
    final docId = '${user.uid}_${token.hashCode}';
    await _db.collection('push_tokens').doc(docId).set({
      'uid': user.uid,
      'token': token,
      'platform': defaultTargetPlatform.name,
      'updated_at': FieldValue.serverTimestamp(),
      'created_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
