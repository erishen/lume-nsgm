#!/usr/bin/env python3
"""mock_pay_gateway.py — PayPal 支付 mock 网关（lume-nsgm 支付 e2e 用）。

PayPal Express Checkout：
  GET  /health           就绪探针
  POST /v1/oauth2/token              OAuth2 client_credentials：验 HTTP Basic
                                     (Base64(client_id:client_secret))，下发 Bearer
  POST /v2/checkout/orders          建单：返回 id + links[].rel=approve（指向本 mock
                                     收银台 /mock/paypal/approve?token=...）
  POST /v2/checkout/orders/{id}/capture  捕获：返回 COMPLETED + capture id
  GET  /v2/checkout/orders/{id}     查单：返回订单详情（含 captures，退款反查兜底用）
  GET  /v2/payments/captures/{id}   查捕获：返回捕获详情（含
                                     supplementary_data.related_ids.order_id——用户把
                                     「交易号/捕获 ID」当订单号填入、订单 GET 404 后的兜底）
  POST /v2/payments/captures/{id}/refund  退款：重复退同一捕获回 422
                                     （body 含 ALREADY_REFUNDED，应用侧按成功对账）
  GET  /mock/paypal/orders       建单计数（e2e 断言收银台复用：刷新/重试不新增订单）
  GET  /mock/paypal/approve?token=..  模拟 PayPal 收银台 approve 后 302 跳回
                                     return_url?token=..（return_url 建单时由应用传入）

只监听 0.0.0.0（localhost 仍可用）；lume 侧 http_post 需 allow_private
（pay.lume 已带）。stdlib only，无第三方依赖。
"""

import argparse
import base64
import json
import os
import secrets
import sys
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import URLError
from urllib.parse import urlparse, parse_qs

PORT = int(os.environ.get("MOCK_PAY_PORT", "18097"))
LISTEN_PORT = PORT  # 实际监听端口（--port 可覆盖），建单 approve 链接用它拼主机

# ----- PayPal (Express Checkout) mock -----
PP_CLIENT_ID = os.environ.get("MOCK_PAYPAL_CLIENT_ID", "AUmock_client_id_sandbox_001").encode()
PP_SECRET = os.environ.get("MOCK_PAYPAL_CLIENT_SECRET", "e2e-mock-key").encode()
PP_ISSUED_TOKEN = [None]   # 最近下发的 access_token（兼容字段）
PP_VALID_TOKENS = set()     # 所有已下发的 token 均视为有效（不主动过期，避免并发/缓存侧相互顶替）
PP_ORDERS = {}             # order_id -> return_url（建单时由应用传入）
PP_CAPTURES = {}           # capture_id -> {"order_id": .., "amount": .., "refunded": bool}
PP_REFUNDS = {}            # refund_id -> capture_id（已退记录）

