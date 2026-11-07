-- AutoAudit | Funciones y generación automática de triggers PostgreSQL 18
-- Nota: PostgreSQL utiliza PL/pgSQL, no PL/SQL de Oracle.

-- Este trigger registra una fila completa (JSONB) y el detalle por columna observada.
CREATE OR REPLACE FUNCTION autoaudit.capturar_cambio()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, autoaudit
AS $$
DECLARE
    v_tabla_id BIGINT := TG_ARGV[0]::BIGINT;
    v_evento_id BIGINT;
    v_antes JSONB;
    v_despues JSONB;
    v_fila_pk JSONB;
    v_col RECORD;
    v_hay_cambio BOOLEAN := FALSE;
    v_usuario_id BIGINT;
    v_estacion_id BIGINT;
    v_bitacora_id BIGINT;
    v_usuario TEXT := session_user;
    v_ip INET := inet_client_addr();
    v_aplicacion TEXT := coalesce(current_setting('application_name', TRUE), '');
BEGIN
    -- Opciones AFTER ROW; no hay auditoría sobre la propia estructura del sistema.
    SELECT e.id INTO v_evento_id
      FROM autoaudit.tabla_auditada t
      JOIN autoaudit.evento_auditado e ON e.tabla_id = t.id
     WHERE t.id = v_tabla_id
       AND t.esquema = TG_TABLE_SCHEMA AND t.tabla = TG_TABLE_NAME
       AND t.habilitada AND e.habilitado AND e.operacion = TG_OP;
    IF v_evento_id IS NULL THEN
        RETURN NULL;
    END IF;

    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        v_antes := to_jsonb(OLD);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        v_despues := to_jsonb(NEW);
    END IF;

    -- No registrar UPDATE si no cambió ninguna columna configurada.
    FOR v_col IN
        SELECT c.id, c.columna
          FROM autoaudit.columna_auditada c
          JOIN autoaudit.columna_evento ce ON ce.columna_id = c.id
         WHERE c.tabla_id = v_tabla_id AND c.habilitada
           AND ce.evento_id = v_evento_id AND ce.habilitado
    LOOP
        IF TG_OP <> 'UPDATE'
           OR (v_antes -> v_col.columna) IS DISTINCT FROM (v_despues -> v_col.columna) THEN
            v_hay_cambio := TRUE;
            EXIT;
        END IF;
    END LOOP;
    IF NOT v_hay_cambio THEN
        RETURN NULL;
    END IF;

    -- Identidad de BD; para aplicaciones compartiendo una cuenta, documentar la limitación.
    INSERT INTO autoaudit.usuario_auditado(nombre)
    VALUES (v_usuario) ON CONFLICT (nombre) DO NOTHING;
    SELECT id INTO STRICT v_usuario_id FROM autoaudit.usuario_auditado WHERE nombre = v_usuario;

    INSERT INTO autoaudit.estacion_trabajo(ip_origen, aplicacion)
    VALUES (v_ip, v_aplicacion) ON CONFLICT (ip_origen, aplicacion) DO NOTHING;
    SELECT id INTO STRICT v_estacion_id FROM autoaudit.estacion_trabajo
     WHERE ip_origen IS NOT DISTINCT FROM v_ip AND aplicacion = v_aplicacion;

    -- Construir PK desde el catálogo. Si no existe PK, se conserva la fila completa.
    SELECT coalesce(jsonb_object_agg(a.attname,
                        coalesce(v_despues, v_antes) -> a.attname), '{}'::jsonb)
      INTO v_fila_pk
      FROM pg_catalog.pg_index i
      JOIN pg_catalog.pg_attribute a ON a.attrelid = i.indrelid
         AND a.attnum = ANY(i.indkey)
     WHERE i.indrelid = TG_RELID AND i.indisprimary;

    INSERT INTO autoaudit.bitacora
       (tabla_id, evento_id, usuario_id, estacion_id, operacion,
        clave_primaria, registro_anterior, registro_nuevo)
    VALUES (v_tabla_id, v_evento_id, v_usuario_id, v_estacion_id, TG_OP,
            v_fila_pk, v_antes, v_despues)
    RETURNING id INTO v_bitacora_id;

    FOR v_col IN
        SELECT c.id, c.columna
          FROM autoaudit.columna_auditada c
          JOIN autoaudit.columna_evento ce ON ce.columna_id = c.id
         WHERE c.tabla_id = v_tabla_id AND c.habilitada
           AND ce.evento_id = v_evento_id AND ce.habilitado
    LOOP
        IF TG_OP <> 'UPDATE'
           OR (v_antes -> v_col.columna) IS DISTINCT FROM (v_despues -> v_col.columna) THEN
            INSERT INTO autoaudit.detalle_cambio
                (bitacora_id, columna_id, nombre_columna, valor_anterior, valor_nuevo)
            VALUES (v_bitacora_id, v_col.id, v_col.columna,
                    v_antes -> v_col.columna, v_despues -> v_col.columna);
        END IF;
    END LOOP;
    RETURN NULL;
