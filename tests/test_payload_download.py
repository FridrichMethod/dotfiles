"""Loopback download deadlines, the failed-download latch and private staging cleanup."""

import contextlib
import http.client
import http.server
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import time
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
PWSH = shutil.which("pwsh")
BODY = b"# a slowly delivered installer\nexit 0\n"


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *_args):
        pass

    def do_GET(self):
        if self.path == "/ready":
            # Fixture setup is separate from the downloads under test.
            self.send_response(204)
            self.end_headers()
            return
        self.server.requests.append(self.path)
        body = b"" if self.path == "/empty" else BODY
        self.send_response(200)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.server.headers_sent.append(time.monotonic())
        try:
            if self.path == "/stall":
                self.wfile.write(body[:1])
                self.wfile.flush()
                self.server.stop.wait(5)
            elif self.path == "/trickle":
                for byte in body:
                    self.wfile.write(bytes([byte]))
                    self.wfile.flush()
                    if self.server.stop.wait(0.12):
                        break
            else:
                self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass


@contextlib.contextmanager
def server():
    httpd = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    httpd.daemon_threads = True
    httpd.requests = []
    httpd.headers_sent = []
    httpd.stop = threading.Event()
    worker = threading.Thread(target=httpd.serve_forever, daemon=True)
    worker.start()
    try:
        # Binding/listening does not mean the worker can handle a request yet.
        # Complete a direct loopback exchange before starting the 1s download
        # deadline; stdlib HTTPConnection does not consult proxy settings.
        with contextlib.closing(http.client.HTTPConnection("127.0.0.1", httpd.server_port,
                                                          timeout=5)) as client:
            client.request("GET", "/ready")
            response = client.getresponse()
            if response.status != 204 or response.read():
                raise RuntimeError("loopback server readiness check failed")
        yield httpd
    finally:
        httpd.stop.set()
        httpd.shutdown()
        httpd.server_close()
        worker.join(5)


class ServerReadiness(unittest.TestCase):
    def test_server_startup_is_outside_request_deadline(self):
        serve_forever = http.server.ThreadingHTTPServer.serve_forever

        def delayed_start(httpd):
            # Longer than the request deadline: setup must wait for service,
            # rather than spend the downloader's budget starting the fixture.
            time.sleep(1.2)
            serve_forever(httpd)

        with mock.patch.object(http.server.ThreadingHTTPServer, "serve_forever", delayed_start):
            with server() as httpd:
                with contextlib.closing(http.client.HTTPConnection("127.0.0.1", httpd.server_port,
                                                                  timeout=1)) as client:
                    try:
                        client.request("GET", "/ok")
                        response = client.getresponse()
                        self.assertEqual(response.status, 200)
                        self.assertEqual(response.read(), BODY)
                    except TimeoutError:
                        self.fail("loopback server startup consumed the request deadline")
                self.assertEqual(httpd.requests, ["/ok"])
                self.assertEqual(len(httpd.headers_sent), 1)