# 投递回调走本机回环，显式禁代理（宿主/沙箱可能设了 http_proxy）
NO_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # 静音默认访问日志（e2e 自己断言）
        sys.stderr.write("[mock-gw] %s\n" % (fmt % args))

    def _json(self, code, obj):
        body = json.dumps(obj, separators=(",", ":")).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _redirect(self, loc):
        self.send_response(302)
        self.send_header("Location", loc)
        self.send_header("Content-Length", "0")
        self.end_headers()

    def do_GET(self):
        if self.path == "/health":
            self._json(200, {"ok": True})
        elif self.path == "/mock/paypal/orders":
            # 建单计数（e2e 断言收银台复用：刷新/重试不应新增 PayPal 侧订单）
            self._json(200, {"orders": len(PP_ORDERS)})
        elif self.path.startswith("/mock/paypal/approve"):
            self._approve()
        elif self.path.startswith("/v2/checkout/orders/"):
            self._pp_get_order(self.path[len("/v2/checkout/orders/"):])
        elif self.path.startswith("/v2/payments/captures/"):
            self._pp_get_capture(self.path[len("/v2/payments/captures/"):])
        else:
            self._json(404, {"code": "NOT_FOUND"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""

        if self.path == "/v1/oauth2/token":
            self._oauth(raw)
        elif self.path == "/v2/checkout/orders":
            self._orders(raw)
        elif self.path.startswith("/v2/checkout/orders/") and self.path.endswith("/capture"):
            oid = self.path[len("/v2/checkout/orders/"):-len("/capture")]
            self._capture(raw, oid)
        elif self.path.startswith("/v2/payments/captures/") and self.path.endswith("/refund"):
            cid = self.path[len("/v2/payments/captures/"):-len("/refund")]
            self._pp_refund(raw, cid)
        else:
            self._json(404, {"code": "NOT_FOUND"})

    # ---------------- PayPal Express Checkout ----------------

    def _pp_basic_ok(self) -> bool:
        """校验 Authorization: Basic base64(client_id:client_secret)"""
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Basic "):
            return False
        try:
            decoded = base64.b64decode(auth[6:]).decode()
            cid, secret = decoded.split(":", 1)
        except Exception:
            return False
        return cid.encode() == PP_CLIENT_ID and secret.encode() == PP_SECRET

    def _pp_bearer_ok(self) -> bool:
        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return False
        return auth[7:] in PP_VALID_TOKENS

    def _oauth(self, raw: bytes):
        if not self._pp_basic_ok():
            self._json(401, {"error": "invalid_client", "message": "bad client credentials"})
            return
        tok = "MOCK-PP-" + secrets.token_hex(8)
        PP_ISSUED_TOKEN[0] = tok
        PP_VALID_TOKENS.add(tok)
        self._json(200, {"access_token": tok, "token_type": "Bearer", "expires_in": 3600})

    def _orders(self, raw: bytes):
        if not self._pp_bearer_ok():
            self._json(401, {"error": "invalid_token"})
            return
        try:
            body = json.loads(raw.decode())
        except Exception:
            self._json(400, {"error": "invalid_json"})
            return
        ret = (body.get("application_context") or {}).get("return_url", "")
        oid = "MOCK-PP-ORDER-" + str(abs(hash(raw)) % 10 ** 9)
        PP_ORDERS[oid] = ret
        approve = f"http://127.0.0.1:{LISTEN_PORT}/mock/paypal/approve?token={oid}"
        self._json(201, {
            "id": oid,
            "status": "CREATED",
            "links": [
                {"rel": "self", "href": f"http://127.0.0.1:{LISTEN_PORT}/v2/checkout/orders/{oid}"},
                {"rel": "approve", "href": approve},
            ],
        })

    def _capture(self, raw: bytes, oid: str):
        if not self._pp_bearer_ok():
            self._json(401, {"error": "invalid_token"})
            return
        if oid not in PP_ORDERS:
            self._json(404, {"error": "order_not_found"})
            return
        cid = "MOCK-CAPTURE-" + oid[-6:]
        PP_CAPTURES.setdefault(cid, {"order_id": oid, "refunded": False})
        self._json(201, {
            "id": oid,
            "status": "COMPLETED",
            "purchase_units": [{"payments": {"captures": [
                {"id": cid, "status": "COMPLETED"}
            ]}}],
        })

    def _pp_get_order(self, oid: str):
        """查单：返回 captures（应用侧退款反查 capture_id 的兜底路径）。"""
        if not self._pp_bearer_ok():
            self._json(401, {"error": "invalid_token"})
            return
        if oid not in PP_ORDERS:
            self._json(404, {"error": "order_not_found"})
            return
        caps = [{"id": cid, "status": "REFUNDED" if c["refunded"] else "COMPLETED"}
                for cid, c in PP_CAPTURES.items() if c["order_id"] == oid]
        self._json(200, {
            "id": oid,
            "status": "COMPLETED" if caps else "CREATED",
            "purchase_units": [{"payments": {"captures": caps}}],
        })

    def _pp_get_capture(self, cid: str):
        """查捕获：GET /v2/payments/captures/{id}。

        应用侧兜底：用户把「交易号 / Transaction ID」（即捕获 ID）当订单号填入时，
        订单 GET 回 404 RESOURCE_NOT_FOUND，随后改查本接口，从
        supplementary_data.related_ids.order_id 反解订单号（对齐真实 PayPal 行为）。
        """
        if not self._pp_bearer_ok():
            self._json(401, {"error": "invalid_token"})
            return
        if cid not in PP_CAPTURES:
            self._json(404, {"name": "RESOURCE_NOT_FOUND",
                             "details": [{"issue": "INVALID_RESOURCE_ID",
                                          "description": "Specified resource ID does not exist. Please check the resource ID and try again."}],
                             "message": "The specified resource does not exist."})
            return
        c = PP_CAPTURES[cid]
        self._json(200, {
            "id": cid,
            "status": "REFUNDED" if c["refunded"] else "COMPLETED",
            "supplementary_data": {"related_ids": {"order_id": c["order_id"]}},
        })

    def _pp_refund(self, raw: bytes, cid: str):
        """退款：POST /v2/payments/captures/{capture_id}/refund。
        重复退同一捕获回 422（body issue=CAPTURE_FULLY_REFUNDED——与真实沙箱
        2026-10-17 实证一致；应用侧按成功对账）。"""
        if not self._pp_bearer_ok():
            self._json(401, {"error": "invalid_token"})
            return
        cap = PP_CAPTURES.get(cid)
        if cap is None:
            self._json(404, {"error": "resource_not_found"})
            return
        if cap["refunded"]:
            self._json(422, {
                "name": "UNPROCESSABLE_ENTITY",
                "details": [{"issue": "CAPTURE_FULLY_REFUNDED",
                             "description": "The capture has already been fully refunded"}],
            })
            return
        try:
            body = json.loads(raw.decode() or "{}")
        except Exception:
            body = {}
        amt = body.get("amount") or {}
        cap["refunded"] = True
        rid = "MOCK-REFUND-" + secrets.token_hex(6)
        PP_REFUNDS[rid] = cid
        self._json(201, {
            "id": rid,
            "status": "COMPLETED",
            "amount": {"value": str(amt.get("value", "")), "currency_code": str(amt.get("currency_code", "USD"))},
            "capture_id": cid,
        })

    def _approve(self):
        """模拟 PayPal 收银台 approve 后 302 跳回 return_url?token=.."""
        q = parse_qs(urlparse(self.path).query)
        oid = (q.get("token") or [""])[0]
        ret = PP_ORDERS.get(oid, "")
        if not ret:
            self._json(404, {"error": "order_not_found"})
            return
        loc = ret + ("&" if "?" in ret else "?") + f"token={oid}"
        self._redirect(loc)


def main():
    global LISTEN_PORT
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=PORT, help="监听端口（默认 MOCK_PAY_PORT 或 18097）")
    ap.add_argument("--paypal", action="store_true", help="保留向前兼容的 no-op（本网关仅 PayPal）")
    args = ap.parse_args()
    LISTEN_PORT = args.port
    # 绑 0.0.0.0：localhost 仍可用（不影响 e2e），同时允许 Docker 容器经
    # host.docker.internal 回访本网关做实支付联调。
    srv = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    sys.stderr.write(f"[mock-gw] listening on 0.0.0.0:{LISTEN_PORT} "
                     f"(paypal client={PP_CLIENT_ID.decode()})\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
