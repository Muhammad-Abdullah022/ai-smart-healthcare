import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_client.dart';
import 'consultation_repository.dart';

/// Phone pop-up notifications for live events (new chat message, payment, prescription, issue reply…).
///
/// While the app is open or in the background, the live connection (WebSocket) is kept and every event
/// for this user shows as an Android notification — like WhatsApp while the app is running.
/// (When Android fully closes the app, messages wait on the server and appear when it is opened again;
/// pop-ups for a fully closed app would need Firebase Cloud Messaging.)
class LiveNotifications {
  LiveNotifications._();

  static final LiveNotifications instance = LiveNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  StreamSubscription? _sub;
  String _role = 'patient';
  int _id = 0;

  /// Called with the in-app link (e.g. /consultation/<id>) when a notification is tapped.
  void Function(String link)? onOpen;

  /// The consultation chat open on screen right now (no pop-up for it).
  String? openConsultationId;

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> start(ApiClient api, {required bool isDoctor}) async {
    _role = isDoctor ? 'doctor' : 'patient';
    LiveEvents.instance.ensureConnected(api);
    if (!supported) return;
    if (!_ready) {
      try {
        await _plugin.initialize(
          const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
          onDidReceiveNotificationResponse: (r) {
            final link = r.payload;
            if (link != null && link.isNotEmpty) onOpen?.call(link);
          },
        );
        await _plugin
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        _ready = true;
      } catch (e) {
        debugPrint('Notifications not available: $e');
        return;
      }
    }
    _sub ??= LiveEvents.instance.events.listen(_onEvent);
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
  }

  void _onEvent(Map<String, dynamic> e) {
    if (e['type'] == 'message') {
      final cid = '${e['consultation_id']}';
      final m = (e['message'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (m['sender'] == _role || cid == openConsultationId) return; // my own message / chat already open
      final kind = '${m['kind']}';
      final title = switch (kind) {
        'payment' => 'Payment screenshot received',
        'payment_ok' => 'Payment confirmed',
        'payment_rejected' => 'Payment not confirmed',
        'prescription' => 'Prescription received',
        'clinic_visit' => 'Please visit the clinic',
        'summary' => 'Symptom check shared',
        'file' => 'New photo or file',
        _ => m['sender'] == 'system' ? 'Consultation update' : 'New message',
      };
      _show(title, '${m['text'] ?? ''}', '/consultation/$cid', channel: 'messages');
    } else if (e['type'] == 'notification') {
      final link = '${e['link'] ?? ''}';
      if (link.startsWith('/consultation/')) return; // already shown from the message itself
      _show('${e['title'] ?? 'Notification'}', '${e['body'] ?? ''}', link, channel: 'alerts');
    }
  }

  Future<void> _show(String title, String body, String link, {required String channel}) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        _id++ % 100000,
        title,
        body.length > 180 ? '${body.substring(0, 180)}…' : body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            channel,
            channel == 'messages' ? 'Doctor chat messages' : 'Alerts',
            channelDescription: channel == 'messages'
                ? 'New messages, payments and prescriptions in online consultations'
                : 'Replies from support and other alerts',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        payload: link,
      );
    } catch (e) {
      debugPrint('Could not show notification: $e');
    }
  }
}