END;
$$;

-- Regenera exclusivamente los triggers de una tabla física.
CREATE OR REPLACE FUNCTION autoaudit.regenerar_triggers(p_tabla_id BIGINT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, autoaudit
AS $$
DECLARE
    v_esquema TEXT;
    v_tabla TEXT;
    v_habilitada BOOLEAN;
    v_relid OID;
    v_evento RECORD;
    v_nombre TEXT;
    v_total INTEGER := 0;
    v_operacion TEXT;
BEGIN
    SELECT esquema, tabla, habilitada INTO v_esquema, v_tabla, v_habilitada
      FROM autoaudit.tabla_auditada WHERE id = p_tabla_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Configuración de tabla % no existe', p_tabla_id;
    END IF;
    SELECT c.oid INTO v_relid
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = v_esquema AND c.relname = v_tabla AND c.relkind = 'r' AND NOT c.relispartition;
    IF v_relid IS NULL THEN
        RAISE EXCEPTION 'La tabla de origen %.% ya no existe o no es tabla ordinaria', v_esquema, v_tabla;
    END IF;

    -- Nombres determinísticos, únicos por ID. Cada trigger pertenece a UNA tabla.
    FOREACH v_operacion IN ARRAY ARRAY['INSERT', 'UPDATE', 'DELETE'] LOOP
        v_nombre := 'aa_' || lower(left(v_operacion, 1)) || '_' || p_tabla_id;
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON %I.%I',
                       v_nombre, v_esquema, v_tabla);
    END LOOP;

    IF NOT v_habilitada THEN
        RETURN 0;
    END IF;
    FOR v_evento IN
        SELECT e.id, e.operacion
          FROM autoaudit.evento_auditado e
         WHERE e.tabla_id = p_tabla_id AND e.habilitado
           AND EXISTS (
               SELECT 1 FROM autoaudit.columna_evento ce
               JOIN autoaudit.columna_auditada ca ON ca.id = ce.columna_id
               WHERE ce.evento_id = e.id AND ce.habilitado AND ca.habilitada
                 AND ca.tabla_id = p_tabla_id)
    LOOP
        v_nombre := 'aa_' || lower(left(v_evento.operacion, 1)) || '_' || p_tabla_id;
        EXECUTE format(
            'CREATE TRIGGER %I AFTER %s ON %I.%I FOR EACH ROW EXECUTE FUNCTION autoaudit.capturar_cambio(%L)',
            v_nombre, v_evento.operacion, v_esquema, v_tabla, p_tabla_id::text
        );
        v_total := v_total + 1;
    END LOOP;
    RETURN v_total;
END;
$$;

-- Configuración declarativa:
-- p_reglas: {"nombre": ["INSERT","UPDATE"], "saldo": ["UPDATE","DELETE"]}
-- p_operaciones: ["INSERT","UPDATE","DELETE"] (habilitaciones globales de la tabla)
CREATE OR REPLACE FUNCTION autoaudit.configurar_tabla(
    p_esquema TEXT,
    p_tabla TEXT,
    p_reglas JSONB,
    p_operaciones JSONB DEFAULT '["INSERT","UPDATE","DELETE"]'::jsonb,
    p_habilitada BOOLEAN DEFAULT TRUE
)
RETURNS BIGINT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, autoaudit
AS $$
DECLARE
    v_relid OID;
    v_tabla_id BIGINT;
    v_columna TEXT;
    v_columna_id BIGINT;
    v_evento_id BIGINT;
    v_operacion TEXT;
    v_array JSONB;
    v_elemento JSONB;
