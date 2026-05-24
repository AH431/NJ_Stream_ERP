"""Shared sync psycopg2 connector — run via asyncio.to_thread."""

import os

import psycopg2
import psycopg2.extras


def db_connect() -> psycopg2.extensions.connection:
    url = os.environ.get("DATABASE_URL", "")
    if not url:
        raise RuntimeError("DATABASE_URL not configured")
    return psycopg2.connect(url, cursor_factory=psycopg2.extras.RealDictCursor)
