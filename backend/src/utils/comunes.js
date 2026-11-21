'use strict';
const config = require('../config');

// ---------------------------------------------------------------------------
// Reloj del sistema. En modo simulación permite adelantar el tiempo para
// demostrar el vencimiento de la tolerancia sin esperar minutos reales.
// ---------------------------------------------------------------------------
let desfaseMs = 0;
const reloj = {
  ahora: () => new Date(Date.now() + desfaseMs),
  avanzar: (minutos) => {
    desfaseMs += minutos * 60 * 1000;
    return desfaseMs / 60000;
  },
  reiniciar: () => {
    desfaseMs = 0;
  },
  desfaseMinutos: () => desfaseMs / 60000,
};

// ---------------------------------------------------------------------------
// Errores HTTP
// ---------------------------------------------------------------------------
class HttpError extends Error {
  constructor(estado, mensaje, detalles) {
    super(mensaje);
    this.estado = estado;
    this.detalles = detalles;
  }
}

/** Envuelve controladores async para que los errores lleguen al middleware de errores. */
const asincrono = (fn) => (req, res, next) => Promise.resolve(fn(req, res, next)).catch(next);

// ---------------------------------------------------------------------------
// Validación de entradas
// ---------------------------------------------------------------------------
const CORREO_RE = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

/**
 * Valida un objeto según reglas simples y devuelve solo los campos permitidos.
 * reglas: { campo: { requerido, tipo: 'texto'|'entero'|'fecha'|'correo'|'booleano', min, max, valores } }
 */
function validar(datos, reglas) {
  const errores = [];
  const limpio = {};
  for (const [campo, r] of Object.entries(reglas)) {
    let v = datos ? datos[campo] : undefined;
    if (typeof v === 'string') v = v.trim();
    if (v === undefined || v === null || v === '') {
      if (r.requerido) errores.push(`El campo "${campo}" es obligatorio.`);
      continue;
    }
    if (r.tipo === 'entero') {
      const n = Number(v);
      if (!Number.isInteger(n)) { errores.push(`"${campo}" debe ser un número entero.`); continue; }
      if (r.min !== undefined && n < r.min) { errores.push(`"${campo}" debe ser mayor o igual a ${r.min}.`); continue; }
      if (r.max !== undefined && n > r.max) { errores.push(`"${campo}" debe ser menor o igual a ${r.max}.`); continue; }
      v = n;
    } else if (r.tipo === 'fecha') {
      const f = new Date(v);
      if (Number.isNaN(f.getTime())) { errores.push(`"${campo}" debe ser una fecha válida (ISO 8601).`); continue; }
      v = f;
    } else if (r.tipo === 'correo') {
      if (!CORREO_RE.test(String(v))) { errores.push(`"${campo}" no es un correo válido.`); continue; }
      v = String(v).toLowerCase();
    } else if (r.tipo === 'booleano') {
      if (typeof v !== 'boolean') { errores.push(`"${campo}" debe ser verdadero o falso.`); continue; }
    } else {
      v = String(v);
      if (r.min !== undefined && v.length < r.min) { errores.push(`"${campo}" debe tener al menos ${r.min} caracteres.`); continue; }
      if (r.max !== undefined && v.length > r.max) { errores.push(`"${campo}" admite máximo ${r.max} caracteres.`); continue; }
    }
    if (r.valores && !r.valores.includes(v)) {
      errores.push(`"${campo}" debe ser uno de: ${r.valores.join(', ')}.`);
      continue;
    }
    limpio[campo] = v;
  }
  if (errores.length) throw new HttpError(400, 'Datos inválidos.', errores);
  return limpio;
}

// ---------------------------------------------------------------------------
// Fechas en la zona horaria configurada (Colombia, UTC-5)
// ---------------------------------------------------------------------------
function desfaseZonaMin() {
  const [, signo, hh, mm] = config.zonaHoraria.match(/([+-])(\d{2}):(\d{2})/);
  return (signo === '-' ? -1 : 1) * (Number(hh) * 60 + Number(mm));
}

/** Rango [inicio, fin) de un día AAAA-MM-DD. */
function rangoDelDia(fechaTexto) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(fechaTexto || '')) return null;
  const inicio = new Date(`${fechaTexto}T00:00:00${config.zonaHoraria}`);
  if (Number.isNaN(inicio.getTime())) return null;
  return { inicio, fin: new Date(inicio.getTime() + 24 * 3600 * 1000) };
}

/** Fecha local AAAA-MM-DD de un instante. */
const fechaLocal = (instante) =>
  new Date(new Date(instante).getTime() + desfaseZonaMin() * 60000).toISOString().slice(0, 10);

/** Hora local HH:MM de un instante. */
const horaLocal = (instante) =>
  new Date(new Date(instante).getTime() + desfaseZonaMin() * 60000).toISOString().slice(11, 16);

module.exports = { reloj, HttpError, asincrono, validar, rangoDelDia, fechaLocal, horaLocal };
