import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:medicheck/modelos.dart';
import 'package:medicheck/servicios/api.dart';
import 'package:medicheck/servicios/cola_offline.dart';
import 'package:medicheck/utilidades/formato.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Respuesta JSON en UTF-8, igual a la que envía el servidor Express.
http.Response jsonResp(Object? datos, int estado) => http.Response.bytes(
  utf8.encode(jsonEncode(datos)),
  estado,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  setUpAll(() => initializeDateFormatting('es'));

  group('Formato', () {
    test('describe la frecuencia en lenguaje sencillo', () {
      expect(Formato.frecuencia(24), 'Una vez al día');
      expect(Formato.frecuencia(8), 'Cada 8 horas (3 veces al día)');
      expect(Formato.frecuencia(48), 'Cada 2 días');
      expect(Formato.frecuencia(6), 'Cada 6 horas');
    });

    test('formatea porcentajes', () {
      expect(Formato.porcentaje(null), '—');
      expect(Formato.porcentaje(100), '100 %');
      expect(Formato.porcentaje(87.5), '87.5 %');
    });

    test('expresa tiempos relativos', () {
      final ahora = DateTime(2026, 11, 20, 8);
      expect(Formato.relativo(ahora.add(const Duration(minutes: 25)), ahora), 'en 25 min');
      expect(Formato.relativo(ahora.subtract(const Duration(minutes: 90)), ahora), 'hace 1 h 30 min');
    });

    test('usa la fecha de la API en formato AAAA-MM-DD', () {
      expect(Formato.fechaApi(DateTime(2026, 3, 7)), '2026-03-07');
    });
  });

  group('Modelos', () {
    test('interpreta una dosis de la API', () {
      final d = Dosis.desdeJson({
        'id_dosis': 5,
        'fecha_hora': '2026-11-20T12:00:00.000Z',
        'estado': 'omitida',
        'confirmada_tarde': false,
        'medicamento': 'Losartán',
        'dosis': '50 mg',
      });
      expect(d.estado, EstadoDosis.omitida);
      expect(d.fechaHora.isUtc, isFalse);
      expect(d.medicamento, 'Losartán');
    });

    test('interpreta el resumen de adherencia', () {
      final a = Adherencia.desdeJson({
        'periodo_dias': 7,
        'tomadas': 9,
        'omitidas': 1,
        'evaluadas': 10,
        'porcentaje': 90,
        'por_dia': [
          {'fecha': '2026-11-19', 'tomadas': 3, 'omitidas': 0, 'porcentaje': 100},
        ],
        'historial': [],
      });
      expect(a.porcentaje, 90.0);
      expect(a.porDia.single.tomadas, 3);
    });
  });

  group('Cliente API', () {
    test('envía el token y convierte los errores de la API', () async {
      late http.Request recibida;
      final api = ApiCliente(
        baseUrl: 'http://api',
        cliente: MockClient((req) async {
          recibida = req;
          return jsonResp({
            'error': 'Datos inválidos.',
            'detalles': ['falta medicamento'],
          }, 400);
        }),
      )..token = 'abc';
      await expectLater(
        api.crearTratamiento({}),
        throwsA(
          isA<ApiError>().having((e) => e.estado, 'estado', 400).having((e) => e.detalles, 'detalles', hasLength(1)),
        ),
      );
      expect(recibida.headers['Authorization'], 'Bearer abc');
    });

    test('reporta sin conexión cuando falla la red', () async {
      final api = ApiCliente(baseUrl: 'http://api', cliente: MockClient((_) => throw Exception('red caída')));
      await expectLater(api.dosisDelDia(), throwsA(isA<ApiError>().having((e) => e.sinConexion, 'sinConexion', true)));
    });
  });

  group('Cola de confirmaciones sin conexión (RF12)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('guarda confirmaciones y las conserva si no hay red', () async {
      final cola = ColaConfirmaciones(ApiCliente(baseUrl: 'http://api', cliente: MockClient((_) => throw Exception())));
      await cola.agregar(10, DateTime(2026, 11, 20, 8, 5));
      await cola.agregar(10, DateTime(2026, 11, 20, 8, 6)); // duplicada: se ignora
      expect(cola.pendientes, hasLength(1));
      expect(await cola.sincronizar(), 0);
      expect(cola.pendientes, hasLength(1));

      // Persistencia: una nueva instancia recupera la cola
      final otra = ColaConfirmaciones(ApiCliente(baseUrl: 'http://api'));
      await otra.cargar();
      expect(otra.contiene(10), isTrue);
    });

    test('sincroniza y vacía la cola cuando vuelve la conexión', () async {
      Map<String, dynamic>? cuerpo;
      final api = ApiCliente(
        baseUrl: 'http://api',
        cliente: MockClient((req) async {
          cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
          return jsonResp({
            'procesadas': 2,
            'resultados': [
              {'id_dosis': 1, 'ok': true},
              {'id_dosis': 2, 'ok': true},
            ],
          }, 200);
        }),
      );
      final cola = ColaConfirmaciones(api);
      await cola.agregar(1, DateTime.utc(2026, 11, 20, 13, 0));
      await cola.agregar(2, DateTime.utc(2026, 11, 20, 21, 0));
      expect(await cola.sincronizar(), 2);
      expect(cola.pendientes, isEmpty);
      expect((cuerpo!['confirmaciones'] as List).first['fecha_confirmacion'], '2026-11-20T13:00:00.000Z');
    });
  });
}
