import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:medicheck/main.dart';
import 'package:medicheck/servicios/api.dart';
import 'package:medicheck/servicios/sesion.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Respuesta JSON en UTF-8, igual a la que envía el servidor Express.
http.Response jsonResp(Object? datos, int estado) => http.Response.bytes(
  utf8.encode(jsonEncode(datos)),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// API simulada para las pruebas de interfaz.
http.Client apiSimulada({void Function(http.Request)? alRecibir}) => MockClient((req) async {
  alRecibir?.call(req);
  return responder(req);
});

Future<http.Response> responder(http.Request req) async {
  final ruta = req.url.path;
  final ahora = DateTime.now().toUtc();
  if (ruta == '/api/auth/login') {
    final datos = jsonDecode(req.body) as Map<String, dynamic>;
    if (datos['contrasena'] != 'Demo1234') {
      return jsonResp({'error': 'Correo o contraseña incorrectos.'}, 401);
    }
    return jsonResp({
      'token': 't1',
      'usuario': {'id_usuario': 1, 'nombre': 'Rosa Elena Díaz', 'correo': 'paciente@medicheck.demo', 'rol': 'paciente'},
    }, 200);
  }
  if (ruta == '/api/dosis') {
    return jsonResp([
      {
        'id_dosis': 7,
        'fecha_hora': ahora.subtract(const Duration(minutes: 5)).toIso8601String(),
        'estado': 'pendiente',
        'medicamento': 'Losartán',
        'dosis': '50 mg - 1 tableta',
        'indicaciones': 'Con agua',
      },
    ], 200);
  }
  if (ruta == '/api/dosis/7/confirmar') {
    return jsonResp({
      'id_dosis': 7,
      'fecha_hora': ahora.toIso8601String(),
      'estado': 'tomada',
      'fecha_confirmacion': ahora.toIso8601String(),
      'confirmada_tarde': false,
    }, 200);
  }
  if (ruta == '/api/dosis/proximas') return jsonResp([], 200);
  if (ruta == '/api/salud') return jsonResp({'simulacion': false}, 200);
  return jsonResp([], 200);
}

Future<void> montar(WidgetTester tester, Sesion sesion) async {
  tester.view.physicalSize = const Size(1080, 2340);
  tester.view.devicePixelRatio = 2.6;
  addTearDown(tester.view.reset);
  await sesion.cargar();
  await tester.pumpWidget(MediCheckApp(sesion: sesion));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => initializeDateFormatting('es'));
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('muestra el inicio de sesión y valida los campos', (tester) async {
    await montar(
      tester,
      Sesion(
        api: ApiCliente(baseUrl: 'http://api', cliente: apiSimulada()),
      ),
    );
    expect(find.text('MediCheck'), findsOneWidget);
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.text('Ingrese un correo válido'), findsOneWidget);
    expect(find.text('Ingrese su contraseña'), findsOneWidget);
  });

  testWidgets('informa credenciales incorrectas', (tester) async {
    await montar(
      tester,
      Sesion(
        api: ApiCliente(baseUrl: 'http://api', cliente: apiSimulada()),
      ),
    );
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente@medicheck.demo');
    await tester.enterText(find.byType(TextFormField).at(1), 'mala');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();
    expect(find.textContaining('incorrectos'), findsOneWidget);
  });

  testWidgets('el paciente inicia sesión y confirma una dosis con un toque (RF06)', (tester) async {
    final rutas = <String>[];
    final sesion = Sesion(
      api: ApiCliente(
        baseUrl: 'http://api',
        cliente: apiSimulada(alRecibir: (r) => rutas.add('${r.method} ${r.url.path}')),
      ),
    );
    await montar(tester, sesion);
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente@medicheck.demo');
    await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    expect(find.text('Hola, Rosa'), findsOneWidget);
    expect(find.text('Losartán'), findsOneWidget);
    expect(find.text('Ya la tomé'), findsOneWidget);

    await tester.tap(find.text('Ya la tomé'));
    await tester.pumpAndSettle();
    expect(rutas, contains('PATCH /api/dosis/7/confirmar'));
    expect(find.text('Tomada'), findsOneWidget);
    expect(find.text('Ya la tomé'), findsNothing);
  });

  testWidgets('sin conexión la confirmación se guarda en el dispositivo (RF12)', (tester) async {
    var conectado = true;
    final sesion = Sesion(
      api: ApiCliente(
        baseUrl: 'http://api',
        cliente: MockClient((req) async {
          if (!conectado) throw Exception('sin red');
          return responder(req);
        }),
      ),
    );
    await montar(tester, sesion);
    await tester.enterText(find.byType(TextFormField).at(0), 'paciente@medicheck.demo');
    await tester.enterText(find.byType(TextFormField).at(1), 'Demo1234');
    await tester.tap(find.text('Ingresar'));
    await tester.pumpAndSettle();

    conectado = false;
    await tester.tap(find.text('Ya la tomé'));
    await tester.pumpAndSettle();
    expect(sesion.cola.contiene(7), isTrue);
    expect(find.text('Tomada · sin enviar'), findsOneWidget);
  });
}
