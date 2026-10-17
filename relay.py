"""LAN sighting relay. Python standard library only; no Roblox credentials."""
import argparse
import hmac
import json
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


class Store:
    def __init__(self, clock=time.monotonic, config_path=None):
        self.clock = clock
        self.lock = threading.Lock()
        self.rows = {}
        self.scans = {}
        self.config_path = Path(config_path) if config_path else None
        self.configs = {}
        if self.config_path and self.config_path.exists():
            self.configs = json.loads(self.config_path.read_text(encoding="utf-8"))

    def apply(self, action, data):
        room, actor = str(data.get("room", "")), str(data.get("actor", ""))
        if not room or not actor or len(room) > 100 or len(actor) > 100:
            raise ValueError("room and actor are required (maximum 100 characters)")
        now = self.clock()
        with self.lock:
            if action in ("settings-get", "settings-set"):
                current = self.configs.get(room, {"revision": 0, "values": {}})
                if action == "settings-set":
                    if data.get("revision") != current["revision"]:
                        return {"ok": True, "conflict": True, **current}
                    values = {**current["values"], **data.get("values", {})}
                    allowed = {"delay", "minlvl", "maxlvl", "tweenspeed", "onlygifted", "mainwait", "activate"}
                    if set(values) - allowed:
                        raise ValueError("unknown setting")
                    for key, lo, hi in (("delay", 0, 3600), ("minlvl", 1, 12), ("maxlvl", 1, 12), ("tweenspeed", 1, 120)):
                        value = values.get(key)
                        if value is not None and (type(value) not in (int, float) or not lo <= value <= hi
                                                  or key in ("minlvl", "maxlvl") and int(value) != value):
                            raise ValueError("invalid numeric setting")
                    if values.get("minlvl", 1) > values.get("maxlvl", 12):
                        raise ValueError("minimum exceeds maximum")
                    for key in ("onlygifted", "mainwait", "activate"):
                        if key in values and type(values[key]) is not bool:
                            raise ValueError("invalid boolean setting")
                    current = {"revision": current["revision"] + 1, "values": values}
                    updated = {**self.configs, room: current}
                    if self.config_path:
                        temp = self.config_path.with_suffix(".tmp")
                        temp.write_text(json.dumps(updated), encoding="utf-8")
                        temp.replace(self.config_path)
                    self.configs = updated
                return {"ok": True, **current}
            self.rows = {k: v for k, v in self.rows.items() if v["expires"] > now}
            self.scans = {k: v for k, v in self.scans.items() if v[1] > now}
            for row in self.rows.values():
                if row.get("lease", 0) <= now:
                    row.pop("owner", None)
            if action == "visit":
                job = str(data.get("job", ""))
                if not job or len(job) > 100:
                    raise ValueError("valid job required")
                key = (room, job)
                reserved = self.scans.get(key)
                available = not reserved or reserved[0] == actor
                if available:
                    self.scans[key] = (actor, now + 60)
                return {"ok": True, "available": available}
            if action == "report":
                job = str(data.get("job", ""))
                level = data.get("level")
                if not job or len(job) > 100 or type(level) is not int or not 1 <= level <= 12:
                    raise ValueError("valid job and level 1..12 required")
                if type(data.get("gifted")) is not bool:
                    raise ValueError("gifted must be a boolean")
                key = (room, job)
                row = self.rows.setdefault(key, {})
                row.update(job=job, room=room, level=level, gifted=data["gifted"],
                           field=str(data.get("field", ""))[:100], reporter=actor,
                           expires=max(now + 60, row.get("lease", 0) if row.get("owner") else 0))
                return {"ok": True}
            if action == "claim":
                low, high = int(data.get("minlvl", 1)), int(data.get("maxlvl", 12))
                excluded = set(data.get("exclude", []))
                choices = [r for (rm, _), r in self.rows.items()
                           if rm == room and low <= r["level"] <= high
                           and (not data.get("onlygifted") or r["gifted"])
                           and (not r.get("owner") or r["owner"] == actor)
                           and r["job"] not in excluded]
                if not choices:
                    return {"ok": True, "sighting": None}
                row = max(choices, key=lambda r: (r["gifted"], r["expires"]))
                row.update(owner=actor, lease=now + 90, expires=max(row["expires"], now + 90))
                return {"ok": True, "sighting": {k: row[k] for k in ("job", "level", "gifted", "field")}}
            if action in ("release", "consume", "withdraw", "renew"):
                key = (room, str(data.get("job", "")))
                row = self.rows.get(key)
                if row:
                    if action == "withdraw" and row.get("reporter") == actor:
                        # A main may already be on its way; preserve the reservation
                        # until it inspects the server, but stop offering this report.
                        if row.get("owner"):
                            row["expires"] = min(row["expires"], now + 20)
                        else:
                            self.rows.pop(key)
                    elif row.get("owner") == actor:
                        if action == "consume":
                            self.rows.pop(key)
                        elif action == "release":
                            row.pop("owner", None)
                        elif action == "renew":
                            row.update(lease=now + 90, expires=now + 90)
                return {"ok": True}
            raise ValueError("unknown action")


class Relay(ThreadingHTTPServer):
    daemon_threads = True

    def __init__(self, address, token, store=None):
        self.token, self.store = token, store or Store()
        super().__init__(address, Handler)


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass  # Do not log request bodies or tokens.

    def reply(self, status, value):
        body = json.dumps(value).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.connection.settimeout(10)
        if not hmac.compare_digest(self.headers.get("Authorization", ""), "Bearer " + self.server.token):
            return self.reply(401, {"error": "unauthorized"})
        try:
            length = int(self.headers.get("Content-Length", 0))
            if not 0 < length <= 16384:
                return self.reply(413, {"error": "body must be 1..16384 bytes"})
            data = json.loads(self.rfile.read(length))
            if not isinstance(data, dict):
                raise ValueError("JSON object required")
            result = self.server.store.apply(self.path.strip("/"), data)
            self.reply(200, result)
        except (ValueError, TypeError, KeyError):
            self.reply(400, {"error": "invalid request"})


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=8787)
    parser.add_argument("--token-file", default=str(Path(__file__).with_name("relay-token.txt")))
    args = parser.parse_args()
    token_path = Path(args.token_file)
    if not token_path.exists():
        token_path.write_text(secrets.token_urlsafe(32), encoding="utf-8")
    token = token_path.read_text(encoding="utf-8").strip()
    if len(token) < 24:
        parser.error("token must contain at least 24 characters")
    server = Relay((args.host, args.port), token,
                   Store(config_path=Path(__file__).with_name("room-settings.json")))
    print(f"Relay listening on {args.host}:{args.port}; token file: {token_path}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
