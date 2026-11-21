import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/sesion.dart';
import '../../tema.dart';
import '../../utilidades/formato.dart';
import '../../widgets/comunes.dart';
import '../historial.dart';
import '../paciente/tratamientos.dart';

/// Lista de pacientes vinculados e invitaciones pendientes del cuidador (RF07, RF11).
class PantallaPacientes extends StatefulWidget {
  const PantallaPacientes({super.key});

  @override
  State<PantallaPacientes> createState() => _PantallaPacientesState();
}

class _PantallaPacientesState extends State<PantallaPacientes> {
  List<PacienteVinculado>? _pacientes;
  List<Vinculo> _invitaciones = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final sesion = SesionScope.de(context);
    try {
      final p = await sesion.api.pacientes();
      final v = await sesion.api.vinculos();
      if (!mounted) return;
      setState(() {
        _pacientes = p;
        _invitaciones = v.where((x) => x.estado == 'pendiente').toList();
        _error = null;
      });
    } catch (e) {
      await sesion.manejarError(e);
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _aceptar(Vinculo v) async {
    try {
      await SesionScope.de(context).api.aceptarInvitacion(v.id);
      if (mounted) mostrarMensaje(context, 'Ahora acompaña a ${v.nombrePaciente}.');
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  Future<void> _unirseConCodigo() async {
    final codigo = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ingresar código'),
        content: TextField(
          controller: codigo,
          textCapitalization: TextCapitalization.characters,
          maxLength: 6,
          style: const TextStyle(fontSize: 24, letterSpacing: 4),
          decoration: const InputDecoration(labelText: 'Código de 6 caracteres'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Vincular'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await SesionScope.de(context).api.unirseConCodigo(codigo.text.trim());
      if (mounted) mostrarMensaje(context, 'Vínculo creado correctamente.');
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget cuerpo;
    if (_error != null) {
      cuerpo = EstadoVacio(icono: Icons.error_outline, mensaje: _error!, accion: _cargar);
    } else if (_pacientes == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else {
      cuerpo = RefreshIndicator(
        onRefresh: _cargar,
        child: ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 96),
          children: [
            for (final v in _invitaciones)
              Card(
                color: Colors.amber.shade50,
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.mail, color: TemaMediCheck.ambar, size: 36),
                  title: Text(
                    '${v.nombrePaciente} lo invitó como cuidador',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  subtitle: Text('Tolerancia: ${v.toleranciaMin} minutos', style: const TextStyle(fontSize: 16)),
                  trailing: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size(100, 48)),
                    onPressed: () => _aceptar(v),
                    child: const Text('Aceptar'),
                  ),
                ),
              ),
            if (_pacientes!.isEmpty && _invitaciones.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: EstadoVacio(
                  icono: Icons.family_restroom,
                  mensaje: 'Aún no acompaña a ningún paciente.\nPídale que lo invite desde su aplicación o ingrese el código que le enviaron.',
                ),
              ),
            for (final p in _pacientes!)
              Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => PantallaPanelPaciente(paciente: p)),
                  ).then((_) => _cargar()),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 26,
                              backgroundColor: TemaMediCheck.azul,
                              child: Text(p.nombre[0], style: const TextStyle(color: Colors.white, fontSize: 22)),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(p.nombre, style: Theme.of(context).textTheme.titleLarge),
                                  Text(
                                    [
                                      if (p.parentesco != null) p.parentesco!,
                                      if (p.telefono != null) 'Tel. ${p.telefono}',
                                    ].join(' · '),
                                    style: const TextStyle(fontSize: 16),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right, size: 32),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text('Hoy', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _Chip('${p.hoy.tomadas} tomadas', TemaMediCheck.verde),
                            _Chip('${p.hoy.pendientes} pendientes', TemaMediCheck.azul),
                            _Chip('${p.hoy.omitidas} no confirmadas', TemaMediCheck.rojo),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return Scaffold(
      body: cuerpo,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'codigo',
        onPressed: _unirseConCodigo,
        icon: const Icon(Icons.qr_code_2),
        label: const Text('Tengo un código', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.texto, this.color);
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
    child: Text(
      texto,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 15),
    ),
  );
}

/// Panel de un paciente: dosis del día, adherencia e historial (RF10, RF11).
class PantallaPanelPaciente extends StatefulWidget {
  const PantallaPanelPaciente({super.key, required this.paciente});
  final PacienteVinculado paciente;

  @override
  State<PantallaPanelPaciente> createState() => _PantallaPanelPacienteState();
}

class _PantallaPanelPacienteState extends State<PantallaPanelPaciente> {
  List<Dosis>? _hoy;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    try {
      final d = await SesionScope.de(context).api.dosisDePaciente(widget.paciente.idPaciente);
      if (mounted) setState(() => _hoy = d);
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.paciente.nombre),
        bottom: const TabBar(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          labelStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          tabs: [
            Tab(text: 'Seguimiento'),
            Tab(text: 'Medicamentos'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          RefreshIndicator(
            onRefresh: _cargar,
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    'Dosis de hoy · ${Formato.fechaLarga(DateTime.now())}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Card(
                  child: _hoy == null
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : _hoy!.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Sin dosis programadas hoy.', style: TextStyle(fontSize: 17)),
                        )
                      : Column(children: [for (final d in _hoy!) FilaDosis(dosis: d)]),
                ),
                PantallaHistorial(idPaciente: widget.paciente.idPaciente, incrustada: true),
              ],
            ),
          ),
          PantallaTratamientos(idPaciente: widget.paciente.idPaciente),
        ],
      ),
    ),
  );
}

/// Bandeja de alertas del cuidador (RF09: notificación push).
class PantallaAlertas extends StatelessWidget {
  const PantallaAlertas({super.key, required this.alertas, required this.onRefrescar, required this.onLeida});

  final List<Alerta>? alertas;
  final Future<void> Function() onRefrescar;
  final void Function(Alerta) onLeida;

  @override
  Widget build(BuildContext context) {
    if (alertas == null) return const Center(child: CircularProgressIndicator());
    if (alertas!.isEmpty) {
      return const EstadoVacio(
        icono: Icons.notifications_none,
        mensaje: 'No hay alertas.\nLe avisaremos si su familiar no confirma una dosis.',
      );
    }
    return RefreshIndicator(
      onRefresh: onRefrescar,
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          for (final a in alertas!)
            Card(
              color: a.leida ? Colors.white : const Color(0xFFFFF1F0),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_rounded, color: a.leida ? Colors.grey : TemaMediCheck.rojo, size: 30),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${a.nombrePaciente} no confirmó una dosis',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${a.medicamento} · ${a.dosis}',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      'Programada: ${Formato.fechaCorta(a.fechaDosis)}, ${Formato.hora(a.fechaDosis)}',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Text('Aviso enviado: ${Formato.hora(a.fechaEnvio)}', style: const TextStyle(fontSize: 16)),
                    if (a.estadoDosis == 'tomada')
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '✓ Luego la confirmó como tomada',
                          style: TextStyle(color: TemaMediCheck.verde, fontWeight: FontWeight.w700, fontSize: 16),
                        ),
                      ),
                    if (a.telefonoPaciente != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Llamar al ${a.telefonoPaciente}',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: TemaMediCheck.azul),
                        ),
                      ),
                    if (!a.leida)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => onLeida(a),
                          icon: const Icon(Icons.done_all),
                          label: const Text('Marcar como vista'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
