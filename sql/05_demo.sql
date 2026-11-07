-- Datos de ejemplo. Optativo; NO ejecutar sobre el ambiente de producción.
CREATE SCHEMA IF NOT EXISTS demo;
CREATE TABLE IF NOT EXISTS demo.clientes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre TEXT NOT NULL,
    correo TEXT,
    saldo NUMERIC(12,2) NOT NULL DEFAULT 0,
    activo BOOLEAN NOT NULL DEFAULT TRUE
);
SELECT autoaudit.configurar_tabla(
    'demo','clientes',
    '{"nombre":["INSERT","UPDATE","DELETE"],"correo":["INSERT","UPDATE","DELETE"],"saldo":["INSERT","UPDATE","DELETE"]}'::jsonb,
    '["INSERT","UPDATE","DELETE"]'::jsonb, TRUE
);
INSERT INTO demo.clientes(nombre, correo, saldo)
VALUES ('Ana Pérez','ana@example.com',100.00);
UPDATE demo.clientes SET saldo=125.00 WHERE correo='ana@example.com';
DELETE FROM demo.clientes WHERE correo='ana@example.com';
SELECT * FROM autoaudit.v_historial WHERE esquema='demo' ORDER BY fecha_hora;
