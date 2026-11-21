# MediCheck

**Aplicación móvil de recordatorio y alerta de adherencia a tratamientos médicos para pacientes con enfermedades crónicas.**

Proyecto aplicado · Programa de Ingeniería de Sistemas · Universidad Nacional Abierta y a Distancia (UNAD)
Curso Proyecto de grado (202016907) · Fase 4: Desarrollo de la propuesta ingenieril · Prototipo funcional TRL 5

MediCheck recuerda al paciente la toma de cada dosis, registra su confirmación con un solo toque y, si la dosis no se confirma dentro del tiempo de tolerancia, **envía automáticamente una alerta a un cuidador o familiar** por notificación push y por correo electrónico.

---

## Contenido del repositorio

| Carpeta | Descripción |
|---|---|
| [`backend/`](backend) | API REST en Node.js + Express, planificador de alertas (node-cron), PostgreSQL, JWT y bcrypt. |
| [`mobile/`](mobile) | Aplicación Flutter (Android y web) con perfiles de paciente y de cuidador. |
| [`docs/`](docs) | Manual de usuario, manual técnico, referencia de la API, registro Scrum y guion del video. |
| [`.github/workflows/`](.github/workflows) | Integración continua: pruebas del backend y de la app en cada *push*. |

## Arquitectura

```
┌──────────────────────┐    HTTPS/JSON    ┌──────────────────────────────┐     SQL     ┌──────────────┐
│  App Flutter         │ ───────────────▶ │  API REST (Node.js/Express)  │ ──────────▶ │  PostgreSQL  │
│  · Paciente          │ ◀─────────────── │  · Autenticación JWT         │             └──────────────┘
│  · Cuidador          │                  │  · Lógica de negocio          │
│  · Recordatorios     │                  │  · Planificador (cada minuto) │ ──▶ Push (FCM / simulado)
│    locales offline   │                  └──────────────────────────────┘ ──▶ Correo (SMTP / simulado)
└──────────────────────┘
```

## Ejecución rápida (modo simulación, sin instalar bases de datos ni cuentas externas)

Requisitos: **Node.js 18+** y **Flutter 3.x**.

```bash
# 1. API con base de datos PostgreSQL emulada en memoria y datos de demostración
cd backend
npm install
npm start -- --seed
```

La API queda en `http://localhost:3000` (verifique en `http://localhost:3000/api/salud`).

```bash
# 2. Aplicación (en otra terminal)
cd mobile
flutter pub get
flutter run -d chrome          # versión web
flutter run                    # emulador o celular Android (usa http://10.0.2.2:3000)
```

Para un celular físico en la misma red: `flutter run --dart-define=API_URL=http://<IP-del-PC>:3000`

### Cuentas de demostración (datos ficticios)

| Rol | Correo | Contraseña |
|---|---|---|
| Paciente | `paciente@medicheck.demo` | `Demo1234` |
| Cuidador | `cuidador@medicheck.demo` | `Demo1234` |

### Simulación del flujo completo

```bash
cd backend
npm run simular     # ejecuta el escenario de extremo a extremo y genera simulacion-resultados.json
npm test            # 45 pruebas unitarias y de integración
```

En la app, el menú de cuenta (ícono superior derecho) ofrece **"Simulación: adelantar 15 min"**, que adelanta el reloj del servidor y ejecuta el planificador: así se demuestra en segundos cómo una dosis no confirmada genera la alerta al cuidador.

## Modos de operación

| Variable | Simulación (por defecto) | Producción |
|---|---|---|
| `DB_MODO` | `memoria` (pg-mem) | `postgres` + `DATABASE_URL` |
| `PUSH_MODO` | `simulado` (bandeja consultada por la app) | `fcm` (Firebase Cloud Messaging) |
| `CORREO_MODO` | `simulado` (mensajes guardados en `backend/buzon/`) | `smtp` |
| `SIMULACION` | `true` (endpoints `/api/simulacion/*`) | `false` |

Vea [`backend/.env.example`](backend/.env.example) y el [manual técnico](docs/manual_tecnico.md).

### Con PostgreSQL real (Docker)

```bash
docker compose up --build
```

## Pruebas y calidad

| Componente | Herramienta | Resultado |
|---|---|---|
| Backend | `node:test` + supertest | 45 pruebas (unitarias e integración) |
| Simulación E2E | `npm run simular` | 13 verificaciones de historias de usuario y requisitos no funcionales |
| App | `flutter test` | 14 pruebas (unitarias y de widgets) |
| Análisis estático | `flutter analyze` | Sin observaciones |

## Trazabilidad con el documento maestro

| Historia | Requerimientos | Implementación |
|---|---|---|
| HU01 Cuenta e inicio de sesión | RF01, RF02, RF13 | `backend/src/routes/auth.routes.js`, `mobile/lib/pantallas/acceso.dart` |
| HU02 Vincular cuidador | RF07 | `backend/src/routes/cuidadores.routes.js`, `mobile/lib/pantallas/paciente/cuidadores.dart` |
| HU03 Registrar medicamentos | RF03, RF04 | `backend/src/routes/tratamientos.routes.js`, `backend/src/services/dosis.service.js` |
| HU04 Recordatorio sin internet | RF05 | `mobile/lib/servicios/recordatorios.dart` |
| HU05 Confirmar con un toque | RF06, RF12 | `backend/src/routes/dosis.routes.js`, `mobile/lib/servicios/cola_offline.dart` |
| HU06 Alerta al cuidador | RF08, RF09 | `backend/src/services/planificador.service.js`, `notificaciones.service.js` |
| HU07 Panel del cuidador | RF11 | `backend/src/routes/pacientes.routes.js`, `mobile/lib/pantallas/cuidador/cuidador.dart` |
| HU08 Historial y adherencia | RF10 | `backend/src/services/adherencia.service.js`, `mobile/lib/pantallas/historial.dart` |

## Aviso

MediCheck es una herramienta de apoyo al autocuidado: **no reemplaza la consulta médica** ni emite recomendaciones clínicas. Los datos de demostración son ficticios. El tratamiento de datos personales sigue la Ley 1581 de 2012.

## Autor

Frankil Emir Zarate Gutiérrez · Ingeniería de Sistemas · UNAD · 2026

Licencia: [MIT](LICENSE)
