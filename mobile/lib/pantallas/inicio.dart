import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../modelos.dart';
import '../servicios/recordatorios.dart';
import '../servicios/sesion.dart';
import '../tema.dart';
import '../widgets/comunes.dart';
import 'cuidador/cuidador.dart';
import 'historial.dart';
import 'paciente/cuidadores.dart';
import 'paciente/hoy.dart';
import 'paciente/tratamientos.dart';

/// Pestaña inicial opcional (?tab=N en la versión web), útil para demostraciones.
int _pestanaInicial(int maximo) {
  if (!kIsWeb) return 0;
  final n = int.tryParse(Uri.base.queryParameters['tab'] ?? '') ?? 0;
  return n.clamp(0, maximo - 1);
}

/// Menú común de la barra superior: modo demostración y cierre de sesión.
class _MenuCuenta extends StatefulWidget {
  const _MenuCuenta({this.alAvanzarReloj});
  final VoidCallback? alAvanzarReloj;

  @override
  State<_MenuCuenta> createState() => _MenuCuentaState();
}

class _MenuCuentaState extends State<_MenuCuenta> {
  bool _simulacion = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final s = await SesionScope.de(context).api.simulacionDisponible();
      if (mounted) setState(() => _simulacion = s);
    });
  }

  Future<void> _avanzar(int minutos) async {
    final sesion = SesionScope.de(context);
    try {
      final r = await sesion.api.avanzarReloj(minutos);
      final ciclo = r['ciclo'] as Map<String, dynamic>;
      if (mounted) {
        mostrarMensaje(
          context,
          'Simulación: reloj +$minutos min. Dosis omitidas: ${ciclo['omitidas']}, alertas enviadas: ${ciclo['alertas']}.',
        );
      }
      widget.alAvanzarReloj?.call();
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sesion = SesionScope.de(context);
    return PopupMenuButton<String>(
      icon: const Icon(Icons.account_circle, size: 32),
      tooltip: 'Cuenta',
      onSelected: (v) {
        if (v == 'salir') sesion.cerrarSesion();
        if (v == 'sim15') _avanzar(15);
        if (v == 'sim60') _avanzar(60);
      },
      itemBuilder: (_) => [
        PopupMenuItem(
          enabled: false,
          child: Text(
            '${sesion.usuario!.nombre}\n${sesion.usuario!.correo}',
            style: const TextStyle(fontSize: 15, color: Colors.black87),
          ),
        ),
        if (_simulacion) ...[
          const PopupMenuDivider(),
          const PopupMenuItem(value: 'sim15', child: Text('Simulación: adelantar 15 min')),
          const PopupMenuItem(value: 'sim60', child: Text('Simulación: adelantar 1 hora')),
        ],
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'salir',
          child: Text('Cerrar sesión', style: TextStyle(fontSize: 17)),
        ),
      ],
    );
  }
}

/// Estructura principal del paciente.
class InicioPaciente extends StatefulWidget {
  const InicioPaciente({super.key});

  @override
  State<InicioPaciente> createState() => _InicioPacienteState();
}

class _InicioPacienteState extends State<InicioPaciente> {
  late int _indice = _pestanaInicial(4);
  final _claveHoy = GlobalKey<PantallaHoyState>();
  int _version = 0;

  static const _titulos = ['Hoy', 'Mis medicamentos', 'Mis cuidadores', 'Mi historial'];

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_titulos[_indice]),
      actions: [
        _MenuCuenta(
          alAvanzarReloj: () {
            _claveHoy.currentState?.cargar();
            setState(() => _version++);
          },
        ),
        const SizedBox(width: 8),
      ],
    ),
    body: IndexedStack(
      index: _indice,
      children: [
        PantallaHoy(key: _claveHoy),
        PantallaTratamientos(key: ValueKey('t$_version')),
        PantallaCuidadores(key: ValueKey('c$_version')),
        PantallaHistorial(key: ValueKey('h$_version-$_indice')),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _indice,
      onDestinationSelected: (i) {
        if (i == 0) _claveHoy.currentState?.cargar();
        setState(() => _indice = i);
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.today, size: 30), label: 'Hoy'),
        NavigationDestination(icon: Icon(Icons.medication, size: 30), label: 'Medicinas'),
        NavigationDestination(icon: Icon(Icons.family_restroom, size: 30), label: 'Cuidadores'),
        NavigationDestination(icon: Icon(Icons.insights, size: 30), label: 'Historial'),
      ],
    ),
  );
}

