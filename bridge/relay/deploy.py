#!/usr/bin/env python3
"""moment-bridge 中继部署（Cloudflare Workers + Durable Objects）。

为什么不用 cf.py 的 workers put：该命令以 application/javascript
裸传脚本、无 metadata，部署不了带 Durable Object 绑定的模块
Worker。本脚本复用 custom.cloudflare 连接器的同一凭据代理
（dynamic_credentials surrogate，令牌不落本文件、不进日志），走
multipart 模块上传：metadata 含 main_module 与
durable_object_namespace 绑定（BRIDGE_ROOM → BridgeRoom）。

用法：python3 deploy.py [--account Overtrees账号ID]
部署后启用 workers.dev 子域名。部署坐标见
docs/reports/impl_bridge_m1.md。
"""
import argparse
import json
import os
import sys
import urllib.request

sys.path.insert(0, "/opt/muse/skills/custom-connector-setup/bin")
from dynamic_credentials import (  # noqa: E402
    add_surrogate_to_request,
    read_json_response,
)

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT_NAME = "moment-bridge"
DEFAULT_ACCOUNT = "4c3178949cce0a3db4f993a3e14712a6"  # Overtrees
BASE = "https://api.cloudflare.com/client/v4"
CONNECTION = "custom.cloudflare"
ALLOWED_HOSTS = ["api.cloudflare.com"]


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        raise RuntimeError("redirect refused, verify the endpoint")


def api(method, path, body=None, content_type="application/json"):
    url = BASE + path
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", content_type)
    add_surrogate_to_request(req, CONNECTION, allowed_hosts=ALLOWED_HOSTS)
    try:
        with urllib.request.build_opener(NoRedirect()).open(req, timeout=60) as resp:
            return resp.status, read_json_response(resp)
    except urllib.error.HTTPError as e:
        raw = e.read().decode(errors="replace")
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, {"error": raw}


def multipart_body(metadata, code_bytes):
    boundary = "----moment-bridge-deploy"
    parts = []
    parts.append(
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="metadata"\r\n'
            "Content-Type: application/json\r\n\r\n"
        ).encode()
        + json.dumps(metadata).encode()
        + b"\r\n"
    )
    parts.append(
        (
            f"--{boundary}\r\n"
            'Content-Disposition: form-data; name="worker.js"; filename="worker.js"\r\n'
            "Content-Type: application/javascript+module\r\n\r\n"
        ).encode()
        + code_bytes
        + b"\r\n"
    )
    parts.append(f"--{boundary}--\r\n".encode())
    return boundary, b"".join(parts)


def put_worker(account, with_migration):
    with open(os.path.join(HERE, "worker.js"), "rb") as f:
        code = f.read()
    metadata = {
        "main_module": "worker.js",
        "compatibility_date": "2024-11-01",
        "bindings": [
            {
                "type": "durable_object_namespace",
                "name": "BRIDGE_ROOM",
                "class_name": "BridgeRoom",
            }
        ],
    }
    if with_migration:
        # 免费计划的 Durable Objects 命名空间必须以
        # SQLite 后端创建（API 错误 10097 口径）。
        metadata["migrations"] = {
            "new_tag": "v1",
            "new_sqlite_classes": ["BridgeRoom"],
        }
    boundary, body = multipart_body(metadata, code)
    path = f"/accounts/{account}/workers/scripts/{SCRIPT_NAME}"
    return api(
        "PUT",
        path,
        body=body,
        content_type=f"multipart/form-data; boundary={boundary}",
    )


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--account", default=DEFAULT_ACCOUNT)
    args = ap.parse_args()
    status, resp = put_worker(args.account, with_migration=False)
    errors = json.dumps(resp.get("errors", [])).lower()
    if status >= 400 and ("migration" in errors or "sqlite" in errors
                          or "durable" in errors):
        print("retry with DO migration tag v1 …")
        status, resp = put_worker(args.account, with_migration=True)
    print("PUT workers/scripts:", status)
    if status >= 400:
        print(json.dumps(resp.get("errors", resp), ensure_ascii=False)[:800])
        return 1
    # 启用 workers.dev 子域名
    status2, resp2 = api(
        "POST",
        f"/accounts/{args.account}/workers/scripts/{SCRIPT_NAME}/subdomain",
        body={"enabled": True},
    )
    print("POST subdomain enabled:", status2)
    if status2 >= 400:
        print(json.dumps(resp2.get("errors", resp2), ensure_ascii=False)[:400])
    return 0


if __name__ == "__main__":
    sys.exit(main())
