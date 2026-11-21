import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../modelos.dart';

/// Error devuelto por la API o por problemas de red.
class ApiError implements Exception {
  final int? estado;
  final String mensaje;
  final List<String> detalles;

  ApiError(this.mensaje, {this.estado, this.detalles = const []});

  /// Verdadero cuando no hubo respuesta del servidor (sin conexión).
  bool get sinConexion => estado == null;

  @override
  String toString() => detalles.isEmpty ? mensaje : '$mensaje\n${detalles.join('\n')}';
}

/// Cliente HTTP de la API REST de MediCheck.
class ApiCliente {
  ApiCliente({http.Client? cliente, String? baseUrl})
    : _http = cliente ?? http.Client(),
      _base = baseUrl ?? Config.apiUrl;

  final http.Client _http;
  final String _base;
  String? token;

  Map<String, String> get _encabezados => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<dynamic> _enviar(String metodo, String ruta, [Object? cuerpo]) async {
    final uri = Uri.parse('$_base$ruta');
    http.Response r;
    try {
      final req = http.Request(metodo, uri)..headers.addAll(_encabezados);
      if (cuerpo != null) req.body = jsonEncode(cuerpo);
      r = await http.Response.fromStream(await _http.send(req).timeout(Config.tiempoEsperaHttp));
    } on TimeoutException {
      throw ApiError('El servidor no respondió a tiempo. Revise su conexión.');
    } catch (_) {
      throw ApiError('Sin conexión con el servidor.');
    }
    final datos = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
      throw ApiError(
        mapa['error'] as String? ?? 'Error ${r.statusCode}',
        estado: r.statusCode,
        detalles: (mapa['detalles'] as List?)?.cast<String>() ?? const [],
      );
    }
    return datos;
  }

  // ---------------- Autenticación (RF01, RF02, RF13) ----------------
  Future<(String, Usuario)> registrar({
    required String nombre,
    required String correo,
    String? telefono,
    required String contrasena,
    required String rol,
    required bool aceptaPolitica,
  }) async {
    final r = await _enviar('POST', '/api/auth/registro', {
      'nombre': nombre,
      'correo': correo,
      'telefono': telefono,
      'contrasena': contrasena,
      'rol': rol,
      'acepta_politica': aceptaPolitica,
    });
    return (r['token'] as String, Usuario.desdeJson(r['usuario']));
  }

  Future<(String, Usuario)> iniciarSesion(String correo, String contrasena) async {
    final r = await _enviar('POST', '/api/auth/login', {'correo': correo, 'contrasena': contrasena});
    return (r['token'] as String, Usuario.desdeJson(r['usuario']));
  }

  Future<String> recuperar(String correo) async =>
      (await _enviar('POST', '/api/auth/recuperar', {'correo': correo}))['mensaje'] as String;

  Future<String> restablecer(String correo, String codigo, String nueva) async =>
      (await _enviar('POST', '/api/auth/restablecer', {
            'correo': correo,
            'codigo': codigo,
            'nueva_contrasena': nueva,
          }))['mensaje']
          as String;

  // ---------------- Tratamientos (RF03, RF04) ----------------
  Future<List<Tratamiento>> tratamientos({int? idPaciente}) async {
    final q = idPaciente == null ? '' : '?id_paciente=$idPaciente';
    final r = await _enviar('GET', '/api/tratamientos$q') as List;
    return r.map((e) => Tratamiento.desdeJson(e)).toList();
  }

  Future<int> crearTratamiento(Map<String, dynamic> datos) async =>
      (await _enviar('POST', '/api/tratamientos', datos))['dosis_generadas'] as int;

  Future<void> actualizarTratamiento(int id, Map<String, dynamic> datos) =>
      _enviar('PUT', '/api/tratamientos/$id', datos);

  Future<void> eliminarTratamiento(int id) => _enviar('DELETE', '/api/tratamientos/$id');

  // ---------------- Dosis (RF05, RF06, RF12) ----------------
  Future<List<Dosis>> dosisDelDia({String? fecha}) async {
    final r = await _enviar('GET', '/api/dosis${fecha == null ? '' : '?fecha=$fecha'}') as List;
    return r.map((e) => Dosis.desdeJson(e)).toList();
  }

  Future<List<Dosis>> proximasDosis() async {
    final r = await _enviar('GET', '/api/dosis/proximas') as List;
    return r.map((e) => Dosis.desdeJson({...e as Map<String, dynamic>, 'estado': 'pendiente'})).toList();
  }

  Future<Dosis> confirmarDosis(int id, {String origen = 'app'}) async => Dosis.desdeJson(
    await _enviar('PATCH', '/api/dosis/$id/confirmar', {'origen': origen})
      ..putIfAbsent('medicamento', () => '')
      ..putIfAbsent('dosis', () => ''),
  );

  Future<List<Map<String, dynamic>>> sincronizar(List<Map<String, dynamic>> confirmaciones) async {
    final r = await _enviar('POST', '/api/dosis/sincronizar', {'confirmaciones': confirmaciones});
    return (r['resultados'] as List).cast<Map<String, dynamic>>();
  }

  // ---------------- Cuidadores (RF07, RF08) ----------------
  Future<List<Vinculo>> vinculos() async {
    final r = await _enviar('GET', '/api/cuidadores') as List;
    return r.map((e) => Vinculo.desdeJson(e)).toList();
  }

  Future<Vinculo> invitarCuidador(String correo, String? parentesco, int tolerancia) async => Vinculo.desdeJson(
    await _enviar('POST', '/api/cuidadores/invitar', {
        'correo': correo,
        'parentesco': parentesco,
        'tolerancia_min': tolerancia,
      })
      ..putIfAbsent('nombre_paciente', () => ''),
  );

  Future<void> aceptarInvitacion(int id) => _enviar('PATCH', '/api/cuidadores/$id/aceptar');

  Future<void> unirseConCodigo(String codigo) => _enviar('POST', '/api/cuidadores/unirse', {'codigo': codigo});

  Future<void> actualizarVinculo(int id, {int? tolerancia, String? parentesco}) =>
      _enviar('PATCH', '/api/cuidadores/$id', {'tolerancia_min': ?tolerancia, 'parentesco': parentesco});

  Future<void> revocarVinculo(int id) => _enviar('DELETE', '/api/cuidadores/$id');

  // ---------------- Panel del cuidador y adherencia (RF10, RF11) ----------------
  Future<List<PacienteVinculado>> pacientes() async {
    final r = await _enviar('GET', '/api/pacientes') as List;
    return r.map((e) => PacienteVinculado.desdeJson(e)).toList();
  }

  Future<List<Dosis>> dosisDePaciente(int idPaciente) async {
    final r = await _enviar('GET', '/api/pacientes/$idPaciente/dosis') as List;
    return r.map((e) => Dosis.desdeJson(e)).toList();
  }

  Future<Adherencia> adherencia({int? idPaciente, int dias = 7}) async {
    final ruta = idPaciente == null ? '/api/adherencia?dias=$dias' : '/api/pacientes/$idPaciente/adherencia?dias=$dias';
    return Adherencia.desdeJson(await _enviar('GET', ruta));
  }

  Future<List<Alerta>> alertas() async {
    final r = await _enviar('GET', '/api/alertas') as List;
    return r.map((e) => Alerta.desdeJson(e)).toList();
  }

  Future<void> marcarAlertaLeida(int id) => _enviar('PATCH', '/api/alertas/$id/leida');

  // ---------------- Simulación (solo en entorno de demostración) ----------------
  Future<bool> simulacionDisponible() async {
    try {
      final r = await _enviar('GET', '/api/salud');
      return r['simulacion'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> avanzarReloj(int minutos) async =>
      (await _enviar('POST', '/api/simulacion/avanzar', {'minutos': minutos})) as Map<String, dynamic>;
}
