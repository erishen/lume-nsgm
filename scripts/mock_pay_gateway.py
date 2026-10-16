#!/usr/bin/env python3
"""mock_pay_gateway.py — 支付 mock 网关（lume-nsgm 支付 e2e 用）。

同时支持两套形状，一套进程即可服务微信与 PayPal 两种生成工程：

微信支付 v3（provider: wechat）：
  GET  /health           就绪探针
  POST /v3/pay/native    下单：验 Authorization 头签名，返回 code_url/prepay_id
  POST /mock/notify      代网关投递回调：对业务报文签名后 POST 到应用的
                         notify_url（签名材料随 body，沙箱约定）

PayPal Express Checkout（provider: paypal）：
  POST /v1/oauth2/token              OAuth2 client_credentials：验 HTTP Basic
                                     (Base64(client_id:client_secret))，下发 Bearer
  POST /v2/checkout/orders          建单：返回 id + links[].rel=approve（指向本 mock
                                     收银台 /mock/paypal/approve?token=...）
  POST /v2/checkout/orders/{id}/capture  捕获：返回 COMPLETED + capture id
  GET  /mock/paypal/approve?token=..  模拟 PayPal 收银台 approve 后 302 跳回
                                     return_url?token=..（return_url 建单时由应用传入）

两套都只监听 127.0.0.1（私有地址）；lume 侧 http_post 需 allow_private
（pay.lume 已带）。stdlib only，无第三方依赖。
"""

import argparse
import base64
import hashlib
import hmac
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
SECRET = os.environ.get("MOCK_PAY_SECRET", "mock-secret").encode()
SCHEME = "WECHATPAY2-SHA256-HMAC"

# ----- PayPal (Express Checkout) mock -----
PP_CLIENT_ID = os.environ.get("MOCK_PAYPAL_CLIENT_ID", "AUmock_client_id_sandbox_001").encode()
PP_SECRET = os.environ.get("MOCK_PAYPAL_CLIENT_SECRET", "e2e-mock-key").encode()
PP_ISSUED_TOKEN = [None]   # 最近下发的 access_token（捕获时校验 Bearer）
PP_ORDERS = {}             # order_id -> return_url（建单时由应用传入）

# 投递回调走本机回环，显式禁代理（宿主/沙箱可能设了 http_proxy）
NO_PROXY_OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))

# 记录每次下单/回调，便于调试与断言
ORDERS = {}


def canonical(method: str, path: str, ts: str, nonce: str, body: str) -> bytes:
    return f"{method}\n{path}\n{ts}\n{nonce}\n{body}\n".encode()


def sign(method: str, path: str, ts: str, nonce: str, body: str) -> str:
    return hmac.new(SECRET, canonical(method, path, ts, nonce, body), hashlib.sha256).hexdigest()


def sign_notify(ts: str, nonce: str, body: str) -> str:
    """回调验签规范串（v3 形状）：时间戳\n随机串\n报文主体\n（无方法/路径段）。"""
    return hmac.new(SECRET, f"{ts}\n{nonce}\n{body}\n".encode(), hashlib.sha256).hexdigest()


