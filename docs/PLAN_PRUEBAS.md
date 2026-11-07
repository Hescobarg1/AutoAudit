# Plan de pruebas de validación

**Estudiante:** Hector Daniel Escobar Gramajo  
**Carné:** 2590-22-22530

## Casos funcionales

| ID | Procedimiento | Resultado esperado | Script |
|---|---|---|---|
| P01 | INSERT en tabla con nombre y saldo seleccionados | Evento INSERT, `registro_nuevo` completo y dos detalles | `tests/01_pruebas_funcionales.sql` |
| P02 | UPDATE únicamente de comentario no auditado | No se crea evento | `tests/01_pruebas_funcionales.sql` |
| P03 | UPDATE de saldo 10 a 20 | Evento UPDATE, valor antiguo 10 y nuevo 20 | `tests/01_pruebas_funcionales.sql` |
| P04 | DELETE de fila auditada | Evento DELETE, fila anterior conservada y nueva NULL | `tests/01_pruebas_funcionales.sql` |
| P05 | Deshabilitar auditoría y ejecutar INSERT | No se genera nueva bitácora; queda historial previo | `tests/01_pruebas_funcionales.sql` |
| P06 | Reactivar solo UPDATE de saldo | Registra actualización de saldo; no otros cambios | `tests/01_pruebas_funcionales.sql` |
| P07 | Probar selección de columna inexistente | Configuración rechazada con excepción | Manual / `configurar_tabla` |
| P08 | Filtrar por usuario y columna desde web | Devuelve solo coincidencias; sin pérdida de datos | UI `/historial` |
| P09 | Exportar CSV de un filtro | Archivo CSV UTF-8 con encabezados y datos | UI `/historial/exportar` |
| P10 | Conectar como rol sin privilegios administrativos | Rechaza configurar auditoría y escritura directa en bitácora | Manual |

## Rendimiento

`tests/02_rendimiento.sql` usa `EXPLAIN (ANALYZE, BUFFERS)` con lotes de 100, 1 000 y 5 000 filas, comparando inserciones con y sin auditoría. Las pruebas se organizan en tres volúmenes de inserción:

| Volumen | Escenario de referencia | Escenario auditado | Indicadores |
|---|---|---|---|
| 100 filas | Inserción sin auditoría | Inserción con triggers | Tiempo y buffers |
| 1 000 filas | Inserción sin auditoría | Inserción con triggers | Tiempo y buffers |
| 5 000 filas | Inserción sin auditoría | Inserción con triggers | Tiempo y buffers |

Fórmula de sobrecarga porcentual: `((con - sin) / sin) * 100`.

Las comparaciones usan un mismo motor y un mismo volumen de datos por escenario.

## Ejecución de pruebas

```bash
export DATABASE_ADMIN_URL='postgresql:///autoaudit_db?host=/var/run/postgresql'
sudo -u postgres env DATABASE_ADMIN_URL="$DATABASE_ADMIN_URL" bash scripts/ejecutar_pruebas.sh
sudo -u postgres psql -d autoaudit_db -v ON_ERROR_STOP=1 -f tests/02_rendimiento.sql
```

Los scripts usan `BEGIN` / `ROLLBACK`. Si una aserción falla, `psql` termina con un error (código distinto de 0 cuando se utiliza `ON_ERROR_STOP`).