/// Estructura principal del cuidador, con consulta periódica de alertas.
class InicioCuidador extends StatefulWidget {
  const InicioCuidador({super.key});

  @override
  State<InicioCuidador> createState() => _InicioCuidadorState();
}

class _InicioCuidadorState extends State<InicioCuidador> {
  late int _indice = _pestanaInicial(2);
  List<Alerta>? _alertas;
  final Set<int> _conocidas = {};
  Timer? _temporizador;
  int _version = 0;
  bool _primeraCarga = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _consultarAlertas());
    _temporizador = Timer.periodic(Config.intervaloAlertas, (_) => _consultarAlertas());
  }

  @override
  void dispose() {
    _temporizador?.cancel();
    super.dispose();
  }

  /// Simulación de notificación push: consulta la bandeja y avisa de las alertas nuevas.
  Future<void> _consultarAlertas() async {
    final sesion = SesionScope.de(context);
    try {
      final lista = await sesion.api.alertas();
      final nuevas = lista.where((a) => !a.leida && !_conocidas.contains(a.id)).toList();
      _conocidas.addAll(lista.map((a) => a.id));
      if (!mounted) return;
      setState(() => _alertas = lista);
      if (!_primeraCarga && nuevas.isNotEmpty) {
        for (final a in nuevas) {
          await Recordatorios.instancia.mostrar(
            a.id,
            '${a.nombrePaciente} no confirmó una dosis',
            '${a.medicamento} ${a.dosis}',
          );
        }
        if (mounted) _avisoEnPantalla(nuevas.first);
        setState(() => _version++);
      }
      _primeraCarga = false;
    } catch (e) {
      await sesion.manejarError(e);
    }
  }

  void _avisoEnPantalla(Alerta a) {
    final m = ScaffoldMessenger.of(context);
    m.clearMaterialBanners();
    m.showMaterialBanner(
      MaterialBanner(
        backgroundColor: const Color(0xFFFFE4E1),
        leading: const Icon(Icons.notification_important, color: TemaMediCheck.rojo, size: 36),
        content: Text(
          'ALERTA: ${a.nombrePaciente} no confirmó ${a.medicamento} ${a.dosis}.',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () {
              m.hideCurrentMaterialBanner();
              setState(() => _indice = 1);
            },
            child: const Text('Ver'),
          ),
          TextButton(onPressed: m.hideCurrentMaterialBanner, child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Future<void> _marcarLeida(Alerta a) async {
    try {
      await SesionScope.de(context).api.marcarAlertaLeida(a.id);
      setState(() => a.leida = true);
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sinLeer = _alertas?.where((a) => !a.leida).length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: Text(_indice == 0 ? 'Mis pacientes' : 'Alertas'),
        actions: [
          _MenuCuenta(
            alAvanzarReloj: () {
              _consultarAlertas();
              setState(() => _version++);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: IndexedStack(
        index: _indice,
        children: [
          PantallaPacientes(key: ValueKey('p$_version')),
          PantallaAlertas(alertas: _alertas, onRefrescar: _consultarAlertas, onLeida: _marcarLeida),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _indice,
        onDestinationSelected: (i) => setState(() => _indice = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.people, size: 30), label: 'Pacientes'),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: sinLeer > 0,
              label: Text('$sinLeer'),
              child: const Icon(Icons.notifications, size: 30),
            ),
            label: 'Alertas',
          ),
        ],
      ),
    );
  }
}
