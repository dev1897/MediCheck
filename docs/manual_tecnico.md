# Manual técnico de MediCheck

## 1. Componentes

| Componente | Tecnología | Ubicación |
|---|---|---|
| Aplicación móvil | Flutter 3 / Dart 3 (Android y web) | `mobile/` |
| API REST | Node.js 18+ con Express 4 | `backend/src/` |
| Planificador de alertas | node-cron (cada minuto) | `backend/src/services/planificador.service.js` |
| Base de datos | PostgreSQL 14+ (o pg-mem en simulación) | `backend/src/db/schema.sql` |
| Notificaciones push | Firebase Cloud Messaging o modo simulado | `backend/src/services/notificaciones.service.js` |
| Correo electrónico | Nodemailer (SMTP o modo simulado) | `backend/src/services/notificaciones.service.js` |
| Recordatorios locales | flutter_local_notifications | `mobile/lib/servicios/recordatorios.dart` |

## 2. Estructura del backend

```
backend/
├── src/
│   ├── app.js                    # Configuración de Express, rutas y manejo de errores
│   ├── server.js                 # Punto de entrada: base de datos, servidor y planificador
│   ├── config/index.js           # Variables de entorno
│   ├── db/{index.js,schema.sql}  # Conexión (pg / pg-mem) y esquema
│   ├── middleware/auth.js        # JWT, control por rol y autorización paciente-cuidador
│   ├── routes/                   # auth, tratamientos, dosis, cuidadores, pacientes, simulacion
│   ├── services/                 # dosis, adherencia, planificador, notificaciones
│   └── utils/comunes.js          # Reloj, errores HTTP, validación y fechas
├── scripts/{seed.js,simular.js}  # Datos de demostración y simulación de extremo a extremo
└── test/                         # Pruebas unitarias e integración (node:test + supertest)
```

## 3. Estructura de la aplicación

```
mobile/lib/
├── main.dart                 # Inicio, localización en español y selección por rol
├── config.dart               # URL de la API (--dart-define=API_URL)
├── tema.dart                 # Tema accesible: letra grande y alto contraste
├── modelos.dart              # Usuario, Tratamiento, Dosis, Vinculo, Alerta, Adherencia
├── servicios/
│   ├── api.dart              # Cliente HTTP de la API REST
│   ├── sesion.dart           # Sesión persistente (shared_preferences)
│   ├── cola_offline.dart     # Confirmaciones sin conexión (RF12)
│   └── recordatorios.dart    # Notificaciones locales programadas (RF05, RF06)
├── pantallas/
│   ├── acceso.dart           # Inicio de sesión, registro y recuperación
│   ├── inicio.dart           # Navegación del paciente y del cuidador
│   ├── historial.dart        # Adherencia e historial (RF10)
│   ├── paciente/             # Hoy, tratamientos, cuidadores
│   └── cuidador/             # Pacientes, panel del paciente, alertas
└── widgets/comunes.dart      # Componentes reutilizables y gráfico de adherencia
```

## 4. Modelo de datos

| Tabla | Propósito | Campos clave |
|---|---|---|
| `usuario` | Pacientes y cuidadores | `correo` único, `contrasena_hash` (bcrypt), `rol`, `acepta_politica_fecha`, `token_push` |
| `tratamiento` | Medicamento de un paciente | `frecuencia_horas` (1–168), `fecha_inicio`, `fecha_fin`, `activo` |
| `dosis_programada` | Cada toma generada | `fecha_hora`, `estado` (pendiente/tomada/omitida), `confirmada_tarde`, `origen_confirmacion` |
| `vinculo_cuidador` | Relación paciente–cuidador | `codigo_invitacion`, `tolerancia_min` (5–240), `estado` (pendiente/activo/revocado) |
| `alerta` | Notificación enviada | `canal` (push/correo), `fecha_envio`, `estado_envio`, `leida` |

## 5. Reglas de negocio

1. **Generación de dosis (RF04).** Al crear un tratamiento se generan las dosis alineadas con `fecha_inicio + k × frecuencia` hasta el horizonte (7 días) o la fecha de fin. No se crean dosis pasadas para evitar alertas falsas. Una tarea diaria (00:05) extiende el horizonte.
2. **Tolerancia efectiva (RF08).** Es la menor tolerancia entre los cuidadores activos del paciente; sin cuidadores se usa el valor por defecto (30 min).
3. **Ciclo del planificador (RF09).** Cada minuto: busca dosis pendientes vencidas; si `ahora ≥ fecha_hora + tolerancia`, las marca como omitidas con una actualización condicionada a `estado = 'pendiente'` (evita duplicados) y envía push y correo a cada cuidador activo, registrando cada envío en `alerta`.
4. **Confirmación (RF06).** Se permite desde 2 horas antes de la dosis. Una dosis omitida puede confirmarse después: queda como tomada con `confirmada_tarde = true`.
5. **Sincronización (RF12).** La app guarda la hora real de la toma sin conexión y la envía en lote a `POST /api/dosis/sincronizar`; la operación es idempotente.
6. **Adherencia (RF10).** `tomadas / (tomadas + omitidas) × 100`; las dosis pendientes no se cuentan.

## 6. Seguridad (RNF04)

