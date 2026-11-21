import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Confirmación registrada sin conexión.
class ConfirmacionPendiente {
  final int idDosis;
  final DateTime fecha;

  const ConfirmacionPendiente(this.idDosis, this.fecha);

  Map<String, dynamic> aJson() => {'id_dosis': idDosis, 'fecha_confirmacion': fecha.toUtc().toIso8601String()};

  factory ConfirmacionPendiente.desdeJson(Map<String, dynamic> j) =>
      ConfirmacionPendiente(j['id_dosis'] as int, DateTime.parse(j['fecha_confirmacion'] as String));
}

/// Cola persistente de confirmaciones realizadas sin conexión (RF12).
///
/// Cada confirmación guarda la hora REAL de la toma, de modo que al
/// sincronizar el servidor registra el momento correcto y no el de la conexión.
class ColaConfirmaciones extends ChangeNotifier {
  ColaConfirmaciones(this._api);

  final ApiCliente _api;
  static const _clave = 'cola_confirmaciones';
  final List<ConfirmacionPendiente> _pendientes = [];
  bool _sincronizando = false;

  List<ConfirmacionPendiente> get pendientes => List.unmodifiable(_pendientes);
  bool contiene(int idDosis) => _pendientes.any((c) => c.idDosis == idDosis);

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final texto = prefs.getString(_clave);
    _pendientes
      ..clear()
      ..addAll(
        texto == null
            ? const []
            : (jsonDecode(texto) as List).map((e) => ConfirmacionPendiente.desdeJson(e as Map<String, dynamic>)),
      );
    notifyListeners();
  }

  Future<void> _persistir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clave, jsonEncode(_pendientes.map((c) => c.aJson()).toList()));
    notifyListeners();
  }

  Future<void> agregar(int idDosis, DateTime fecha) async {
    if (contiene(idDosis)) return;
    _pendientes.add(ConfirmacionPendiente(idDosis, fecha));
    await _persistir();
  }

  /// Envía las confirmaciones pendientes. Devuelve cuántas se sincronizaron.
  Future<int> sincronizar() async {
    if (_pendientes.isEmpty || _sincronizando) return 0;
    _sincronizando = true;
    try {
      final resultados = await _api.sincronizar(_pendientes.map((c) => c.aJson()).toList());
      // Se retiran las exitosas y las rechazadas de forma definitiva (p. ej. dosis eliminada)
      final procesadas = resultados.map((r) => r['id_dosis']).toSet();
      final antes = _pendientes.length;
      _pendientes.removeWhere((c) => procesadas.contains(c.idDosis));
      await _persistir();
      return antes - _pendientes.length;
    } on ApiError catch (e) {
      if (!e.sinConexion) rethrow;
      return 0;
    } finally {
      _sincronizando = false;
    }
  }
}
