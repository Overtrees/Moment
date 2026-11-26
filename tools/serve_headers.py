#!/usr/bin/env python3
"""Serve a directory with the production COOP/COEP/CORP headers.
Usage: serve_headers.py <dir> <port>"""
import http.server
import sys
import functools

directory, port = sys.argv[1], int(sys.argv[2])


class H(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cross-Origin-Opener-Policy", "same-origin")
        self.send_header("Cross-Origin-Embedder-Policy", "require-corp")
        self.send_header("Cross-Origin-Resource-Policy", "same-origin")
        super().end_headers()

    def log_message(self, *a):
        pass


http.server.HTTPServer(
    ("127.0.0.1", port),
    functools.partial(H, directory=directory),
).serve_forever()
