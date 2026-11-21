import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/sesion.dart';
import '../../tema.dart';
import '../../utilidades/formato.dart';
import '../../widgets/comunes.dart';

/// Lista de tratamientos (RF03). Si [idPaciente] no es nulo, la usa un cuidador.
class PantallaTratamientos extends StatefulWidget {
  const PantallaTratamientos({super.key, this.idPaciente});
  final int? idPaciente;

  @override
  State<PantallaTratamientos> createState() => _PantallaTratamientosState();
}

class _PantallaTratamientosState extends State<PantallaTratamientos> {
  List<Tratamiento>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final sesion = SesionScope.de(context);
    try {
      final l = await sesion.api.tratamientos(idPaciente: widget.idPaciente);
      if (mounted) {
        setState(() {
          _lista = l;
          _error = null;
        });
      }
    } catch (e) {
      await sesion.manejarError(e);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _abrirFormulario([Tratamiento? t]) async {
    final guardado = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => FormularioTratamiento(tratamiento: t, idPaciente: widget.idPaciente),
      ),
    );
    if (guardado == true) _cargar();
  }

  Future<void> _cambiarActivo(Tratamiento t, bool activo) async {
    try {
      await SesionScope.de(context).api.actualizarTratamiento(t.id, {'activo': activo});
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  Future<void> _eliminar(Tratamiento t) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar medicamento'),
        content: Text('¿Desea eliminar ${t.medicamento} y su historial?', style: const TextStyle(fontSize: 18)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TemaMediCheck.rojo, minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SesionScope.de(context).api.eliminarTratamiento(t.id);
      if (mounted) mostrarMensaje(context, 'Medicamento eliminado.');
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cuerpo = _error != null
        ? EstadoVacio(icono: Icons.error_outline, mensaje: _error!, accion: _cargar)
        : _lista == null
        ? const Center(child: CircularProgressIndicator())
        : _lista!.isEmpty
        ? EstadoVacio(
            icono: Icons.medication_outlined,
            mensaje: 'Aún no hay medicamentos registrados.',
            accion: () => _abrirFormulario(),
            textoAccion: 'Agregar medicamento',
          )
        : RefreshIndicator(
            onRefresh: _cargar,
            child: ListView(
              padding: const EdgeInsets.only(top: 8, bottom: 96),
              children: [
                for (final t in _lista!)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 8, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.medication, color: t.activo ? TemaMediCheck.azul : Colors.grey, size: 30),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  t.medicamento,
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(color: t.activo ? null : Colors.grey),
                                ),
                              ),
                              Switch(value: t.activo, onChanged: (v) => _cambiarActivo(t, v)),
                            ],
                          ),
                          Text(
                            '${t.dosis} · ${Formato.frecuencia(t.frecuenciaHoras)}',
                            style: const TextStyle(fontSize: 17),
                          ),
                          Text(
                            'Desde ${Formato.fechaCorta(t.fechaInicio)}, ${Formato.hora(t.fechaInicio)}'
                            '${t.fechaFin == null ? ' · Sin fecha de fin' : ' · Hasta ${Formato.fechaCorta(t.fechaFin!)}'}',
                            style: const TextStyle(fontSize: 15, color: Colors.black54),
                          ),
                          if (!t.activo)
                            const Text(
                              'Suspendido',
                              style: TextStyle(color: TemaMediCheck.ambar, fontWeight: FontWeight.w700),
                            ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                onPressed: () => _abrirFormulario(t),
                                icon: const Icon(Icons.edit),
                                label: const Text('Editar'),
                              ),
                              TextButton.icon(
                                onPressed: () => _eliminar(t),
                                icon: const Icon(Icons.delete_outline, color: TemaMediCheck.rojo),
                                label: const Text('Eliminar', style: TextStyle(color: TemaMediCheck.rojo)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
    return Scaffold(
      body: cuerpo,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'nuevo-tratamiento-${widget.idPaciente}',
        onPressed: () => _abrirFormulario(),
        icon: const Icon(Icons.add, size: 28),
        label: const Text('Agregar medicamento', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Formulario de registro y edición de tratamiento (RF03).
class FormularioTratamiento extends StatefulWidget {
  const FormularioTratamiento({super.key, this.tratamiento, this.idPaciente});
  final Tratamiento? tratamiento;
  final int? idPaciente;

  @override
  State<FormularioTratamiento> createState() => _FormularioTratamientoState();
}

class _FormularioTratamientoState extends State<FormularioTratamiento> {
  final _form = GlobalKey<FormState>();
  late final _medicamento = TextEditingController(text: widget.tratamiento?.medicamento);
  late final _dosis = TextEditingController(text: widget.tratamiento?.dosis);
  late final _indicaciones = TextEditingController(text: widget.tratamiento?.indicaciones);
  late int _frecuencia = widget.tratamiento?.frecuenciaHoras ?? 12;
  late DateTime _inicio = widget.tratamiento?.fechaInicio ?? _proximaHoraRedonda();
  late int? _duracionDias = widget.tratamiento?.fechaFin == null
      ? null
      : widget.tratamiento!.fechaFin!.difference(widget.tratamiento!.fechaInicio).inDays;
  bool _guardando = false;

  static DateTime _proximaHoraRedonda() {
    final a = DateTime.now().add(const Duration(hours: 1));
    return DateTime(a.year, a.month, a.day, a.hour);
  }

  static const _frecuencias = [4, 6, 8, 12, 24, 48, 168];
  static const _duraciones = <int?>[null, 5, 7, 10, 14, 30, 90];

  Future<void> _elegirFecha() async {
    final f = await showDatePicker(
      context: context,
      initialDate: _inicio,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (f != null) setState(() => _inicio = DateTime(f.year, f.month, f.day, _inicio.hour, _inicio.minute));
  }

  Future<void> _elegirHora() async {
    final h = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_inicio));
    if (h != null) setState(() => _inicio = DateTime(_inicio.year, _inicio.month, _inicio.day, h.hour, h.minute));
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _guardando = true);
    final api = SesionScope.de(context).api;
    final datos = {
      if (widget.idPaciente != null) 'id_paciente': widget.idPaciente,
      'medicamento': _medicamento.text.trim(),
      'dosis': _dosis.text.trim(),
      'frecuencia_horas': _frecuencia,
      'fecha_inicio': _inicio.toUtc().toIso8601String(),
      'fecha_fin': _duracionDias == null ? null : _inicio.add(Duration(days: _duracionDias!)).toUtc().toIso8601String(),
      'indicaciones': _indicaciones.text.trim(),
    };
    try {
      if (widget.tratamiento == null) {
        final n = await api.crearTratamiento(datos);
        if (mounted) mostrarMensaje(context, 'Medicamento guardado. Se programaron $n recordatorios.');
      } else {
        await api.actualizarTratamiento(widget.tratamiento!.id, datos);
        if (mounted) mostrarMensaje(context, 'Cambios guardados.');
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.tratamiento == null ? 'Nuevo medicamento' : 'Editar medicamento')),
    body: Form(
      key: _form,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextFormField(
            controller: _medicamento,
            textCapitalization: TextCapitalization.sentences,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: 'Nombre del medicamento', hintText: 'Ej.: Losartán'),
            validator: (v) => (v == null || v.trim().length < 2) ? 'Ingrese el nombre' : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _dosis,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(labelText: 'Dosis', hintText: 'Ej.: 50 mg - 1 tableta'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Ingrese la dosis' : null,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _frecuencias.contains(_frecuencia) ? _frecuencia : null,
            decoration: const InputDecoration(labelText: '¿Cada cuánto?'),
            style: const TextStyle(fontSize: 18, color: Colors.black),
            items: [for (final f in _frecuencias) DropdownMenuItem(value: f, child: Text(Formato.frecuencia(f)))],
            onChanged: (v) => setState(() => _frecuencia = v ?? _frecuencia),
          ),
          const SizedBox(height: 20),
          Text('Primera toma', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _elegirFecha,
                  icon: const Icon(Icons.calendar_month),
                  label: Text(Formato.fechaCorta(_inicio)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _elegirHora,
                  icon: const Icon(Icons.access_time),
                  label: Text(Formato.hora(_inicio)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<int?>(
            initialValue: _duraciones.contains(_duracionDias) ? _duracionDias : null,
            decoration: const InputDecoration(labelText: 'Duración del tratamiento'),
            style: const TextStyle(fontSize: 18, color: Colors.black),
            items: [
              for (final d in _duraciones)
                DropdownMenuItem(value: d, child: Text(d == null ? 'Permanente (sin fecha de fin)' : '$d días')),
            ],
            onChanged: (v) => setState(() => _duracionDias = v),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _indicaciones,
            maxLines: 2,
            style: const TextStyle(fontSize: 18),
            decoration: const InputDecoration(
              labelText: 'Indicaciones (opcional)',
              hintText: 'Ej.: Tomar con las comidas',
            ),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _guardando ? null : _guardar,
            icon: const Icon(Icons.save),
            label: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
}
