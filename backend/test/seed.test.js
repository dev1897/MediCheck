'use strict';
process.env.NODE_ENV = 'test';
process.env.DB_MODO = 'memoria';

const { test, after } = require('node:test');
const assert = require('node:assert/strict');
const request = require('supertest');
const db = require('../src/db');
const { crearApp } = require('../src/app');
const { sembrar } = require('../scripts/seed');

after(() => db.cerrar());

test('los datos de demostración permiten iniciar sesión y consultar el historial', async () => {
  await sembrar();
  await sembrar(); // idempotente
  const app = crearApp();
  const login = await request(app)
    .post('/api/auth/login')
    .send({ correo: 'cuidador@medicheck.demo', contrasena: 'Demo1234' })
    .expect(200);
  const pacientes = await request(app).get('/api/pacientes').set('Authorization', `Bearer ${login.body.token}`);
  assert.equal(pacientes.body.length, 1);
  const adh = await request(app)
    .get(`/api/pacientes/${pacientes.body[0].id_paciente}/adherencia?dias=7`)
    .set('Authorization', `Bearer ${login.body.token}`);
  assert.ok(adh.body.evaluadas > 30);
  assert.ok(adh.body.porcentaje > 80 && adh.body.porcentaje < 100);
});
