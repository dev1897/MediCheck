'use strict';
const express = require('express');
const db = require('../db');
const { autenticar, exigirRol, resolverPaciente } = require('../middleware/auth');
const { asincrono, validar, HttpError, reloj, rangoDelDia, fechaLocal } = require('../utils/comunes');

const router = express.Router();
router.use(autenticar);

/** Dosis de un paciente en un día local (RF06 pantalla "Hoy", RF11 panel del cuidador). */
async function dosisDelDia(idPaciente, fechaTexto) {
  const rango = rangoDelDia(fechaTexto || fechaLocal(reloj.ahora()));
  if (!rango) throw new HttpError(400, 'La fecha debe tener el formato AAAA-MM-DD.');
  const { rows } = await db.query(
    `SELECT d.id_dosis, d.id_tratamiento, d.fecha_hora, d.estado, d.fecha_confirmacion,
            d.confirmada_tarde, t.medicamento, t.dosis, t.indicaciones
       FROM dosis_programada d
       JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
      WHERE t.id_paciente = $1 AND d.fecha_hora >= $2 AND d.fecha_hora < $3
      ORDER BY d.fecha_hora`,
    [idPaciente, rango.inicio, rango.fin],
  );
  return rows;
}

router.get(
  '/',
  asincrono(async (req, res) => {
    const idPaciente = await resolverPaciente(req, req.query.id_paciente);
    res.json(await dosisDelDia(idPaciente, req.query.fecha));
  }),
);

/** Próximas dosis pendientes (para programar recordatorios locales en el dispositivo, RF05). */
router.get(
  '/proximas',
  exigirRol('paciente'),
  asincrono(async (req, res) => {
    const ahora = reloj.ahora();
    const { rows } = await db.query(
      `SELECT d.id_dosis, d.fecha_hora, t.medicamento, t.dosis
         FROM dosis_programada d
         JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
        WHERE t.id_paciente = $1 AND d.estado = 'pendiente' AND d.fecha_hora >= $2
        ORDER BY d.fecha_hora LIMIT 50`,
      [req.usuario.id, new Date(ahora.getTime() - 60 * 60000)],
    );
    res.json(rows);
  }),
);

/**
 * Registra la confirmación de una dosis. Se acepta también una dosis ya
 * marcada como omitida (el paciente la tomó tarde): queda como tomada y
 * con la marca confirmada_tarde.
 */
async function confirmar(idUsuario, idDosis, fechaConfirmacion, origen) {
  const { rows } = await db.query(
    `SELECT d.*, t.id_paciente FROM dosis_programada d
       JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
      WHERE d.id_dosis = $1`,
    [idDosis],
  );
  const dosis = rows[0];
  if (!dosis || dosis.id_paciente !== idUsuario) throw new HttpError(404, 'Dosis no encontrada.');
  if (dosis.estado === 'tomada') return { ...dosis, ya_confirmada: true };

  const ahora = reloj.ahora();
  let fecha = fechaConfirmacion || ahora;
  if (fecha > ahora) fecha = ahora;
  const limiteAnticipado = new Date(new Date(dosis.fecha_hora).getTime() - 2 * 3600 * 1000);
  if (fecha < limiteAnticipado) {
    throw new HttpError(409, 'Solo puede confirmar una dosis desde dos horas antes de su horario.');
  }
  const tarde = dosis.estado === 'omitida';
  const act = await db.query(
    `UPDATE dosis_programada
        SET estado = 'tomada', fecha_confirmacion = $1, confirmada_tarde = $2, origen_confirmacion = $3
      WHERE id_dosis = $4 RETURNING *`,
    [fecha, tarde, origen, idDosis],
  );
  return act.rows[0];
}

// RF06: confirmar la toma con un solo toque
router.patch(
  '/:id/confirmar',
  exigirRol('paciente'),
  asincrono(async (req, res) => {
    const d = validar(req.body || {}, { fecha_confirmacion: { tipo: 'fecha' } });
    const origen = req.body && req.body.origen === 'notificacion' ? 'notificacion' : 'app';
    res.json(await confirmar(req.usuario.id, Number(req.params.id), d.fecha_confirmacion, origen));
  }),
);

// RF12: sincronizar confirmaciones registradas sin conexión
router.post(
  '/sincronizar',
  exigirRol('paciente'),
  asincrono(async (req, res) => {
    const lista = Array.isArray(req.body && req.body.confirmaciones) ? req.body.confirmaciones : null;
    if (!lista || lista.length > 200) {
      throw new HttpError(400, 'Envíe "confirmaciones" como una lista de máximo 200 elementos.');
    }
    const resultados = [];
    for (const item of lista) {
      try {
        const d = validar(item, {
          id_dosis: { requerido: true, tipo: 'entero', min: 1 },
          fecha_confirmacion: { requerido: true, tipo: 'fecha' },
        });
        const r = await confirmar(req.usuario.id, d.id_dosis, d.fecha_confirmacion, 'sincronizada');
        resultados.push({ id_dosis: d.id_dosis, ok: true, estado: r.estado, confirmada_tarde: r.confirmada_tarde });
      } catch (e) {
        resultados.push({ id_dosis: item && item.id_dosis, ok: false, error: e.message });
      }
    }
    res.json({ procesadas: resultados.length, resultados });
  }),
);

module.exports = { router, dosisDelDia };
