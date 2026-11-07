-- AutoAudit | Roles de configuración y acceso restringido
-- Ejecutar con un rol capaz de crear roles, p.ej. postgres.
DO $$ BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_catalog.pg_roles WHERE rolname='autoaudit_admin') THEN
        CREATE ROLE autoaudit_admin NOLOGIN;
    END IF;
END $$;

REVOKE ALL ON SCHEMA autoaudit FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA autoaudit FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA autoaudit FROM PUBLIC;
REVOKE ALL ON ALL FUNCTIONS IN SCHEMA autoaudit FROM PUBLIC;

GRANT USAGE ON SCHEMA autoaudit TO autoaudit_admin;
GRANT SELECT ON ALL TABLES IN SCHEMA autoaudit TO autoaudit_admin;
GRANT EXECUTE ON FUNCTION autoaudit.configurar_tabla(TEXT,TEXT,JSONB,JSONB,BOOLEAN) TO autoaudit_admin;
GRANT EXECUTE ON FUNCTION autoaudit.regenerar_triggers(BIGINT) TO autoaudit_admin;
-- No se concede INSERT/UPDATE/DELETE sobre la bitácora ni el detalle a autoaudit_admin.
-- Los triggers de seguridad definida escriben bajo el propietario del sistema.
-- Para la interfaz: CREATE ROLE aa_ui LOGIN PASSWORD 'CONTRASENA_SEGURA';
--                   GRANT autoaudit_admin TO aa_ui;
