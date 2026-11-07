# Diccionario de datos | AutoAudit

**Estudiante:** Hector Daniel Escobar Gramajo  
**Carné:** 2590-22-22530

Todas las tablas del sistema pertenecen al esquema `autoaudit`. Claves primarias de tipo `BIGINT GENERATED ALWAYS AS IDENTITY`.

## tabla_auditada

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador persistente de la tabla configurada. |
| esquema | TEXT | NOT NULL, UNIQUE compuesto | Esquema origen. |
| tabla | TEXT | NOT NULL, UNIQUE compuesto | Nombre de tabla origen. |
| habilitada | BOOLEAN | NOT NULL | Interruptor general de auditoría. |
| creada_en | TIMESTAMPTZ | DEFAULT | Fecha de alta. |
| actualizada_en | TIMESTAMPTZ | DEFAULT | Fecha de modificación. |

## columna_auditada

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de configuración de columna. |
| tabla_id | BIGINT | FK a tabla_auditada, RESTRICT | Tabla a la que pertenece. |
| columna | TEXT | UNIQUE (tabla_id, columna) | Nombre de columna del origen. |
| habilitada | BOOLEAN | NOT NULL | Estado de selección. |

## evento_auditado

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de evento. |
| tabla_id | BIGINT | FK a tabla_auditada, RESTRICT | Tabla origen. |
| operacion | TEXT | CHECK INSERT/UPDATE/DELETE | Operación DML. |
| habilitado | BOOLEAN | NOT NULL | Estado del evento. |

## columna_evento

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de regla detallada. |
| columna_id | BIGINT | FK a columna_auditada, RESTRICT | Columna configurada. |
| evento_id | BIGINT | FK a evento_auditado, RESTRICT | Operación configurada. |
| habilitado | BOOLEAN | NOT NULL | Activación de esta combinación. |

## usuario_auditado

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de actor de BD. |
| nombre | TEXT | UNIQUE, NOT NULL | Nombre obtenido de `session_user`. |
| creado_en | TIMESTAMPTZ | DEFAULT | Primera aparición. |

## estacion_trabajo

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de estación. |
| ip_origen | INET | Nullable | IP reportada por `inet_client_addr()`. |
| aplicacion | TEXT | NOT NULL | `application_name` de conexión. |

Par `(ip_origen, aplicacion)` único incluso cuando la IP sea NULL (PostgreSQL 18 `NULLS NOT DISTINCT`).

## bitacora

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de evento histórico. |
| tabla_id | BIGINT | FK a tabla_auditada | Configuración origen, conservada a largo plazo. |
| evento_id | BIGINT | FK a evento_auditado | Evento configurado. |
| usuario_id | BIGINT | FK a usuario_auditado | Actor de BD. |
| estacion_id | BIGINT | FK a estacion_trabajo | IP y aplicación de conexión. |
| operacion | TEXT | CHECK | INSERT / UPDATE / DELETE. |
| fecha_hora | TIMESTAMPTZ | DEFAULT clock_timestamp() | Hora de registro. |
| transaccion_id | BIGINT | DEFAULT txid_current() | Transacción PostgreSQL. |
| clave_primaria | JSONB | NOT NULL | Valores de PK del origen, si existe. |
| registro_anterior | JSONB | Nullable | Fila anterior completa (UPDATE/DELETE). |
| registro_nuevo | JSONB | Nullable | Fila nueva completa (INSERT/UPDATE). |

## detalle_cambio

| Campo | Tipo | Restricciones | Descripción |
|---|---|---|---|
| id | BIGINT | PK | Identificador de detalle. |
| bitacora_id | BIGINT | FK a bitacora, RESTRICT | Encabezado del evento. |
| columna_id | BIGINT | FK a columna_auditada, RESTRICT | Configuración de columna usada. |
| nombre_columna | TEXT | NOT NULL | Nombre histórico de la columna. |
| valor_anterior | JSONB | Nullable | Valor anterior de la columna. |
| valor_nuevo | JSONB | Nullable | Valor nuevo de la columna. |

## Cardinalidades del modelo

- `tabla_auditada` 1:N `columna_auditada`, 1:N `evento_auditado`, 1:N `bitacora`.
- `columna_auditada` N:M `evento_auditado` mediante `columna_evento`.
- `usuario_auditado` 1:N `bitacora`.
- `estacion_trabajo` 1:N `bitacora`.
- `evento_auditado` 1:N `bitacora`.
- `bitacora` 1:N `detalle_cambio`.
- `columna_auditada` 1:N `detalle_cambio`.

**Nota:** no se usan claves foráneas a las filas físicas de la tabla auditada, ya que esas filas pueden eliminarse y el historial debe sobrevivir.
