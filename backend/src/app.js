'use strict';
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const config = require('./config');
const { HttpError, reloj } = require('./utils/comunes');

function crearApp() {
  const app = express();
  app.use(helmet());
  app.use(cors());
  app.use(express.json({ limit: '100kb' }));

  app.get('/api/salud', (req, res) => {
    res.json({
      servicio: 'MediCheck API',
      version: '1.0.0',
      estado: 'ok',
      base_datos: config.dbModo,
      push: config.pushModo,
      correo: config.correoModo,
      simulacion: config.simulacion,
      ahora: reloj.ahora(),
    });
  });

  app.use('/api/auth', require('./routes/auth.routes'));
  app.use('/api/tratamientos', require('./routes/tratamientos.routes'));
  app.use('/api/dosis', require('./routes/dosis.routes').router);
  app.use('/api/cuidadores', require('./routes/cuidadores.routes'));
  app.use('/api', require('./routes/pacientes.routes'));
  if (config.simulacion) app.use('/api/simulacion', require('./routes/simulacion.routes'));

  app.use((req, res, next) => next(new HttpError(404, `Ruta no encontrada: ${req.method} ${req.path}`)));

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err.type === 'entity.parse.failed') {
      return res.status(400).json({ error: 'El cuerpo de la solicitud no es un JSON válido.' });
    }
    const estado = err.estado || 500;
    if (estado === 500) console.error(err);
    return res.status(estado).json({
      error: estado === 500 ? 'Error interno del servidor.' : err.message,
      ...(err.detalles ? { detalles: err.detalles } : {}),
    });
  });

  return app;
}

module.exports = { crearApp };
