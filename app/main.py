
from __future__ import annotations

import csv
import hmac
import io
import json
import os
import secrets
from datetime import date
from functools import wraps

import psycopg
from dotenv import load_dotenv
from flask import Flask, Response, abort, flash, redirect, render_template, request, session, url_for
from psycopg.rows import dict_row
from psycopg.types.json import Jsonb

load_dotenv()

app = Flask(__name__)
app.config.update(
    SECRET_KEY=os.environ.get("FLASK_SECRET_KEY", ""),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    SESSION_COOKIE_SECURE=os.environ.get("COOKIE_SECURE", "0") == "1",
)


def settings_valid() -> None:
    needed = ("DATABASE_URL", "AUTOAUDIT_WEB_USER", "AUTOAUDIT_WEB_PASSWORD", "FLASK_SECRET_KEY")
    missing = [name for name in needed if not os.environ.get(name)]
    if missing:
        raise RuntimeError("Faltan variables requeridas: " + ", ".join(missing))


def conn():
    return psycopg.connect(os.environ["DATABASE_URL"], row_factory=dict_row)


def protected(handler):
    @wraps(handler)
    def wrapper(*args, **kwargs):
        auth = request.authorization
        user = os.environ.get("AUTOAUDIT_WEB_USER", "")
        pwd = os.environ.get("AUTOAUDIT_WEB_PASSWORD", "")
        valid = (
            auth is not None and auth.type.lower() == "basic"
            and bool(user) and bool(pwd)
            and hmac.compare_digest(auth.username or "", user)
            and hmac.compare_digest(auth.password or "", pwd)
        )
        if not valid:
            return Response(
                "Acceso exclusivo a administradores de AutoAudit.", 401,
                {"WWW-Authenticate": 'Basic realm="AutoAudit"'}
            )
        return handler(*args, **kwargs)
    return wrapper


def csrf() -> str:
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


def verify_csrf() -> None:
    expected = session.get("csrf", "")
    received = request.form.get("csrf", "")
    if not expected or not hmac.compare_digest(expected, received):
        abort(400, "Token de formulario inválido o sesión vencida")


@app.context_processor
def globals_for_templates():
    return {"csrf_token": csrf}


@app.route("/")
@protected
def index():
    sql = """
        SELECT n.nspname AS esquema, c.relname AS tabla, coalesce(t.habilitada, FALSE) AS habilitada,
               t.id AS configuracion_id,
               (SELECT count(*) FROM autoaudit.columna_auditada ca
                  WHERE ca.tabla_id = t.id AND ca.habilitada) AS columnas,
               (SELECT count(*) FROM autoaudit.evento_auditado ea
                  WHERE ea.tabla_id = t.id AND ea.habilitado) AS operaciones
          FROM pg_catalog.pg_class c
          JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
          LEFT JOIN autoaudit.tabla_auditada t
            ON t.esquema = n.nspname AND t.tabla = c.relname
         WHERE c.relkind = 'r' AND NOT c.relispartition
           AND n.nspname <> 'autoaudit' AND n.nspname <> 'information_schema'
           AND n.nspname !~ '^pg_'
         ORDER BY n.nspname, c.relname
    """
    with conn() as db, db.cursor() as cur:
        cur.execute(sql)
        tables = cur.fetchall()
        cur.execute("SELECT count(*) AS n FROM autoaudit.bitacora")
        total = cur.fetchone()["n"]
    return render_template("index.html", tables=tables, total=total)


@app.route("/configurar/<esquema>/<tabla>", methods=["GET", "POST"])
@protected
def configurar(esquema: str, tabla: str):
    with conn() as db, db.cursor() as cur:
        cur.execute("""
            SELECT a.attname AS nombre, pg_catalog.format_type(a.atttypid, a.atttypmod) AS tipo,
                   a.attnotnull AS obligatorio
              FROM pg_catalog.pg_attribute a
              JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
              JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
             WHERE n.nspname = %s AND c.relname = %s AND c.relkind = 'r'
               AND NOT c.relispartition AND n.nspname <> 'autoaudit'
               AND n.nspname <> 'information_schema' AND n.nspname !~ '^pg_'
               AND a.attnum > 0 AND NOT a.attisdropped
             ORDER BY a.attnum
        """, (esquema, tabla))
        columns = cur.fetchall()
        if not columns:
            abort(404, "Tabla no disponible para auditoría")

        cur.execute("""
            SELECT t.id, t.habilitada FROM autoaudit.tabla_auditada t
            WHERE t.esquema=%s AND t.tabla=%s
        """, (esquema, tabla))
        configured = cur.fetchone()
        active_rules = set()
        active_ops = {"INSERT", "UPDATE", "DELETE"}
        if configured:
            cur.execute("""
                SELECT c.columna, e.operacion
                  FROM autoaudit.columna_auditada c
                  JOIN autoaudit.columna_evento ce ON ce.columna_id = c.id
                  JOIN autoaudit.evento_auditado e ON e.id = ce.evento_id
                 WHERE c.tabla_id=%s AND c.habilitada AND ce.habilitado
            """, (configured["id"],))
            active_rules = {(r["columna"], r["operacion"]) for r in cur.fetchall()}
            cur.execute("""SELECT operacion FROM autoaudit.evento_auditado
                           WHERE tabla_id=%s AND habilitado""", (configured["id"],))
            active_ops = {r["operacion"] for r in cur.fetchall()}

        if request.method == "POST":
            verify_csrf()
            rules = {}
            for i, column in enumerate(columns):
                ops = [op for op in ("INSERT", "UPDATE", "DELETE")
                       if request.form.get(f"column_{i}_{op}") == "on"]
                if ops:
                    rules[column["nombre"]] = ops
            global_ops = [op for op in ("INSERT", "UPDATE", "DELETE")
                          if request.form.get(f"global_{op}") == "on"]
            enabled = request.form.get("enabled") == "on"
            if enabled and not any(set(ops).intersection(global_ops) for ops in rules.values()):
                flash("Seleccione por lo menos una columna y una operación global coincidente.", "error")
            else:
                try:
                    cur.execute(
                        "SELECT autoaudit.configurar_tabla(%s, %s, %s, %s, %s) AS id",
                        (esquema, tabla, Jsonb(rules), Jsonb(global_ops), enabled)
                    )
                    id_ = cur.fetchone()["id"]
                    db.commit()
                    flash(f"Configuración #{id_} guardada y triggers regenerados.", "ok")
                    return redirect(url_for("configurar", esquema=esquema, tabla=tabla))
                except psycopg.Error as err:
                    db.rollback()
                    flash("PostgreSQL rechazó la configuración: " + str(err).splitlines()[0], "error")
    return render_template("configure.html", esquema=esquema, tabla=tabla, columns=columns,
                           configured=configured, active_rules=active_rules, active_ops=active_ops)


