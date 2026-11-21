-- =============================================================
-- MediCheck - Esquema de base de datos (PostgreSQL 14+)
-- Modelo: USUARIO, TRATAMIENTO, DOSIS_PROGRAMADA,
--         VINCULO_CUIDADOR, ALERTA
-- =============================================================

CREATE TABLE IF NOT EXISTS usuario (
  id_usuario                 SERIAL PRIMARY KEY,
  nombre                     VARCHAR(120) NOT NULL,
  correo                     VARCHAR(160) NOT NULL UNIQUE,
  telefono                   VARCHAR(20),
  contrasena_hash            VARCHAR(100) NOT NULL,
  rol                        VARCHAR(10)  NOT NULL CHECK (rol IN ('paciente', 'cuidador')),
  token_push                 TEXT,
  acepta_politica_fecha      TIMESTAMPTZ  NOT NULL,
  codigo_recuperacion_hash   VARCHAR(100),
  codigo_recuperacion_expira TIMESTAMPTZ,
  fecha_registro             TIMESTAMPTZ  NOT NULL
);

CREATE TABLE IF NOT EXISTS tratamiento (
  id_tratamiento   SERIAL PRIMARY KEY,
  id_paciente      INTEGER      NOT NULL REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  medicamento      VARCHAR(120) NOT NULL,
  dosis            VARCHAR(80)  NOT NULL,
  frecuencia_horas INTEGER      NOT NULL CHECK (frecuencia_horas BETWEEN 1 AND 168),
  fecha_inicio     TIMESTAMPTZ  NOT NULL,
  fecha_fin        TIMESTAMPTZ,
  indicaciones     VARCHAR(255),
  activo           BOOLEAN      NOT NULL DEFAULT TRUE,
  fecha_creacion   TIMESTAMPTZ  NOT NULL
);

CREATE TABLE IF NOT EXISTS dosis_programada (
  id_dosis            SERIAL PRIMARY KEY,
  id_tratamiento      INTEGER     NOT NULL REFERENCES tratamiento(id_tratamiento) ON DELETE CASCADE,
  fecha_hora          TIMESTAMPTZ NOT NULL,
  estado              VARCHAR(10) NOT NULL DEFAULT 'pendiente'
                      CHECK (estado IN ('pendiente', 'tomada', 'omitida')),
  fecha_confirmacion  TIMESTAMPTZ,
  confirmada_tarde    BOOLEAN     NOT NULL DEFAULT FALSE,
  origen_confirmacion VARCHAR(12)
);

CREATE INDEX IF NOT EXISTS idx_dosis_estado_fecha ON dosis_programada (estado, fecha_hora);

CREATE TABLE IF NOT EXISTS vinculo_cuidador (
  id_vinculo        SERIAL PRIMARY KEY,
  id_paciente       INTEGER      NOT NULL REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  id_cuidador       INTEGER      REFERENCES usuario(id_usuario) ON DELETE CASCADE,
  correo_invitado   VARCHAR(160) NOT NULL,
  codigo_invitacion VARCHAR(8)   NOT NULL,
  parentesco        VARCHAR(40),
  tolerancia_min    INTEGER      NOT NULL DEFAULT 30 CHECK (tolerancia_min BETWEEN 5 AND 240),
  estado            VARCHAR(10)  NOT NULL DEFAULT 'pendiente'
                    CHECK (estado IN ('pendiente', 'activo', 'revocado')),
  fecha_creacion    TIMESTAMPTZ  NOT NULL
);

CREATE TABLE IF NOT EXISTS alerta (
  id_alerta    SERIAL PRIMARY KEY,
  id_dosis     INTEGER      NOT NULL REFERENCES dosis_programada(id_dosis) ON DELETE CASCADE,
  id_vinculo   INTEGER      NOT NULL REFERENCES vinculo_cuidador(id_vinculo) ON DELETE CASCADE,
  canal        VARCHAR(10)  NOT NULL CHECK (canal IN ('push', 'correo')),
  fecha_envio  TIMESTAMPTZ  NOT NULL,
  estado_envio VARCHAR(10)  NOT NULL CHECK (estado_envio IN ('enviada', 'fallida')),
  detalle      VARCHAR(255),
  leida        BOOLEAN      NOT NULL DEFAULT FALSE
);
