import 'package:flutter/material.dart';

import '../../modelos.dart';
import '../../servicios/sesion.dart';
import '../../tema.dart';
import '../../widgets/comunes.dart';

const _tolerancias = [5, 10, 15, 30, 45, 60, 90, 120];

/// Gestión de cuidadores del paciente (RF07, RF08).
class PantallaCuidadores extends StatefulWidget {
  const PantallaCuidadores({super.key});

  @override
  State<PantallaCuidadores> createState() => _PantallaCuidadoresState();
}

class _PantallaCuidadoresState extends State<PantallaCuidadores> {
  List<Vinculo>? _lista;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _cargar());
  }

  Future<void> _cargar() async {
    final sesion = SesionScope.de(context);
    try {
      final l = await sesion.api.vinculos();
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

  Future<void> _invitar() async {
    final correo = TextEditingController();
    final parentesco = TextEditingController();
    var tolerancia = 30;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Invitar cuidador'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Esta persona recibirá un aviso si usted no confirma una dosis.',
                  style: TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo del cuidador'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: parentesco,
                  decoration: const InputDecoration(labelText: 'Parentesco (ej.: Hija)'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  initialValue: tolerancia,
                  decoration: const InputDecoration(labelText: 'Avisar si no confirmo en'),
                  items: [for (final t in _tolerancias) DropdownMenuItem(value: t, child: Text('$t minutos'))],
                  onChanged: (v) => setD(() => tolerancia = v ?? 30),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 48)),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Invitar'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final v = await SesionScope.de(context).api.invitarCuidador(
        correo.text.trim(),
        parentesco.text.trim().isEmpty ? null : parentesco.text.trim(),
        tolerancia,
      );
      if (mounted) mostrarMensaje(context, 'Invitación enviada. Código: ${v.codigo}');
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  Future<void> _cambiarTolerancia(Vinculo v) async {
    final nueva = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Tiempo de tolerancia'),
        children: [
          for (final t in _tolerancias)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, t),
              child: Text('$t minutos${t == v.toleranciaMin ? '  ✓' : ''}', style: const TextStyle(fontSize: 18)),
            ),
        ],
      ),
    );
    if (nueva == null || !mounted) return;
    try {
      await SesionScope.de(context).api.actualizarVinculo(v.id, tolerancia: nueva, parentesco: v.parentesco);
      _cargar();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  Future<void> _revocar(Vinculo v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Quitar cuidador'),
        content: Text(
          '${v.nombreCuidador ?? v.correoInvitado} dejará de recibir avisos y de ver su información.',
          style: const TextStyle(fontSize: 17),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: TemaMediCheck.rojo, minimumSize: const Size(110, 48)),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Quitar'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await SesionScope.de(context).api.revocarVinculo(v.id);
    _cargar();
  }

  @override
  Widget build(BuildContext context) {
    final Widget cuerpo;
    if (_error != null) {
      cuerpo = EstadoVacio(icono: Icons.error_outline, mensaje: _error!, accion: _cargar);
    } else if (_lista == null) {
      cuerpo = const Center(child: CircularProgressIndicator());
    } else if (_lista!.isEmpty) {
      cuerpo = EstadoVacio(
        icono: Icons.family_restroom,
        mensaje: 'Invite a un familiar o persona de confianza para que reciba un aviso si olvida una dosis.',
        accion: _invitar,
        textoAccion: 'Invitar cuidador',
      );
    } else {
      cuerpo = ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 96),
        children: [
          for (final v in _lista!)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: (v.activo ? TemaMediCheck.verde : TemaMediCheck.ambar).withValues(
                            alpha: 0.15,
                          ),
                          child: Icon(
                            v.activo ? Icons.verified_user : Icons.hourglass_top,
                            color: v.activo ? TemaMediCheck.verde : TemaMediCheck.ambar,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                v.nombreCuidador ?? v.correoInvitado,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                [
                                  if (v.parentesco != null) v.parentesco!,
                                  v.activo ? 'Activo' : 'Invitación pendiente',
                                ].join(' · '),
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (!v.activo && v.codigo != null)
                      Text(
                        'Código de invitación: ${v.codigo}',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: 1),
                      ),
                    Text(
                      'Recibe aviso si no confirma en ${v.toleranciaMin} minutos',
                      style: const TextStyle(fontSize: 16),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => _cambiarTolerancia(v),
                          icon: const Icon(Icons.timer),
                          label: const Text('Tolerancia'),
                        ),
                        TextButton.icon(
                          onPressed: () => _revocar(v),
                          icon: const Icon(Icons.person_remove, color: TemaMediCheck.rojo),
                          label: const Text('Quitar', style: TextStyle(color: TemaMediCheck.rojo)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      );
    }
    return Scaffold(
      body: cuerpo,
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'invitar',
        onPressed: _invitar,
        icon: const Icon(Icons.person_add),
        label: const Text('Invitar cuidador', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
