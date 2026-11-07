# AutoAudit | Sistema de auditoría automatizada

Proyecto del curso **Bases de Datos I**, Universidad Mariano Gálvez de Guatemala, según especificación «AutoAudit - proy - bd1», agosto 2026.

## Características

- Selección de tablas ordinarias y columnas desde el catálogo de PostgreSQL.
- Reglas por columna y por operación (`INSERT`, `UPDATE`, `DELETE`).
- Generación automática de triggers `AFTER` específicos de cada tabla.
- Bitácora central con usuario de BD, fecha/hora, dirección IP de conexión, nombre de aplicación, identificador de transacción, clave primaria, registro anterior y nuevo.
- Detalle normalizado de valores antiguos y nuevos por columna modificada.
- Consulta por usuario, por columna, por operación y período, con exportación CSV.
- Interfaz web administrativa local en Flask.
- Pruebas de INSERT, UPDATE, DELETE, desactivación, reactivación y rendimiento.


## Requisitos

- Ubuntu 26.04 LTS, PostgreSQL 18 y `psql` del mismo servidor.
- Python 3.12+ y entorno virtual (`python3-venv`), conexión a PostgreSQL.
- Cuenta administradora para instalar y crear el rol `aa_ui`.
- `DATABASE_ADMIN_URL` con la conexión administrativa a una **base ya creada**.

## Inicio rápido en Ubuntu

**1. Crear la base de datos con un administrador PostgreSQL:**

```bash
sudo -u postgres createdb autoaudit_db
```

**2. Instalar esquema, funciones y permisos:**

```bash
export DATABASE_ADMIN_URL='postgresql:///autoaudit_db?host=/var/run/postgresql'
# Si su usuario de SO no es administrador de BD, ejecute como postgres:
sudo -u postgres env DATABASE_ADMIN_URL="$DATABASE_ADMIN_URL" bash scripts/instalar.sh
```

Alternativa manual: ejecute, en orden, `sql/01_schema.sql`, `sql/02_functions.sql` y `sql/03_security.sql` desde `psql` usando el usuario propietario. El script no crea la base de datos.

**3. Crear el usuario de la interfaz:**

En `psql` como administrador (reemplazar la clave antes de ejecutar):

```sql
CREATE ROLE aa_ui LOGIN PASSWORD 'CLAVE_LARGA_Y_UNICA';
GRANT CONNECT ON DATABASE autoaudit_db TO aa_ui;
GRANT autoaudit_admin TO aa_ui;
```

Los cambios en tablas de negocio los realizan sus usuarios de BD, no la cuenta de la interfaz. Para que la instalación de triggers funcione en cualquier tabla, el **propietario de las funciones** debe disponer de privilegio `TRIGGER` en esa tabla. Instalar como `postgres` cubre el ambiente docente local. En producción, gestione permisos explícitos.

**4. Preparar la interfaz y las variables:**

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Editar .env: DATABASE_URL, AUTOAUDIT_WEB_USER, AUTOAUDIT_WEB_PASSWORD, FLASK_SECRET_KEY
python run.py
```

La interfaz queda en `http://127.0.0.1:5000` (con autenticación HTTP Basic). **No publique este servidor de desarrollo en Internet.** En un despliegue real, use HTTPS, proxy autenticado y servidor WSGI.

**5. Ejemplo opcional y pruebas:**

```bash
sudo -u postgres psql -d autoaudit_db -v ON_ERROR_STOP=1 -f sql/05_demo.sql
sudo -u postgres psql -d autoaudit_db -v ON_ERROR_STOP=1 -f tests/01_pruebas_funcionales.sql
sudo -u postgres psql -d autoaudit_db -v ON_ERROR_STOP=1 -f tests/02_rendimiento.sql
```

La prueba funcional está dentro de una transacción y termina en `ROLLBACK`: no deja tablas de pruebas. La prueba de rendimiento también se revierte, pero mide tiempos reales si se ejecuta en PostgreSQL.

