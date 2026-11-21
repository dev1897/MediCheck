'use strict';
const crypto = require('crypto');
const express = require('express');
const db = require('../db');
const config = require('../config');
const { autenticar, exigirRol } = require('../middleware/auth');
const { asincrono, validar, HttpError, reloj } = require('../utils/comunes');
const notificaciones = require('../services/notificaciones.service');

const router = express.Router();
router.use(autenticar);

const ALFABETO = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // sin caracteres ambiguos (0/O, 1/I)
const generarCodigo = () =>
  Array.from({ length: 6 }, () => ALFABETO[crypto.randomInt(ALFABETO.length)]).join('');

const SELECT_VINCULO = `
  SELECT v.*, p.nombre AS nombre_paciente, p.correo AS correo_paciente, p.telefono AS telefono_paciente,
         c.nombre AS nombre_cuidador, c.telefono AS telefono_cuidador
    FROM vinculo_cuidador v
    JOIN usuario p ON p.id_usuario = v.id_paciente
    LEFT JOIN usuario c ON c.id_usuario = v.id_cuidador`;

// Lista de vínculos del usuario: el paciente ve sus cuidadores; el cuidador, sus pacientes e invitaciones
router.get(
  '/',
  asincrono(async (req, res) => {
    if (req.usuario.rol === 'paciente') {
      const { rows } = await db.query(
        `${SELECT_VINCULO} WHERE v.id_paciente = $1 AND v.estado <> 'revocado' ORDER BY v.id_vinculo`,
        [req.usuario.id],
      );
      return res.json(rows);
    }
    const yo = (await db.query('SELECT correo FROM usuario WHERE id_usuario = $1', [req.usuario.id])).rows[0];
    const { rows } = await db.query(
      `${SELECT_VINCULO}
        WHERE v.estado <> 'revocado' AND (v.id_cuidador = $1 OR (v.estado = 'pendiente' AND v.correo_invitado = $2))
        ORDER BY v.id_vinculo`,
      [req.usuario.id, yo.correo],
    );
    return res.json(rows.map(({ codigo_invitacion: _c, ...v }) => v));
  }),
);

// RF07: el paciente invita a un cuidador por correo; se genera un código de 6 caracteres
router.post(
  '/invitar',
  exigirRol('paciente'),
  asincrono(async (req, res) => {
    const d = validar(req.body, {
      correo: { requerido: true, tipo: 'correo' },
      parentesco: { max: 40 },
      tolerancia_min: { tipo: 'entero', min: 5, max: 240 },
    });
    const paciente = (await db.query('SELECT * FROM usuario WHERE id_usuario = $1', [req.usuario.id])).rows[0];
    if (paciente.correo === d.correo) throw new HttpError(400, 'No puede invitarse a sí mismo.');
    const repetido = await db.query(
      "SELECT 1 FROM vinculo_cuidador WHERE id_paciente = $1 AND correo_invitado = $2 AND estado <> 'revocado'",
      [req.usuario.id, d.correo],
    );
    if (repetido.rows.length) throw new HttpError(409, 'Ya existe una invitación o vínculo con ese correo.');

    const codigo = generarCodigo();
    const { rows } = await db.query(
      `INSERT INTO vinculo_cuidador (id_paciente, correo_invitado, codigo_invitacion, parentesco, tolerancia_min,
                                     estado, fecha_creacion)
       VALUES ($1, $2, $3, $4, $5, 'pendiente', $6) RETURNING *`,
      [req.usuario.id, d.correo, codigo, d.parentesco || null,
        d.tolerancia_min || config.toleranciaPorDefectoMin, reloj.ahora()],
    );
    await notificaciones.enviarCorreo(
      d.correo,
      `MediCheck: ${paciente.nombre} lo invitó como cuidador`,
      `${paciente.nombre} desea que usted reciba avisos cuando no confirme la toma de sus medicamentos.\n\n` +
        `1. Instale MediCheck y cree una cuenta de cuidador con este correo.\n` +
        `2. En "Mis pacientes" acepte la invitación o ingrese el código ${codigo}.`,
    );
    res.status(201).json(rows[0]);
  }),
);

async function activarVinculo(vinculo, idCuidador) {
  const { rows } = await db.query(
    "UPDATE vinculo_cuidador SET id_cuidador = $1, estado = 'activo' WHERE id_vinculo = $2 RETURNING *",
    [idCuidador, vinculo.id_vinculo],
  );
  return rows[0];
}

// RF07: el cuidador acepta una invitación dirigida a su correo
router.patch(
  '/:id/aceptar',
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const yo = (await db.query('SELECT correo FROM usuario WHERE id_usuario = $1', [req.usuario.id])).rows[0];
    const { rows } = await db.query(
      "SELECT * FROM vinculo_cuidador WHERE id_vinculo = $1 AND estado = 'pendiente'",
      [Number(req.params.id)],
    );
    if (!rows.length || rows[0].correo_invitado !== yo.correo) {
      throw new HttpError(404, 'Invitación no encontrada o ya utilizada.');
    }
    res.json(await activarVinculo(rows[0], req.usuario.id));
  }),
);

// RF07 (alternativa): el cuidador ingresa el código recibido
router.post(
  '/unirse',
  exigirRol('cuidador'),
  asincrono(async (req, res) => {
    const { codigo } = validar(req.body, { codigo: { requerido: true, min: 6, max: 6 } });
    const { rows } = await db.query(
      "SELECT * FROM vinculo_cuidador WHERE codigo_invitacion = $1 AND estado = 'pendiente'",
      [codigo.toUpperCase()],
    );
    if (!rows.length) throw new HttpError(404, 'El código no es válido o ya fue utilizado.');
    if (rows[0].id_paciente === req.usuario.id) throw new HttpError(400, 'Código no válido.');
    res.json(await activarVinculo(rows[0], req.usuario.id));
  }),
);

async function vinculoDelUsuario(req) {
  const { rows } = await db.query('SELECT * FROM vinculo_cuidador WHERE id_vinculo = $1', [Number(req.params.id)]);
  const v = rows[0];
  if (!v || (v.id_paciente !== req.usuario.id && v.id_cuidador !== req.usuario.id)) {
    throw new HttpError(404, 'Vínculo no encontrado.');
  }
  return v;
}

// RF08: configurar tiempo de tolerancia y parentesco
router.patch(
  '/:id',
  asincrono(async (req, res) => {
    const v = await vinculoDelUsuario(req);
    const d = validar(req.body, {
      tolerancia_min: { tipo: 'entero', min: 5, max: 240 },
      parentesco: { max: 40 },
    });
    const { rows } = await db.query(
      'UPDATE vinculo_cuidador SET tolerancia_min = $1, parentesco = $2 WHERE id_vinculo = $3 RETURNING *',
      [d.tolerancia_min || v.tolerancia_min, d.parentesco === undefined ? v.parentesco : d.parentesco, v.id_vinculo],
    );
    res.json(rows[0]);
  }),
);

// Revocar el vínculo (cualquiera de las dos partes)
router.delete(
  '/:id',
  asincrono(async (req, res) => {
    const v = await vinculoDelUsuario(req);
    await db.query("UPDATE vinculo_cuidador SET estado = 'revocado' WHERE id_vinculo = $1", [v.id_vinculo]);
    res.status(204).end();
  }),
);

module.exports = router;
