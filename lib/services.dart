import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:image_picker/image_picker.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class DeviceServices {
  static final notifications = FlutterLocalNotificationsPlugin();
  static const native = MethodChannel('bolso_claro/files');
  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      final name = (await FlutterTimezone.getLocalTimezone()).identifier;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    }
    await notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    await notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
  }

  static Future<void> remind(
    int id,
    String title,
    DateTime due,
    double amount, {
    int daysBefore = 1,
  }) async {
    final when = tz.TZDateTime(
      tz.local,
      due.year,
      due.month,
      due.day - daysBefore,
      9,
    );
    if (!when.isAfter(tz.TZDateTime.now(tz.local))) return;
    await notifications.zonedSchedule(
      id: id,
      title: daysBefore == 0
          ? 'Vence hoje: $title'
          : 'Vencimento em $daysBefore dia(s): $title',
      body: 'Valor previsto: R\$ ${amount.toStringAsFixed(2)}',
      scheduledDate: when,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'vencimentos',
          'Vencimentos',
          channelDescription: 'Lembretes de contas a pagar',
          importance: Importance.high,
          priority: Priority.high,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  static Future<void> cancel(int id) => notifications.cancel(id: id);
  static Future<String?> attach() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg', 'webp'],
    );
    final source = result.isEmpty ? null : result.single.path;
    if (source == null) return null;
    final dir = Directory(
      await native.invokeMethod<String>('attachmentDirectory') ?? '',
    );
    await dir.create(recursive: true);
    final safeName = result.single.name.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    final target = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-$safeName',
    );
    await File(source).copy(target.path);
    return target.path;
  }

  static Future<String?> takePhoto() async {
    final photo = await ImagePicker().pickImage(
      source: ImageSource.camera,
      imageQuality: 95,
    );
    if (photo == null) return null;
    final dir = Directory(
      await native.invokeMethod<String>('attachmentDirectory') ?? '',
    );
    await dir.create(recursive: true);
    final target = File(
      '${dir.path}/${DateTime.now().microsecondsSinceEpoch}-foto.jpg',
    );
    await File(photo.path).copy(target.path);
    return target.path;
  }

  static String suggestTitle(String path) {
    final file = path.split('/').last.replaceFirst(RegExp(r'^[0-9]+-'), '');
    return file
        .replaceAll(RegExp(r'[_-]+'), ' ')
        .replaceAll(
          RegExp(r'\.(pdf|png|jpe?g|webp)$', caseSensitive: false),
          '',
        )
        .trim();
  }

  static Future<void> open(String path) =>
      native.invokeMethod('open', {'path': path});

  static Future<void> deleteAttachment(String path) =>
      native.invokeMethod('delete', {'path': path});

  static Future<String> recognize(String path) async =>
      await native.invokeMethod<String>('recognize', {'path': path}) ?? '';
}
