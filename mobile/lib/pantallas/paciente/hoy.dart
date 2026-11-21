import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../modelos.dart';
import '../../servicios/api.dart';
import '../../servicios/recordatorios.dart';
import '../../servicios/sesion.dart';
import '../../tema.dart';
import '../../utilidades/formato.dart';
import '../../widgets/comunes.dart';

/// Pantalla "Hoy" del paciente: dosis del día y confirmación con un toque (RF05, RF06, RF12).
class PantallaHoy extends StatefulWidget {
  const PantallaHoy({super.key});

  @override
  State<PantallaHoy> createState() => PantallaHoyState();
}

class PantallaHoyState extends State<PantallaHoy> {
  List<Dosis> _dosis = [];
  bool _cargando = true;
  String? _error;
  bool _sinConexion = false;
  Timer? _temporizador;
  final Set<int> _avisadas = {};
  late Sesion _sesion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sesion = SesionScope.de(context);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Recordatorios.instancia.alConfirmarDesdeNotificacion = (id) => _confirmar(id, origen: 'notificacion');
      cargar();
    });
    _temporizador = Timer.periodic(Config.intervaloRecordatorio, (_) => _tic());
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  Future<void> cargar() async {
    try {
      await _sesion.cola.sincronizar();
      final dosis = await _sesion.api.dosisDelDia(fecha: Formato.fechaApi(DateTime.now()));
      for (final d in dosis) {
        if (_sesion.cola.contiene(d.id)) {
          d
            ..estado = EstadoDosis.tomada
            ..pendienteSincronizar = true;
        }
      }
      // Reprograma los recordatorios locales con las próximas dosis (RF05)
      unawaited(_sesion.api.proximasDosis().then(Recordatorios.instancia.programar).catchError((_) => 0));
      if (!mounted) return;
      setState(() {
        _dosis = dosis;
        _cargando = false;
        _error = null;
        _sinConexion = false;
      });
    } on ApiError catch (e) {
      await _sesion.manejarError(e);
      if (!mounted) return;
      setState(() {
        _cargando = false;
        _sinConexion = e.sinConexion;
        if (_dosis.isEmpty) _error = e.mensaje;
      });
    }
  }

  /// Cada 30 segundos: sincroniza la cola, actualiza tiempos y muestra el recordatorio en pantalla.
  Future<void> _tic() async {
    if (!mounted) return;
    if (_sesion.cola.pendientes.isNotEmpty) {
      final n = await _sesion.cola.sincronizar();
      if (n > 0) {
        if (mounted) mostrarMensaje(context, '$n confirmación(es) sincronizada(s) con el servidor.');
        await cargar();
        return;
      }
    }
    final ahora = DateTime.now();
    final debida = _dosis.where(
      (d) =>
          d.estado == EstadoDosis.pendiente &&
          !_avisadas.contains(d.id) &&
          !d.fechaHora.isAfter(ahora) &&
          ahora.difference(d.fechaHora).inMinutes < 60,
    );
    if (debida.isNotEmpty && !Recordatorios.instancia.soportado) {
      final d = debida.first;
      _avisadas.add(d.id);
      _mostrarRecordatorio(d);
    }
    if (mounted) setState(() {});
  }

  void _mostrarRecordatorio(Dosis d) => showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.alarm, size: 48, color: TemaMediCheck.azul),
      title: const Text('Hora de su medicamento'),
      content: Text(
        '${d.medicamento}\n${d.cantidad}',
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Más tarde')),
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size(180, 56), backgroundColor: TemaMediCheck.verde),
          onPressed: () {
            Navigator.pop(ctx);
            _confirmar(d.id, origen: 'notificacion');
          },
          icon: const Icon(Icons.check),
          label: const Text('Ya la tomé'),
        ),
      ],
    ),
  );

  Future<void> _confirmar(int idDosis, {String origen = 'app'}) async {
    final i = _dosis.indexWhere((d) => d.id == idDosis);
    try {
      final r = await _sesion.api.confirmarDosis(idDosis, origen: origen);
      if (i >= 0) {
        setState(() {
          _dosis[i]
            ..estado = EstadoDosis.tomada
            ..confirmadaTarde = r.confirmadaTarde
            ..fechaConfirmacion = r.fechaConfirmacion;
        });
      }
      if (mounted) mostrarMensaje(context, '¡Muy bien! Dosis registrada.');
    } on ApiError catch (e) {
      if (e.sinConexion) {
        // Sin internet: se guarda en el dispositivo con la hora real de la toma (RF12)
        await _sesion.cola.agregar(idDosis, DateTime.now());
        if (i >= 0) {
          setState(
            () => _dosis[i]
              ..estado = EstadoDosis.tomada
              ..pendienteSincronizar = true,
          );
        }
        if (mounted) mostrarMensaje(context, 'Sin conexión: la toma quedó guardada y se enviará al reconectar.');
      } else {
        await _sesion.manejarError(e);
        if (mounted) mostrarMensaje(context, e.mensaje, error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return EstadoVacio(icono: Icons.wifi_off, mensaje: _error!, accion: cargar);
    }
    final ahora = DateTime.now();
    final pendientes = _dosis.where((d) => d.estado == EstadoDosis.pendiente).toList();
    final siguiente = pendientes.isEmpty ? null : pendientes.first;
    final tomadas = _dosis.where((d) => d.estado == EstadoDosis.tomada).length;

    return RefreshIndicator(
      onRefresh: cargar,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_sinConexion || _sesion.cola.pendientes.isNotEmpty)
            MaterialBanner(
              backgroundColor: Colors.amber.shade100,
              leading: const Icon(Icons.cloud_off, color: TemaMediCheck.ambar),
              content: Text(
                _sesion.cola.pendientes.isEmpty
                    ? 'Sin conexión. Sus recordatorios siguen funcionando.'
                    : 'Sin conexión: ${_sesion.cola.pendientes.length} toma(s) por sincronizar.',
                style: const TextStyle(fontSize: 16),
              ),
              actions: [TextButton(onPressed: cargar, child: const Text('Reintentar'))],
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 4),
            child: Text(
              'Hola, ${_sesion.usuario!.nombre.split(' ').first}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              '${Formato.fechaLarga(ahora)} · $tomadas de ${_dosis.length} dosis tomadas',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(height: 8),
          if (_dosis.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 40),
              child: EstadoVacio(
                icono: Icons.event_available,
                mensaje: 'No tiene dosis programadas para hoy.\nAgregue sus medicamentos en la pestaña "Medicinas".',
              ),
            ),
          for (final d in _dosis)
            _TarjetaDosis(dosis: d, esSiguiente: d == siguiente, ahora: ahora, onConfirmar: () => _confirmar(d.id)),
        ],
      ),
    );
  }
}

