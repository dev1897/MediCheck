'use strict';
const express = require('express');
const db = require('../db');
const { autenticar, resolverPaciente } = require('../middleware/auth');
const { asincrono, validar, HttpError, reloj } = require('../utils/comunes');
const dosisService = require('../services/dosis.service');

const router = express.Router();
router.use(autenticar);

const REGLAS = {
  medicamento: { requerido: true, min: 2, max: 120 },
  dosis: { requerido: true, min: 1, max: 80 },
  frecuencia_horas: { requerido: true, tipo: 'entero', min: 1, max: 168 },
  fecha_inicio: { requerido: true, tipo: 'fecha' },
  fecha_fin: { tipo: 'fecha' },
  indicaciones: { max: 255 },
};

async function obtenerAutorizado(req, id) {
  const { rows } = await db.query('SELECT * FROM tratamiento WHERE id_tratamiento = $1', [Number(id)]);
  if (!rows.length) throw new HttpError(404, 'Tratamiento no encontrado.');
  await resolverPaciente(req, rows[0].id_paciente).then((idPac) => {
    if (idPac !== rows[0].id_paciente) throw new HttpError(403, 'No tiene permiso sobre este tratamiento.');
  });
  return rows[0];
}

// RF03: listar tratamientos del paciente (o del paciente vinculado si es cuidador)
router.get(
  '/',
  asincrono(async (req, res) => {
    const idPaciente = await resolverPaciente(req, req.query.id_paciente);
    const { rows } = await db.query(
      'SELECT * FROM tratamiento WHERE id_paciente = $1 ORDER BY activo DESC, medicamento',
      [idPaciente],
    );
    res.json(rows);
  }),
);

// RF03 + RF04: crear tratamiento y generar sus dosis
router.post(
  '/',
  asincrono(async (req, res) => {
    const idPaciente = await resolverPaciente(req, req.body.id_paciente);
    const d = validar(req.body, REGLAS);
    if (d.fecha_fin && d.fecha_fin <= d.fecha_inicio) {
      throw new HttpError(400, 'La fecha de fin debe ser posterior a la fecha de inicio.');
    }
    const { rows } = await db.query(
      `INSERT INTO tratamiento (id_paciente, medicamento, dosis, frecuencia_horas, fecha_inicio, fecha_fin,
                                indicaciones, activo, fecha_creacion)
       VALUES ($1, $2, $3, $4, $5, $6, $7, TRUE, $8) RETURNING *`,
      [idPaciente, d.medicamento, d.dosis, d.frecuencia_horas, d.fecha_inicio, d.fecha_fin || null,
        d.indicaciones || null, reloj.ahora()],
    );
    const generadas = await dosisService.generarDosis(rows[0]);
    res.status(201).json({ ...rows[0], dosis_generadas: generadas });
  }),
);

// RF03: editar o suspender (activo = false). Se regeneran las dosis futuras.
router.put(
  '/:id',
  asincrono(async (req, res) => {
    const actual = await obtenerAutorizado(req, req.params.id);
    const d = validar({ ...actual, ...req.body }, { ...REGLAS, activo: { tipo: 'booleano' } });
    const activo = d.activo === undefined ? actual.activo : d.activo;
    const { rows } = await db.query(
      `UPDATE tratamiento SET medicamento = $1, dosis = $2, frecuencia_horas = $3, fecha_inicio = $4,
              fecha_fin = $5, indicaciones = $6, activo = $7
        WHERE id_tratamiento = $8 RETURNING *`,
      [d.medicamento, d.dosis, d.frecuencia_horas, d.fecha_inicio, d.fecha_fin || null,
        d.indicaciones || null, activo, actual.id_tratamiento],
    );
    await dosisService.eliminarDosisFuturas(actual.id_tratamiento);
    const generadas = await dosisService.generarDosis(rows[0]);
    res.json({ ...rows[0], dosis_generadas: generadas });
  }),
);

// RF03: eliminar tratamiento (y en cascada sus dosis y alertas)
router.delete(
  '/:id',
  asincrono(async (req, res) => {
    const actual = await obtenerAutorizado(req, req.params.id);
    await db.query('DELETE FROM alerta WHERE id_dosis IN (SELECT id_dosis FROM dosis_programada WHERE id_tratamiento = $1)', [actual.id_tratamiento]);
    await db.query('DELETE FROM dosis_programada WHERE id_tratamiento = $1', [actual.id_tratamiento]);
    await db.query('DELETE FROM tratamiento WHERE id_tratamiento = $1', [actual.id_tratamiento]);
    res.status(204).end();
  }),
);

module.exports = router;