BEGIN
    IF p_esquema IS NULL OR p_tabla IS NULL OR p_esquema IN ('autoaudit', 'information_schema')
       OR p_esquema ~ '^pg_' THEN
        RAISE EXCEPTION 'Esquema no permitido: %', p_esquema;
    END IF;
    SELECT c.oid INTO v_relid
      FROM pg_catalog.pg_class c
      JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = p_esquema AND c.relname = p_tabla
       AND c.relkind = 'r' AND NOT c.relispartition;
    IF v_relid IS NULL THEN
        RAISE EXCEPTION 'No existe la tabla ordinaria %.% (sin particiones)', p_esquema, p_tabla;
    END IF;
    IF p_reglas IS NULL OR jsonb_typeof(p_reglas) <> 'object'
       OR p_operaciones IS NULL OR jsonb_typeof(p_operaciones) <> 'array' THEN
        RAISE EXCEPTION 'Formato inválido: reglas=OBJETO, operaciones=ARREGLO';
    END IF;
    IF p_habilitada AND p_reglas = '{}'::jsonb THEN
        RAISE EXCEPTION 'Seleccione al menos una columna para activar la auditoría';
    END IF;

    -- Validación completa ANTES de mutar la configuración.
    FOR v_elemento IN SELECT value FROM jsonb_array_elements(p_operaciones) LOOP
        IF jsonb_typeof(v_elemento) <> 'string'
           OR (v_elemento #>> '{}') NOT IN ('INSERT','UPDATE','DELETE') THEN
            RAISE EXCEPTION 'Operación general no válida: %', v_elemento;
        END IF;
    END LOOP;
    FOR v_columna IN SELECT key FROM jsonb_each(p_reglas) LOOP
        IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_attribute
                       WHERE attrelid = v_relid AND attname = v_columna
                         AND attnum > 0 AND NOT attisdropped) THEN
            RAISE EXCEPTION 'Columna inexistente: %.%.%', p_esquema, p_tabla, v_columna;
        END IF;
        v_array := p_reglas -> v_columna;
        IF jsonb_typeof(v_array) <> 'array' THEN
            RAISE EXCEPTION 'Las operaciones de la columna % deben ser un arreglo', v_columna;
        END IF;
        FOR v_elemento IN SELECT value FROM jsonb_array_elements(v_array) LOOP
            IF jsonb_typeof(v_elemento) <> 'string'
               OR (v_elemento #>> '{}') NOT IN ('INSERT','UPDATE','DELETE') THEN
                RAISE EXCEPTION 'Operación inválida en columna %: %', v_columna, v_elemento;
            END IF;
        END LOOP;
    END LOOP;

    INSERT INTO autoaudit.tabla_auditada(esquema, tabla, habilitada)
    VALUES (p_esquema, p_tabla, p_habilitada)
    ON CONFLICT (esquema, tabla) DO UPDATE
      SET habilitada = excluded.habilitada, actualizada_en = clock_timestamp()
    RETURNING id INTO v_tabla_id;

    -- Se deshabilita sin borrar, para conservar las FK de los registros históricos.
    UPDATE autoaudit.columna_auditada SET habilitada = FALSE WHERE tabla_id = v_tabla_id;
    UPDATE autoaudit.columna_evento ce SET habilitado = FALSE
      FROM autoaudit.columna_auditada ca
     WHERE ca.id = ce.columna_id AND ca.tabla_id = v_tabla_id;

    FOREACH v_operacion IN ARRAY ARRAY['INSERT','UPDATE','DELETE'] LOOP
        INSERT INTO autoaudit.evento_auditado(tabla_id, operacion, habilitado)
        VALUES (v_tabla_id, v_operacion, p_operaciones ? v_operacion)
        ON CONFLICT (tabla_id, operacion) DO UPDATE
          SET habilitado = excluded.habilitado;
    END LOOP;

    FOR v_columna IN SELECT key FROM jsonb_each(p_reglas) LOOP
        INSERT INTO autoaudit.columna_auditada(tabla_id, columna, habilitada)
        VALUES (v_tabla_id, v_columna, TRUE)
        ON CONFLICT (tabla_id, columna) DO UPDATE SET habilitada = TRUE
        RETURNING id INTO v_columna_id;
        v_array := p_reglas -> v_columna;
        FOR v_operacion IN SELECT jsonb_array_elements_text(v_array) LOOP
            SELECT id INTO STRICT v_evento_id FROM autoaudit.evento_auditado
             WHERE tabla_id = v_tabla_id AND operacion = v_operacion;
            INSERT INTO autoaudit.columna_evento(columna_id, evento_id, habilitado)
            VALUES (v_columna_id, v_evento_id, TRUE)
            ON CONFLICT (columna_id, evento_id) DO UPDATE SET habilitado = TRUE;
        END LOOP;
    END LOOP;
    PERFORM autoaudit.regenerar_triggers(v_tabla_id);
    RETURN v_tabla_id;
END;
$$;

-- Vista útil para el módulo de consulta (solo lectura para los administradores).
CREATE OR REPLACE VIEW autoaudit.v_historial AS
SELECT b.id, t.esquema, t.tabla, b.operacion, b.fecha_hora,
       u.nombre AS usuario, et.ip_origen, et.aplicacion,
       b.clave_primaria, b.registro_anterior, b.registro_nuevo,
       b.transaccion_id
FROM autoaudit.bitacora b
JOIN autoaudit.tabla_auditada t ON t.id = b.tabla_id
JOIN autoaudit.usuario_auditado u ON u.id = b.usuario_id
JOIN autoaudit.estacion_trabajo et ON et.id = b.estacion_id;
