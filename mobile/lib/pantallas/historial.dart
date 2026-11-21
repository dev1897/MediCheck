import 'package:flutter/material.dart';

import '../modelos.dart';
import '../servicios/sesion.dart';
import '../widgets/comunes.dart';

/// Historial y porcentaje de adherencia (RF10). Lo usan el paciente y el cuidador.
class PantallaHistorial extends StatefulWidget {
  const PantallaHistorial({super.key, this.idPaciente, this.incrustada = false});

  /// Nulo para el paciente autenticado; id del paciente cuando consulta un cuidador.
  final int? idPaciente;

  /// Verdadero cuando se muestra dentro de otra pantalla con scroll propio.
  final bool incrustada;

  @override
  State<PantallaHistorial> createState() => _PantallaHistorialState();
}

class _PantallaHistorialState extends State<PantallaHistorial> {
  int _dias = 7;
  Adherencia? _datos;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final sesion = SesionScope.de(context);
    try {
      final a = await sesion.api.adherencia(idPaciente: widget.idPaciente, dias: _dias);
      if (mounted) {
        setState(() {
          _datos = a;
          _error = null;
        });
      }
    } catch (e) {
      await sesion.manejarError(e);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return EstadoVacio(icono: Icons.error_outline, mensaje: _error!, accion: _cargar);
    if (_datos == null) {
      return const Center(
        child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()),
      );
    }
    final d = _datos!;
    final hijos = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 7, label: Text('7 días')),
            ButtonSegment(value: 30, label: Text('30 días')),
          ],
          selected: {_dias},
          onSelectionChanged: (s) {
            setState(() => _dias = s.first);
            _cargar();
          },
        ),
      ),
      TarjetaIndicador(adherencia: d),
      if (d.porDia.isNotEmpty)
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 12),
                  child: Text('Adherencia diaria (%)', style: Theme.of(context).textTheme.titleMedium),
                ),
                GraficoAdherencia(dias: d.porDia),
              ],
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
        child: Text('Detalle de dosis', style: Theme.of(context).textTheme.titleMedium),
      ),
      if (d.historial.isEmpty)
        const Padding(
          padding: EdgeInsets.all(20),
          child: Text('Sin registros en este periodo.', style: TextStyle(fontSize: 17)),
        ),
      Card(
        child: Column(
          children: [for (final dosis in d.historial.take(60)) FilaDosis(dosis: dosis, mostrarFecha: true)],
        ),
      ),
      const SizedBox(height: 24),
    ];
    if (widget.incrustada) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos);
    return RefreshIndicator(
      onRefresh: _cargar,
      child: ListView(children: hijos),
    );
  }
}