def historial_query(args, limit=500):
    filters = []
    params = []
    if args.get("usuario", "").strip():
        filters.append("u.nombre = %s")
        params.append(args["usuario"].strip())
    if args.get("columna", "").strip():
        filters.append("EXISTS (SELECT 1 FROM autoaudit.detalle_cambio d2 WHERE d2.bitacora_id=b.id AND d2.nombre_columna=%s)")
        params.append(args["columna"].strip())
    if args.get("operacion", "") in {"INSERT", "UPDATE", "DELETE"}:
        filters.append("b.operacion = %s")
        params.append(args["operacion"])
    for param, op in (("inicio", ">="), ("fin", "<")):
        if args.get(param, "").strip():
            try:
                value = date.fromisoformat(args[param].strip())
            except ValueError:
                abort(400, "Fecha inválida")
            filters.append(f"b.fecha_hora {op} %s::date" + (" + INTERVAL '1 day'" if param == "fin" else ""))
            params.append(value)
    where = "WHERE " + " AND ".join(filters) if filters else ""
    query = f"""
        SELECT b.id, t.esquema, t.tabla, b.operacion, b.fecha_hora,
               u.nombre AS usuario, est.ip_origen::text AS ip_origen,
               est.aplicacion, b.clave_primaria,
               (SELECT string_agg(d.nombre_columna, ', ' ORDER BY d.nombre_columna)
                  FROM autoaudit.detalle_cambio d WHERE d.bitacora_id=b.id) AS columnas
          FROM autoaudit.bitacora b
          JOIN autoaudit.tabla_auditada t ON t.id=b.tabla_id
          JOIN autoaudit.usuario_auditado u ON u.id=b.usuario_id
          JOIN autoaudit.estacion_trabajo est ON est.id=b.estacion_id
        {where}
         ORDER BY b.fecha_hora DESC, b.id DESC LIMIT %s
    """
    return query, tuple(params + [limit])


@app.route("/historial")
@protected
def historial():
    query, params = historial_query(request.args)
    with conn() as db, db.cursor() as cur:
        cur.execute(query, params)
        rows = cur.fetchall()
    return render_template("reports.html", rows=rows, filters=request.args)


@app.route("/historial/exportar")
@protected
def exportar():
    query, params = historial_query(request.args, limit=10000)
    with conn() as db, db.cursor() as cur:
        cur.execute(query, params)
        rows = cur.fetchall()
    output = io.StringIO()
    output.write("\ufeff")  # Compatibilidad con hojas de cálculo UTF-8.
    fields = ["id", "esquema", "tabla", "operacion", "fecha_hora", "usuario", "ip_origen", "aplicacion", "clave_primaria", "columnas"]
    writer = csv.DictWriter(output, fieldnames=fields, quoting=csv.QUOTE_ALL)
    writer.writeheader()
    for row in rows:
        line = {}
        for field in fields:
            value = row.get(field)
            if isinstance(value, (dict, list)):
                value = json.dumps(value, ensure_ascii=False)
            value = "" if value is None else str(value)
            # Neutralizar fórmulas si se abre el CSV con Excel o LibreOffice.
            if value.startswith(("=", "+", "-", "@", "\t", "\r")):
                value = "'" + value
            line[field] = value
        writer.writerow(line)
    return Response(output.getvalue(), mimetype="text/csv; charset=utf-8", headers={
        "Content-Disposition": 'attachment; filename="autoaudit_historial.csv"'
    })


@app.route("/historial/<int:registro_id>")
@protected
def registro(registro_id: int):
    with conn() as db, db.cursor() as cur:
        cur.execute("SELECT * FROM autoaudit.v_historial WHERE id=%s", (registro_id,))
        row = cur.fetchone()
        if row is None:
            abort(404)
        cur.execute("""
            SELECT nombre_columna, valor_anterior, valor_nuevo FROM autoaudit.detalle_cambio
            WHERE bitacora_id=%s ORDER BY nombre_columna
        """, (registro_id,))
        details = cur.fetchall()
    before = json.dumps(row["registro_anterior"], ensure_ascii=False, indent=2)
    after = json.dumps(row["registro_nuevo"], ensure_ascii=False, indent=2)
    return render_template("detail.html", row=row, details=details, before=before, after=after)


if __name__ == "__main__":
    settings_valid()
    app.run(host=os.environ.get("FLASK_HOST", "127.0.0.1"),
            port=int(os.environ.get("FLASK_PORT", "5000")), debug=False)
