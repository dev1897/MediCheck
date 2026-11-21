'use strict';
const fs = require('fs');
const path = require('path');
const config = require('../config');

let pool = null;

function crearPool() {
  if (config.dbModo === 'postgres') {
    const { Pool } = require('pg');
    return new Pool({
      connectionString: config.databaseUrl,
      ssl: /sslmode=require/.test(config.databaseUrl) ? { rejectUnauthorized: false } : undefined,
    });
  }
  // Modo simulado: motor PostgreSQL en memoria que expone la misma interfaz de "pg"
  const { newDb } = require('pg-mem');
  const db = newDb({ autoCreateForeignKeyIndices: true });
  const { Pool } = db.adapters.createPg();
  return new Pool();
}

async function iniciar() {
  if (pool) return pool;
  pool = crearPool();
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  // Se ejecuta sentencia por sentencia para que funcione igual en ambos motores
  const sentencias = sql
    .replace(/--.*$/gm, '')
    .split(';')
    .map((s) => s.trim())
    .filter(Boolean);
  for (const s of sentencias) {
    await pool.query(s);
  }
  return pool;
}

async function query(texto, parametros = []) {
  if (!pool) await iniciar();
  return pool.query(texto, parametros);
}

async function cerrar() {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

module.exports = { iniciar, query, cerrar };
