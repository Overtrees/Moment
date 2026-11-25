#!/usr/bin/env python3
"""spike 静态服务：正确 wasm MIME；刻意不下发 COOP/COEP，
验证 SAHPool 免头口径（与评估报告路线 ①′ 的前提一致）。"""
import http.server
import sys

class H(http.server.SimpleHTTPRequestHandler):
    extensions_map = {
        **http.server.SimpleHTTPRequestHandler.extensions_map,
        ".wasm": "application/wasm",
        ".js": "text/javascript",
        ".html": "text/html; charset=utf-8",
    }
    def log_message(self, *a):
        pass

if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8177
    http.server.ThreadingHTTPServer(("127.0.0.1", port), H).serve_forever()
