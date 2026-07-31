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
import plistlib
import re
import secrets
import subprocess
import sys
import threading
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
VERSION = "2.9.0"
SIGNAL_PLIST = Path("/Applications/Signal.app/Contents/Info.plist")
SHIPIT_CACHE = Path.home() / "Library" / "Caches" / "org.whispersystems.signal-desktop.ShipIt"
RAW_SELF = ("https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/"
            "signal_manager_server.py")
INSTALL_URL = ("https://raw.githubusercontent.com/dev-lo-18tuoi/multi-signal/main/"
               "install.sh")

TOKEN = ""  # set in serve()
_latest_cache = {"at": 0.0, "ver": None}  # cache 6h cho check bản mới
# Ý muốn của user: account nào user CHỦ ĐỘNG tắt qua tool thì watchdog 🛡
# không tự mở lại (đến khi user mở lại). "__ALL__" = vừa bấm Tắt tất cả.
_quit_intent = {}


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
        if path == "/api/latest":
            # phiên bản mới nhất trên GitHub (cache 6h, lỗi mạng → coi như bằng hiện tại)
            now = time.time()
            if now - _latest_cache["at"] > 6 * 3600 or not _latest_cache["ver"]:
                latest = VERSION
                try:
                    with urllib.request.urlopen(RAW_SELF, timeout=4) as r:
                        m = re.search(rb'VERSION = "([0-9.]+)"', r.read())
                        if m:
                            latest = m.group(1).decode()
                except Exception:
                    pass
                _latest_cache.update(at=now, ver=latest)
            return self._json({"current": VERSION, "latest": _latest_cache["ver"]})
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
                p["keepalive"] = bool(m.get("keepalive"))
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
                _quit_intent.clear()
                rc, out, err = engine("open", "all", timeout=120)
            elif path == "/api/quit-all":
                _quit_intent["__ALL__"] = True
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
                    # ghi nhận ý muốn để watchdog 🛡 hành xử đúng
                    if action == "quit":
                        _quit_intent[name] = True
                    elif action == "open":
                        _quit_intent.pop(name, None)
                        _quit_intent.pop("__ALL__", None)
                    rc, out, err = engine(action, target)
            elif path == "/api/autostart":
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                target = "default" if name == "__default__" else name
                mode = "on" if body.get("enable") else "off"
                rc, out, err = engine("autostart", target, mode)
            elif path == "/api/clean":
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                target = "default" if name == "__default__" else name
                rc, out, err = engine("clean", target, timeout=120)
                if rc == 0:
                    m = re.search(r"FREED_KB=(\d+)", out)
                    return self._json({"ok": True, "freed_kb": int(m.group(1)) if m else 0})
            elif path == "/api/reveal":
                d = profile_path(name if name == "__default__" else name)
                if name != "__default__" and not NAME_RE.match(name):
                    return self._deny(400, "tên account không hợp lệ")
                subprocess.run(["open", str(d)], check=False)
                rc, out, err = 0, "", ""
            elif path == "/api/self-update":
                # tải installer chính thức và chạy — app bundle được thay bằng bản mới;
                # server hiện tại sẽ tự bị thay ở lần mở app kế tiếp (so version)
                p = subprocess.run(
                    ["/bin/bash", "-c", "curl -fsSL '%s' | bash" % INSTALL_URL],
                    capture_output=True, text=True, timeout=300,
                )
                rc, out, err = p.returncode, p.stdout.strip(), p.stderr.strip()
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
                if "keepalive" in body:
                    entry["keepalive"] = bool(body["keepalive"])
                    if entry["keepalive"]:
                        _quit_intent.pop(name, None)
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


def notify_mac(msg):
    msg = msg.replace('"', "").replace("\\", "")
    subprocess.run(
        ["osascript", "-e",
         'display notification "%s" with title "Signal Manager 🦆"' % msg],
        check=False, timeout=10)


def signal_version():
    try:
        with open(SIGNAL_PLIST, "rb") as f:
            return plistlib.load(f).get("CFBundleShortVersionString", "?")
    except Exception:
        return "?"


def latest_signal_version():
    """Phiên bản Signal mới nhất theo feed chính thức; lỗi mạng → None."""
    for host in ("updates.signal.org", "updates2.signal.org"):
        try:
            req = urllib.request.Request(
                "https://%s/desktop/latest-mac.yml" % host,
                headers={"User-Agent": "SignalManager/" + VERSION})  # CDN chặn UA mặc định của Python (403)
            with urllib.request.urlopen(req, timeout=6) as r:
                m = re.search(rb"^version:\s*([0-9.]+)", r.read(), re.M)
                if m:
                    return m.group(1).decode()
        except Exception:
            continue
    return None


def ver_tuple(v):
    try:
        return tuple(int(x) for x in str(v).split("."))
    except ValueError:
        return (0,)


def running_profiles():
    """Danh sách target đang chạy theo engine state (['default', '3', ...])."""
    rc, out, _ = engine("state", "--fast", timeout=20)
    if rc != 0:
        return []
    result = []
    for p in json.loads(out):
        if p.get("running"):
            result.append("default" if p.get("is_default") else p["name"])
    return result


