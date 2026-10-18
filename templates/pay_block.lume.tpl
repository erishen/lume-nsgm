// ---- PayPal 支付接线（lume-nsgm 生成；client_id 来自配置，client_secret 走环境变量 {{secret_env}}）----
// 全量 SPA：本块只出 JSON API。创建接口返回 { ok, approve_url, paypal_order_id }；
// 收银台 /api/shop/cashier 复用 PAYPAL_CFG 建单，回跳走 /spa/ hash 路由（由前端接管）。
// PayPal 跳回 return?token=<pp_order_id>&order_no=<本地单号> 后服务端捕获并改状态。
let PAYPAL_CLIENT_ID_RAW = env("PAYPAL_CLIENT_ID");
let PAYPAL_CLIENT_ID = (PAYPAL_CLIENT_ID_RAW != null && PAYPAL_CLIENT_ID_RAW != "" ? str(PAYPAL_CLIENT_ID_RAW) : "{{client_id}}");
let PAYPAL_CLIENT_SECRET_RAW = env("{{secret_env}}");
let PAYPAL_GATEWAY_RAW = env("PAY_GATEWAY");
let PAYPAL_RETURN_RAW = env("PAYPAL_RETURN_URL");
// 回跳基址默认跟随 server 实际监听地址；0.0.0.0 绑定全部网卡时浏览器不可达，改用 localhost。
let _lh = (env("HOST") != null && env("HOST") != "") ? env("HOST") : "127.0.0.1";
let _lp = (env("PORT") != null && env("PORT") != "") ? int(env("PORT")) : 8081;
let _rh = (_lh == "0.0.0.0" || _lh == "") ? "localhost" : _lh;
let _dflt_ret = "http://" + _rh + ":" + str(_lp);
let PAYPAL_CFG = {
  "gw": (PAYPAL_GATEWAY_RAW != null && PAYPAL_GATEWAY_RAW != "" ? str(PAYPAL_GATEWAY_RAW) : pay.paypal_base_url("{{mode}}")),
  "client_id": PAYPAL_CLIENT_ID,
  "client_secret": (PAYPAL_CLIENT_SECRET_RAW != null ? str(PAYPAL_CLIENT_SECRET_RAW) : ""),
  "currency": "{{currency}}",
  "brand": "{{brand}}"
};
let PAYPAL_RETURN_BASE = (PAYPAL_RETURN_RAW != null && PAYPAL_RETURN_RAW != "") ? str(PAYPAL_RETURN_RAW) : _dflt_ret;
let csym = "{{csym}}";

// 创建支付单：返回 approve_url（前端据此跳转 PayPal）；回跳走 /spa/ hash 路由。
post "/api/pay/create", func(req) {
  if (get(req, "body", null) == null) { return { "ok": false, "err": "empty_body" }; }
  let data = json(req.body);
  if (data == null) { return { "ok": false, "err": "invalid_json" }; }
  let order_no = str(get(data, "order_no", ""));
  if (order_no == "") { return { "ok": false, "err": "missing_order_no" }; }
  let rows = sql_query(db.dsn(), "SELECT \"{{amf}}\" FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [order_no]);
  if (len(rows) == 0) { return { "ok": false, "err": "order_not_found" }; }
  let cents = int(get(rows[0], "{{amf}}", 0));
  let tk = pay.paypal_token(PAYPAL_CFG);
  if (get(tk, "ok", false) != true) { return { "ok": false, "err": "paypal_token_failed", "detail": str(get(tk, "err", "")) }; }
  let return_url = PAYPAL_RETURN_BASE + "/spa/#/pay/return?order_no=" + order_no;
  let cancel_url = PAYPAL_RETURN_BASE + "/spa/#/pay/cancel?order_no=" + order_no;
  let cr = pay.paypal_create(PAYPAL_CFG, str(get(tk, "token", "")), order_no, cents, "Order " + order_no, return_url, cancel_url);
  if (get(cr, "ok", false) != true) { return { "ok": false, "err": "paypal_create_failed", "detail": str(get(cr, "err", "")) }; }
  return { "ok": true, "approve_url": str(get(cr, "approve_url", "")), "paypal_order_id": str(get(cr, "paypal_order_id", "")) };
};

// PayPal 跳回：捕获并改状态（幂等）。SPA 在 /spa/#/pay/return 读取 hash 后调用本接口。
get "/api/pay/return", func(req) {
  let order_no = str(get(req.query_params, "order_no", ""));
  let pptoken = str(get(req.query_params, "token", ""));
  if (order_no == "" || pptoken == "") { return { "ok": false, "err": "missing_params", "msg": "参数缺失" }; }
  let cur = sql_query(db.dsn(), "SELECT \"{{stf}}\", \"{{amf}}\" FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [order_no]);
  // 订单存在性检查：未知单号不进捕获流程（否则捕获成功也只 UPDATE 0 行却给用户看成功页）。
  if (len(cur) == 0) { return { "ok": false, "err": "order_not_found", "msg": "订单不存在" }; }
  let cents = int(get(cur[0], "{{amf}}", 0));
  if (str(get(cur[0], "{{stf}}", "")) == "paid") {
    return { "ok": true, "status": "paid", "order_no": order_no, "amount_cents": cents, "currency_symbol": csym };
  }
  let tk = pay.paypal_token(PAYPAL_CFG);
  if (get(tk, "ok", false) != true) { return { "ok": false, "err": "paypal_token_failed", "detail": str(get(tk, "err", "")) }; }
  let cap = pay.paypal_capture(PAYPAL_CFG, str(get(tk, "token", "")), pptoken);
  if (get(cap, "ok", false) != true) { return { "ok": false, "err": "paypal_capture_failed", "detail": str(get(cap, "err", "")) }; }
  // 回填 PayPal 侧 ID（paypal_order_id=approve token，capture_id=捕获记录）——退款凭 capture_id 退。
  sql_write(db.dsn(), "UPDATE \"{{om}}\" SET \"{{stf}}\" = 'paid', \"{{ppidf}}\" = ?, \"{{capf}}\" = ? WHERE \"{{onf}}\" = ?", [pptoken, str(get(cap, "capture_id", "")), order_no]);
  return { "ok": true, "status": "paid", "order_no": order_no, "amount_cents": cents, "currency_symbol": csym };
};

// 用户取消（PayPal 跳回 cancel_url=/spa/#/pay/cancel）。SPA 接管展示，本接口仅作确认。
get "/api/pay/cancel", func(req) {
  let order_no = str(get(req.query_params, "order_no", ""));
  return { "ok": true, "cancelled": true, "order_no": order_no };
};

{{#if has_webhook}}
// 可选 webhook：简化 HMAC 验签（webhook_path 配置时生成）。
post "{{webhook_path}}", func(req) {
  let data = json(req.body);
  if (data == null) { return { "ok": false, "err": "invalid_json" }; }
  let id = str(get(data, "verify_id", ""));
  let ts = str(get(data, "verify_ts", ""));
  let sign = str(get(data, "verify_sign", ""));
  let payload = str(get(data, "payload", ""));
  if (!pay.paypal_verify_webhook(str(get(PAYPAL_CFG, "client_secret", "")), id, ts, payload, sign)) {
    return { "ok": false, "err": "signature_mismatch" };
  }
  return { "ok": true };
};
{{/if}}
