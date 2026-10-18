// ---- 店面（lume-nsgm 生成：商品列表 -> 下单 -> 收银台 -> 结果页 -> 退款）----
// 全量 SPA：本块只出 JSON API；页面由 /spa/ 下 React 渲染。
// 幂等：下单复用同一笔 pending 单；库存补偿锁（先建单再原子扣减，0 行=售罄补偿删单）；
// 退款凭捕获回填 ID 退；早期订单缺关联 ID 可经「恢复」页补 ID 或本地标记。
let THUMBS = ["⌨️", "👕", "☕", "📦", "🎧", "🖱️", "💡", "🎒"];

func shop_result(ono: string) {
  let orows = sql_query(db.dsn(), "SELECT * FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [ono]);
  if (len(orows) == 0) { return { "ok": false, "err": "order_not_found", "msg": "订单不存在" }; }
  let st = str(get(orows[0], "{{stf}}", ""));
  let cents = int(get(orows[0], "{{amf}}", 0));
  if (st == "paid") {
    return { "ok": true, "status": "paid", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" };
  }
  if (st == "refunded") {
    return { "ok": true, "status": "refunded", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" };
  }
  return { "ok": true, "status": st, "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" };
}

func shop_cashier(ono: string) {
  let orows = sql_query(db.dsn(), "SELECT * FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [ono]);
  if (len(orows) == 0) { return { "ok": false, "err": "order_not_found", "msg": "订单不存在" }; }
  let o = orows[0];
  if (str(get(o, "{{stf}}", "")) == "paid") { return shop_result(ono); }
  let cents = int(get(o, "{{amf}}", 0));
  // 收银台复用：订单行已回填 paypal_order_id（本次或此前渲染建过单）时直接重建 approve 链接，
  // 不再向 PayPal 重复建单——否则刷新/重试会留下孤儿单。SQL NULL 读出是 lume null，先归一。
  let ppid = str(get(o, "{{ppidf}}", ""));
  if (ppid == "null") { ppid = ""; }
  let approve = "";
  if (ppid != "") {
    approve = pay.paypal_approve_url(PAYPAL_CFG, ppid);
  } else {
    let tk = pay.paypal_token(PAYPAL_CFG);
    if (get(tk, "ok", false) != true) {
      return { "ok": false, "err": "paypal_token_failed", "detail": str(get(tk, "err", "")) };
    }
    let return_url = PAYPAL_RETURN_BASE + "/spa/#/pay/return?order_no=" + ono;
    let cancel_url = PAYPAL_RETURN_BASE + "/spa/#/pay/cancel?order_no=" + ono;
    let r = pay.paypal_create(PAYPAL_CFG, str(get(tk, "token", "")), ono, cents, "Shop order " + ono, return_url, cancel_url);
    if (get(r, "ok", false) != true) {
      return { "ok": false, "err": "paypal_create_failed", "detail": str(get(r, "err", "")) };
    }
    approve = str(get(r, "approve_url", ""));
    // 建单成功即回填 PayPal 订单 ID：后续渲染复用同一笔，不在 PayPal 侧堆孤儿单
    sql_write(db.dsn(), "UPDATE \"{{om}}\" SET \"{{ppidf}}\" = ? WHERE \"{{onf}}\" = ?", [str(get(r, "paypal_order_id", "")), ono]);
  }
  return { "ok": true, "order_no": ono, "status": "pending", "amount_cents": cents, "currency_symbol": "{{csym}}", "approve_url": approve };
}

func shop_ensure_meta(): int {
  sql_write(db.dsn(), "CREATE TABLE IF NOT EXISTS \"_nsgm_shop_meta\" (\"k\" TEXT PRIMARY KEY, \"v\" TEXT)", []);
  return 0;
}
func shop_seeded(): int {
  shop_ensure_meta();
  return len(sql_query(db.dsn(), "SELECT \"v\" FROM \"_nsgm_shop_meta\" WHERE \"k\" = 'seeded'", []));
}

// 商品列表 + 元信息（首次访问自动播种示例；act=clear 清空目录；act=seed 手动载入）
get "/api/shop/products", func(req) {
  let act = str(get(req.query_params, "act", ""));
  shop_ensure_meta();
  let seeded = shop_seeded();
  if (seeded == 0) { sql_write(db.dsn(), "INSERT OR REPLACE INTO \"_nsgm_shop_meta\" (\"k\", \"v\") VALUES ('seeded', '1')", []); }
  let flash = "";
  if (act == "clear") {
    sql_write(db.dsn(), "INSERT OR REPLACE INTO \"_nsgm_shop_meta\" (\"k\", \"v\") VALUES ('seeded', '1')", []);
    let allrows = sql_query(db.dsn(), "SELECT \"id\" FROM \"{{pm}}\"", []);
    let ci = 0;
    while (ci < len(allrows)) {
      sql_write(db.dsn(), "DELETE FROM \"{{pm}}\" WHERE \"id\" = ?", [int(get(allrows[ci], "id", 0))]);
      ci = ci + 1;
    }
    flash = "已清空全部商品（订单记录不受影响，可重新载入示例）。";
  }
  let prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" ORDER BY \"id\"", []);
  if (act == "seed" && len(prows) == 0) {
{{#if has_stock}}
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["Lume 机械键盘", 39900, 10]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["lume 主题卫衣", 19900, 5]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["程序员马克杯", 5900, 0]);
{{else}}
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["Lume 机械键盘", 39900]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["lume 主题卫衣", 19900]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["程序员马克杯", 5900]);
{{/if}}
    sql_write(db.dsn(), "INSERT OR REPLACE INTO \"_nsgm_shop_meta\" (\"k\", \"v\") VALUES ('seeded', '1')", []);
    prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" ORDER BY \"id\"", []);
    flash = "示例商品已载入。";
  }
  else if (act == "seed") {
    flash = "商品目录非空，未重复载入。";
  }
  // 新库一次性自动播种：无标记且空表（act 必须为空——clear 后标记已在，不会复活）
  if (act == "" && seeded == 0 && len(prows) == 0) {
{{#if has_stock}}
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["Lume 机械键盘", 39900, 10]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["lume 主题卫衣", 19900, 5]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\", \"{{skf}}\") VALUES (?, ?, ?)", ["程序员马克杯", 5900, 0]);
{{else}}
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["Lume 机械键盘", 39900]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["lume 主题卫衣", 19900]);
    sql_write(db.dsn(), "INSERT INTO \"{{pm}}\" (\"{{nf}}\", \"{{pf}}\") VALUES (?, ?)", ["程序员马克杯", 5900]);
{{/if}}
    prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" ORDER BY \"id\"", []);
  }
  let items = [];
  let i = 0;
  while (i < len(prows)) {
    let p = prows[i];
    let thumb = THUMBS[int(get(p, "id", 0)) % len(THUMBS)];
    let stk_s = str(get(p, "{{skf}}", ""));
    if (stk_s == "null" || stk_s == "") { stk_s = "0"; }
    let it = {
      "id": int(get(p, "id", 0)),
      "name": str(get(p, "{{nf}}", "")),
      "price_cents": int(get(p, "{{pf}}", 0)),
      "detail": (str(get(p, "detail", "")) == "null" ? "" : str(get(p, "detail", ""))),
      "thumb": thumb
{{#if has_stock}}
      , "stock": int(stk_s)
{{/if}}
    };
    push(items, it);
    i = i + 1;
  }
  return { "ok": true, "items": items, "currency_symbol": "{{csym}}", "seeded": seeded, "empty": (len(items) == 0 ? 1 : 0), "flash": flash };
};

// 下单（幂等）：无 ik（直接打开购买链接）时复用该商品最近一笔 pending 单；
// 已支付后再点同 ik 开新单（SHOP-<ik>-r<ts>）。返回 order_no 供前端跳转收银台。
post "/api/shop/buy", func(req) {
  let body = json(req.body);
  if (body == null) { return { "ok": false, "err": "invalid_json" }; }
  let pid = int(get(body, "product_id", 0));
  let ik = str(get(body, "ik", ""));
  let prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" WHERE \"id\" = ?", [pid]);
  if (len(prows) == 0) { return { "ok": false, "err": "product_not_found", "msg": "商品不存在" }; }
  let p = prows[0];
{{#if has_pref}}
  // 无 ik 时复用该商品最近一笔 pending 单（列表每次渲染都生成新 ik，不带 ik 的重复购买会各建各的单）
  if (ik == "") {
    let pend = sql_query(db.dsn(), "SELECT \"{{onf}}\" FROM \"{{om}}\" WHERE \"{{prdf}}\" = ? AND \"{{stf}}\" = 'pending' ORDER BY \"id\" DESC LIMIT 1", [pid]);
    if (len(pend) > 0) { return shop_cashier(str(get(pend[0], "{{onf}}", ""))); }
    ik = str(pid) + "-" + str(now());
  }
{{/if}}
  let ono = "SHOP-" + ik;
  let ex = sql_query(db.dsn(), "SELECT * FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [ono]);
  if (len(ex) > 0) {
    if (str(get(ex[0], "{{stf}}", "")) == "paid") { ono = ono + "-r" + str(now()); }
    else { return shop_cashier(ono); }
  }
{{#if has_pref}}
  sql_write(db.dsn(), "INSERT INTO \"{{om}}\" (\"{{onf}}\", \"{{amf}}\", \"{{prdf}}\"{{#if has_name}}, \"{{pnmf}}\"{{/if}}, \"{{stf}}\") VALUES (?, ?, ?{{#if has_name}}, ?{{/if}}, 'pending')", [
    ono, int(get(p, "{{pf}}", 0)), pid{{#if has_name}}, str(get(p, "{{nf}}", "")){{/if}}
  ]);
{{else}}
  sql_write(db.dsn(), "INSERT INTO \"{{om}}\" (\"{{onf}}\", \"{{amf}}\", \"{{stf}}\") VALUES (?, ?, 'pending')", [
    ono, int(get(p, "{{pf}}", 0))
  ]);
{{/if}}
{{#if has_stock}}
  // 下单扣库存（补偿模式）：先建单，再在 stock >= 1 守卫内原子扣减；0 行=售罄/并发被抢 -> 补偿删除本笔 pending 单
  let n = sql_write(db.dsn(), "UPDATE \"{{pm}}\" SET \"{{skf}}\" = \"{{skf}}\" - 1 WHERE \"id\" = ? AND \"{{skf}}\" >= 1", [pid]);
  if (n == 0) {
    sql_write(db.dsn(), "DELETE FROM \"{{om}}\" WHERE \"{{onf}}\" = ? AND \"{{stf}}\" = 'pending'", [ono]);
    return { "ok": false, "err": "sold_out", "msg": "「" + str(get(p, "{{nf}}", "")) + "」已售罄" };
  }
{{/if}}
  return shop_cashier(ono);
};

get "/shop/pay/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  return shop_cashier(ono);
};

get "/shop/result/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  return shop_result(ono);
};

// SPA 专用 /api 前缀别名（与 /shop/pay、/shop/result 同逻辑）：
// 走 /api 前缀以便 Vite dev/preview 代理（proxy 只配了 "/api"），免 CORS。
get "/api/shop/cashier/:ono", func(req) {
  return shop_cashier(str(get(req.params, "ono", "")));
};

get "/api/shop/result/:ono", func(req) {
  return shop_result(str(get(req.params, "ono", "")));
};

// 退款确认页数据（非变更）：返回订单状态 + 关联 ID；缺关联 ID 时 need_recover=1 引导去恢复。
get "/api/shop/refund/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  let orows = sql_query(db.dsn(), "SELECT * FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [ono]);
  if (len(orows) == 0) { return { "ok": false, "err": "order_not_found", "msg": "订单不存在" }; }
  let o = orows[0];
  let cents = int(get(o, "{{amf}}", 0));
  let st = str(get(o, "{{stf}}", ""));
  if (st == "refunded") { return { "ok": true, "status": "refunded", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" }; }
  let ppid = str(get(o, "{{ppidf}}", ""));
  if (ppid == "null") { ppid = ""; }
  let cap_id = str(get(o, "{{capf}}", ""));
  if (cap_id == "null") { cap_id = ""; }
  let need_recover = (cap_id == "" && ppid == "") ? 1 : 0;
  return { "ok": true, "order_no": ono, "status": st, "amount_cents": cents, "currency_symbol": "{{csym}}", "need_recover": need_recover, "ppid": ppid, "cap_id": cap_id };
};

// 执行退款：confirm=1 才退；仅 paid 可退；重复退幂等；缺关联 ID 可经 ppid/capid 反查或 manual 本地标记。
post "/api/shop/refund/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  let body = json(req.body);
  let confirm = (body != null ? str(get(body, "confirm", "")) : "");
  let q_ppid = (body != null ? str(get(body, "ppid", "")) : "");
  let q_capid = (body != null ? str(get(body, "capid", "")) : "");
  let manual = (body != null ? str(get(body, "manual", "")) : "");
  let orows = sql_query(db.dsn(), "SELECT * FROM \"{{om}}\" WHERE \"{{onf}}\" = ?", [ono]);
  if (len(orows) == 0) { return { "ok": false, "err": "order_not_found", "msg": "订单不存在" }; }
  let o = orows[0];
  let cents = int(get(o, "{{amf}}", 0));
  let st = str(get(o, "{{stf}}", ""));
  if (confirm != "1") { return { "ok": false, "err": "need_confirm" }; }
  if (st == "refunded") { return { "ok": true, "status": "refunded", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" }; }
  if (st != "paid") { return { "ok": false, "err": "not_paid", "status": st, "msg": "仅已支付订单可退款（当前状态：" + st + "）" }; }
  // 关联 ID 归一（SQL NULL 读出是 lume null，先归一）；早期订单缺列时允许从请求带入手动恢复的关联 ID
  let ppid = str(get(o, "{{ppidf}}", ""));
  if (ppid == "null") { ppid = ""; }
  let cap_id = str(get(o, "{{capf}}", ""));
  if (cap_id == "null") { cap_id = ""; }
  if (ppid == "" && q_ppid != "") { ppid = q_ppid; }
  if (cap_id == "" && q_capid != "") { cap_id = q_capid; }
  // 已在 PayPal 后台手动退款：仅本地标记退款（状态 + 库存闭环），不调 PayPal API
  if (manual == "1") {
    sql_write(db.dsn(), "UPDATE \"{{om}}\" SET \"{{stf}}\" = 'refunded' WHERE \"{{onf}}\" = ?", [ono]);
{{#if has_stock}}
    let rpid_s = str(get(o, "{{prdf}}", ""));
    if (rpid_s == "null" || rpid_s == "") { rpid_s = "0"; }
    if (int(rpid_s) > 0) { sql_write(db.dsn(), "UPDATE \"{{pm}}\" SET \"{{skf}}\" = \"{{skf}}\" + 1 WHERE \"id\" = ?", [int(rpid_s)]); }
{{/if}}
    return { "ok": true, "status": "refunded", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}", "manual": true };
  }
  // 捕获 ID 定位：本地 cap_id -> 本地/请求 ppid 反查 -> 请求 capid 直达
  // ppid 反查带捕获兜底：用户常把 PayPal 后台的「交易号/Transaction ID」（即捕获 ID）当订单号填入
  // ——订单 GET 对捕获 ID 回 404，改查捕获接口（related_ids.order_id 反解真实订单号）。
  if (cap_id == "" && ppid != "") {
    let tk0 = pay.paypal_token(PAYPAL_CFG);
    if (get(tk0, "ok", false) != true) { return { "ok": false, "err": "paypal_token_failed", "detail": str(get(tk0, "err", "")) }; }
    let tok0 = str(get(tk0, "token", ""));
    let go = pay.paypal_get_order(PAYPAL_CFG, tok0, ppid);
    if (get(go, "ok", false) != true) {
      let gc = pay.paypal_get_capture(PAYPAL_CFG, tok0, ppid);
      if (get(gc, "ok", false) == true) {
        cap_id = str(get(gc, "capture_id", ""));
        let rppid = str(get(gc, "order_id", ""));
        if (rppid != "") { ppid = rppid; }
      }
    } else {
      cap_id = str(get(go, "capture_id", ""));
    }
    if (cap_id == "") { return { "ok": false, "err": "capture_not_found", "msg": "无法从 PayPal 反查捕获记录" }; }
  }
  if (cap_id == "") { return { "ok": false, "err": "need_recover", "msg": "仍未定位到捕获记录，请到恢复页填入关联 ID" }; }
  let tk = pay.paypal_token(PAYPAL_CFG);
  if (get(tk, "ok", false) != true) { return { "ok": false, "err": "paypal_token_failed", "detail": str(get(tk, "err", "")) }; }
  let rf = pay.paypal_refund(PAYPAL_CFG, str(get(tk, "token", "")), cap_id, cents, "Refund " + ono);
  if (get(rf, "ok", false) != true) { return { "ok": false, "err": "paypal_refund_failed", "detail": str(get(rf, "err", "")) }; }
  // 回补关联 ID（本次靠手动/反查补齐，使后续操作一致）
  if (ppid != "" || cap_id != "") { sql_write(db.dsn(), "UPDATE \"{{om}}\" SET \"{{ppidf}}\" = ?, \"{{capf}}\" = ? WHERE \"{{onf}}\" = ?", [ppid, cap_id, ono]); }
{{#if has_stock}}
  // 退款回补库存：凭订单行商品 id 列定位商品行；早期订单无商品引用则跳过
  let rpid_s = str(get(o, "{{prdf}}", ""));
  if (rpid_s == "null" || rpid_s == "") { rpid_s = "0"; }
  if (int(rpid_s) > 0) { sql_write(db.dsn(), "UPDATE \"{{pm}}\" SET \"{{skf}}\" = \"{{skf}}\" + 1 WHERE \"id\" = ?", [int(rpid_s)]); }
{{/if}}
  sql_write(db.dsn(), "UPDATE \"{{om}}\" SET \"{{stf}}\" = 'refunded' WHERE \"{{onf}}\" = ?", [ono]);
  return { "ok": true, "status": "refunded", "order_no": ono, "amount_cents": cents, "currency_symbol": "{{csym}}" };
};
