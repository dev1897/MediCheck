'use strict';
process.env.NODE_ENV = 'test';
process.env.DB_MODO = 'memoria';
process.env.SIMULACION = 'true';

const { test, describe, before, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const db = require('../src/db');
const { crearApp } = require('../src/app');
const { reloj } = require('../src/utils/comunes');
const planificador = require('../src/services/planificador.service');
const { buzonSimulado } = require('../src/services/notificaciones.service');

let app;
const ctx = {};

const registrar = (datos) =>
  request(app).post('/api/auth/registro').send({ contrasena: 'Clave2026', acepta_politica: true, ...datos });

before(async () => {
  await db.iniciar();
  app = crearApp();
});
after(() => db.cerrar());

describe('Autenticación (RF01, RF02, RF13)', () => {
  test('registra un paciente y devuelve un token JWT', async () => {
    const r = await registrar({ nombre: 'Ana Paciente', correo: 'ana@test.co', rol: 'paciente' });
    assert.equal(r.status, 201);
    assert.ok(r.body.token);
    assert.equal(r.body.usuario.rol, 'paciente');
    assert.equal(r.body.usuario.contrasena_hash, undefined);
    ctx.paciente = r.body;
  });

  test('exige aceptar la política de datos personales', async () => {
    const r = await registrar({ nombre: 'Sin Política', correo: 'x@test.co', rol: 'paciente', acepta_politica: false });
    assert.equal(r.status, 400);
  });

  test('rechaza un correo duplicado', async () => {
    const r = await registrar({ nombre: 'Ana Otra', correo: 'ANA@test.co', rol: 'paciente' });
    assert.equal(r.status, 409);
  });

  test('valida los campos obligatorios', async () => {
    const r = await request(app).post('/api/auth/registro').send({ correo: 'malo' });
    assert.equal(r.status, 400);
    assert.ok(r.body.detalles.length >= 3);
  });

  test('inicia sesión con credenciales correctas y rechaza las incorrectas', async () => {
    const ok = await request(app).post('/api/auth/login').send({ correo: 'ana@test.co', contrasena: 'Clave2026' });
    assert.equal(ok.status, 200);
    const mal = await request(app).post('/api/auth/login').send({ correo: 'ana@test.co', contrasena: 'otra-clave' });
    assert.equal(mal.status, 401);
  });

  test('bloquea las rutas protegidas sin token', async () => {
    const r = await request(app).get('/api/tratamientos');
    assert.equal(r.status, 401);
  });

  test('recupera la contraseña con el código enviado por correo', async () => {
    await request(app).post('/api/auth/recuperar').send({ correo: 'ana@test.co' }).expect(200);
    const correo = buzonSimulado.find((c) => c.para === 'ana@test.co');
    const codigo = correo.texto.match(/\d{6}/)[0];
    await request(app)
      .post('/api/auth/restablecer')
      .send({ correo: 'ana@test.co', codigo, nueva_contrasena: 'Nueva2026' })
      .expect(200);
    await request(app).post('/api/auth/login').send({ correo: 'ana@test.co', contrasena: 'Nueva2026' }).expect(200);
  });
});

describe('Vínculo con cuidador (RF07, RF08)', () => {
  test('el paciente invita y el cuidador acepta', async () => {
    const c = await registrar({ nombre: 'Luis Cuidador', correo: 'luis@test.co', rol: 'cuidador' });
    ctx.cuidador = c.body;
    const inv = await request(app)
      .post('/api/cuidadores/invitar')
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ correo: 'luis@test.co', parentesco: 'Esposo', tolerancia_min: 20 });
    assert.equal(inv.status, 201);
    assert.match(inv.body.codigo_invitacion, /^[A-Z2-9]{6}$/);

    const lista = await request(app).get('/api/cuidadores').set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(lista.body.length, 1);
    assert.equal(lista.body[0].codigo_invitacion, undefined, 'el cuidador no debe ver el código');

    const acep = await request(app)
      .patch(`/api/cuidadores/${inv.body.id_vinculo}/aceptar`)
      .set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(acep.body.estado, 'activo');
    ctx.vinculo = acep.body;
  });

  test('un paciente no puede aceptar invitaciones (control por rol)', async () => {
    const r = await request(app)
      .patch(`/api/cuidadores/${ctx.vinculo.id_vinculo}/aceptar`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`);
    assert.equal(r.status, 403);
  });

  test('el cuidador se vincula con el código de invitación', async () => {
    const p2 = await registrar({ nombre: 'Pedro Paciente', correo: 'pedro@test.co', rol: 'paciente' });
    ctx.paciente2 = p2.body;
    const inv = await request(app)
      .post('/api/cuidadores/invitar')
      .set('Authorization', `Bearer ${p2.body.token}`)
      .send({ correo: 'otro.correo@test.co' });
    const r = await request(app)
      .post('/api/cuidadores/unirse')
      .set('Authorization', `Bearer ${ctx.cuidador.token}`)
      .send({ codigo: inv.body.codigo_invitacion.toLowerCase() });
    assert.equal(r.status, 200);
    assert.equal(r.body.estado, 'activo');
  });

  test('configura el tiempo de tolerancia dentro de los límites', async () => {
    const ok = await request(app)
      .patch(`/api/cuidadores/${ctx.vinculo.id_vinculo}`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ tolerancia_min: 15 });
    assert.equal(ok.body.tolerancia_min, 15);
    const mal = await request(app)
      .patch(`/api/cuidadores/${ctx.vinculo.id_vinculo}`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ tolerancia_min: 1 });
    assert.equal(mal.status, 400);
  });
});

describe('Tratamientos y dosis (RF03 a RF06)', () => {
  test('crea un tratamiento y genera sus dosis', async () => {
    const inicio = new Date(reloj.ahora().getTime() + 30 * 60000);
    const r = await request(app)
      .post('/api/tratamientos')
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ medicamento: 'Amlodipino', dosis: '5 mg', frecuencia_horas: 24, fecha_inicio: inicio.toISOString() });
    assert.equal(r.status, 201);
    assert.equal(r.body.dosis_generadas, 7); // horizonte de 7 días: +0,5 h, +24,5 h ... +144,5 h
    ctx.tratamiento = r.body;
  });

  test('rechaza una fecha de fin anterior al inicio', async () => {
    const r = await request(app)
      .post('/api/tratamientos')
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ medicamento: 'X', dosis: '1', frecuencia_horas: 8, fecha_inicio: '2026-12-10T10:00:00Z', fecha_fin: '2026-12-01T10:00:00Z' });
    assert.equal(r.status, 400);
  });

  test('el cuidador vinculado puede registrar tratamientos del paciente', async () => {
    const r = await request(app)
      .post('/api/tratamientos')
      .set('Authorization', `Bearer ${ctx.cuidador.token}`)
      .send({ id_paciente: ctx.paciente.usuario.id_usuario, medicamento: 'Atorvastatina', dosis: '20 mg', frecuencia_horas: 24, fecha_inicio: new Date(reloj.ahora().getTime() + 3600000).toISOString() });
    assert.equal(r.status, 201);
    ctx.tratamientoCuidador = r.body;
  });

  test('un tercero no puede ver tratamientos ajenos', async () => {
    const r = await request(app)
      .get(`/api/tratamientos?id_paciente=${ctx.paciente.usuario.id_usuario}`)
      .set('Authorization', `Bearer ${ctx.paciente2.token}`);
    // Un paciente solo ve los suyos: la lista de Pedro no incluye los tratamientos de Ana
    assert.equal(r.body.length, 0);
  });

  test('suspender un tratamiento elimina sus dosis futuras', async () => {
    const r = await request(app)
      .put(`/api/tratamientos/${ctx.tratamientoCuidador.id_tratamiento}`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ activo: false });
    assert.equal(r.body.activo, false);
    assert.equal(r.body.dosis_generadas, 0);
  });

  test('elimina un tratamiento', async () => {
    await request(app)
      .delete(`/api/tratamientos/${ctx.tratamientoCuidador.id_tratamiento}`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .expect(204);
  });

  test('confirma una dosis con un solo toque', async () => {
    const prox = await request(app).get('/api/dosis/proximas').set('Authorization', `Bearer ${ctx.paciente.token}`);
    ctx.dosis = prox.body;
    reloj.avanzar(31);
    const r = await request(app)
      .patch(`/api/dosis/${ctx.dosis[0].id_dosis}/confirmar`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({});
    assert.equal(r.status, 200);
    assert.equal(r.body.estado, 'tomada');
    assert.equal(r.body.confirmada_tarde, false);
  });

  test('no permite confirmar con más de dos horas de anticipación', async () => {
    const r = await request(app)
      .patch(`/api/dosis/${ctx.dosis[3].id_dosis}/confirmar`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({});
    assert.equal(r.status, 409);
  });

  test('consulta las dosis del día', async () => {
    const r = await request(app).get('/api/dosis').set('Authorization', `Bearer ${ctx.paciente.token}`);
    assert.equal(r.status, 200);
    assert.ok(Array.isArray(r.body));
  });
});

describe('Planificador, alertas y adherencia (RF09 a RF11)', () => {
  test('marca la dosis no confirmada como omitida y alerta al cuidador', async () => {
    const segunda = ctx.dosis[1];
    reloj.avanzar((new Date(segunda.fecha_hora) - reloj.ahora()) / 60000 + 16);
    const ciclo = await planificador.ejecutarCiclo();
    assert.equal(ciclo.omitidas, 1);
    assert.equal(ciclo.alertas, 2); // push + correo
    const alertas = await request(app).get('/api/alertas').set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(alertas.body.length, 1);
    assert.equal(alertas.body[0].medicamento, 'Amlodipino');
    ctx.alerta = alertas.body[0];
  });

  test('no duplica alertas en ciclos posteriores', async () => {
    const ciclo = await planificador.ejecutarCiclo();
    assert.equal(ciclo.omitidas, 0);
  });

  test('marca una alerta como leída', async () => {
    const r = await request(app)
      .patch(`/api/alertas/${ctx.alerta.id_alerta}/leida`)
      .set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(r.body.leida, true);
  });

  test('el cuidador consulta el panel y la adherencia del paciente', async () => {
    const panel = await request(app).get('/api/pacientes').set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(panel.body.length, 2);
    const adh = await request(app)
      .get(`/api/pacientes/${ctx.paciente.usuario.id_usuario}/adherencia?dias=30`)
      .set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(adh.body.tomadas, 1);
    assert.equal(adh.body.omitidas, 1);
    assert.equal(adh.body.porcentaje, 50);
  });

  test('el paciente consulta su propia adherencia', async () => {
    const r = await request(app).get('/api/adherencia?dias=7').set('Authorization', `Bearer ${ctx.paciente.token}`);
    assert.equal(r.body.porcentaje, 50);
  });

  test('sincroniza confirmaciones sin conexión, incluida una dosis omitida', async () => {
    const r = await request(app)
      .post('/api/dosis/sincronizar')
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .send({ confirmaciones: [{ id_dosis: ctx.dosis[1].id_dosis, fecha_confirmacion: reloj.ahora().toISOString() }, { id_dosis: 99999, fecha_confirmacion: reloj.ahora().toISOString() }] });
    assert.equal(r.body.resultados[0].ok, true);
    assert.equal(r.body.resultados[0].confirmada_tarde, true);
    assert.equal(r.body.resultados[1].ok, false);
  });

  test('un cuidador revocado pierde el acceso', async () => {
    await request(app)
      .delete(`/api/cuidadores/${ctx.vinculo.id_vinculo}`)
      .set('Authorization', `Bearer ${ctx.paciente.token}`)
      .expect(204);
    const r = await request(app)
      .get(`/api/pacientes/${ctx.paciente.usuario.id_usuario}/dosis`)
      .set('Authorization', `Bearer ${ctx.cuidador.token}`);
    assert.equal(r.status, 403);
  });
});

describe('Servicios generales', () => {
  test('responde el estado de salud de la API', async () => {
    const r = await request(app).get('/api/salud');
    assert.equal(r.body.estado, 'ok');
  });

  test('devuelve 404 en rutas inexistentes y 400 con JSON inválido', async () => {
    await request(app).get('/api/no-existe').expect(404);
    await request(app).post('/api/auth/login').set('Content-Type', 'application/json').send('{malo').expect(400);
  });
});
