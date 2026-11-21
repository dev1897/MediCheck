import 'package:flutter/material.dart';

import '../modelos.dart';
import '../tema.dart';
import '../utilidades/formato.dart';

/// Estado vacío o de error con mensaje y acción opcional.
class EstadoVacio extends StatelessWidget {
  const EstadoVacio({super.key, required this.icono, required this.mensaje, this.accion, this.textoAccion});

  final IconData icono;
  final String mensaje;
  final VoidCallback? accion;
  final String? textoAccion;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 64, color: Colors.blueGrey.shade300),
          const SizedBox(height: 16),
          Text(mensaje, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
          if (accion != null) ...[
            const SizedBox(height: 20),
            OutlinedButton(onPressed: accion, child: Text(textoAccion ?? 'Reintentar')),
          ],
        ],
      ),
    ),
  );
}

/// Etiqueta de color según el estado de la dosis.
class EtiquetaEstado extends StatelessWidget {
  const EtiquetaEstado({super.key, required this.dosis});
  final Dosis dosis;

  @override
  Widget build(BuildContext context) {
    final (texto, color, icono) = switch (dosis.estado) {
      EstadoDosis.tomada when dosis.pendienteSincronizar => (
        'Tomada · sin enviar',
        TemaMediCheck.verde,
        Icons.cloud_off,
      ),
      EstadoDosis.tomada when dosis.confirmadaTarde => ('Tomada tarde', TemaMediCheck.ambar, Icons.check_circle),
      EstadoDosis.tomada => ('Tomada', TemaMediCheck.verde, Icons.check_circle),
      EstadoDosis.omitida => ('No confirmada', TemaMediCheck.rojo, Icons.warning_rounded),
      EstadoDosis.pendiente => ('Pendiente', TemaMediCheck.azul, Icons.schedule),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 18, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              texto,
              softWrap: true,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fila de dosis para listas de historial y panel del cuidador.
class FilaDosis extends StatelessWidget {
  const FilaDosis({super.key, required this.dosis, this.mostrarFecha = false});
  final Dosis dosis;
  final bool mostrarFecha;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
    leading: CircleAvatar(
      backgroundColor: TemaMediCheck.azul.withValues(alpha: 0.1),
      child: const Icon(Icons.medication, color: TemaMediCheck.azul),
    ),
    title: Text('${dosis.medicamento} · ${dosis.cantidad}', style: Theme.of(context).textTheme.titleMedium),
    subtitle: Text(
      mostrarFecha
          ? '${Formato.fechaCorta(dosis.fechaHora)}, ${Formato.hora(dosis.fechaHora)}'
          : Formato.hora(dosis.fechaHora),
      style: const TextStyle(fontSize: 16),
    ),
    trailing: EtiquetaEstado(dosis: dosis),
  );
}

/// Gráfico de barras simple de adherencia diaria (sin dependencias externas).
class GraficoAdherencia extends StatelessWidget {
  const GraficoAdherencia({super.key, required this.dias});
  final List<DiaAdherencia> dias;

  @override
  Widget build(BuildContext context) {
    final ultimos = dias.length > 14 ? dias.sublist(dias.length - 14) : dias;
    if (ultimos.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 170,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final d in ultimos)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(d.porcentaje == null ? '' : '${d.porcentaje!.round()}', style: const TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Container(
                      height: 110 * ((d.porcentaje ?? 0) / 100) + 4,
                      decoration: BoxDecoration(
                        color: (d.porcentaje ?? 0) >= 80
                            ? TemaMediCheck.verde
                            : (d.porcentaje ?? 0) >= 50
                            ? TemaMediCheck.ambar
                            : TemaMediCheck.rojo,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(Formato.diaSemana(d.fecha), style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta de indicador grande (porcentaje de adherencia).
class TarjetaIndicador extends StatelessWidget {
  const TarjetaIndicador({super.key, required this.adherencia});
  final Adherencia adherencia;

  @override
  Widget build(BuildContext context) {
    final p = adherencia.porcentaje;
    final color = p == null
        ? Colors.blueGrey
        : p >= 80
        ? TemaMediCheck.verde
        : p >= 50
        ? TemaMediCheck.ambar
        : TemaMediCheck.rojo;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  CircularProgressIndicator(
                    value: (p ?? 0) / 100,
                    strokeWidth: 10,
                    backgroundColor: color.withValues(alpha: 0.15),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                  Center(
                    child: Text(
                      Formato.porcentaje(p),
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adherencia últimos ${adherencia.dias} días', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text('${adherencia.tomadas} dosis tomadas', style: const TextStyle(fontSize: 17)),
                  Text('${adherencia.omitidas} dosis no confirmadas', style: const TextStyle(fontSize: 17)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Muestra un mensaje breve en la parte inferior.
void mostrarMensaje(BuildContext context, String texto, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(texto), backgroundColor: error ? TemaMediCheck.rojo : null));
}