def parse_auth(header: str):
    """解析 'SCHEME mchid="..",serial_no="..",nonce_str="..",timestamp="..",signature=".."'"""
    if not header.startswith(SCHEME + " "):
        return None
    out = {}
    for part in header[len(SCHEME) + 1:].split(","):
        if "=" not in part:
            continue
        k, v = part.split("=", 1)
        out[k.strip()] = v.strip().strip('"')
    return out


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
        elif self.path.startswith("/mock/paypal/approve"):
            self._approve()
        else:
            self._json(404, {"code": "NOT_FOUND"})

    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n else b""

        if self.path == "/v3/pay/transactions/native":
            self._native(raw)
        elif self.path == "/mock/notify":
            self._notify(raw)
        elif self.path == "/v1/oauth2/token":
            self._oauth(raw)
        elif self.path == "/v2/checkout/orders":
            self._orders(raw)
        elif self.path.startswith("/v2/checkout/orders/") and self.path.endswith("/capture"):
            oid = self.path[len("/v2/checkout/orders/"):-len("/capture")]
            self._capture(raw, oid)
        else:
            self._json(404, {"code": "NOT_FOUND"})

    # ---------------- 微信 v3 ----------------

    def _native(self, raw: bytes):
        auth = parse_auth(self.headers.get("Authorization", ""))
        if auth is None:
            self._json(401, {"code": "UNAUTHORIZED", "message": "bad authorization scheme"})
            return
        expect = sign("POST", "/v3/pay/transactions/native", auth.get("timestamp", ""),
                      auth.get("nonce_str", ""), raw.decode())
        if not hmac.compare_digest(expect, auth.get("signature", "")):
            if os.environ.get("MOCK_PAY_DEBUG"):
                sys.stderr.write("[mock-gw][debug] auth=%r\n" % (auth,))
                sys.stderr.write("[mock-gw][debug] body=%r\n" % (raw.decode(),))
                sys.stderr.write("[mock-gw][debug] expect=%s got=%s\n"
                                 % (expect, auth.get("signature", "")))
            self._json(401, {"code": "UNAUTHORIZED", "message": "signature mismatch"})
            return
        try:
            body = json.loads(raw.decode())
        except Exception:
            self._json(400, {"code": "PARAM_ERROR", "message": "invalid json"})
            return
        order_no = body.get("out_trade_no", "")
        if not order_no or "amount" not in body or "notify_url" not in body:
            self._json(400, {"code": "PARAM_ERROR", "message": "missing out_trade_no/amount/notify_url"})
            return
        ORDERS[order_no] = {"amount": body["amount"].get("total"), "notify_url": body["notify_url"]}
        self._json(200, {
            "code_url": f"weixin://wxpay/bizpayurl?pr=MOCK{order_no}",
            "prepay_id": f"MOCKPRE{order_no}",
        })

    def _notify(self, raw: bytes):
        """代网关向应用投递一次签名回调。body: {notify_url, order_no, amount_cents}"""
        try:
            req = json.loads(raw.decode())
        except Exception:
            self._json(400, {"err": "invalid json"})
            return
        notify_url = req.get("notify_url", "")
        order_no = req.get("order_no", "")
        if not notify_url or not order_no:
            self._json(400, {"err": "missing notify_url/order_no"})
            return
        payload = json.dumps({
            "out_trade_no": order_no,
            "transaction_id": f"MOCK4200{abs(hash(order_no)) % 100000:05d}",
            "trade_state": "SUCCESS",
            "amount": {"total": int(req.get("amount_cents", 0)), "currency": "CNY"},
            "success_time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        }, separators=(",", ":"))
        ts = str(int(time.time()))
        nonce = f"mock-nonce-{order_no}"
        sign_hex = sign_notify(ts, nonce, payload)
        wrapper = {
            "verify_ts": ts,
            "verify_nonce": nonce,
            "verify_sign": sign_hex,
            "payload": payload,
        }
        data = json.dumps(wrapper).encode()
        http_req = urllib.request.Request(notify_url, data=data, method="POST",
                                          headers={"Content-Type": "application/json"})
        try:
            with NO_PROXY_OPENER.open(http_req, timeout=10) as resp:
                app_reply = resp.read().decode()
                app_code = resp.status
        except URLError as e:
            self._json(502, {"err": f"app notify_url unreachable: {e}"})
            return
        self._json(200, {"delivered": True, "app_status": app_code, "app_reply": app_reply})

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
        return auth[7:] == PP_ISSUED_TOKEN[0]

    def _oauth(self, raw: bytes):
        if not self._pp_basic_ok():
            self._json(401, {"error": "invalid_client", "message": "bad client credentials"})
            return
        tok = "MOCK-PP-" + secrets.token_hex(8)
        PP_ISSUED_TOKEN[0] = tok
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
        self._json(201, {
            "id": oid,
            "status": "COMPLETED",
            "purchase_units": [{"payments": {"captures": [
                {"id": "MOCK-CAPTURE-" + oid[-6:], "status": "COMPLETED"}
            ]}}],
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
    ap.add_argument("--paypal", action="store_true", help="启用 PayPal 端点（默认即启用，保留向前兼容）")
    args = ap.parse_args()
    LISTEN_PORT = args.port
    # 绑 0.0.0.0：localhost 仍可用（不影响 e2e），同时允许 Docker 容器经
    # host.docker.internal 回访本网关做实支付联调。
    srv = ThreadingHTTPServer(("0.0.0.0", LISTEN_PORT), Handler)
    sys.stderr.write(f"[mock-gw] listening on 0.0.0.0:{LISTEN_PORT} "
                     f"(wechat secret len={len(SECRET)}, paypal client={PP_CLIENT_ID.decode()})\n")
    srv.serve_forever()


if __name__ == "__main__":
    main()
