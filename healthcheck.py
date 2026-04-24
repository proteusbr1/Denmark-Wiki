#!/usr/bin/env python3
"""Health sidecar para o demark-wiki (Wiki.js).

Wiki.js expõe /healthz nativo, mas é apenas liveness (não valida DB).
Este sidecar agrega os 2 concerns reais do projeto e responde no padrão
comum ({"status":"ok"} / {"status":"degraded"}).

  GET /health         → 200 sempre (liveness do próprio sidecar)
  GET /health/ready   → 200 se checks passam, 503 caso contrário

Checks:
  - http://wiki:3000/healthz  retorna 200 + "ok":true  (processo Wiki.js vivo)
  - db:5432 aceita TCP                                  (Postgres respondendo)
"""
import json
import socket
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

TIMEOUT = 3.0
WIKI_URL = "http://wiki:3000/healthz"
DB_HOST = "db"
DB_PORT = 5432


def check_wiki():
    try:
        with urllib.request.urlopen(WIKI_URL, timeout=TIMEOUT) as r:
            if not (200 <= r.status < 300):
                return False, f"http={r.status}"
            body = r.read(200).decode(errors="ignore")
            if '"ok":true' not in body.replace(" ", ""):
                return False, "body não contém ok:true"
            return True, None
    except urllib.error.HTTPError as e:
        return False, f"http={e.code}"
    except (urllib.error.URLError, socket.timeout, OSError) as e:
        return False, str(e)


def check_postgres():
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=TIMEOUT):
            return True, None
    except OSError as e:
        return False, f"tcp {DB_HOST}:{DB_PORT}: {e}"


def run_checks():
    results: dict[str, dict[str, object]] = {}
    for name, fn in (("wiki", check_wiki), ("postgres", check_postgres)):
        ok, err = fn()
        entry: dict[str, object] = {"healthy": ok}
        if err:
            entry["error"] = err
        results[name] = entry
    return all(bool(r["healthy"]) for r in results.values()), results


class Handler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args: object) -> None:
        return

    def _write(self, status: int, body: dict):
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path == "/health":
            self._write(200, {"status": "ok", "checks": {}})
        elif self.path == "/health/ready":
            ok, checks = run_checks()
            self._write(
                200 if ok else 503,
                {"status": "ok" if ok else "degraded", "checks": checks},
            )
        else:
            self.send_response(404)
            self.end_headers()


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
