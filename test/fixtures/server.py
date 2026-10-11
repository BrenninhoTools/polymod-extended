import hashlib
import http.server
import json
import os
import sys
import threading

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
STATE = {"file_id": 9001}


class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send_bytes(self, data, status=200, headers=None):
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def profile(self, good):
        memory = open(os.path.join(ROOT, "fixtures", "memory_mod.zip"), "rb").read()
        base = "http://127.0.0.1:%d" % self.server.server_port
        return json.dumps({
            "_idRow": 123,
            "_sName": "Memory Mod",
            "_sVersion": "1.0",
            "_tsDateUpdated": 1700000000 + STATE["file_id"],
            "_aFiles": [
                {"_idRow": 1, "_sFile": "old.zip", "_sDownloadUrl": base + "/missing.zip", "_bIsArchived": True, "_sAvResult": "clean"},
                {
                    "_idRow": STATE["file_id"],
                    "_sFile": "memory_mod.zip",
                    "_nFilesize": len(memory),
                    "_sDownloadUrl": base + "/dl/" + str(STATE["file_id"]),
                    "_sMd5Checksum": hashlib.md5(memory).hexdigest() if good else "0" * 32,
                    "_bIsArchived": False,
                    "_sAvResult": "clean",
                },
            ],
        }).encode("utf-8")

    def do_GET(self):
        path = self.path.split("?")[0]

        if path in ("/api/Mod/123/ProfilePage", "/api/Mod/124/ProfilePage"):
            self.send_bytes(self.profile(path.startswith("/api/Mod/123")), headers={"Content-Type": "application/json"})
            return

        if path == "/state/next":
            STATE["file_id"] += 1
            self.send_bytes(b"ok")
            return

        if path.startswith("/dl/"):
            self.send_response(302)
            self.send_header("Location", "/fixtures/memory_mod.zip")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return

        if path == "/named":
            data = open(os.path.join(ROOT, "mods", "zip_mod.zip"), "rb").read()
            self.send_bytes(data, headers={"Content-Disposition": 'attachment; filename="named_mod.zip"'})
            return

        if path == "/big.zip":
            self.send_bytes(b"\0" * (64 * 1024))
            return

        file = os.path.abspath(os.path.join(ROOT, path.lstrip("/")))

        if not file.startswith(ROOT) or not os.path.isfile(file):
            self.send_bytes(b"not found", status=404)
            return

        self.send_bytes(open(file, "rb").read())


def main():
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    sys.stdin.read()
    server.shutdown()


if __name__ == "__main__":
    main()