- Contraseñas con bcrypt (costo 10); el hash nunca se devuelve en las respuestas.
- Autenticación sin estado con JWT (expiración de 12 h) en `Authorization: Bearer`.
- Control por rol (`exigirRol`) y por vínculo (`resolverPaciente`): un cuidador solo accede a pacientes con vínculo activo.
- Cabeceras seguras con Helmet, límite de 100 KB en el cuerpo y validación de todas las entradas.
- Recuperación de contraseña con código de 6 dígitos (hash bcrypt, vigencia de 15 min) y respuesta que no revela si el correo existe.
- En producción: HTTPS en el proveedor de nube, `JWT_SECRETO` obligatorio y `SIMULACION=false`.

## 7. Referencia de la API

Todas las rutas, excepto registro, login, recuperación y salud, requieren `Authorization: Bearer <token>`.

| Método | Ruta | Rol | Descripción | RF |
|---|---|---|---|---|
| GET | `/api/salud` | — | Estado del servicio y modos activos | — |
| POST | `/api/auth/registro` | — | Crea una cuenta (exige `acepta_politica: true`) | RF01, RF13 |
| POST | `/api/auth/login` | — | Devuelve token JWT y usuario | RF02 |
| POST | `/api/auth/recuperar` | — | Envía código de recuperación por correo | RF02 |
| POST | `/api/auth/restablecer` | — | Cambia la contraseña con el código | RF02 |
| GET | `/api/auth/perfil` | Ambos | Datos del usuario autenticado | — |
| PUT | `/api/auth/token-push` | Ambos | Registra el token FCM del dispositivo | RF09 |
| GET | `/api/tratamientos[?id_paciente=]` | Ambos | Lista tratamientos | RF03 |
| POST | `/api/tratamientos` | Ambos | Crea tratamiento y genera dosis | RF03, RF04 |
| PUT | `/api/tratamientos/{id}` | Ambos | Edita o suspende (`activo`) y regenera dosis futuras | RF03 |
| DELETE | `/api/tratamientos/{id}` | Ambos | Elimina tratamiento, dosis y alertas | RF03 |
| GET | `/api/dosis?fecha=AAAA-MM-DD` | Paciente | Dosis del día | RF06 |
| GET | `/api/dosis/proximas` | Paciente | Próximas dosis para recordatorios locales | RF05 |
| PATCH | `/api/dosis/{id}/confirmar` | Paciente | Confirma una dosis | RF06 |
| POST | `/api/dosis/sincronizar` | Paciente | Confirmaciones registradas sin conexión | RF12 |
| GET | `/api/cuidadores` | Ambos | Vínculos e invitaciones | RF07 |
| POST | `/api/cuidadores/invitar` | Paciente | Invita por correo y genera código | RF07 |
| PATCH | `/api/cuidadores/{id}/aceptar` | Cuidador | Acepta una invitación | RF07 |
| POST | `/api/cuidadores/unirse` | Cuidador | Se vincula con el código | RF07 |
| PATCH | `/api/cuidadores/{id}` | Ambos | Cambia tolerancia o parentesco | RF08 |
| DELETE | `/api/cuidadores/{id}` | Ambos | Revoca el vínculo | RF07 |
| GET | `/api/adherencia?dias=7` | Paciente | Adherencia propia | RF10 |
| GET | `/api/pacientes` | Cuidador | Pacientes vinculados y resumen del día | RF11 |
| GET | `/api/pacientes/{id}/dosis` | Cuidador | Dosis del día del paciente | RF11 |
| GET | `/api/pacientes/{id}/adherencia?dias=` | Cuidador | Historial y porcentaje | RF10 |
| GET | `/api/alertas` | Cuidador | Bandeja de alertas (push) | RF09 |
| PATCH | `/api/alertas/{id}/leida` | Cuidador | Marca una alerta como vista | — |
| GET | `/api/simulacion/estado` | — | Hora del reloj simulado | Simulación |
| POST | `/api/simulacion/avanzar` | — | Adelanta el reloj y ejecuta el planificador | Simulación |
| POST | `/api/simulacion/planificador` | — | Ejecuta un ciclo del planificador | Simulación |
| GET | `/api/simulacion/buzon` | — | Correos generados en modo simulado | Simulación |

Errores: `{"error": "mensaje", "detalles": ["..."]}` con códigos 400, 401, 403, 404, 409 o 500.

### Ejemplo

```bash
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"correo":"paciente@medicheck.demo","contrasena":"Demo1234"}'
```

## 8. Despliegue en la nube (Render o Railway)

1. Crear una base de datos PostgreSQL administrada y copiar su `DATABASE_URL`.
2. Crear un servicio web desde la carpeta `backend` con el comando `npm start`.
3. Definir `DB_MODO=postgres`, `DATABASE_URL`, `JWT_SECRETO`, `SIMULACION=false`, `CORREO_MODO=smtp` y las variables SMTP; para push real, `PUSH_MODO=fcm`, instalar `firebase-admin` y cargar la cuenta de servicio.
4. Compilar la app: `flutter build apk --release --dart-define=API_URL=https://<servicio>.onrender.com`.

## 9. Pruebas

```bash
cd backend && npm test && npm run simular
cd mobile && flutter analyze && flutter test
```

La integración continua (`.github/workflows/ci.yml`) ejecuta los mismos comandos en cada *push*.
