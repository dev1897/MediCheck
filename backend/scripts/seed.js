'use strict';
/**
 * Carga datos FICTICIOS de demostración: un paciente, un cuidador vinculado,
 * dos tratamientos y el historial de los últimos 7 días.
 *
 *   Paciente: paciente@medicheck.demo / Demo1234
 *   Cuidador: cuidador@medicheck.demo / Demo1234
 *
 * Uso: npm run seed   (o iniciar el servidor con: npm start -- --seed)
 */
const bcrypt = require('bcryptjs');
const db = require('../src/db');
const { reloj, rangoDelDia, fechaLocal } = require('../src/utils/comunes');
const dosisService = require('../src/services/dosis.service');

const HORA = 3600 * 1000;

async function sembrar() {
  await db.iniciar();
  const existe = await db.query("SELECT 1 FROM usuario WHERE correo = 'paciente@medicheck.demo'");
  if (existe.rows.length) {
    console.log('[Seed] Los datos de demostración ya existen.');
    return;
  }
  const ahora = reloj.ahora();
  const hash = await bcrypt.hash('Demo1234', 10);
  const crearUsuario = async (nombre, correo, telefono, rol) =>
    (
      await db.query(
        `INSERT INTO usuario (nombre, correo, telefono, contrasena_hash, rol, acepta_politica_fecha, fecha_registro)
         VALUES ($1, $2, $3, $4, $5, $6, $6) RETURNING *`,
        [nombre, correo, telefono, hash, rol, new Date(ahora.getTime() - 8 * 24 * HORA)],
      )
    ).rows[0];

  const paciente = await crearUsuario('Rosa Elena Díaz', 'paciente@medicheck.demo', '3001112233', 'paciente');
  const cuidador = await crearUsuario('Carlos Díaz', 'cuidador@medicheck.demo', '3004445566', 'cuidador');

  const vinculo = (
    await db.query(
      `INSERT INTO vinculo_cuidador (id_paciente, id_cuidador, correo_invitado, codigo_invitacion, parentesco,
                                     tolerancia_min, estado, fecha_creacion)
       VALUES ($1, $2, $3, 'DEMO01', 'Hijo', 15, 'activo', $4) RETURNING *`,
      [paciente.id_usuario, cuidador.id_usuario, cuidador.correo, new Date(ahora.getTime() - 8 * 24 * HORA)],
    )
  ).rows[0];

  // Los tratamientos inician hace 7 días a las 7:00 a. m. (hora de Colombia)
  const hace7 = fechaLocal(new Date(ahora.getTime() - 7 * 24 * HORA));
  const base = rangoDelDia(hace7).inicio.getTime();
  const tratamientos = [
    { medicamento: 'Losartán', dosis: '50 mg - 1 tableta', frecuencia: 12, inicio: base + 7 * HORA,
      indicaciones: 'Para la presión arterial. Tomar con agua.' },
    { medicamento: 'Metformina', dosis: '850 mg - 1 tableta', frecuencia: 8, inicio: base + 6 * HORA,
      indicaciones: 'Tomar con las comidas.' },
  ];

  // Patrón determinista de dosis omitidas para que el historial sea reproducible
  const omitir = new Set([2, 7, 11, 16]);
  let contador = 0;

  for (const t of tratamientos) {
    const trat = (
      await db.query(
        `INSERT INTO tratamiento (id_paciente, medicamento, dosis, frecuencia_horas, fecha_inicio, indicaciones,
                                  activo, fecha_creacion)
         VALUES ($1, $2, $3, $4, $5, $6, TRUE, $7) RETURNING *`,
        [paciente.id_usuario, t.medicamento, t.dosis, t.frecuencia, new Date(t.inicio), t.indicaciones,
          new Date(t.inicio - HORA)],
      )
    ).rows[0];

    // Historial: dosis anteriores a hace 1 hora
    const limite = ahora.getTime() - HORA;
    for (let f = t.inicio; f <= limite; f += t.frecuencia * HORA) {
      contador += 1;
      const omitida = omitir.has(contador);
      const d = (
        await db.query(
          `INSERT INTO dosis_programada (id_tratamiento, fecha_hora, estado, fecha_confirmacion, origen_confirmacion)
           VALUES ($1, $2, $3, $4, $5) RETURNING *`,
          [trat.id_tratamiento, new Date(f), omitida ? 'omitida' : 'tomada',
            omitida ? null : new Date(f + (5 + (contador % 9)) * 60000), omitida ? null : 'app'],
        )
      ).rows[0];
      if (omitida) {
        for (const canal of ['push', 'correo']) {
          await db.query(
            `INSERT INTO alerta (id_dosis, id_vinculo, canal, fecha_envio, estado_envio, detalle, leida)
             VALUES ($1, $2, $3, $4, 'enviada', 'Alerta histórica de demostración', TRUE)`,
            [d.id_dosis, vinculo.id_vinculo, canal, new Date(f + 16 * 60000)],
          );
        }
      }
    }
    await dosisService.generarDosis(trat);
  }
  console.log('[Seed] Datos de demostración creados:');
  console.log('       Paciente: paciente@medicheck.demo / Demo1234');
  console.log('       Cuidador: cuidador@medicheck.demo / Demo1234');
}

module.exports = { sembrar };

if (require.main === module) {
  sembrar()
    .then(() => console.log('[Seed] Nota: en modo memoria los datos viven mientras el proceso esté activo. Use "npm start -- --seed".'))
    .catch((e) => {
      console.error(e);
      process.exit(1);
    })
    .finally(() => db.cerrar());
}
