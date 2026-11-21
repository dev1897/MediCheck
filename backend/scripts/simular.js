'use strict';
/**
 * Simulación de extremo a extremo del flujo principal de MediCheck (TRL5:
 * validación del prototipo en un entorno simulado representativo).
 *
 * Levanta la API en un puerto libre con base de datos en memoria, notificaciones
 * simuladas y reloj controlable, y ejecuta por HTTP el escenario completo:
 *   1. Registro de paciente y cuidador (con aceptación de la política de datos).
 *   2. Invitación y aceptación del vínculo con tolerancia de 15 minutos.
 *   3. Registro de un tratamiento cada 8 horas y generación automática de dosis.
 *   4. Escenario A: el paciente confirma la dosis a tiempo -> sin alerta.
 *   5. Escenario B: el paciente no confirma -> dosis omitida y alerta push + correo.
 *   6. Escenario C: confirmaciones sin conexión sincronizadas después.
 *   7. Consulta de adherencia por el cuidador y medición de tiempos de respuesta.
 *
 * Uso: npm run simular      (genera además simulacion-resultados.json)
 */
process.env.NODE_ENV = process.env.NODE_ENV || 'simulacion';
process.env.DB_MODO = 'memoria';
process.env.SIMULACION = 'true';
process.env.CARPETA_BUZON = process.env.CARPETA_BUZON || 'buzon-simulacion';

const fs = require('fs');
const db = require('../src/db');
const { crearApp } = require('../src/app');
const { reloj } = require('../src/utils/comunes');

const tiempos = [];
const pasos = [];
let base = '';

async function api(metodo, ruta, cuerpo, token) {
  const t0 = performance.now();
  const r = await fetch(base + ruta, {
    method: metodo,
    headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    body: cuerpo ? JSON.stringify(cuerpo) : undefined,
  });
  tiempos.push({ ruta: `${metodo} ${ruta.split('?')[0].replace(/\/\d+/g, '/:id')}`, ms: performance.now() - t0 });
  const texto = await r.text();
  const datos = texto ? JSON.parse(texto) : null;
  if (!r.ok) throw new Error(`${metodo} ${ruta} -> ${r.status}: ${JSON.stringify(datos)}`);
  return datos;
}

function verificar(nombre, condicion, detalle = '') {
  pasos.push({ paso: nombre, resultado: condicion ? 'CUMPLE' : 'NO CUMPLE', detalle });
  console.log(`${condicion ? '  [OK]  ' : '  [FALLA]'} ${nombre}${detalle ? ` - ${detalle}` : ''}`);
}

