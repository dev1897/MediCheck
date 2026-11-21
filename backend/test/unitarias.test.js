'use strict';
process.env.NODE_ENV = 'test';

const { test, describe } = require('node:test');
const assert = require('node:assert/strict');
const { calcularHorarios } = require('../src/services/dosis.service');
const { calcularPorcentaje, serieDiaria } = require('../src/services/adherencia.service');
const { estaVencida, toleranciaEfectiva } = require('../src/services/planificador.service');
const { validar, rangoDelDia, fechaLocal, horaLocal } = require('../src/utils/comunes');

const H = 3600 * 1000;

describe('Generación de dosis (RF04)', () => {
  const inicio = new Date('2026-11-01T12:00:00Z');

  test('genera dosis cada 8 horas dentro del rango', () => {
    const r = calcularHorarios({ fechaInicio: inicio, frecuenciaHoras: 8 }, inicio, new Date(inicio.getTime() + 24 * H));
    assert.equal(r.length, 4); // 0, 8, 16 y 24 horas
    assert.equal(r[1].getTime() - r[0].getTime(), 8 * H);
  });

  test('respeta la fecha de fin del tratamiento', () => {
    const r = calcularHorarios(
      { fechaInicio: inicio, frecuenciaHoras: 12, fechaFin: new Date(inicio.getTime() + 30 * H) },
      inicio,
      new Date(inicio.getTime() + 100 * H),
    );
    assert.equal(r.length, 3); // 0, 12 y 24 horas
  });

  test('alinea las dosis con la fecha de inicio cuando el rango empieza después', () => {
    const desde = new Date(inicio.getTime() + 5 * H);
    const r = calcularHorarios({ fechaInicio: inicio, frecuenciaHoras: 8 }, desde, new Date(inicio.getTime() + 20 * H));
    assert.deepEqual(r.map((d) => (d.getTime() - inicio.getTime()) / H), [8, 16]);
  });

  test('no genera dosis antes de la fecha de inicio', () => {
    const r = calcularHorarios(
      { fechaInicio: inicio, frecuenciaHoras: 24 },
      new Date(inicio.getTime() - 48 * H),
      new Date(inicio.getTime() + 1 * H),
    );
    assert.equal(r.length, 1);
    assert.equal(r[0].getTime(), inicio.getTime());
  });
});

describe('Cálculo de adherencia (RF10)', () => {
  test('excluye las dosis pendientes del cálculo', () => {
    const r = calcularPorcentaje([{ estado: 'tomada' }, { estado: 'tomada' }, { estado: 'omitida' }, { estado: 'pendiente' }]);
    assert.deepEqual(r, { tomadas: 2, omitidas: 1, evaluadas: 3, porcentaje: 66.7 });
  });

  test('devuelve null cuando no hay dosis evaluables', () => {
    assert.equal(calcularPorcentaje([{ estado: 'pendiente' }]).porcentaje, null);
  });

  test('agrupa la serie diaria por fecha local de Colombia', () => {
    const serie = serieDiaria([
      { estado: 'tomada', fecha_hora: '2026-11-10T04:00:00Z' }, // 9 nov 23:00 en Colombia
      { estado: 'omitida', fecha_hora: '2026-11-10T13:00:00Z' }, // 10 nov 08:00
    ]);
    assert.deepEqual(serie.map((d) => d.fecha), ['2026-11-09', '2026-11-10']);
  });
});

describe('Planificador de alertas (RF08, RF09)', () => {
  const programada = new Date('2026-11-10T13:00:00Z');

  test('no considera vencida una dosis dentro de la tolerancia', () => {
    assert.equal(estaVencida(programada, 15, new Date(programada.getTime() + 14 * 60000)), false);
  });

  test('considera vencida la dosis al cumplirse la tolerancia', () => {
    assert.equal(estaVencida(programada, 15, new Date(programada.getTime() + 15 * 60000)), true);
  });

  test('usa la tolerancia más estricta entre los cuidadores', () => {
    assert.equal(toleranciaEfectiva([{ tolerancia_min: 30 }, { tolerancia_min: 10 }]), 10);
  });

  test('usa la tolerancia por defecto si no hay cuidadores', () => {
    assert.equal(toleranciaEfectiva([]), 30);
  });
});

describe('Validación y fechas', () => {
  test('rechaza datos inválidos con la lista de errores', () => {
    assert.throws(
      () => validar({ correo: 'no-es-correo', edad: 'x' }, { correo: { tipo: 'correo' }, edad: { tipo: 'entero' }, nombre: { requerido: true } }),
      (e) => e.estado === 400 && e.detalles.length === 3,
    );
  });

  test('normaliza el correo a minúsculas y convierte enteros', () => {
    assert.deepEqual(validar({ correo: ' Ana@Correo.CO ', n: '5' }, { correo: { tipo: 'correo' }, n: { tipo: 'entero' } }), {
      correo: 'ana@correo.co',
      n: 5,
    });
  });

  test('calcula el rango de un día en hora de Colombia (UTC-5)', () => {
    const r = rangoDelDia('2026-11-20');
    assert.equal(r.inicio.toISOString(), '2026-11-20T05:00:00.000Z');
    assert.equal(rangoDelDia('20-11-2026'), null);
  });

  test('formatea fecha y hora local', () => {
    assert.equal(fechaLocal('2026-11-20T03:30:00Z'), '2026-11-19');
    assert.equal(horaLocal('2026-11-20T13:05:00Z'), '08:05');
  });
});