## Uso solo con SQL

```sql
CREATE TABLE public.clientes (id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
                              nombre TEXT NOT NULL, saldo NUMERIC(12,2));
SELECT autoaudit.configurar_tabla(
  'public', 'clientes',
  '{"nombre":["INSERT","UPDATE","DELETE"],"saldo":["UPDATE","DELETE"]}'::jsonb,
  '["INSERT","UPDATE","DELETE"]'::jsonb,
  TRUE);
-- Triggers generados en public.clientes: aa_i_ID, aa_u_ID, aa_d_ID.
SELECT * FROM autoaudit.v_historial ORDER BY fecha_hora DESC;
```

Para apagar sin borrar historial:

```sql
SELECT autoaudit.configurar_tabla(
  'public', 'clientes', '{"saldo":["UPDATE"]}'::jsonb,
  '["UPDATE"]'::jsonb, FALSE);
```

Para activarlo nuevamente, establezca `TRUE` en el último parámetro. El SQL valida la tabla y columnas antes de aplicar reglas.

## Estructura de entregables

```text
AutoAudit/
├── docs/                    # PDF técnico, MER/ER, diccionario y manuales
├── sql/                     # DDL, PL/pgSQL, seguridad, consultas y demostración
├── app/                     # Interfaz Flask, HTML y CSS
├── tests/                   # Pruebas transaccionales y rendimiento
├── scripts/                 # Instalación y pruebas
├── run.py                   # Punto de entrada web
├── requirements.txt         # Dependencias Python
└── .env.example             # Variables requeridas sin contraseñas reales
```

## Consideraciones de integridad y seguridad

1. Los registros se guardan en dos niveles: `bitacora` almacena la fila completa como JSONB y `detalle_cambio` almacena los cambios por columna. El origen no tiene una FK física desde la bitácora: eso rompería el historial cuando el registro se elimine. La referencia estable es a la **configuración de la tabla origen**, que no se elimina al deshabilitarla.
2. El usuario registrado es `session_user` de PostgreSQL, no un nombre que un cliente pueda arbitrariamente declarar. Si varios usuarios humanos comparten la misma conexión de BD, aparecerá la cuenta compartida y debe añadirse una integración de identidad verificada.
3. La dirección IP procede de `inet_client_addr()`; puede quedar en `NULL` para conexiones mediante socket local y puede ser la IP del proxy de conexiones en una arquitectura con pool.
4. Las funciones del trigger usan `SECURITY DEFINER` para escribir en la bitácora sin otorgar `INSERT` directo a los usuarios ordinarios. Solo miembros de `autoaudit_admin` pueden llamar a `configurar_tabla`.
5. La auditoría se ejecuta en la **misma transacción** que el cambio original: si la transacción falla o revierte, su bitácora también revierte. Para registrar intentos fallidos o cambios DDL/`TRUNCATE` se necesitaría otro mecanismo.
6. `UPDATE` genera bitácora solo cuando cambia un valor de una columna habilitada. Se conserva la estructura para reactivar y se retienen datos de auditoría al desactivar.
7. Por simplicidad académica, se incluyen solo tablas ordinarias no particionadas. La UI no gestiona `TRUNCATE`, DDL ni modificaciones hechas por superusuarios que alteren triggers.
8. Capturar datos personales en JSONB puede requerir mascarado, retención y cumplimiento de las políticas de privacidad vigentes. No configure columnas sensibles sin autorización.

## Publicación del repositorio

El PDF exige **un enlace real de GitHub o GitLab**, que debe crearse desde la cuenta del estudiante. Este paquete está listo para subirlo:

```bash
git init
git add .
git commit -m "AutoAudit: sistema de auditoría PostgreSQL"
git branch -M main
git remote add origin https://github.com/USUARIO/AutoAudit.git
git push -u origin main
```

Reemplace `USUARIO` por su usuario y cree antes el repositorio vacío en GitHub. El archivo `.gitignore` evita subir `.env`.

