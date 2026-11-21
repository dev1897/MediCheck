import 'package:flutter/foundation.dart';

/// Configuración de la aplicación.
///
/// La URL de la API se puede cambiar al compilar:
///   flutter run --dart-define=API_URL=https://mi-servidor.com
class Config {
  static const String _apiDefinida = String.fromEnvironment('API_URL');

  /// En el emulador de Android, 10.0.2.2 apunta al computador anfitrión.
  static String get apiUrl {
    if (_apiDefinida.isNotEmpty) return _apiDefinida;
    if (kIsWeb) return 'http://localhost:3000';
    return 'http://10.0.2.2:3000';
  }

  /// Intervalo de consulta de alertas del cuidador (simulación de push).
  static const Duration intervaloAlertas = Duration(seconds: 20);

  /// Intervalo de revisión de recordatorios en pantalla y de sincronización.
  static const Duration intervaloRecordatorio = Duration(seconds: 30);

  static const Duration tiempoEsperaHttp = Duration(seconds: 12);
}
