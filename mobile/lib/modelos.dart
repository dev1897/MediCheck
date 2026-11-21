/// Modelos de datos de MediCheck. Reflejan las entidades del modelo
/// relacional: USUARIO, TRATAMIENTO, DOSIS_PROGRAMADA, VINCULO_CUIDADOR y ALERTA.
library;

DateTime _fecha(dynamic v) => DateTime.parse(v as String).toLocal();
DateTime? _fechaOpc(dynamic v) => v == null ? null : _fecha(v);
int _entero(dynamic v) => v is int ? v : int.parse(v.toString());

class Usuario {
  final int id;
  final String nombre;
  final String correo;
  final String? telefono;
  final String rol;

  const Usuario({required this.id, required this.nombre, required this.correo, this.telefono, required this.rol});

  bool get esPaciente => rol == 'paciente';

  factory Usuario.desdeJson(Map<String, dynamic> j) => Usuario(
    id: _entero(j['id_usuario']),
    nombre: j['nombre'] as String,
    correo: j['correo'] as String,
    telefono: j['telefono'] as String?,
    rol: j['rol'] as String,
  );

  Map<String, dynamic> aJson() => {
    'id_usuario': id,
    'nombre': nombre,
    'correo': correo,
    'telefono': telefono,
    'rol': rol,
  };
}

enum EstadoDosis { pendiente, tomada, omitida }

class Dosis {
  final int id;
  final DateTime fechaHora;
  EstadoDosis estado;
  DateTime? fechaConfirmacion;
  bool confirmadaTarde;
  final String medicamento;
  final String cantidad;
  final String? indicaciones;

  /// Confirmada en el dispositivo, pendiente de sincronizar con el servidor (RF12).
  bool pendienteSincronizar;

  Dosis({
    required this.id,
    required this.fechaHora,
    required this.estado,
    this.fechaConfirmacion,
    this.confirmadaTarde = false,
    required this.medicamento,
    required this.cantidad,
    this.indicaciones,
    this.pendienteSincronizar = false,
  });

  factory Dosis.desdeJson(Map<String, dynamic> j) => Dosis(
    id: _entero(j['id_dosis']),
    fechaHora: _fecha(j['fecha_hora']),
    estado: EstadoDosis.values.byName(j['estado'] as String? ?? 'pendiente'),
    fechaConfirmacion: _fechaOpc(j['fecha_confirmacion']),
    confirmadaTarde: j['confirmada_tarde'] == true,
    medicamento: j['medicamento'] as String,
    cantidad: j['dosis'] as String,
    indicaciones: j['indicaciones'] as String?,
  );
}

class Tratamiento {
  final int id;
  final String medicamento;
  final String dosis;
  final int frecuenciaHoras;
  final DateTime fechaInicio;
  final DateTime? fechaFin;
  final String? indicaciones;
  final bool activo;

  const Tratamiento({
    required this.id,
    required this.medicamento,
    required this.dosis,
    required this.frecuenciaHoras,
    required this.fechaInicio,
    this.fechaFin,
    this.indicaciones,
    required this.activo,
  });

  factory Tratamiento.desdeJson(Map<String, dynamic> j) => Tratamiento(
    id: _entero(j['id_tratamiento']),
    medicamento: j['medicamento'] as String,
    dosis: j['dosis'] as String,
    frecuenciaHoras: _entero(j['frecuencia_horas']),
    fechaInicio: _fecha(j['fecha_inicio']),
    fechaFin: _fechaOpc(j['fecha_fin']),
    indicaciones: j['indicaciones'] as String?,
    activo: j['activo'] == true,
  );
}

class Vinculo {
  final int id;
  final int idPaciente;
  final String nombrePaciente;
  final String? nombreCuidador;
  final String correoInvitado;
  final String? codigo;
  final String? parentesco;
  final int toleranciaMin;
  final String estado;

  const Vinculo({
    required this.id,
    required this.idPaciente,
    required this.nombrePaciente,
    this.nombreCuidador,
    required this.correoInvitado,
    this.codigo,
    this.parentesco,
    required this.toleranciaMin,
    required this.estado,
  });

  bool get activo => estado == 'activo';

