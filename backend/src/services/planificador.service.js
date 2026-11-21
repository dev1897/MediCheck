'use strict';
const cron = require('node-cron');
const db = require('../db');
const config = require('../config');
const { reloj, horaLocal } = require('../utils/comunes');
const notificaciones = require('./notificaciones.service');
const dosisService = require('./dosis.service');

/**
 * Tolerancia efectiva de un paciente: la menor configurada entre sus vínculos
 * activos (el cuidador más exigente) o el valor por defecto si no tiene cuidadores.
 */
function toleranciaEfectiva(vinculos) {
  if (!vinculos.length) return config.toleranciaPorDefectoMin;
  return Math.min(...vinculos.map((v) => v.tolerancia_min));
}

/** Indica si una dosis pendiente ya superó su tiempo de tolerancia. Función pura. */
function estaVencida(fechaHora, toleranciaMin, ahora) {
  return new Date(ahora).getTime() >= new Date(fechaHora).getTime() + toleranciaMin * 60000;
}

/**
 * Ciclo del planificador (RF09). Se ejecuta cada minuto:
 * 1. Busca dosis pendientes cuya hora ya pasó.
 * 2. Si superaron la tolerancia, las marca como omitidas.
 * 3. Envía una alerta por push y por correo a cada cuidador activo y la registra.
 */
async function ejecutarCiclo() {
  const ahora = reloj.ahora();
  const { rows: pendientes } = await db.query(
    `SELECT d.id_dosis, d.fecha_hora, t.medicamento, t.dosis, t.id_paciente,
            u.nombre AS nombre_paciente
       FROM dosis_programada d
       JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
       JOIN usuario u ON u.id_usuario = t.id_paciente
      WHERE d.estado = 'pendiente' AND d.fecha_hora <= $1
      ORDER BY d.fecha_hora`,
    [ahora],
  );

  const resultado = { revisadas: pendientes.length, omitidas: 0, alertas: 0 };
  const cacheVinculos = new Map();

  for (const dosis of pendientes) {
    if (!cacheVinculos.has(dosis.id_paciente)) {
      const { rows } = await db.query(
        `SELECT v.id_vinculo, v.tolerancia_min, c.id_usuario, c.nombre, c.correo, c.token_push
           FROM vinculo_cuidador v
           JOIN usuario c ON c.id_usuario = v.id_cuidador
          WHERE v.id_paciente = $1 AND v.estado = 'activo'`,
        [dosis.id_paciente],
      );
      cacheVinculos.set(dosis.id_paciente, rows);
    }
    const vinculos = cacheVinculos.get(dosis.id_paciente);
    if (!estaVencida(dosis.fecha_hora, toleranciaEfectiva(vinculos), ahora)) continue;

    // La condición "estado = 'pendiente'" evita duplicados si la dosis se confirmó mientras tanto
    const act = await db.query(
      "UPDATE dosis_programada SET estado = 'omitida' WHERE id_dosis = $1 AND estado = 'pendiente' RETURNING id_dosis",
      [dosis.id_dosis],
    );
    if (!act.rows.length) continue;
    resultado.omitidas += 1;

    const hora = horaLocal(dosis.fecha_hora);
    const titulo = `MediCheck: ${dosis.nombre_paciente} no confirmó una dosis`;
    const cuerpo = `${dosis.medicamento} ${dosis.dosis} programado a las ${hora} no fue confirmado. Comuníquese con el paciente.`;

    for (const v of vinculos) {
      const envios = [
        ['push', await notificaciones.enviarPush(v, titulo, cuerpo, { id_dosis: dosis.id_dosis })],
        [
          'correo',
          await notificaciones.enviarCorreo(
            v.correo,
            titulo,
            `Hola ${v.nombre}:\n\n${cuerpo}\n\nEste es un mensaje automático de MediCheck.`,
          ),
        ],
      ];
      for (const [canal, r] of envios) {
        await db.query(
          `INSERT INTO alerta (id_dosis, id_vinculo, canal, fecha_envio, estado_envio, detalle)
           VALUES ($1, $2, $3, $4, $5, $6)`,
          [dosis.id_dosis, v.id_vinculo, canal, reloj.ahora(), r.ok ? 'enviada' : 'fallida', r.detalle],
        );
        resultado.alertas += 1;
      }
    }
  }
  return resultado;
}

const tareas = [];

/** Programa las tareas periódicas: verificación cada minuto y extensión diaria de dosis. */
function iniciar() {
  tareas.push(
    cron.schedule(config.cronPlanificador, () => {
      ejecutarCiclo()
        .then((r) => {
          if (r.omitidas) console.log(`[Planificador] ${r.omitidas} dosis omitidas, ${r.alertas} alertas enviadas.`);
        })
        .catch((e) => console.error('[Planificador] Error:', e.message));
    }),
  );
  tareas.push(
    cron.schedule('5 0 * * *', () => {
      dosisService.extenderTodos().catch((e) => console.error('[Planificador] Error al extender dosis:', e.message));
    }),
  );
}

function detener() {
  while (tareas.length) tareas.pop().stop();
}

module.exports = { ejecutarCiclo, estaVencida, toleranciaEfectiva, iniciar, detener };
