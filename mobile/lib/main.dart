import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'pantallas/acceso.dart';
import 'pantallas/inicio.dart';
import 'servicios/recordatorios.dart';
import 'servicios/sesion.dart';
import 'tema.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('es');
  await Recordatorios.instancia.iniciar();
  final sesion = Sesion();
  await sesion.cargar();
  runApp(MediCheckApp(sesion: sesion));
}

class MediCheckApp extends StatelessWidget {
  const MediCheckApp({super.key, required this.sesion});
  final Sesion sesion;

  @override
  Widget build(BuildContext context) => SesionScope(
    sesion: sesion,
    child: MaterialApp(
      title: 'MediCheck',
      debugShowCheckedModeBanner: false,
      theme: TemaMediCheck.claro,
      locale: const Locale('es', 'CO'),
      supportedLocales: const [Locale('es', 'CO'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Raiz(),
    ),
  );
}

/// Decide la pantalla inicial según el estado de la sesión y el rol del usuario.
class _Raiz extends StatelessWidget {
  const _Raiz();

  @override
  Widget build(BuildContext context) {
    final sesion = SesionScope.de(context);
    if (sesion.cargando) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (!sesion.autenticado) return const PantallaInicioSesion();
    return sesion.usuario!.esPaciente
        ? InicioPaciente(key: ValueKey('p${sesion.usuario!.id}'))
        : InicioCuidador(key: ValueKey('c${sesion.usuario!.id}'));
  }
}
