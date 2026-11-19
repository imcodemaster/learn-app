"""Reads a database address such as postgres://user:password@host:5432/name.

Hosting services (Render, Railway, Heroku and others) give the database
connection as one DATABASE_URL value instead of separate DB_* settings.
"""

from urllib.parse import parse_qsl, unquote, urlsplit

_ENGINES = {
    "postgres": ("django.db.backends.postgresql", 5432),
    "postgresql": ("django.db.backends.postgresql", 5432),
    "mysql": ("django.db.backends.mysql", 3306),
}


def database_from_url(url: str) -> dict:
    """Django DATABASES["default"] entry for a postgres:// or mysql:// address."""
    parts = urlsplit(url.strip())
    scheme = parts.scheme.split("+", 1)[0].lower()
    if scheme not in _ENGINES:
        raise ValueError("DATABASE_URL must start with postgres://, postgresql:// or mysql://.")
    engine, default_port = _ENGINES[scheme]
    name = unquote(parts.path.lstrip("/"))
    if not name or not parts.hostname:
        raise ValueError("DATABASE_URL needs a host and a database name.")
    try:
        port = parts.port or default_port
    except ValueError as exc:
        raise ValueError("DATABASE_URL has an invalid port.") from exc
    config = {
        "ENGINE": engine,
        "NAME": name,
        "USER": unquote(parts.username or ""),
        "PASSWORD": unquote(parts.password or ""),
        "HOST": parts.hostname,
        "PORT": str(port),
        "CONN_MAX_AGE": 60,
    }
    options = dict(parse_qsl(parts.query))
    if scheme == "mysql":
        options = {"charset": "utf8mb4", "init_command": "SET sql_mode='STRICT_TRANS_TABLES'", **options}
    if options:
        config["OPTIONS"] = options
    return config
