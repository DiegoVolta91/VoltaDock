#!/usr/bin/env python3
"""A stand-in for the VoltaDock desktop app, written from docs/REMOTE.md.

Used by CI to check the iPad client end to end. Pairing key = bytes 0..31.
Sends a welcome with one pending Bash request, waits for ack + decision, then
answers `resolved` with the decision it received. Exits after one client.
"""
import json
import os
import socket
import struct
import sys

from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.ciphers.aead import ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

KEY = bytes(range(32))
PORT = 47821


class Dir:
    def __init__(self, key):
        self.aead = ChaCha20Poly1305(key)
        self.counter = 0

    def nonce(self):
        n = b"\0" * 4 + self.counter.to_bytes(8, "big")
        self.counter += 1
        return n


def read_exact(conn, n):
    buf = b""
    while len(buf) < n:
        chunk = conn.recv(n - len(buf))
        if not chunk:
            raise EOFError
        buf += chunk
    return buf


def main():
    srv = socket.socket()
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("127.0.0.1", PORT))
    srv.listen(1)
    print("mock desktop listening", flush=True)
    conn, _ = srv.accept()
    conn.settimeout(20)
    hello = read_exact(conn, 36)
    assert hello[:4] == b"VDR1", "bad magic"
    server_random = os.urandom(32)
    conn.sendall(b"VDR1" + server_random)
    okm = HKDF(hashes.SHA256(), 64, hello[4:] + server_random, b"voltadock-remote/1").derive(KEY)
    c2s, s2c = Dir(okm[:32]), Dir(okm[32:])

    def recv():
        (n,) = struct.unpack(">I", read_exact(conn, 4))
        return json.loads(c2s.aead.decrypt(c2s.nonce(), read_exact(conn, n), None))

    def send(msg):
        ct = s2c.aead.encrypt(s2c.nonce(), json.dumps(msg).encode(), None)
        conn.sendall(struct.pack(">I", len(ct)) + ct)

    first = recv()
    assert first["type"] == "hello", first
    request = {
        "hook_event_name": "PermissionRequest",
        "request_id": "42-1",
        "cwd": "C:\\dev\\coucou",
        "tool_name": "Bash",
        "tool_input": {"command": "npm test"},
    }
    send({"type": "welcome", "host": "MOCK", "version": "0", "pending": [request], "sessions": [], "today": None})
    seen = []
    while True:
        msg = recv()
        seen.append(msg["type"])
        if msg["type"] == "decision":
            assert "ack" in seen, "decision before ack"
            send({"type": "resolved", "request_id": msg["request_id"], "decision": msg["decision"]})
            break
    print("mock desktop: ok", seen, flush=True)
    conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — CI log
        print(f"mock desktop failed: {exc}", file=sys.stderr)
        sys.exit(1)