def update_stuck():
    """Log của profile nào đó có lỗi updater trong 45 phút gần đây?"""
    now = time.time()
    for d in BASE.glob("Signal*"):
        log = d / "logs" / "main.log"
        if not log.is_file():
            continue
        try:
            with open(log, "rb") as f:
                f.seek(max(0, log.stat().st_size - 80_000))
                tail = f.read().decode("utf-8", "replace")
        except OSError:
            continue
        for line in tail.splitlines():
            if '"level":50' not in line:
                continue
            if "Cannot_Update" not in line and "updater" not in line:
                continue
            m = re.search(r'"time":"([0-9T:.\-]+)Z?"', line)
            if not m:
                continue
            try:
                ts = time.mktime(time.strptime(m.group(1)[:19], "%Y-%m-%dT%H:%M:%S"))
                # log ghi giờ UTC
                if now - (ts - time.timezone) < 45 * 60:
                    return True
            except ValueError:
                continue
    return False


_last_heal = {"at": 0.0}


def heal_signal_update():
    """Tự chữa update kẹt: tắt hết → macOS swap bundle → (nếu cần) dọn cache và
    cho 1 instance tải lại → mở lại đúng các account đang chạy trước đó."""
    saved = running_profiles()
    if not saved:
        return  # không có gì đang chạy — lần mở tới sẽ tự nhận bản mới
    v0 = signal_version()
    notify_mac("Signal có bản mới — đang tự cập nhật (~2 phút), các cửa sổ sẽ tạm đóng")
    engine("quit", "all", timeout=60)
    time.sleep(30)  # ShipIt thay bundle ngay khi mọi instance thoát
    if signal_version() == v0:
        # gói dàn dựng hỏng → dọn, cho MỘT instance tải lại một mình
        subprocess.run(["rm", "-rf", str(SHIPIT_CACHE)], check=False)
        engine("open", "default", timeout=30)
        time.sleep(240)  # chờ tải bản mới (updater tự chạy lúc khởi động)
        engine("quit", "default", timeout=60)
        time.sleep(30)
    v1 = signal_version()
    for target in saved:
        engine("open", target, timeout=30)
        time.sleep(1)
    if v1 != v0:
        notify_mac("✅ Đã cập nhật Signal %s → %s, các account đã mở lại" % (v0, v1))
    else:
        notify_mac("⚠️ Chưa cập nhật được Signal — xem mục FAQ trên GitHub")
        _last_heal["at"] = time.time() + 10 * 3600  # đừng thử lại liên tục


# Watchdog 🛡: (1) "Giữ luôn chạy" — account bật keepalive bị đóng NGOÀI ý muốn
# → tự mở lại; (2) mỗi ~10 phút khám log updater — Signal update kẹt do nhiều
# instance → tự chữa theo quy trình heal_signal_update.
def watchdog():
    tick = 0
    while True:
        time.sleep(45)
        tick += 1
        try:
            if tick % 13 == 0 and time.time() - _last_heal["at"] > 2 * 3600:
                if update_stuck():
                    latest = latest_signal_version()
                    # chỉ chữa khi THẬT SỰ còn bản mới chưa cài (tránh vết lỗi cũ)
                    if latest and ver_tuple(latest) > ver_tuple(signal_version()):
                        _last_heal["at"] = time.time()
                        heal_signal_update()
                        continue
        except Exception:
            pass
        try:
            rc, out, _ = engine("state", "--fast", timeout=20)
            if rc != 0:
                continue
            meta = load_meta()
            for p in json.loads(out):
                nm = p.get("name", "")
                m = meta.get(nm, {})
                if not m.get("keepalive"):
                    continue
                if p.get("running") or _quit_intent.get(nm) or _quit_intent.get("__ALL__"):
                    continue
                target = "default" if nm == "__default__" else nm
                engine("open", target, timeout=30)
                nick = m.get("nickname") or ("Signal chính" if nm == "__default__" else nm)
                nick = nick.replace('"', "").replace("\\", "")
                subprocess.run(
                    ["osascript", "-e",
                     'display notification "Đã tự mở lại %s (bị đóng ngoài ý muốn)" '
                     'with title "Signal Manager 🛡"' % nick],
                    check=False, timeout=10)
        except Exception:
            pass


def serve():
    global TOKEN
    TOKEN = secrets.token_hex(16)
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    threading.Thread(target=watchdog, daemon=True).start()
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


def launch(open_in_browser=True):
    """Đảm bảo server đúng version đang chạy; mở browser hoặc chỉ in URL."""
    def done(info):
        url = "http://127.0.0.1:%d/?token=%s" % (info["port"], info["token"])
        if open_in_browser:
            open_browser(url)
        else:
            print(url)

    info = read_runtime()
    if info:
        ver = ping(info)
        if ver == VERSION:
            return done(info)
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
            return done(info)
    sys.exit("Không khởi động được server — xem log: %s" % LOG_FILE)


if __name__ == "__main__":
    mode = sys.argv[1] if len(sys.argv) > 1 else "--launch"
    if mode == "--serve":
        serve()
    elif mode == "--url":
        launch(open_in_browser=False)
    else:
        launch()
