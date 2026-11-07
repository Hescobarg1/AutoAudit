# Manual de configuración y activación

**Estudiante:** Hector Daniel Escobar Gramajo  
**Carné:** 2590-22-22530

## Acceso y activación

1. Instalar PostgreSQL 18 en Ubuntu 26.04 LTS y crear la base `autoaudit_db`.
2. Ejecutar `sql/01_schema.sql`, `sql/02_functions.sql`, `sql/03_security.sql` en ese orden como administrador, o usar `scripts/instalar.sh`.
3. Crear el usuario `aa_ui`, con `GRANT autoaudit_admin TO aa_ui`; editar `.env` y ejecutar `python run.py`.
4. Abrir `http://127.0.0.1:5000` e introducir las credenciales del administrador web.
5. Hacer clic en **Configurar** junto a una tabla ordinaria de usuario.
6. Marcar o desmarcar las tres operaciones generales, las casillas correspondientes a cada columna y el estado «Auditoría habilitada».
7. Pulsar **Guardar y generar triggers**. PostgreSQL valida la configuración, conserva las claves históricas, elimina los triggers anteriores de AutoAudit y genera solo los requeridos.
8. Realizar operaciones de prueba `INSERT`, `UPDATE`, `DELETE` con un usuario que tenga permisos sobre la tabla y consultar **Historial**.
9. Filtrar por usuario de PostgreSQL, columna, operación y fechas; abrir el detalle del evento o exportar un CSV.

## Ejemplo técnico

```sql
SELECT autoaudit.configurar_tabla(
 'demo','clientes',
 '{"nombre":["INSERT","UPDATE","DELETE"],"saldo":["UPDATE","DELETE"]}'::jsonb,
 '["INSERT","UPDATE","DELETE"]'::jsonb, TRUE);
```

La configuración produce un trigger `AFTER` por operación habilitada, cada uno unido exclusivamente a `demo.clientes`. Si la única columna configurada para `UPDATE` es `saldo`, modificar `correo` no agrega bitácora. Un `DELETE` conserva `registro_anterior`, y los cambios almacenados siguen siendo consultables después de borrar el origen.

## Validación y despliegue de triggers

- La función `configurar_tabla` valida esquema, tipo de relación y columnas mediante `pg_class`, `pg_namespace`, `pg_attribute`.
- `regenerar_triggers` elimina los nombres asociados a esa configuración y los vuelve a crear con `format('%I', identificador)` para impedir inyección por identificadores.
- La función `capturar_cambio` obtiene la configuración activa y guarda los registros en JSONB en la misma transacción del cambio.
- Puede ver triggers activos con:

```sql
SELECT tgname, pg_get_triggerdef(oid) AS definicion
FROM pg_catalog.pg_trigger
WHERE tgrelid = 'demo.clientes'::regclass AND NOT tgisinternal;
```

## Desactivación

En la web, desmarcar «Auditoría habilitada» y guardar. En SQL, llamar a `configurar_tabla` con último argumento `FALSE`. Para reactivar, usar `TRUE` y la selección requerida.

## Seguridad

Las credenciales deben mantenerse fuera de Git. Limite el servidor web a localhost o utilice TLS y un proxy autenticado. Proteja la base con controles de acceso y permisos mínimos. `session_user` registra la identidad de la conexión de BD, e `inet_client_addr()` la IP observada por PostgreSQL. Conexiones por socket no reportan IP.