class _TarjetaDosis extends StatelessWidget {
  const _TarjetaDosis({required this.dosis, required this.esSiguiente, required this.ahora, required this.onConfirmar});

  final Dosis dosis;
  final bool esSiguiente;
  final DateTime ahora;
  final VoidCallback onConfirmar;

  @override
  Widget build(BuildContext context) {
    final puedeConfirmar = dosis.estado != EstadoDosis.tomada && dosis.fechaHora.difference(ahora).inMinutes <= 120;
    final destacada = esSiguiente || dosis.estado == EstadoDosis.omitida;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: destacada
            ? BorderSide(color: dosis.estado == EstadoDosis.omitida ? TemaMediCheck.rojo : TemaMediCheck.azul, width: 2)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrap evita desbordes en pantallas angostas o con letra ampliada (accesibilidad)
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  Formato.hora(dosis.fechaHora),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xFF102A43)),
                ),
                if (dosis.estado == EstadoDosis.pendiente)
                  Text(
                    Formato.relativo(dosis.fechaHora, ahora),
                    style: const TextStyle(fontSize: 16, color: Colors.black54),
                  ),
                EtiquetaEstado(dosis: dosis),
              ],
            ),
            const SizedBox(height: 8),
            Text(dosis.medicamento, style: Theme.of(context).textTheme.titleLarge),
            Text(dosis.cantidad, style: const TextStyle(fontSize: 18)),
            if (dosis.indicaciones != null && dosis.indicaciones!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(dosis.indicaciones!, style: const TextStyle(fontSize: 16, color: Colors.black54)),
              ),
            if (puedeConfirmar) ...[
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: dosis.estado == EstadoDosis.omitida ? TemaMediCheck.ambar : TemaMediCheck.verde,
                  minimumSize: const Size.fromHeight(60),
                ),
                onPressed: onConfirmar,
                icon: const Icon(Icons.check_circle_outline, size: 28),
                label: Text(dosis.estado == EstadoDosis.omitida ? 'La tomé tarde' : 'Ya la tomé'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
