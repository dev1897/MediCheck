'use strict';
const fs = require('fs');
const path = require('path');
const nodemailer = require('nodemailer');
const config = require('../config');
const { reloj } = require('../utils/comunes');

// ---------------------------------------------------------------------------
// Canal PUSH
//  - "simulado": el mensaje queda registrado en la tabla ALERTA y la app del
//    cuidador lo obtiene consultando GET /api/alertas (sondeo cada 20 s).
//  - "fcm": se envía con Firebase Cloud Messaging (requiere firebase-admin y
//    la variable GOOGLE_APPLICATION_CREDENTIALS con la cuenta de servicio).
// ---------------------------------------------------------------------------
let fcm = null;
function obtenerFcm() {
  if (fcm) return fcm;
  // eslint-disable-next-line global-require, import/no-unresolved
  const admin = require('firebase-admin');
  if (!admin.apps.length) admin.initializeApp({ credential: admin.credential.applicationDefault() });
  fcm = admin.messaging();
  return fcm;
}

async function enviarPush(destinatario, titulo, cuerpo, datos = {}) {
  if (config.pushModo === 'fcm') {
    if (!destinatario.token_push) {
      return { ok: false, detalle: 'El cuidador no tiene un dispositivo registrado.' };
    }
    try {
      const id = await obtenerFcm().send({
        token: destinatario.token_push,
        notification: { title: titulo, body: cuerpo },
        data: Object.fromEntries(Object.entries(datos).map(([k, v]) => [k, String(v)])),
        android: { priority: 'high' },
      });
      return { ok: true, detalle: `FCM ${id}` };
    } catch (e) {
      return { ok: false, detalle: `FCM: ${e.message}`.slice(0, 250) };
    }
  }
  console.log(`[PUSH simulado] -> ${destinatario.correo}: ${titulo} | ${cuerpo}`);
  return { ok: true, detalle: 'Push simulado entregado a la bandeja del cuidador.' };
}

// ---------------------------------------------------------------------------
// Canal CORREO
//  - "simulado": Nodemailer genera el mensaje completo y lo guarda como JSON en
//    la carpeta "buzon/" (evidencia verificable del envío).
//  - "smtp": envío real mediante el servidor SMTP configurado.
// ---------------------------------------------------------------------------
let transporte = null;
const buzonSimulado = [];

function obtenerTransporte() {
  if (transporte) return transporte;
  transporte =
    config.correoModo === 'smtp'
      ? nodemailer.createTransport({
          host: config.smtp.host,
          port: config.smtp.puerto,
          secure: config.smtp.puerto === 465,
          auth: { user: config.smtp.usuario, pass: config.smtp.contrasena },
        })
      : nodemailer.createTransport({ jsonTransport: true });
  return transporte;
}

async function enviarCorreo(para, asunto, texto, html) {
  try {
    const info = await obtenerTransporte().sendMail({
      from: config.smtp.remitente,
      to: para,
      subject: asunto,
      text: texto,
      html: html || `<p>${texto.replace(/\n/g, '<br>')}</p>`,
    });
    if (config.correoModo !== 'smtp') {
      const mensaje = { fecha: reloj.ahora().toISOString(), para, asunto, texto };
      buzonSimulado.push(mensaje);
      if (buzonSimulado.length > 200) buzonSimulado.shift();
      if (config.entorno !== 'test') {
        fs.mkdirSync(config.carpetaBuzon, { recursive: true });
        const archivo = path.join(
          config.carpetaBuzon,
          `${Date.now()}-${para.replace(/[^a-z0-9]/gi, '_')}.json`,
        );
        fs.writeFileSync(archivo, info.message.toString());
      }
      console.log(`[CORREO simulado] -> ${para}: ${asunto}`);
    }
    return { ok: true, detalle: config.correoModo === 'smtp' ? `SMTP ${info.messageId}` : 'Correo simulado generado.' };
  } catch (e) {
    return { ok: false, detalle: `Correo: ${e.message}`.slice(0, 250) };
  }
}

module.exports = { enviarPush, enviarCorreo, buzonSimulado };
