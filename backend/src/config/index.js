'use strict';
require('dotenv').config({ quiet: true });

const entero = (valor, porDefecto) => {
  const n = Number.parseInt(valor, 10);
  return Number.isNaN(n) ? porDefecto : n;
};

const config = {
  entorno: process.env.NODE_ENV || 'development',
  puerto: entero(process.env.PORT, 3000),

  // Base de datos: "memoria" (PostgreSQL emulado con pg-mem) o "postgres" (servidor real)
  dbModo: process.env.DB_MODO || 'memoria',
  databaseUrl: process.env.DATABASE_URL || '',

  jwtSecreto: process.env.JWT_SECRETO || 'cambie-este-secreto-en-produccion',
  jwtExpira: process.env.JWT_EXPIRA || '12h',

  // Zona horaria de Colombia (UTC-5, sin horario de verano)
  zonaHoraria: process.env.ZONA_HORARIA || '-05:00',

  toleranciaPorDefectoMin: entero(process.env.TOLERANCIA_POR_DEFECTO_MIN, 30),
  horizonteDias: entero(process.env.HORIZONTE_DIAS, 7),
  cronPlanificador: process.env.CRON_PLANIFICADOR || '* * * * *',

  // Notificaciones: "simulado" (no requiere cuentas externas), "fcm" / "smtp" (servicios reales)
  pushModo: process.env.PUSH_MODO || 'simulado',
  correoModo: process.env.CORREO_MODO || 'simulado',
  smtp: {
    host: process.env.SMTP_HOST || '',
    puerto: entero(process.env.SMTP_PUERTO, 587),
    usuario: process.env.SMTP_USUARIO || '',
    contrasena: process.env.SMTP_CONTRASENA || '',
    remitente: process.env.SMTP_REMITENTE || 'MediCheck <no-responder@medicheck.app>',
  },
  carpetaBuzon: process.env.CARPETA_BUZON || 'buzon',

  // Habilita los endpoints /api/simulacion (reloj simulado y ejecución manual del planificador)
  simulacion: (process.env.SIMULACION || 'true') === 'true',
};

if (config.entorno === 'production' && config.jwtSecreto.startsWith('cambie')) {
  throw new Error('Debe definir JWT_SECRETO en producción.');
}

module.exports = config;
