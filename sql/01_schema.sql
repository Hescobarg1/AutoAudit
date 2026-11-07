-- AutoAudit | PostgreSQL 18 | Estructura principal
-- Ejecutar como propietario de la base de datos o administrador.
BEGIN;
CREATE SCHEMA IF NOT EXISTS autoaudit;

CREATE TABLE IF NOT EXISTS autoaudit.tabla_auditada (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    esquema TEXT NOT NULL,
    tabla TEXT NOT NULL,
    habilitada BOOLEAN NOT NULL DEFAULT TRUE,
    creada_en TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    actualizada_en TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    CONSTRAINT uq_tabla_auditada UNIQUE (esquema, tabla),
    CONSTRAINT ck_tabla_nombres CHECK (length(esquema) > 0 AND length(tabla) > 0)
);

CREATE TABLE IF NOT EXISTS autoaudit.columna_auditada (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla_id BIGINT NOT NULL REFERENCES autoaudit.tabla_auditada(id) ON DELETE RESTRICT,
    columna TEXT NOT NULL,
    habilitada BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_columna_auditada UNIQUE (tabla_id, columna)
);

CREATE TABLE IF NOT EXISTS autoaudit.evento_auditado (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla_id BIGINT NOT NULL REFERENCES autoaudit.tabla_auditada(id) ON DELETE RESTRICT,
    operacion TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    habilitado BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_evento_auditado UNIQUE (tabla_id, operacion)
);

-- Relación entre columnas y eventos. Permite granularidad por columna y operación.
CREATE TABLE IF NOT EXISTS autoaudit.columna_evento (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    columna_id BIGINT NOT NULL REFERENCES autoaudit.columna_auditada(id) ON DELETE RESTRICT,
    evento_id BIGINT NOT NULL REFERENCES autoaudit.evento_auditado(id) ON DELETE RESTRICT,
    habilitado BOOLEAN NOT NULL DEFAULT TRUE,
    CONSTRAINT uq_columna_evento UNIQUE (columna_id, evento_id)
);

CREATE TABLE IF NOT EXISTS autoaudit.usuario_auditado (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre TEXT NOT NULL UNIQUE,
    creado_en TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp()
);

CREATE TABLE IF NOT EXISTS autoaudit.estacion_trabajo (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ip_origen INET,
    aplicacion TEXT NOT NULL DEFAULT '',
    -- NULLS NOT DISTINCT permite identificar de forma consistente conexiones locales.
    CONSTRAINT uq_estacion UNIQUE NULLS NOT DISTINCT (ip_origen, aplicacion)
);

CREATE TABLE IF NOT EXISTS autoaudit.bitacora (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tabla_id BIGINT NOT NULL REFERENCES autoaudit.tabla_auditada(id) ON DELETE RESTRICT,
    evento_id BIGINT NOT NULL REFERENCES autoaudit.evento_auditado(id) ON DELETE RESTRICT,
    usuario_id BIGINT NOT NULL REFERENCES autoaudit.usuario_auditado(id) ON DELETE RESTRICT,
    estacion_id BIGINT NOT NULL REFERENCES autoaudit.estacion_trabajo(id) ON DELETE RESTRICT,
    operacion TEXT NOT NULL CHECK (operacion IN ('INSERT','UPDATE','DELETE')),
    fecha_hora TIMESTAMPTZ NOT NULL DEFAULT clock_timestamp(),
    transaccion_id BIGINT NOT NULL DEFAULT txid_current(),
    clave_primaria JSONB NOT NULL DEFAULT '{}'::jsonb,
    registro_anterior JSONB,
    registro_nuevo JSONB
);

CREATE TABLE IF NOT EXISTS autoaudit.detalle_cambio (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    bitacora_id BIGINT NOT NULL REFERENCES autoaudit.bitacora(id) ON DELETE RESTRICT,
    columna_id BIGINT NOT NULL REFERENCES autoaudit.columna_auditada(id) ON DELETE RESTRICT,
    nombre_columna TEXT NOT NULL,
    valor_anterior JSONB,
    valor_nuevo JSONB,
    CONSTRAINT uq_detalle_por_columna UNIQUE (bitacora_id, columna_id)
);

CREATE INDEX IF NOT EXISTS ix_bitacora_fecha ON autoaudit.bitacora(fecha_hora DESC);
CREATE INDEX IF NOT EXISTS ix_bitacora_usuario_fecha ON autoaudit.bitacora(usuario_id, fecha_hora DESC);
CREATE INDEX IF NOT EXISTS ix_bitacora_tabla_fecha ON autoaudit.bitacora(tabla_id, fecha_hora DESC);
CREATE INDEX IF NOT EXISTS ix_detalle_columna ON autoaudit.detalle_cambio(nombre_columna, bitacora_id);
CREATE INDEX IF NOT EXISTS ix_detalle_bitacora ON autoaudit.detalle_cambio(bitacora_id);
CREATE INDEX IF NOT EXISTS ix_columna_evento_evento ON autoaudit.columna_evento(evento_id) WHERE habilitado;
COMMIT;
