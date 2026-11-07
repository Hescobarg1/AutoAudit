-- Pruebas automáticas transaccionales. Todo se deshace al finalizar.
\set ON_ERROR_STOP on
BEGIN;
CREATE SCHEMA aa_pruebas;
CREATE TABLE aa_pruebas.productos (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre TEXT NOT NULL,
    saldo NUMERIC(12,2),
    comentario TEXT
);
SELECT autoaudit.configurar_tabla('aa_pruebas','productos',
  '{"nombre":["INSERT","DELETE"],"saldo":["INSERT","UPDATE","DELETE"]}'::jsonb,
  '["INSERT","UPDATE","DELETE"]'::jsonb, TRUE);

INSERT INTO aa_pruebas.productos(nombre,saldo,comentario)
VALUES ('Producto prueba', 10.00, 'inicial');
UPDATE aa_pruebas.productos SET comentario='no auditada' WHERE id=1;
UPDATE aa_pruebas.productos SET saldo=20.00 WHERE id=1;
DELETE FROM aa_pruebas.productos WHERE id=1;

DO $$
DECLARE v_count INTEGER;
BEGIN
 SELECT count(*) INTO v_count FROM autoaudit.bitacora b
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
 WHERE t.esquema='aa_pruebas' AND t.tabla='productos';
 IF v_count <> 3 THEN RAISE EXCEPTION 'Se esperaban 3 eventos auditados; hay %',v_count; END IF;

 SELECT count(*) INTO v_count FROM autoaudit.detalle_cambio d
 JOIN autoaudit.bitacora b ON b.id=d.bitacora_id
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
 WHERE t.esquema='aa_pruebas' AND t.tabla='productos';
 IF v_count <> 5 THEN RAISE EXCEPTION 'Se esperaban 5 detalles de columna; hay %',v_count; END IF;

 SELECT count(*) INTO v_count FROM autoaudit.detalle_cambio d
 JOIN autoaudit.bitacora b ON b.id=d.bitacora_id
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
 WHERE t.esquema='aa_pruebas' AND b.operacion='UPDATE'
   AND d.nombre_columna='saldo' AND d.valor_anterior='10'::jsonb
   AND d.valor_nuevo='20'::jsonb;
 IF v_count <> 1 THEN RAISE EXCEPTION 'UPDATE no preservó valor anterior y nuevo'; END IF;

 SELECT count(*) INTO v_count FROM autoaudit.bitacora b
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
 WHERE t.esquema='aa_pruebas' AND b.operacion='DELETE'
   AND b.registro_anterior ->> 'nombre' = 'Producto prueba' AND b.registro_nuevo IS NULL;
 IF v_count <> 1 THEN RAISE EXCEPTION 'DELETE no preservó la fila eliminada'; END IF;

 SELECT count(*) INTO v_count FROM aa_pruebas.productos;
 IF v_count <> 0 THEN RAISE EXCEPTION 'DELETE no se ejecutó'; END IF;
 RAISE NOTICE 'OK: INSERT/UPDATE/DELETE, datos anteriores/nuevos y eliminación';
END $$;

-- La desactivación retira todos los triggers, pero no elimina el historial previo.
SELECT autoaudit.configurar_tabla('aa_pruebas','productos',
  '{"saldo":["UPDATE"]}'::jsonb, '["UPDATE"]'::jsonb, FALSE);
INSERT INTO aa_pruebas.productos(nombre,saldo) VALUES('Sin auditar',5.00);
DO $$
DECLARE v_count INTEGER;
BEGIN
 SELECT count(*) INTO v_count FROM autoaudit.bitacora b
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id WHERE t.esquema='aa_pruebas';
 IF v_count <> 3 THEN RAISE EXCEPTION 'Auditoría desactivada registró cambios'; END IF;
 RAISE NOTICE 'OK: desactivación sin borrar el historial';
END $$;

SELECT autoaudit.configurar_tabla('aa_pruebas','productos',
  '{"saldo":["UPDATE"]}'::jsonb, '["UPDATE"]'::jsonb, TRUE);
UPDATE aa_pruebas.productos SET saldo=6.00 WHERE nombre='Sin auditar';
DO $$
DECLARE v_count INTEGER;
BEGIN
 SELECT count(*) INTO v_count FROM autoaudit.bitacora b
 JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id WHERE t.esquema='aa_pruebas';
 IF v_count <> 4 THEN RAISE EXCEPTION 'Reactivación no generó el evento esperado'; END IF;
 RAISE NOTICE 'OK: reactivación con selección granular';
END $$;
ROLLBACK;
\echo 'Pruebas funcionales completadas: todas las aserciones superadas si no hubo errores.'
