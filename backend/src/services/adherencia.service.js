'use strict';
const db = require('../db');
const { reloj, fechaLocal } = require('../utils/comunes');

/**
 * Porcentaje de adherencia = dosis tomadas / (tomadas + omitidas) * 100.
 * Las dosis pendientes no se cuentan porque aún pueden confirmarse.
 * Función pura: se prueba de forma unitaria.
 */
function calcularPorcentaje(dosis) {
  const tomadas = dosis.filter((d) => d.estado === 'tomada').length;
  const omitidas = dosis.filter((d) => d.estado === 'omitida').length;
  const evaluadas = tomadas + omitidas;
  return {
    tomadas,
    omitidas,
    evaluadas,
    porcentaje: evaluadas === 0 ? null : Math.round((tomadas / evaluadas) * 1000) / 10,
  };
}

/** Agrupa las dosis por día local y calcula la adherencia diaria. */
function serieDiaria(dosis) {
  const porDia = new Map();
  for (const d of dosis) {
    const dia = fechaLocal(d.fecha_hora);
    if (!porDia.has(dia)) porDia.set(dia, []);
    porDia.get(dia).push(d);
  }
  return [...porDia.entries()]
    .sort(([a], [b]) => a.localeCompare(b))
    .map(([fecha, lista]) => ({ fecha, ...calcularPorcentaje(lista) }));
}

/** Historial y adherencia de un paciente en los últimos `dias` días (RF10). */
async function resumen(idPaciente, dias = 7) {
  const ahora = reloj.ahora();
  const desde = new Date(ahora.getTime() - dias * 24 * 3600 * 1000);
  const { rows } = await db.query(
    `SELECT d.id_dosis, d.fecha_hora, d.estado, d.fecha_confirmacion, d.confirmada_tarde,
            t.medicamento, t.dosis
       FROM dosis_programada d
       JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
      WHERE t.id_paciente = $1 AND d.fecha_hora >= $2 AND d.fecha_hora <= $3
      ORDER BY d.fecha_hora DESC`,
    [idPaciente, desde, ahora],
  );
  return {
    periodo_dias: dias,
    desde,
    hasta: ahora,
    ...calcularPorcentaje(rows),
    por_dia: serieDiaria(rows),
    historial: rows,
  };
}

module.exports = { calcularPorcentaje, serieDiaria, resumen };
