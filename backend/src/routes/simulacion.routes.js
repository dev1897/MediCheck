'use strict';
/**
 * Endpoints de simulación (solo si SIMULACION=true). Permiten demostrar el
 * prototipo en un entorno controlado sin esperar los tiempos reales:
 *  - adelantar el reloj del sistema,
 *  - ejecutar de inmediato el ciclo del planificador de alertas,
 *  - consultar los correos generados en modo simulado.
 */
const express = require('express');
const { asincrono, validar, reloj } = require('../utils/comunes');
const planificador = require('../services/planificador.service');
const { buzonSimulado } = require('../services/notificaciones.service');

const router = express.Router();

router.get('/estado', (req, res) => {
  res.json({ ahora: reloj.ahora(), desfase_minutos: reloj.desfaseMinutos() });
});

router.post(
  '/avanzar',
  asincrono(async (req, res) => {
    const { minutos } = validar(req.body, { minutos: { requerido: true, tipo: 'entero', min: 1, max: 1440 } });
    reloj.avanzar(minutos);
    const ciclo = await planificador.ejecutarCiclo();
    res.json({ ahora: reloj.ahora(), desfase_minutos: reloj.desfaseMinutos(), ciclo });
  }),
);

router.post('/reiniciar-reloj', (req, res) => {
  reloj.reiniciar();
  res.json({ ahora: reloj.ahora(), desfase_minutos: 0 });
});

router.post(
  '/planificador',
  asincrono(async (req, res) => {
    res.json(await planificador.ejecutarCiclo());
  }),
);

router.get('/buzon', (req, res) => {
  res.json([...buzonSimulado].reverse());
});

module.exports = router;