class PayloadDownload(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="dotfiles-payload-http-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.home = self.root / "home"
        for directory in ("scripts", "config", "lib"):
            (self.repo / directory).mkdir(parents=True)
        self.home.mkdir()
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.env = {
            key: value for key, value in os.environ.items()
            if not key.startswith(("GIT_", "DOTFILES_", "_DOTFILES_", "AWESOME_SKILLS_", "CODING_AGENT_KIT_", "XDG_"))
        }
        self.env.update({
            "HOME": str(self.home), "LOCALAPPDATA": str(self.home / "data"),
            "TMPDIR": str(self.root), "TMP": str(self.root), "TEMP": str(self.root),
            "XDG_CACHE_HOME": str(self.home / "cache"), "XDG_CONFIG_HOME": str(self.home / "config"),
            "XDG_DATA_HOME": str(self.home / "share"), "XDG_STATE_HOME": str(self.home / "state"),
            "DOTFILES_PAYLOAD_TIMEOUT": "1", "NO_PROXY": "127.0.0.1", "no_proxy": "127.0.0.1",
            "POWERSHELL_TELEMETRY_OPTOUT": "1", "POWERSHELL_UPDATECHECK": "Off",
        })
        for suffix in ("sh", "ps1"):
            shutil.copyfile(ROOT / f"scripts/payload-update.{suffix}", self.repo / f"scripts/payload-update.{suffix}")
            shutil.copyfile(ROOT / f"lib/terminal.{suffix}", self.repo / f"lib/terminal.{suffix}")

    def configure(self, kind, first, second=None):
        lines = []
        for name, source in (("pymol", first), ("skills", second)):
            if source is None:
                continue
            command = f"payload_script sh '{source}'" if kind == "sh" else f"Invoke-DotfilesPayloadScript '{source}'"
            platform = "unix" if kind == "sh" else "windows"
            # Any row names a known item; none of them needs a days row.
            lines.extend((f"{name}\t{platform}-probe\t{'false' if kind == 'sh' else '$false'}",
                          f"{name}\t{platform}-install\t{command}"))
        (self.repo / "config/payloads.tsv").write_text("\n".join(lines) + "\n")

    def shell_path(self, backend, deadline="timeout"):
        if os.name == "nt":
            self.skipTest("POSIX payload backend")
        for name in ("sh", "bash", "date", "mkdir", "mktemp", "mv", "rm", "cat", "dirname"):
            executable = shutil.which(name)
            self.assertIsNotNone(executable, name)
            (self.bin / name).symlink_to(executable)
        if backend:
            executable = shutil.which(backend)
            if not executable:
                self.skipTest(f"{backend} unavailable")
            (self.bin / backend).symlink_to(executable)
        if backend == "wget" and deadline:
            executable = shutil.which("timeout") or shutil.which("gtimeout")
            if not executable:
                self.skipTest("timeout/gtimeout unavailable")
            (self.bin / deadline).symlink_to(executable)
        self.env["PATH"] = str(self.bin)

    def command(self, kind, both=False):
        items = ["pymol", "skills"] if both else ["pymol"]
        if kind == "sh":
            return [str(self.bin / "sh"), str(self.repo / "scripts/payload-update.sh"), "--now", *items]
        if not PWSH:
            self.skipTest("pwsh unavailable")
        return [PWSH, "-NoProfile", "-NonInteractive", "-File", str(self.repo / "scripts/payload-update.ps1"), "-Now", *items]

    def assert_no_state(self):
        # The hook keeps no state of its own.
        self.assertFalse((self.home / "state").exists())
        self.assertFalse((self.home / "data/dotfiles").exists())

    def run_hook(self, kind, both=False):
        start = time.monotonic()
        result = subprocess.run(self.command(kind, both), env=self.env, cwd=self.root,
                                capture_output=True, text=True, timeout=15)
        return result, time.monotonic() - start

    def check_download(self, kind, path, backend=None, deadline="timeout"):
        if kind == "sh":
            self.shell_path(backend, deadline)
        with server() as httpd:
            base = f"http://127.0.0.1:{httpd.server_port}"
            self.configure(kind, base + path, base + "/second")
            result, _ = self.run_hook(kind, both=True)
            diagnostics = f"hook exit {result.returncode}\n{result.stdout}{result.stderr}"
            self.assertEqual(result.returncode, 1, diagnostics)
            # Cold pwsh startup is outside the download's deadline. Measure
            # from real headers, while run_hook retains an overall hang cap.
            self.assertTrue(httpd.headers_sent, f"no subject HTTP response headers\n{diagnostics}")
            elapsed = time.monotonic() - httpd.headers_sent[0]
            self.assertLess(elapsed, 4, f"body exceeded the 1s deadline: {elapsed:.2f}s\n{diagnostics}")
            self.assertEqual(httpd.requests, [path], diagnostics)
            self.assertIn("already failed", result.stdout + result.stderr, diagnostics)
            self.assert_no_state()
            self.assertFalse(list(self.root.glob("dotfiles-payload.*")))
            self.assertFalse(list(self.root.glob("dotfiles-payload-*")))

    def check_http_success(self, kind, backend=None):
        if kind == "sh":
            self.shell_path(backend)
        with server() as httpd:
            self.configure(kind, f"http://127.0.0.1:{httpd.server_port}/ok")
            result, _ = self.run_hook(kind)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(httpd.requests, ["/ok"])
            self.assert_no_state()
            self.assertFalse(list(self.root.glob("dotfiles-payload.*")))
            self.assertFalse(list(self.root.glob("dotfiles-payload-*")))

    def test_wget_complete_http_response_runs(self):
        self.check_http_success("sh", "wget")

    def test_powershell_complete_http_response_runs(self):
        self.check_http_success("ps1")

    def test_curl_trickle_deadline(self):
        self.check_download("sh", "/trickle", "curl")

    def test_wget_trickle_deadline(self):
        self.check_download("sh", "/trickle", "wget")

    def test_wget_gtimeout_trickle_deadline(self):
        self.check_download("sh", "/trickle", "wget", "gtimeout")

    def test_shell_empty_response_keeps_failure_latch(self):
        self.check_download("sh", "/empty", "curl")

    def test_powershell_empty_response_keeps_failure_latch(self):
        self.check_download("ps1", "/empty")

    def test_powershell_body_stall_deadline(self):
        self.check_download("ps1", "/stall")

    def test_powershell_body_trickle_deadline(self):
        self.check_download("ps1", "/trickle")

    def test_wget_without_deadline_tool_fails_before_network(self):
        self.shell_path("wget", None)
        with server() as httpd:
            self.configure("sh", f"http://127.0.0.1:{httpd.server_port}/ok")
            result, _ = self.run_hook("sh")
            self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
            self.assertEqual(httpd.requests, [])
            self.assertIn("timeout", result.stderr)


if __name__ == "__main__":
    unittest.main()
