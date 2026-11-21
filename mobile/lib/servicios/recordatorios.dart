import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdatos;
import 'package:timezone/timezone.dart' as tz;

import '../modelos.dart';

/// Recordatorios locales en el dispositivo (RF05).
///
/// Se programan con flutter_local_notifications, por lo que suenan aunque no
/// haya internet ni la aplicación esté abierta. La notificación incluye la
/// acción "Ya la tomé" para confirmar con un solo toque (RF06).
/// En la versión web los recordatorios se muestran dentro de la aplicación.
class Recordatorios {
  Recordatorios._();
  static final Recordatorios instancia = Recordatorios._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _listo = false;

  static const String accionConfirmar = 'confirmar';

  /// Se invoca cuando el usuario toca "Ya la tomé" en la notificación.
  void Function(int idDosis)? alConfirmarDesdeNotificacion;

  bool get soportado => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> iniciar() async {
    if (!soportado || _listo) return;
    tzdatos.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Bogota'));
    await _plugin.initialize(
      settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      onDidReceiveNotificationResponse: (respuesta) {
        final id = int.tryParse(respuesta.payload ?? '');
        if (id != null && respuesta.actionId == accionConfirmar) alConfirmarDesdeNotificacion?.call(id);
      },
    );
    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.requestNotificationsPermission();
    await android?.requestExactAlarmsPermission();
    _listo = true;
  }

  static const _detalles = NotificationDetails(
    android: AndroidNotificationDetails(
      'dosis',
      'Recordatorios de dosis',
      channelDescription: 'Avisos a la hora de tomar cada medicamento',
      importance: Importance.max,
      priority: Priority.high,
      category: AndroidNotificationCategory.alarm,
      fullScreenIntent: false,
      actions: [AndroidNotificationAction(accionConfirmar, 'Ya la tomé', showsUserInterface: true)],
    ),
  );

  /// Reprograma los recordatorios de las próximas dosis pendientes.
  Future<int> programar(List<Dosis> proximas) async {
    if (!soportado) return 0;
    await iniciar();
    await _plugin.cancelAll();
    var programadas = 0;
    final ahora = DateTime.now();
    for (final d in proximas.where((d) => d.fechaHora.isAfter(ahora)).take(40)) {
      await _plugin.zonedSchedule(
        id: d.id,
        scheduledDate: tz.TZDateTime.from(d.fechaHora, tz.local),
        notificationDetails: _detalles,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        title: 'Hora de su medicamento',
        body: '${d.medicamento} - ${d.cantidad}',
        payload: '${d.id}',
      );
      programadas++;
    }
    return programadas;
  }

  /// Notificación inmediata (usada para avisar al cuidador de una alerta nueva).
  Future<void> mostrar(int id, String titulo, String cuerpo) async {
    if (!soportado) return;
    await iniciar();
    await _plugin.show(
      id: id,
      title: titulo,
      body: cuerpo,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          'alertas',
          'Alertas de cuidador',
          importance: Importance.max,
          priority: Priority.high,
        ),
      ),
    );
  }

  Future<void> cancelarTodos() async {
    if (soportado && _listo) await _plugin.cancelAll();
  }
}
