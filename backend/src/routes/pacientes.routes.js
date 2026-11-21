'use strict';
const express = require('express');
const db = require('../db');
const { autenticar, exigirRol, resolverPaciente } = require('../middleware/auth');
const { asincrono, validar, HttpError, reloj, fechaLocal } = require('../utils/comunes');
const adherencia = require('../services/adherencia.service');
const { dosisDelDia } = require('./dosis.routes');

const router = express.Router();
// Autenticación por ruta: este router se monta en /api y no debe afectar a otras rutas

const diasConsulta = (q) => {
  const { dias } = validar(q, { dias: { tipo: 'entero', min: 1, max: 90 } });
  return dias || 7;
};

// RF10: adherencia propia del paciente autenticado
router.get(
  '/adherencia',
  autenticar,
  exigirRol('paciente'),
  asincrono(async (req, res) => {
    res.json(await adherencia.resumen(req.usuario.id, diasConsulta(req.query)));
  }),
);

// Pacientes vinculados al cuidador, con el estado resumido del día (RF11)
router.get(
  '/pacientes',
  autenticar,
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const { rows } = await db.query(
      `SELECT v.id_vinculo, v.parentesco, v.tolerancia_min, u.id_usuario AS id_paciente, u.nombre, u.telefono
         FROM vinculo_cuidador v JOIN usuario u ON u.id_usuario = v.id_paciente
        WHERE v.id_cuidador = $1 AND v.estado = 'activo' ORDER BY u.nombre`,
      [req.usuario.id],
    );
    const hoy = fechaLocal(reloj.ahora());
    const resultado = [];
    for (const p of rows) {
      const dosis = await dosisDelDia(p.id_paciente, hoy);
      resultado.push({
        ...p,
        hoy: {
          total: dosis.length,
          tomadas: dosis.filter((d) => d.estado === 'tomada').length,
          omitidas: dosis.filter((d) => d.estado === 'omitida').length,
          pendientes: dosis.filter((d) => d.estado === 'pendiente').length,
        },
      });
    }
    res.json(resultado);
  }),
);

// RF11: dosis del día de un paciente vinculado
router.get(
  '/pacientes/:id/dosis',
  autenticar,
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const id = await resolverPaciente(req, req.params.id);
    res.json(await dosisDelDia(id, req.query.fecha));
  }),
);

// RF10: historial y porcentaje de adherencia de un paciente vinculado
router.get(
  '/pacientes/:id/adherencia',
  autenticar,
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const id = await resolverPaciente(req, req.params.id);
    res.json(await adherencia.resumen(id, diasConsulta(req.query)));
  }),
);

// Alertas recibidas por el cuidador (bandeja de notificaciones push simuladas)
router.get(
  '/alertas',
  autenticar,
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const { desde } = validar(req.query, { desde: { tipo: 'fecha' } });
    const parametros = [req.usuario.id];
    let filtro = '';
    if (desde) {
      parametros.push(desde);
      filtro = 'AND a.fecha_envio > $2';
    }
    const { rows } = await db.query(
      `SELECT a.id_alerta, a.canal, a.fecha_envio, a.estado_envio, a.detalle, a.leida,
              d.id_dosis, d.fecha_hora, d.estado AS estado_dosis, t.medicamento, t.dosis,
              p.id_usuario AS id_paciente, p.nombre AS nombre_paciente, p.telefono AS telefono_paciente
         FROM alerta a
         JOIN vinculo_cuidador v ON v.id_vinculo = a.id_vinculo
         JOIN dosis_programada d ON d.id_dosis = a.id_dosis
         JOIN tratamiento t ON t.id_tratamiento = d.id_tratamiento
         JOIN usuario p ON p.id_usuario = v.id_paciente
        WHERE v.id_cuidador = $1 AND a.canal = 'push' ${filtro}
        ORDER BY a.fecha_envio DESC LIMIT 100`,
      parametros,
    );
    res.json(rows);
  }),
);

router.patch(
  '/alertas/:id/leida',
  autenticar,
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const { rows } = await db.query(
      `UPDATE alerta SET leida = TRUE
        WHERE id_alerta = $1
          AND id_vinculo IN (SELECT id_vinculo FROM vinculo_cuidador WHERE id_cuidador = $2)
        RETURNING id_alerta, leida`,
      [Number(req.params.id), req.usuario.id],
    );
    if (!rows.length) throw new HttpError(404, 'Alerta no encontrada.');
    res.json(rows[0]);
  }),
);

module.exports = router;
