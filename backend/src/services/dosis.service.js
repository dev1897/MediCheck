'use strict';
const db = require('../db');
const config = require('../config');
const { reloj } = require('../utils/comunes');

const HORA_MS = 3600 * 1000;
// Margen para incluir la dosis de "ahora mismo" cuando se crea un tratamiento
const MARGEN_INICIAL_MS = 5 * 60 * 1000;

/**
 * Calcula los instantes de las dosis de un tratamiento dentro de [desde, hasta].
 * Las dosis se alinean con fecha_inicio + k * frecuencia (RF04).
 * Función pura: se prueba de forma unitaria.
 */
function calcularHorarios({ fechaInicio, frecuenciaHoras, fechaFin }, desde, hasta) {
  const inicio = new Date(fechaInicio).getTime();
  const paso = frecuenciaHoras * HORA_MS;
  const limite = Math.min(
    new Date(hasta).getTime(),
    fechaFin ? new Date(fechaFin).getTime() : Number.POSITIVE_INFINITY,
  );
  const desdeMs = Math.max(new Date(desde).getTime(), inicio);
  let k = Math.max(0, Math.ceil((desdeMs - inicio) / paso));
  const horarios = [];
  for (let t = inicio + k * paso; t <= limite; k += 1, t = inicio + k * paso) {
    horarios.push(new Date(t));
  }
  return horarios;
}

/**
 * Genera (o extiende) las dosis programadas de un tratamiento hasta el horizonte configurado.
 * No crea dosis en el pasado para no producir alertas falsas.
 */
async function generarDosis(tratamiento) {
  if (!tratamiento.activo) return 0;
  const ahora = reloj.ahora();
  const { rows } = await db.query(
    'SELECT MAX(fecha_hora) AS ultima FROM dosis_programada WHERE id_tratamiento = $1',
    [tratamiento.id_tratamiento],
  );
  const ultima = rows[0] && rows[0].ultima ? new Date(rows[0].ultima) : null;
  const desde = ultima
    ? new Date(ultima.getTime() + 1000)
    : new Date(ahora.getTime() - MARGEN_INICIAL_MS);
  const hasta = new Date(ahora.getTime() + config.horizonteDias * 24 * HORA_MS);

  const horarios = calcularHorarios(
    {
      fechaInicio: tratamiento.fecha_inicio,
      frecuenciaHoras: tratamiento.frecuencia_horas,
      fechaFin: tratamiento.fecha_fin,
    },
    desde,
    hasta,
  );
  for (const h of horarios) {
    await db.query(
      "INSERT INTO dosis_programada (id_tratamiento, fecha_hora, estado) VALUES ($1, $2, 'pendiente')",
      [tratamiento.id_tratamiento, h],
    );
  }
  return horarios.length;
}

/** Elimina las dosis futuras pendientes (al editar, suspender o eliminar un tratamiento). */
async function eliminarDosisFuturas(idTratamiento) {
  await db.query(
    "DELETE FROM dosis_programada WHERE id_tratamiento = $1 AND estado = 'pendiente' AND fecha_hora > $2",
    [idTratamiento, reloj.ahora()],
  );
}

/** Extiende el horizonte de dosis de todos los tratamientos activos (tarea diaria). */
async function extenderTodos() {
  const { rows } = await db.query('SELECT * FROM tratamiento WHERE activo = TRUE');
  let total = 0;
  for (const t of rows) total += await generarDosis(t);
  return total;
}

module.exports = { calcularHorarios, generarDosis, eliminarDosisFuturas, extenderTodos };
