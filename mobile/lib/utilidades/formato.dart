import 'package:intl/intl.dart';

/// Utilidades de formato en español (Colombia).
class Formato {
  static String hora(DateTime f) => DateFormat('h:mm a', 'es').format(f);

  static String fechaCorta(DateTime f) => DateFormat("d 'de' MMM", 'es').format(f);

  static String fechaLarga(DateTime f) {
    final t = DateFormat("EEEE d 'de' MMMM", 'es').format(f);
    return t[0].toUpperCase() + t.substring(1);
  }

  static String diaSemana(DateTime f) => DateFormat('E', 'es').format(f).replaceAll('.', '');

  static String fechaApi(DateTime f) => DateFormat('yyyy-MM-dd').format(f);

  static String porcentaje(double? p) => p == null ? '—' : '${p.toStringAsFixed(p % 1 == 0 ? 0 : 1)} %';

  static String frecuencia(int horas) {
    if (horas == 24) return 'Una vez al día';
    if (horas == 12) return 'Cada 12 horas (2 veces al día)';
    if (horas == 8) return 'Cada 8 horas (3 veces al día)';
    if (horas % 24 == 0) return 'Cada ${horas ~/ 24} días';
    return 'Cada $horas horas';
  }

  /// Texto relativo para una dosis: "en 25 min", "hace 10 min".
  static String relativo(DateTime f, DateTime ahora) {
    final diff = f.difference(ahora);
    final min = diff.inMinutes.abs();
    final texto = min < 60 ? '$min min' : '${min ~/ 60} h ${min % 60} min';
    if (min == 0) return 'ahora';
    return diff.isNegative ? 'hace $texto' : 'en $texto';
  }
}
