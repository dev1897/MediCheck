'use strict';
const crypto = require('crypto');
const express = require('express');
const bcrypt = require('bcryptjs');
const db = require('../db');
const { firmarToken, autenticar } = require('../middleware/auth');
const { asincrono, validar, HttpError, reloj } = require('../utils/comunes');
const notificaciones = require('../services/notificaciones.service');

const router = express.Router();
const COSTO_BCRYPT = 10;

const usuarioPublico = (u) => ({
  id_usuario: u.id_usuario,
  nombre: u.nombre,
  correo: u.correo,
  telefono: u.telefono,
  rol: u.rol,
  fecha_registro: u.fecha_registro,
});

// RF01 + RF13: registro con aceptación expresa de la política de datos (Ley 1581 de 2012)
router.post(
  '/registro',
  asincrono(async (req, res) => {
    const datos = validar(req.body, {
      nombre: { requerido: true, min: 3, max: 120 },
      correo: { requerido: true, tipo: 'correo' },
      telefono: { max: 20 },
      contrasena: { requerido: true, min: 8, max: 72 },
      rol: { requerido: true, valores: ['paciente', 'cuidador'] },
      acepta_politica: { requerido: true, tipo: 'booleano' },
    });
    if (!datos.acepta_politica) {
      throw new HttpError(400, 'Debe aceptar la política de tratamiento de datos personales.');
    }
    const existe = await db.query('SELECT 1 FROM usuario WHERE correo = $1', [datos.correo]);
    if (existe.rows.length) throw new HttpError(409, 'Ya existe una cuenta con ese correo.');

    const hash = await bcrypt.hash(datos.contrasena, COSTO_BCRYPT);
    const ahora = reloj.ahora();
    const { rows } = await db.query(
      `INSERT INTO usuario (nombre, correo, telefono, contrasena_hash, rol, acepta_politica_fecha, fecha_registro)
       VALUES ($1, $2, $3, $4, $5, $6, $7) RETURNING *`,
      [datos.nombre, datos.correo, datos.telefono || null, hash, datos.rol, ahora, ahora],
    );
    const usuario = rows[0];
    res.status(201).json({ token: firmarToken(usuario), usuario: usuarioPublico(usuario) });
  }),
);

// RF02: inicio de sesión
router.post(
  '/login',
  asincrono(async (req, res) => {
    const datos = validar(req.body, {
      correo: { requerido: true, tipo: 'correo' },
      contrasena: { requerido: true },
    });
    const { rows } = await db.query('SELECT * FROM usuario WHERE correo = $1', [datos.correo]);
    const usuario = rows[0];
    const valido = usuario && (await bcrypt.compare(datos.contrasena, usuario.contrasena_hash));
    if (!valido) throw new HttpError(401, 'Correo o contraseña incorrectos.');
    res.json({ token: firmarToken(usuario), usuario: usuarioPublico(usuario) });
  }),
);

// RF02: recuperación de contraseña (código de 6 dígitos enviado por correo, válido 15 minutos)
router.post(
  '/recuperar',
  asincrono(async (req, res) => {
    const { correo } = validar(req.body, { correo: { requerido: true, tipo: 'correo' } });
    const { rows } = await db.query('SELECT * FROM usuario WHERE correo = $1', [correo]);
    if (rows.length) {
      const codigo = String(crypto.randomInt(100000, 1000000));
      const expira = new Date(reloj.ahora().getTime() + 15 * 60000);
      await db.query(
        'UPDATE usuario SET codigo_recuperacion_hash = $1, codigo_recuperacion_expira = $2 WHERE id_usuario = $3',
        [await bcrypt.hash(codigo, COSTO_BCRYPT), expira, rows[0].id_usuario],
      );
      await notificaciones.enviarCorreo(
        correo,
        'MediCheck: código para restablecer su contraseña',
        `Su código de recuperación es ${codigo}. Vence en 15 minutos.`,
      );
    }
    // Respuesta idéntica exista o no la cuenta, para no revelar qué correos están registrados
    res.json({ mensaje: 'Si el correo está registrado, recibirá un código de recuperación.' });
  }),
);

router.post(
  '/restablecer',
  asincrono(async (req, res) => {
    const datos = validar(req.body, {
      correo: { requerido: true, tipo: 'correo' },
      codigo: { requerido: true, min: 6, max: 6 },
      nueva_contrasena: { requerido: true, min: 8, max: 72 },
    });
    const { rows } = await db.query('SELECT * FROM usuario WHERE correo = $1', [datos.correo]);
    const u = rows[0];
    const vigente =
      u &&
      u.codigo_recuperacion_hash &&
      new Date(u.codigo_recuperacion_expira) > reloj.ahora() &&
      (await bcrypt.compare(datos.codigo, u.codigo_recuperacion_hash));
    if (!vigente) throw new HttpError(400, 'El código no es válido o ya venció.');
    await db.query(
      `UPDATE usuario SET contrasena_hash = $1, codigo_recuperacion_hash = NULL,
              codigo_recuperacion_expira = NULL WHERE id_usuario = $2`,
      [await bcrypt.hash(datos.nueva_contrasena, COSTO_BCRYPT), u.id_usuario],
    );
    res.json({ mensaje: 'Contraseña actualizada. Ya puede iniciar sesión.' });
  }),
);

router.get(
  '/perfil',
  autenticar,
  asincrono(async (req, res) => {
    const { rows } = await db.query('SELECT * FROM usuario WHERE id_usuario = $1', [req.usuario.id]);
    if (!rows.length) throw new HttpError(404, 'Usuario no encontrado.');
    res.json(usuarioPublico(rows[0]));
  }),
);

// Registro del token del dispositivo para notificaciones push (FCM)
router.put(
  '/token-push',
  autenticar,
  asincrono(async (req, res) => {
    const { token_push: token } = validar(req.body, { token_push: { requerido: true, max: 4096 } });
    await db.query('UPDATE usuario SET token_push = $1 WHERE id_usuario = $2', [token, req.usuario.id]);
    res.json({ mensaje: 'Dispositivo registrado.' });
  }),
);

module.exports = router;
