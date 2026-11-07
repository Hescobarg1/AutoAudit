-- Consultas de diccionario de datos y de historial, listas para usar en psql.

-- Tablas ordinarias configurables (no sistema, no particiones).
SELECT n.nspname AS esquema, c.relname AS tabla
FROM pg_catalog.pg_class c
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relkind = 'r' AND NOT c.relispartition
  AND n.nspname !~ '^pg_' AND n.nspname NOT IN ('information_schema','autoaudit')
ORDER BY 1, 2;

-- Columnas de una tabla mediante el diccionario de datos.
-- Reemplace los dos valores del WHERE por su esquema y tabla.
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema='public' AND table_name='clientes'
ORDER BY ordinal_position;

-- Historial reciente con contexto y registros completos.
SELECT * FROM autoaudit.v_historial ORDER BY fecha_hora DESC LIMIT 100;

-- Variables parametrizadas de psql: cambie los valores según su caso.
\set audit_user 'postgres'
\set audit_column 'saldo'

-- Consultar cambios por usuario (variable :audit_user).
SELECT * FROM autoaudit.v_historial
WHERE usuario = :'audit_user' ORDER BY fecha_hora DESC;

-- Consultar cambios por columna (variable :audit_column).
SELECT v.*, d.nombre_columna, d.valor_anterior, d.valor_nuevo
FROM autoaudit.v_historial v
JOIN autoaudit.detalle_cambio d ON d.bitacora_id = v.id
WHERE d.nombre_columna = :'audit_column'
ORDER BY v.fecha_hora DESC;
