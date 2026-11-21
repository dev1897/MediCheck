import 'package:flutter/material.dart';

import '../servicios/sesion.dart';
import '../tema.dart';
import '../widgets/comunes.dart';

/// Pantalla de inicio de sesión (RF02).
class PantallaInicioSesion extends StatefulWidget {
  const PantallaInicioSesion({super.key});

  @override
  State<PantallaInicioSesion> createState() => _PantallaInicioSesionState();
}

class _PantallaInicioSesionState extends State<PantallaInicioSesion> {
  final _form = GlobalKey<FormState>();
  final _correo = TextEditingController();
  final _clave = TextEditingController();
  bool _enviando = false;
  bool _verClave = false;

  Future<void> _entrar() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _enviando = true);
    try {
      await SesionScope.de(context).iniciarSesion(_correo.text.trim(), _clave.text);
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.medication_liquid_rounded, size: 84, color: TemaMediCheck.azul),
                  const SizedBox(height: 8),
                  Text(
                    'MediCheck',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontSize: 34, color: TemaMediCheck.azul),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Sus medicamentos a tiempo, su familia tranquila',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _correo,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    style: const TextStyle(fontSize: 18),
                    decoration: const InputDecoration(
                      labelText: 'Correo electrónico',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Ingrese un correo válido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _clave,
                    obscureText: !_verClave,
                    style: const TextStyle(fontSize: 18),
                    onFieldSubmitted: (_) => _entrar(),
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        tooltip: _verClave ? 'Ocultar' : 'Mostrar',
                        icon: Icon(_verClave ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _verClave = !_verClave),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Ingrese su contraseña' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _enviando ? null : _entrar,
                    child: _enviando
                        ? const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3))
                        : const Text('Ingresar'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaRegistro())),
                    child: const Text('Crear una cuenta'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const PantallaRecuperar())),
                    child: const Text('¿Olvidó su contraseña?', style: TextStyle(fontSize: 17)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Registro de paciente o cuidador con aceptación de la política de datos (RF01, RF13).
class PantallaRegistro extends StatefulWidget {
  const PantallaRegistro({super.key});

  @override
  State<PantallaRegistro> createState() => _PantallaRegistroState();
}

class _PantallaRegistroState extends State<PantallaRegistro> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _correo = TextEditingController();
  final _telefono = TextEditingController();
  final _clave = TextEditingController();
  String _rol = 'paciente';
  bool _acepta = false;
  bool _enviando = false;

  Future<void> _registrar() async {
    if (!_form.currentState!.validate()) return;
    if (!_acepta) {
      mostrarMensaje(context, 'Debe aceptar la política de tratamiento de datos.', error: true);
      return;
    }
    setState(() => _enviando = true);
    try {
      await SesionScope.de(context).registrar(
        nombre: _nombre.text.trim(),
        correo: _correo.text.trim(),
        telefono: _telefono.text.trim().isEmpty ? null : _telefono.text.trim(),
        contrasena: _clave.text,
        rol: _rol,
        aceptaPolitica: _acepta,
      );
      if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  void _verPolitica() => showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Política de tratamiento de datos'),
      content: const SingleChildScrollView(
        child: Text(
          'En cumplimiento de la Ley 1581 de 2012 y el Decreto 1377 de 2013, MediCheck recolecta su nombre, '
          'correo, teléfono y la información de sus tratamientos con la única finalidad de programar '
          'recordatorios, registrar la toma de medicamentos y avisar a los cuidadores que usted autorice.\n\n'
          'Los datos de salud son datos sensibles: su autorización es voluntaria. Sus datos no se venden ni se '
          'comparten con terceros. Puede consultar, actualizar o eliminar su información y revocar el acceso '
          'de un cuidador en cualquier momento desde la aplicación.\n\n'
          'MediCheck es una herramienta de apoyo y no reemplaza la consulta médica.',
          style: TextStyle(fontSize: 16),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Crear cuenta')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('¿Cómo usará MediCheck?', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'paciente', label: Text('Soy paciente'), icon: Icon(Icons.person)),
                    ButtonSegment(value: 'cuidador', label: Text('Soy cuidador'), icon: Icon(Icons.family_restroom)),
                  ],
                  selected: {_rol},
                  onSelectionChanged: (s) => setState(() => _rol = s.first),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nombre,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'Nombre completo'),
                  validator: (v) => (v == null || v.trim().length < 3) ? 'Ingrese su nombre' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _correo,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Correo electrónico'),
                  validator: (v) => (v == null || !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v.trim()))
                      ? 'Ingrese un correo válido'
                      : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Celular (opcional)'),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _clave,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Contraseña', helperText: 'Mínimo 8 caracteres'),
                  validator: (v) => (v == null || v.length < 8) ? 'Use al menos 8 caracteres' : null,
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  value: _acepta,
                  onChanged: (v) => setState(() => _acepta = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Autorizo el tratamiento de mis datos personales y de salud',
                    style: TextStyle(fontSize: 16),
                  ),
                  subtitle: TextButton(
                    style: TextButton.styleFrom(alignment: Alignment.centerLeft, padding: EdgeInsets.zero),
                    onPressed: _verPolitica,
                    child: const Text('Leer la política de datos'),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _enviando ? null : _registrar,
                  child: _enviando ? const CircularProgressIndicator() : const Text('Crear cuenta'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// Recuperación de contraseña con código enviado por correo (RF02).
class PantallaRecuperar extends StatefulWidget {
  const PantallaRecuperar({super.key});

  @override
  State<PantallaRecuperar> createState() => _PantallaRecuperarState();
}

class _PantallaRecuperarState extends State<PantallaRecuperar> {
  final _correo = TextEditingController();
  final _codigo = TextEditingController();
  final _clave = TextEditingController();
  bool _codigoEnviado = false;
  bool _enviando = false;

  Future<void> _accion() async {
    final api = SesionScope.de(context).api;
    setState(() => _enviando = true);
    try {
      final msg = _codigoEnviado
          ? await api.restablecer(_correo.text.trim(), _codigo.text.trim(), _clave.text)
          : await api.recuperar(_correo.text.trim());
      if (!mounted) return;
      mostrarMensaje(context, msg);
      if (_codigoEnviado) {
        Navigator.pop(context);
      } else {
        setState(() => _codigoEnviado = true);
      }
    } catch (e) {
      if (mounted) mostrarMensaje(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Recuperar contraseña')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('Le enviaremos un código de 6 dígitos a su correo.', style: TextStyle(fontSize: 18)),
        const SizedBox(height: 20),
        TextField(
          controller: _correo,
          decoration: const InputDecoration(labelText: 'Correo electrónico'),
        ),
        if (_codigoEnviado) ...[
          const SizedBox(height: 14),
          TextField(
            controller: _codigo,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Código recibido'),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _clave,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Nueva contraseña (mínimo 8 caracteres)'),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _enviando ? null : _accion,
          child: Text(_codigoEnviado ? 'Cambiar contraseña' : 'Enviar código'),
        ),
      ],
    ),
  );
}
