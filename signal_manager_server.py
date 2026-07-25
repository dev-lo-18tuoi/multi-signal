#!/usr/bin/env python3
"""Signal Manager — local web dashboard server.

Thin HTTP layer over signal-manager.sh (the engine). No external dependencies.
Security model: binds 127.0.0.1 only; every /api call requires the session
token (constant-time compared); Host header checked against localhost.

Modes:
  --launch  reuse healthy running server (same version) or spawn one, then
            open the dashboard in an app-style browser window
  --serve   run the HTTP server in the foreground (spawned detached by --launch)
"""

import json
import os
import re
import secrets
import subprocess
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
ENGINE = HERE / "signal-manager.sh"
UI_FILE = HERE / "signal-manager-ui.html"
STATE_DIR = Path.home() / "Library" / "Application Support" / "Signal Manager"
RUNTIME_FILE = STATE_DIR / "server.json"
META_FILE = STATE_DIR / "meta.json"
LOG_FILE = STATE_DIR / "server.log"
NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,31}$")
COLOR_RE = re.compile(r"^#[0-9a-fA-F]{6}$")
BASE = Path.home() / "Library" / "Application Support"
VERSION = "2.1.0"

TOKEN = ""  # set in serve()


# ---------- engine + meta helpers ----------

def engine(*args, timeout=60):
    """Run the shell engine; return (rc, stdout, stderr)."""
    p = subprocess.run(
        ["/bin/bash", str(ENGINE), *args],
        capture_output=True, text=True, timeout=timeout,
    )
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def load_meta():
    try:
        data = json.loads(META_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def save_meta(meta):
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    META_FILE.write_text(json.dumps(meta, ensure_ascii=False, indent=1))


def profile_path(name):
    return BASE / "Signal" if name == "__default__" else BASE / f"Signal-{name}"


# ---------- HTTP handler ----------

class Handler(BaseHTTPRequestHandler):
    server_version = "SignalManager/" + VERSION

    def log_message(self, fmt, *args):  # gọn log
        sys.stderr.write("%s %s\n" % (self.address_string(), fmt % args))

    # -- helpers --
    def _deny(self, code, msg):
        body = json.dumps({"error": msg}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _json(self, obj, code=200):
        body = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def _host_ok(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        return host in ("127.0.0.1", "localhost")

    def _auth_ok(self):
        tok = self.headers.get("X-Token") or ""
        if not tok:
            q = parse_qs(urlparse(self.path).query)
            tok = (q.get("token") or [""])[0]
        return secrets.compare_digest(tok, TOKEN)

    def _read_body(self):
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n > 65536:
                return None
            return json.loads(self.rfile.read(n) or b"{}")
        except Exception:
            return None

    # -- routes --
    def do_GET(self):
        if not self._host_ok():
            return self._deny(403, "bad host")
        path = urlparse(self.path).path
        if path == "/":
            try:
                body = UI_FILE.read_bytes()
            except OSError:
                return self._deny(500, "thiếu file giao diện")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)
            return
        if not self._auth_ok():
            return self._deny(401, "token sai hoặc thiếu")
        if path == "/api/ping":
            return self._json({"ok": True, "version": VERSION})
        if path == "/api/state":
            fast = "fast" in parse_qs(urlparse(self.path).query)
            args = ["state", "--fast"] if fast else ["state"]
            rc, out, err = engine(*args)
            if rc != 0:
                return self._deny(500, err or "engine state lỗi")
            profiles = json.loads(out)
            meta = load_meta()
            for p in profiles:
                m = meta.get(p["name"], {})
                p["nickname"] = m.get("nickname") or ""
                p["color"] = m.get("color") or ""
            return self._json({"profiles": profiles, "version": VERSION})
        return self._deny(404, "not found")

    def do_POST(self):
        if not self._host_ok():
            return self._deny(403, "bad host")
        if not self._auth_ok():
            return self._deny(401, "token sai hoặc thiếu")
        path = urlparse(self.path).path
        body = self._read_body()
        if body is None:
            return self._deny(400, "body không hợp lệ")
        name = str(body.get("name") or "")

        try:
            if path == "/api/open-all":
                rc, out, err = engine("open", "all", timeout=120)
            elif path == "/api/quit-all":
                rc, out, err = engine("quit", "all")
            elif path in ("/api/open", "/api/quit", "/api/add", "/api/remove"):
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                action = path.rsplit("/", 1)[1]
                target = "default" if name == "__default__" else name
                if action == "remove":
                    if name == "__default__":
                        return self._deny(400, "không thể xóa bản Signal chính")
                    rc, out, err = engine("remove", target, "--yes")
                    if rc == 0:
                        meta = load_meta()
                        meta.pop(name, None)
                        save_meta(meta)
                elif action == "add":
                    rc, out, err = engine("add", target)
                else:
                    rc, out, err = engine(action, target)
            elif path == "/api/autostart":
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                target = "default" if name == "__default__" else name
                mode = "on" if body.get("enable") else "off"
                rc, out, err = engine("autostart", target, mode)
            elif path == "/api/reveal":
                d = profile_path(name if name == "__default__" else name)
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                subprocess.run(["open", str(d)], check=False)
                rc, out, err = 0, "", ""
            elif path == "/api/meta":
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                meta = load_meta()
                entry = meta.get(name, {})
                if "nickname" in body:
                    nick = str(body["nickname"]).strip()[:40]
                    entry["nickname"] = nick
                if "color" in body:
                    color = str(body["color"])
                    if color and not COLOR_RE.match(color):
                        return self._deny(400, "màu không hợp lệ")
                    entry["color"] = color
                meta[name] = entry
                save_meta(meta)
                rc, out, err = 0, "", ""
            else:
                return self._deny(404, "not found")
        except subprocess.TimeoutExpired:
            return self._deny(500, "engine chạy quá lâu")

        if rc != 0:
            return self._deny(422, err or "thao tác thất bại")
        return self._json({"ok": True, "message": out})


# ---------- lifecycle ----------

def read_runtime():
    try:
        return json.loads(RUNTIME_FILE.read_text())
    except Exception:
        return None


def ping(info, timeout=1.0):
    """Return remote version if server healthy, else None."""
    try:
        req = urllib.request.Request(
            "http://127.0.0.1:%d/api/ping" % info["port"],
            headers={"X-Token": info["token"]},
        )
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.load(r)
            return data.get("version") if data.get("ok") else None
    except Exception:
        return None


def serve():
    global TOKEN
    TOKEN = secrets.token_hex(16)
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    httpd = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    port = httpd.server_address[1]
    RUNTIME_FILE.write_text(json.dumps(
        {"port": port, "token": TOKEN, "pid": os.getpid(), "version": VERSION}))
    os.chmod(RUNTIME_FILE, 0o600)
    sys.stderr.write("Signal Manager v%s http://127.0.0.1:%d\n" % (VERSION, port))
    httpd.serve_forever()


def open_browser(url):
    """Mở dạng app window (Chrome/Edge/Brave) nếu có, không thì browser mặc định."""
    for app in ("Google Chrome", "Microsoft Edge", "Brave Browser"):
        if Path("/Applications/%s.app" % app).exists():
            subprocess.run(["open", "-na", app, "--args", "--app=%s" % url], check=False)
            return
    subprocess.run(["open", url], check=False)


def launch():
    info = read_runtime()
    if info:
        ver = ping(info)
        if ver == VERSION:
            open_browser("http://127.0.0.1:%d/?token=%s" % (info["port"], info["token"]))
            return
        if ver is not None:
            # server cũ khác version → thay bằng bản mới
            try:
                os.kill(info["pid"], 15)
                time.sleep(0.5)
            except OSError:
                pass
    # spawn server mới, tách hẳn khỏi process này
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    with open(LOG_FILE, "ab") as log:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--serve"],
            stdout=log, stderr=log, start_new_session=True,
        )
    # chờ server lên (tối đa 6s)
    for _ in range(60):
        time.sleep(0.1)
        info = read_runtime()
        if info and ping(info, timeout=0.3) == VERSION:
            open_browser("http://127.0.0.1:%d/?token=%s" % (info["port"], info["token"]))
            return
    sys.exit("Không khởi động được server — xem log: %s" % LOG_FILE)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--launch"
    if mode == "--serve":
        serve()
    else:
        launch()