async function main() {
  await db.iniciar();
  const servidor = crearApp().listen(0);
  base = `http://127.0.0.1:${servidor.address().port}`;
  console.log(`\nSimulación MediCheck - API en ${base}\n`);

  // 1. Registro
  const pac = await api('POST', '/api/auth/registro', {
    nombre: 'Paciente Simulado', correo: 'paciente.sim@medicheck.test', telefono: '3000000001',
    contrasena: 'Segura2026', rol: 'paciente', acepta_politica: true,
  });
  const cui = await api('POST', '/api/auth/registro', {
    nombre: 'Cuidador Simulado', correo: 'cuidador.sim@medicheck.test', telefono: '3000000002',
    contrasena: 'Segura2026', rol: 'cuidador', acepta_politica: true,
  });
  verificar('HU01 Registro e inicio de sesión de paciente y cuidador', Boolean(pac.token && cui.token));

  // 2. Vínculo
  const inv = await api('POST', '/api/cuidadores/invitar', { correo: 'cuidador.sim@medicheck.test', parentesco: 'Hija', tolerancia_min: 15 }, pac.token);
  const vinc = await api('PATCH', `/api/cuidadores/${inv.id_vinculo}/aceptar`, null, cui.token);
  verificar('HU02 Vinculación del cuidador por invitación', vinc.estado === 'activo', `tolerancia ${vinc.tolerancia_min} min`);

  // 3. Tratamiento: primera dosis dentro de 10 minutos, cada 8 horas, durante 3 días
  const inicio = new Date(reloj.ahora().getTime() + 10 * 60000);
  const trat = await api('POST', '/api/tratamientos', {
    medicamento: 'Enalapril', dosis: '20 mg', frecuencia_horas: 8,
    fecha_inicio: inicio.toISOString(), fecha_fin: new Date(inicio.getTime() + 3 * 24 * 3600 * 1000).toISOString(),
  }, pac.token);
  verificar('HU03 Registro de tratamiento y generación automática de dosis', trat.dosis_generadas === 10, `${trat.dosis_generadas} dosis generadas en 3 días`);

  const proximas = await api('GET', '/api/dosis/proximas', null, pac.token);
  const [d1, d2, d3, d4] = proximas;
  verificar('HU04 Dosis disponibles para programar recordatorios locales', proximas.length === 10);

  // 4. Escenario A: confirmación a tiempo
  reloj.avanzar(12); // 2 minutos después de la hora programada
  const conf = await api('PATCH', `/api/dosis/${d1.id_dosis}/confirmar`, { origen: 'notificacion' }, pac.token);
  reloj.avanzar(20);
  const cicloA = await api('POST', '/api/simulacion/planificador');
  verificar('HU05 Escenario A: confirmación a tiempo sin alerta', conf.estado === 'tomada' && cicloA.alertas === 0);

  // 5. Escenario B: dosis 2 sin confirmar (8 h después)
  const hastaD2 = new Date(d2.fecha_hora).getTime() - reloj.ahora().getTime();
  reloj.avanzar(Math.ceil(hastaD2 / 60000) + 14); // 14 min: aún dentro de la tolerancia
  const cicloB1 = await api('POST', '/api/simulacion/planificador');
  verificar('HU06 Dentro de la tolerancia no se alerta', cicloB1.omitidas === 0);
  reloj.avanzar(1); // se cumple la tolerancia de 15 minutos
  const t0 = performance.now();
  const cicloB2 = await api('POST', '/api/simulacion/planificador');
  const latenciaAlertaMs = performance.now() - t0;
  const alertas = await api('GET', '/api/alertas', null, cui.token);
  const buzon = await api('GET', '/api/simulacion/buzon');
  const correoAlerta = buzon.find((c) => c.para === 'cuidador.sim@medicheck.test' && /no confirmó/.test(c.asunto));
  verificar(
    'HU06 Escenario B: dosis omitida genera alerta push y correo',
    cicloB2.omitidas === 1 && cicloB2.alertas === 2 && alertas.length === 1 && Boolean(correoAlerta),
    `procesada en ${latenciaAlertaMs.toFixed(0)} ms tras vencer la tolerancia`,
  );

  // Confirmación tardía de la dosis omitida
  const tarde = await api('PATCH', `/api/dosis/${d2.id_dosis}/confirmar`, {}, pac.token);
  verificar('Confirmación tardía queda registrada como tomada tarde', tarde.estado === 'tomada' && tarde.confirmada_tarde === true);

  // 6. Escenario C: sin conexión; confirmaciones guardadas en el dispositivo y sincronizadas
  const hastaD3 = new Date(d3.fecha_hora).getTime() - reloj.ahora().getTime();
  reloj.avanzar(Math.ceil(hastaD3 / 60000) + 3);
  const confOffline3 = reloj.ahora().toISOString();
  const hastaD4 = new Date(d4.fecha_hora).getTime() - reloj.ahora().getTime();
  reloj.avanzar(Math.ceil(hastaD4 / 60000) + 4);
  const confOffline4 = reloj.ahora().toISOString();
  const sinc = await api('POST', '/api/dosis/sincronizar', {
    confirmaciones: [
      { id_dosis: d3.id_dosis, fecha_confirmacion: confOffline3 },
      { id_dosis: d4.id_dosis, fecha_confirmacion: confOffline4 },
    ],
  }, pac.token);
  const resincronizado = await api('POST', '/api/dosis/sincronizar', {
    confirmaciones: [{ id_dosis: d3.id_dosis, fecha_confirmacion: confOffline3 }],
  }, pac.token);
  verificar(
    'RF12 Escenario C: sincronización de confirmaciones sin conexión (idempotente)',
    sinc.resultados.every((r) => r.ok && r.estado === 'tomada') && resincronizado.resultados[0].ok,
    `${sinc.procesadas} confirmaciones sincronizadas`,
  );

  // 7. Panel del cuidador y adherencia
  const panel = await api('GET', '/api/pacientes', null, cui.token);
  const adh = await api('GET', `/api/pacientes/${pac.usuario.id_usuario}/adherencia?dias=7`, null, cui.token);
  verificar('HU07 Panel del cuidador con el resumen del paciente', panel.length === 1);
  verificar('HU08 Historial y porcentaje de adherencia', adh.evaluadas === 4 && adh.porcentaje === 100, `${adh.tomadas}/${adh.evaluadas} dosis tomadas (${adh.porcentaje} %)`);

  // Seguridad: un tercero no puede consultar al paciente
  const otro = await api('POST', '/api/auth/registro', {
    nombre: 'Cuidador No Autorizado', correo: 'otro@medicheck.test', contrasena: 'Segura2026', rol: 'cuidador', acepta_politica: true,
  });
  let denegado = false;
  try {
    await api('GET', `/api/pacientes/${pac.usuario.id_usuario}/adherencia`, null, otro.token);
  } catch (e) {
    denegado = /403/.test(e.message);
  }
  verificar('RNF04 Un cuidador no vinculado no accede a los datos del paciente', denegado);

  // Tiempos de respuesta (RNF02)
  const ms = tiempos.map((t) => t.ms).sort((a, b) => a - b);
  const p95 = ms[Math.min(ms.length - 1, Math.ceil(ms.length * 0.95) - 1)];
  verificar('RNF02 El 95 % de las solicitudes responde en menos de 2 s', p95 < 2000, `p95 = ${p95.toFixed(1)} ms en ${ms.length} solicitudes`);

  const cumplidos = pasos.filter((p) => p.resultado === 'CUMPLE').length;
  const resumen = {
    fecha_ejecucion: new Date().toISOString(),
    entorno: { node: process.version, base_datos: 'PostgreSQL emulado (pg-mem)', notificaciones: 'simuladas' },
    pasos,
    cumplidos,
    total: pasos.length,
    tiempos: {
      solicitudes: ms.length,
      promedio_ms: Number((ms.reduce((a, b) => a + b, 0) / ms.length).toFixed(1)),
      p95_ms: Number(p95.toFixed(1)),
      maximo_ms: Number(ms[ms.length - 1].toFixed(1)),
      latencia_alerta_ms: Number(latenciaAlertaMs.toFixed(1)),
    },
  };
  fs.writeFileSync('simulacion-resultados.json', JSON.stringify(resumen, null, 2));
  console.log(`\nResultado: ${cumplidos}/${pasos.length} verificaciones cumplidas. Detalle en simulacion-resultados.json\n`);

  servidor.close();
  await db.cerrar();
  process.exit(cumplidos === pasos.length ? 0 : 1);
}

main().catch(async (e) => {
  console.error('\nLa simulación falló:', e.message);
  process.exit(1);
});