  factory Vinculo.desdeJson(Map<String, dynamic> j) => Vinculo(
    id: _entero(j['id_vinculo']),
    idPaciente: _entero(j['id_paciente']),
    nombrePaciente: j['nombre_paciente'] as String? ?? '',
    nombreCuidador: j['nombre_cuidador'] as String?,
    correoInvitado: j['correo_invitado'] as String,
    codigo: j['codigo_invitacion'] as String?,
    parentesco: j['parentesco'] as String?,
    toleranciaMin: _entero(j['tolerancia_min']),
    estado: j['estado'] as String,
  );
}

class ResumenHoy {
  final int total, tomadas, omitidas, pendientes;
  const ResumenHoy(this.total, this.tomadas, this.omitidas, this.pendientes);
}

class PacienteVinculado {
  final int idPaciente;
  final String nombre;
  final String? telefono;
  final String? parentesco;
  final int toleranciaMin;
  final ResumenHoy hoy;

  const PacienteVinculado({
    required this.idPaciente,
    required this.nombre,
    this.telefono,
    this.parentesco,
    required this.toleranciaMin,
    required this.hoy,
  });

  factory PacienteVinculado.desdeJson(Map<String, dynamic> j) {
    final h = j['hoy'] as Map<String, dynamic>;
    return PacienteVinculado(
      idPaciente: _entero(j['id_paciente']),
      nombre: j['nombre'] as String,
      telefono: j['telefono'] as String?,
      parentesco: j['parentesco'] as String?,
      toleranciaMin: _entero(j['tolerancia_min']),
      hoy: ResumenHoy(_entero(h['total']), _entero(h['tomadas']), _entero(h['omitidas']), _entero(h['pendientes'])),
    );
  }
}

class Alerta {
  final int id;
  final DateTime fechaEnvio;
  final DateTime fechaDosis;
  final String medicamento;
  final String dosis;
  final String nombrePaciente;
  final String? telefonoPaciente;
  final String estadoDosis;
  bool leida;

  Alerta({
    required this.id,
    required this.fechaEnvio,
    required this.fechaDosis,
    required this.medicamento,
    required this.dosis,
    required this.nombrePaciente,
    this.telefonoPaciente,
    required this.estadoDosis,
    required this.leida,
  });

  factory Alerta.desdeJson(Map<String, dynamic> j) => Alerta(
    id: _entero(j['id_alerta']),
    fechaEnvio: _fecha(j['fecha_envio']),
    fechaDosis: _fecha(j['fecha_hora']),
    medicamento: j['medicamento'] as String,
    dosis: j['dosis'] as String,
    nombrePaciente: j['nombre_paciente'] as String,
    telefonoPaciente: j['telefono_paciente'] as String?,
    estadoDosis: j['estado_dosis'] as String,
    leida: j['leida'] == true,
  );
}

class DiaAdherencia {
  final DateTime fecha;
  final int tomadas, omitidas;
  final double? porcentaje;
  const DiaAdherencia(this.fecha, this.tomadas, this.omitidas, this.porcentaje);
}

class Adherencia {
  final int dias;
  final int tomadas, omitidas, evaluadas;
  final double? porcentaje;
  final List<DiaAdherencia> porDia;
  final List<Dosis> historial;

  const Adherencia({
    required this.dias,
    required this.tomadas,
    required this.omitidas,
    required this.evaluadas,
    required this.porcentaje,
    required this.porDia,
    required this.historial,
  });

  factory Adherencia.desdeJson(Map<String, dynamic> j) => Adherencia(
    dias: _entero(j['periodo_dias']),
    tomadas: _entero(j['tomadas']),
    omitidas: _entero(j['omitidas']),
    evaluadas: _entero(j['evaluadas']),
    porcentaje: (j['porcentaje'] as num?)?.toDouble(),
    porDia: (j['por_dia'] as List)
        .map(
          (d) => DiaAdherencia(
            DateTime.parse(d['fecha'] as String),
            _entero(d['tomadas']),
            _entero(d['omitidas']),
            (d['porcentaje'] as num?)?.toDouble(),
          ),
        )
        .toList(),
    historial: (j['historial'] as List).map((d) => Dosis.desdeJson(d as Map<String, dynamic>)).toList(),
  );
}
