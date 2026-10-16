#!/usr/bin/env python3
# 一次性重构：店面下单改为「直接渲染收银台 + 幂等 Key 复用 pending 单」，去掉 JS 跳转中间页。
p = "lib/base.lume"
s = open(p, encoding="utf-8").read()

i = s.index('    + "// ---- 店面（lume-nsgm 生成')
j = s.index('  // 占位符统一在拼接完成后替换')

def esc(line):
    e = line.replace('\\', '\\\\').replace('"', '\\"')
    return '    + "' + e + '\\n"'

def block(text):
    return ''.join(esc(l) + '\n' for l in text.split('\n') if l != '')

partA = r'''// ---- 店面（lume-nsgm 生成：商品列表 -> 下单 -> 收银台 -> 结果页）----
// 幂等：渲染商品列表时为每个商品附带 ik（幂等 Key）。下单 GET /shop/buy/:id?ik= 复用同一笔 pending 单，
// 避免刷新 / 重复点击产生重复订单；下单后直接渲染收银台，不再经 JS 跳转中间页。
func shop_result(ono: string): string {
  let orows = sql_query(db.dsn(), "SELECT * FROM \"__OM__\" WHERE \"__ONF__\" = ?", [ono]);
  if (len(orows) == 0) { return ui.page("支付结果", "shop", "<div class=\"flash err\">订单不存在</div><p><a href=\"/shop\">返回商城</a></p>"); }
  let st = str(get(orows[0], "__STF__", ""));
  if (st == "paid") {
    return ui.page("支付成功", "shop", "<h1>支付成功</h1><p>订单 <code>" + ui.esc(ono) + "</code> 已完成。</p><p><a class=\"btn primary\" href=\"/shop\">继续购物</a></p>");
  }
  return ui.page("等待支付", "shop", "<h1>等待支付</h1><p>订单 <code>" + ui.esc(ono) + "</code> 状态：" + ui.esc(st) + "。</p><p><a class=\"btn primary\" href=\"/shop/pay/" + ono + "\">去支付</a></p>");
}

func shop_cashier(ono: string): string {
  let orows = sql_query(db.dsn(), "SELECT * FROM \"__OM__\" WHERE \"__ONF__\" = ?", [ono]);
  if (len(orows) == 0) { return ui.page("支付", "shop", "<div class=\"flash err\">订单不存在</div><p><a href=\"/shop\">返回商城</a></p>"); }
  let o = orows[0];
  if (str(get(o, "__STF__", "")) == "paid") { return shop_result(ono); }
  let cents = int(get(o, "__AMF__", 0));'''

partB_paypal = r'''  let tk = pay.paypal_token(PAYPAL_CFG);
  if (get(tk, "ok", false) != true) {
    return ui.page("支付", "shop", "<div class=\"flash err\">PayPal 令牌失败：" + ui.esc(str(get(tk, "err", ""))) + "</div>");
  }
  let return_url = PAYPAL_RETURN_BASE + "/api/pay/return?order_no=" + ono;
  let cancel_url = PAYPAL_RETURN_BASE + "/api/pay/cancel?order_no=" + ono;
  let r = pay.paypal_create(PAYPAL_CFG, str(get(tk, "token", "")), ono, cents, "Shop order " + ono, return_url, cancel_url);
  if (get(r, "ok", false) != true) {
    return ui.page("支付", "shop", "<div class=\"flash err\">支付网关错误：" + ui.esc(str(get(r, "err", ""))) + "</div><p><a href=\"/shop/pay/" + ono + "\">重试</a></p>");
  }
  let body = "<h1>收银台</h1>\n<p>订单 <code>" + ui.esc(ono) + "</code> · 金额 <strong>$" + pay.fmt_cents(cents) + "</strong></p>\n"
    + "<p><a class=\"btn primary\" href=\"" + ui.esc(str(get(r, "approve_url", ""))) + "\">前往 PayPal 支付</a> <a class=\"btn ghost\" href=\"/shop/result/" + ono + "\">查询支付结果</a></p>\n";
  return ui.page("收银台", "shop", body);'''

partB_wechat = r'''  let r = pay.create_native(PAY_CFG, ono, cents, "商城订单 " + ono, PAY_NOTIFY_URL);
  if (get(r, "ok", false) != true) {
    return ui.page("支付", "shop", "<div class=\"flash err\">支付网关错误：" + ui.esc(str(get(r, "err", ""))) + "</div><p><a href=\"/shop/pay/" + ono + "\">重试</a></p>");
  }
  let body = "<h1>收银台</h1>\n<p>订单 <code>" + ui.esc(ono) + "</code> · 金额 <strong>¥" + pay.fmt_cents(cents) + "</strong></p>\n"
    + "<p>微信扫码支付（mock）：</p><p><code>" + ui.esc(str(get(r, "code_url", ""))) + "</code></p>\n"
    + "<p><a class=\"btn primary\" href=\"/shop/mock-pay/" + ono + "\">模拟支付成功（demo）</a> <a class=\"btn ghost\" href=\"/shop/result/" + ono + "\">查询支付结果</a></p>\n";
  return ui.page("收银台", "shop", body);'''

