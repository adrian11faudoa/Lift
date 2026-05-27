import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;

/// NotificationService handles:
/// - Rest timer completion alerts (highest priority)
/// - Workout reminder scheduling
/// - PR achievement alerts
/// - Sync status updates
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  // ─── Channel IDs ──────────────────────────────────────────────
  static const _channelRestTimer    = 'rest_timer';
  static const _channelWorkout      = 'workout';
  static const _channelPR           = 'personal_record';
  static const _channelReminder     = 'reminder';

  // ─── Notification IDs ─────────────────────────────────────────
  static const _idRestComplete  = 1;
  static const _idWorkoutRemind = 2;
  static const _idPRAlert       = 3;

  Future<void> initialize() async {
    if (_initialized) return;
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    await _createChannels();
    _initialized = true;
    debugPrint('[NotificationService] Initialized');
  }

  Future<void> _createChannels() async {
    const channels = [
      AndroidNotificationChannel(
        _channelRestTimer,
        'Rest Timer',
        description:  'Alerts when rest period is complete',
        importance:   Importance.high,
        playSound:    true,
        enableVibration: true,
      ),
      AndroidNotificationChannel(
        _channelWorkout,
        'Workout',
        description:  'Active workout status',
        importance:   Importance.low,
        playSound:    false,
      ),
      AndroidNotificationChannel(
        _channelPR,
        'Personal Records',
        description:  'New PR achievements',
        importance:   Importance.high,
        playSound:    true,
      ),
      AndroidNotificationChannel(
        _channelReminder,
        'Reminders',
        description:  'Workout reminders',
        importance:   Importance.defaultImportance,
      ),
    ];

    final androidPlugin = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    for (final channel in channels) {
      await androidPlugin?.createNotificationChannel(channel);
    }
  }

  // ─── REST TIMER ───────────────────────────────────────────────
  Future<void> showRestComplete() async {
    await _plugin.show(
      _idRestComplete,
      '⏱ Rest Complete!',
      'Time for your next set. You\'ve got this! 💪',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelRestTimer, 'Rest Timer',
          importance:     Importance.high,
          priority:       Priority.high,
          playSound:      true,
          enableVibration: true,
          vibrationPattern: Int64List.fromList([0, 200, 100, 200]),
          icon: '@mipmap/ic_launcher',
          color: const Color(0xFF2563EB),
          styleInformation: const BigTextStyleInformation(
            'Time for your next set. You\'ve got this! 💪',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
    );
  }

  // ─── PR ACHIEVEMENT ───────────────────────────────────────────
  Future<void> showNewPR({
    required String exerciseName,
    required double weight,
    required int reps,
    required double estimated1RM,
  }) async {
    await _plugin.show(
      _idPRAlert,
      '🏆 New Personal Record!',
      '$exerciseName: ${weight.toStringAsFixed(1)}kg × $reps reps (${estimated1RM.toStringAsFixed(1)}kg e1RM)',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelPR, 'Personal Records',
          importance:  Importance.high,
          priority:    Priority.high,
          icon:        '@mipmap/ic_launcher',
          color:       const Color(0xFFFFD700),
          styleInformation: BigTextStyleInformation(
            '$exerciseName: ${weight.toStringAsFixed(1)}kg × $reps reps\nEstimated 1RM: ${estimated1RM.toStringAsFixed(1)}kg 🎉',
          ),
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          interruptionLevel: InterruptionLevel.active,
        ),
      ),
    );
  }

  // ─── WORKOUT REMINDER ─────────────────────────────────────────
  Future<void> scheduleWorkoutReminder({
    required String message,
    required DateTime scheduledDate,
  }) async {
    await _plugin.zonedSchedule(
      _idWorkoutRemind,
      '🏋️ Time to Train!',
      message,
      tz.TZDateTime.from(scheduledDate, tz.local),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelReminder, 'Reminders',
          importance: Importance.defaultImportance,
          priority:   Priority.defaultPriority,
          icon:       '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> cancelWorkoutReminder() async {
    await _plugin.cancel(_idWorkoutRemind);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }

  // ─── PERMISSION REQUEST ───────────────────────────────────────
  Future<bool> requestPermissions() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final ios = _plugin
        .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();

    final androidResult = await android?.requestNotificationsPermission();
    final iosResult     = await ios?.requestPermissions(alert: true, badge: true, sound: true);

    return androidResult ?? iosResult ?? false;
  }

  void _onNotificationTapped(NotificationResponse response) {
    debugPrint('[NotificationService] Tapped: ${response.id} payload: ${response.payload}');
    // Navigate based on payload
  }
}

// Minimal Int64List stub for platforms without it
class Int64List extends List<int> {
  Int64List.fromList(List<int> list) : super.filled(list.length, 0) {
    for (var i = 0; i < list.length; i++) { this[i] = list[i]; }
  }
}
