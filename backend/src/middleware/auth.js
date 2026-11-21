'use strict';
const jwt = require('jsonwebtoken');
const config = require('../config');
const db = require('../db');
const { HttpError } = require('../utils/comunes');

function firmarToken(usuario) {
  return jwt.sign({ sub: usuario.id_usuario, rol: usuario.rol }, config.jwtSecreto, {
    expiresIn: config.jwtExpira,
  });
}

/** Exige un token JWT válido en el encabezado Authorization: Bearer <token>. */
function autenticar(req, res, next) {
  const encabezado = req.headers.authorization || '';
  const [tipo, token] = encabezado.split(' ');
  if (tipo !== 'Bearer' || !token) return next(new HttpError(401, 'Debe iniciar sesión.'));
  try {
    const datos = jwt.verify(token, config.jwtSecreto);
    req.usuario = { id: Number(datos.sub), rol: datos.rol };
    return next();
  } catch {
    return next(new HttpError(401, 'La sesión expiró o el token no es válido.'));
  }
}

/** Restringe una ruta a uno o varios roles. */
const exigirRol = (...roles) => (req, res, next) =>
  roles.includes(req.usuario.rol) ? next() : next(new HttpError(403, 'No tiene permiso para esta acción.'));

/**
 * Determina sobre qué paciente actúa la solicitud (RNF04):
 *  - Un paciente solo puede actuar sobre sí mismo.
 *  - Un cuidador debe indicar id_paciente y tener un vínculo ACTIVO con él.
 */
async function resolverPaciente(req, idPacienteSolicitado) {
  if (req.usuario.rol === 'paciente') return req.usuario.id;
  const id = Number(idPacienteSolicitado);
  if (!Number.isInteger(id)) throw new HttpError(400, 'Debe indicar el paciente (id_paciente).');
  const { rows } = await db.query(
    "SELECT 1 FROM vinculo_cuidador WHERE id_paciente = $1 AND id_cuidador = $2 AND estado = 'activo'",
    [id, req.usuario.id],
  );
  if (!rows.length) throw new HttpError(403, 'No está autorizado para consultar este paciente.');
  return id;
}

module.exports = { firmarToken, autenticar, exigirRol, resolverPaciente };
