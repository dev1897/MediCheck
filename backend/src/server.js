'use strict';
const config = require('./config');
const db = require('./db');
const { crearApp } = require('./app');
const planificador = require('./services/planificador.service');

async function main() {
  await db.iniciar();
  if (process.argv.includes('--seed') || process.env.SEED === 'true') {
    await require('../scripts/seed').sembrar();
  }
  const app = crearApp();
  app.listen(config.puerto, () => {
    console.log('==============================================');
    console.log(` MediCheck API escuchando en http://localhost:${config.puerto}`);
    console.log(` Base de datos: ${config.dbModo} | Push: ${config.pushModo} | Correo: ${config.correoModo}`);
    console.log(` Simulación: ${config.simulacion ? 'habilitada' : 'deshabilitada'}`);
    console.log('==============================================');
  });
  planificador.iniciar();
}

main().catch((e) => {
  console.error('No fue posible iniciar el servidor:', e);
  process.exit(1);
});
