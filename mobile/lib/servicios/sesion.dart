import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../modelos.dart';
import 'api.dart';
import 'cola_offline.dart';
import 'recordatorios.dart';

/// Estado global de la sesión: token, usuario autenticado y servicios asociados.
class Sesion extends ChangeNotifier {
  Sesion({ApiCliente? api}) : api = api ?? ApiCliente();

  final ApiCliente api;
  late final ColaConfirmaciones cola = ColaConfirmaciones(api);
  Usuario? usuario;
  bool cargando = true;

  static const _claveToken = 'token';
  static const _claveUsuario = 'usuario';

  bool get autenticado => usuario != null;

  Future<void> cargar() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_claveToken);
    final datos = prefs.getString(_claveUsuario);
    if (token != null && datos != null) {
      api.token = token;
      usuario = Usuario.desdeJson(jsonDecode(datos) as Map<String, dynamic>);
      await cola.cargar();
    }
    cargando = false;
    notifyListeners();
  }

  Future<void> _guardar(String token, Usuario u) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_claveToken, token);
    await prefs.setString(_claveUsuario, jsonEncode(u.aJson()));
    api.token = token;
    usuario = u;
    await cola.cargar();
    notifyListeners();
  }

  Future<void> iniciarSesion(String correo, String contrasena) async {
    final (token, u) = await api.iniciarSesion(correo, contrasena);
    await _guardar(token, u);
  }

  Future<void> registrar({
    required String nombre,
    required String correo,
    String? telefono,
    required String contrasena,
    required String rol,
    required bool aceptaPolitica,
  }) async {
    final (token, u) = await api.registrar(
      nombre: nombre,
      correo: correo,
      telefono: telefono,
      contrasena: contrasena,
      rol: rol,
      aceptaPolitica: aceptaPolitica,
    );
    await _guardar(token, u);
  }

  Future<void> cerrarSesion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_claveToken);
    await prefs.remove(_claveUsuario);
    await Recordatorios.instancia.cancelarTodos();
    api.token = null;
    usuario = null;
    notifyListeners();
  }

  /// Llamar cuando la API responde 401 (token vencido).
  Future<void> manejarError(Object e) async {
    if (e is ApiError && e.estado == 401) await cerrarSesion();
  }
}

/// Acceso a la sesión desde cualquier widget del árbol.
class SesionScope extends InheritedNotifier<Sesion> {
  const SesionScope({super.key, required Sesion sesion, required super.child}) : super(notifier: sesion);

  static Sesion de(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SesionScope>()!.notifier!;
}