partC = r'''get "/shop", func(req) {
  let prows = sql_query(db.dsn(), "SELECT * FROM \"__PM__\" ORDER BY \"id\"", []);
  if (len(prows) == 0) {
    sql_write(db.dsn(), "INSERT INTO \"__PM__\" (\"__NF__\", \"__PF__\") VALUES (?, ?)", ["Lume 机械键盘", 39900]);
    sql_write(db.dsn(), "INSERT INTO \"__PM__\" (\"__NF__\", \"__PF__\") VALUES (?, ?)", ["lume 主题卫衣", 19900]);
    sql_write(db.dsn(), "INSERT INTO \"__PM__\" (\"__NF__\", \"__PF__\") VALUES (?, ?)", ["程序员马克杯", 5900]);
    prows = sql_query(db.dsn(), "SELECT * FROM \"__PM__\" ORDER BY \"id\"", []);
  }
  let body = "<h1>商城</h1>\n<p class=\"muted\">演示店面：点「购买」下单，收银台完成支付，回调自动落库。</p>\n";
  let i = 0;
  while (i < len(prows)) {
    let p = prows[i];
    let ik = str(get(p, "id", 0)) + "-" + str(now());
    body = body + "<div class=\"card\"><h3>" + ui.esc(str(get(p, "__NF__", ""))) + "</h3>\n"
      + "<p class=\"price\">¥" + pay.fmt_cents(int(get(p, "__PF__", 0))) + "</p>\n"
      + "<p class=\"muted\">" + ui.esc(str(get(p, "detail", ""))) + "</p>\n"
      + "<a class=\"btn primary\" href=\"/shop/buy/" + str(get(p, "id", 0)) + "?ik=" + ik + "\">购买</a></div>\n";
    i = i + 1;
  }
  return ui.page("商城", "shop", body);
};

get "/shop/buy/:id", func(req) {
  let pid = db.qs_int(req.params, "id", 0);
  let ik = str(get(req.query_params, "ik", ""));
  if (ik == "") { ik = str(pid) + "-" + str(now()); }
  let ono = "SHOP-" + ik;
  let prows = sql_query(db.dsn(), "SELECT * FROM \"__PM__\" WHERE \"id\" = ?", [pid]);
  if (len(prows) == 0) { return ui.page("商城", "shop", "<div class=\"flash err\">商品不存在</div><p><a href=\"/shop\">返回商城</a></p>"); }
  let p = prows[0];
  let ex = sql_query(db.dsn(), "SELECT * FROM \"__OM__\" WHERE \"__ONF__\" = ?", [ono]);
  if (len(ex) > 0) {
    if (str(get(ex[0], "__STF__", "")) == "paid") { ono = ono + "-r" + str(now()); }
    else { return shop_cashier(ono); }
  }
  sql_write(db.dsn(), "INSERT INTO \"__OM__\" (\"__ONF__\", \"__AMF__\", \"__STF__\") VALUES (?, ?, 'pending')", [ono, int(get(p, "__PF__", 0))]);
  return shop_cashier(ono);
};

get "/shop/pay/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  return shop_cashier(ono);
};

// demo 专用：让 mock 网关代投递签名回调（真实环境由微信服务器打 notify）
get "/shop/mock-pay/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  let orows = sql_query(db.dsn(), "SELECT * FROM \"__OM__\" WHERE \"__ONF__\" = ?", [ono]);
  if (len(orows) == 0) { return ui.page("支付", "shop", "<div class=\"flash err\">订单不存在</div>"); }
  let cents = int(get(orows[0], "__AMF__", 0));
  let nb = stringify({ "notify_url": PAY_NOTIFY_URL, "order_no": ono, "amount_cents": cents });
  http_post(str(get(PAY_CFG, "gw", "")) + "/mock/notify", { "headers": { "Content-Type": "application/json" }, "body": nb, "allow_private": true, "timeout": 10 });
  return shop_result(ono);
};

get "/shop/result/:ono", func(req) {
  let ono = str(get(req.params, "ono", ""));
  return shop_result(ono);
};'''

prov = (
'  if (provider == "paypal") {\n'
'    t = t + ""\n'
+ block(partB_paypal)
+ '      ;\n'
'  } else {\n'
'    t = t + ""\n'
+ block(partB_wechat)
+ '      ;\n'
'  }\n'
'  t = t + "}\\n"\n'
)

new_region = block(partA) + '  ;\n' + prov + block(partC) + '    ;\n'

s2 = s[:i] + new_region + s[j:]
if s2 == s:
    print("NO CHANGE (anchors may mismatch)")
    import sys
    sys.exit(1)
open(p, "w", encoding="utf-8").write(s2)
print("patched base.lume OK; region chars:", len(new_region))
