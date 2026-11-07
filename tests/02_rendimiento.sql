-- Pruebas de carga, aisladamente y con rollback. No ejecutar durante horas pico.
\set ON_ERROR_STOP on
\timing on
BEGIN;
CREATE SCHEMA aa_perf;
CREATE TABLE aa_perf.sin_auditar (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, valor TEXT);
CREATE TABLE aa_perf.con_auditoria (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY, valor TEXT);
SELECT autoaudit.configurar_tabla('aa_perf', 'con_auditoria',
  '{"valor":["INSERT","UPDATE","DELETE"]}'::jsonb,
  '["INSERT","UPDATE","DELETE"]'::jsonb, TRUE);

\echo 'SIN auditoría: 100 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.sin_auditar(valor)
SELECT 'test_' || g FROM generate_series(1,100) g;
\echo 'CON auditoría: 100 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.con_auditoria(valor)
SELECT 'test_' || g FROM generate_series(1,100) g;

\echo 'SIN auditoría: 1,000 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.sin_auditar(valor)
SELECT 'test_' || g FROM generate_series(101,1100) g;
\echo 'CON auditoría: 1,000 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.con_auditoria(valor)
SELECT 'test_' || g FROM generate_series(101,1100) g;

\echo 'SIN auditoría: 5,000 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.sin_auditar(valor)
SELECT 'test_' || g FROM generate_series(1101,6100) g;
\echo 'CON auditoría: 5,000 filas'
EXPLAIN (ANALYZE, BUFFERS) INSERT INTO aa_perf.con_auditoria(valor)
SELECT 'test_' || g FROM generate_series(1101,6100) g;

SELECT count(*) AS filas_auditadas FROM autoaudit.bitacora b
JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
WHERE t.esquema='aa_perf';
ROLLBACK;
\echo 'Reporte: compare Execution Time para cada volumen en el mismo hardware.'
