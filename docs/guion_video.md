# Guion del video de socialización (máximo 10 minutos)

Requisito de la guía: el estudiante debe tener la **cámara web encendida durante toda la grabación**.
Sugerencia: grabar con OBS Studio o Microsoft Teams/Zoom (compartir pantalla + cámara) y subir a YouTube como *No listado*.

## Preparación (antes de grabar)

```bash
cd backend && npm install && npm start -- --seed     # terminal 1
cd mobile && flutter run -d chrome                   # terminal 2 (o emulador Android)
```

Abra dos ventanas del navegador (o navegador + emulador): una con el **paciente** y otra con el **cuidador**.

## Guion

| Min. | Sección | Qué mostrar y decir |
|---|---|---|
| 0:00–0:45 | Presentación | Nombre, curso, título del proyecto. Problema: baja adherencia (≈50 % según la OMS) y falta de seguimiento familiar. |
| 0:45–1:45 | Solución y arquitectura | Mostrar el diagrama de arquitectura del documento: Flutter, API REST Node.js, PostgreSQL, planificador, push y correo. Mencionar Scrum (sprint 0 + 5 sprints). |
| 1:45–2:30 | Repositorio | GitHub: estructura `backend/`, `mobile/`, `docs/`, README e integración continua. |
| 2:30–3:15 | Registro (HU01) | Crear una cuenta de paciente; resaltar la aceptación de la política de datos (Ley 1581). |
| 3:15–4:15 | Medicamentos (HU03) | Agregar "Enalapril 20 mg cada 8 horas"; mostrar que se generan los recordatorios. |
| 4:15–5:00 | Cuidador (HU02) | Invitar al cuidador; en la otra ventana, ingresar como cuidador y aceptar la invitación. |
| 5:00–5:45 | Recordatorio y confirmación (HU04–HU05) | Pantalla Hoy con letra grande; tocar **Ya la tomé**. Explicar el funcionamiento sin conexión. |
| 5:45–7:15 | Alerta automática (HU06) | Menú de cuenta → **Simulación: adelantar 15 min**. En la ventana del cuidador aparece la alerta (banner y bandeja). Mostrar el correo simulado en `backend/buzon/`. |
| 7:15–8:15 | Panel e historial (HU07–HU08) | Panel del cuidador con el resumen del día; historial con porcentaje y gráfico de adherencia. |
| 8:15–9:15 | Pruebas y TRL 5 | Ejecutar `npm test` (45 pruebas) y `npm run simular` (13/13 verificaciones). Explicar por qué el prototipo alcanza TRL 5. |
| 9:15–10:00 | Cierre | Resultados, próximos pasos (prueba de usabilidad con usuarios reales, despliegue en la nube) y agradecimiento. |
