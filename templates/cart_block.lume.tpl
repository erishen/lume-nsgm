// ---- 购物车（lume-nsgm 生成：落库持久化，session 仅存 cart_id）----
// 设计（P2-4）：加性能力，不改动既有「直接下单」(/api/shop/buy) 链路。
//   cart(id, status, created_at)        —— 一购物车一行；status: active/done
//   cart_item(id, cart_id, product_id, qty, price_cents, name)
//     —— 价格/名称下单时快照；结算复用单商品建单 + 库存守卫（与 P1-2 同口径）
// session 仅存 cart_id（S1 边界：WORKERS=1 下 session 跨请求持久；cart 落库故重启不丢）
// 全量 SPA：本块只出 JSON API；页面由 /spa/ 下 React 渲染。
// 幂等：同名商品加购合并数量；结算逐行建单，成功行即清出购物车。

// 取当前购物车 id：session 里有且为 active 则复用；must_create=1 且无则新建并写回 session
func cart_get_or_create(req, must_create: int): int {
  let cid_s = str(get(req.session, "cart_id", ""));
  if (cid_s != "" && cid_s != "null") {
    let ex = sql_query(db.dsn(), "SELECT \"id\", \"status\" FROM \"cart\" WHERE \"id\" = ?", [int(cid_s)]);
    if (len(ex) > 0 && str(get(ex[0], "status", "")) == "active") { return int(cid_s); }
  }
  if (must_create == 0) { return 0; }
  sql_write(db.dsn(), "INSERT INTO \"cart\" (\"status\", \"created_at\") VALUES ('active', ?)", [str(now())]);
  let nr = sql_query(db.dsn(), "SELECT \"id\" FROM \"cart\" ORDER BY \"id\" DESC LIMIT 1", []);
  let nid = (len(nr) > 0 ? int(get(nr[0], "id", 0)) : 0);
  put(req.session, "cart_id", str(nid));
  return nid;
}

// 购物车摘要：LEFT JOIN 商品取名称/价格/库存；失败（商品被删）回落快照；汇总 total_cents
func cart_summary(cid: int) {
  let rows = sql_query(db.dsn(), "SELECT ci.\"id\" AS ci_id, ci.\"product_id\" AS pid, ci.\"qty\" AS qty, ci.\"price_cents\" AS price, ci.\"name\" AS cname, p.\"{{nf}}\" AS pname, p.\"{{pf}}\" AS pprice{{#if has_stock}}, p.\"{{skf}}\" AS pstock{{/if}} FROM \"cart_item\" ci LEFT JOIN \"{{pm}}\" p ON ci.\"product_id\" = p.\"id\" WHERE ci.\"cart_id\" = ? ORDER BY ci.\"id\"", [cid]);
  let items = [];
  let total = 0;
  let i = 0;
  while (i < len(rows)) {
    let r = rows[i];
    let pid = int(get(r, "pid", 0));
    let qty = int(get(r, "qty", 0));
    let price = int(get(r, "price", 0));
    let name = str(get(r, "cname", ""));
    if (name == "" || name == "null") { name = str(get(r, "pname", "")); }
    let stock = -1;
{{#if has_stock}}
    stock = int(get(r, "pstock", -1));
{{/if}}
    total = total + price * qty;
    push(items, {
      "item_id": int(get(r, "ci_id", 0)),
      "product_id": pid,
      "qty": qty,
      "price_cents": price,
      "name": name
{{#if has_stock}}
      , "stock": stock
{{/if}}
    });
    i = i + 1;
  }
  return { "ok": true, "items": items, "total_cents": total, "currency_symbol": "{{csym}}", "count": len(items) };
}

// 加购（合并同名商品数量）；返回购物车摘要
post "/api/shop/cart/add", func(req) {
  let body = json(req.body);
  if (body == null) { return { "ok": false, "err": "invalid_json" }; }
  let pid = int(get(body, "product_id", 0));
  let qty = int(get(body, "qty", 0));
  if (qty <= 0) { qty = 1; }
  let prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" WHERE \"id\" = ?", [pid]);
  if (len(prows) == 0) { return { "ok": false, "err": "product_not_found", "msg": "商品不存在" }; }
  let p = prows[0];
  let cid = cart_get_or_create(req, 1);
  let exist = sql_query(db.dsn(), "SELECT \"id\", \"qty\" FROM \"cart_item\" WHERE \"cart_id\" = ? AND \"product_id\" = ?", [cid, pid]);
  if (len(exist) > 0) {
    sql_write(db.dsn(), "UPDATE \"cart_item\" SET \"qty\" = ? WHERE \"id\" = ?", [int(get(exist[0], "qty", 0)) + qty, int(get(exist[0], "id", 0))]);
  } else {
    sql_write(db.dsn(), "INSERT INTO \"cart_item\" (\"cart_id\", \"product_id\", \"qty\", \"price_cents\", \"name\") VALUES (?, ?, ?, ?, ?)", [cid, pid, qty, int(get(p, "{{pf}}", 0)), str(get(p, "{{nf}}", ""))]);
  }
  return cart_summary(cid);
};

// 查看购物车（无购物车则返回空摘要，不建空车）
get "/api/shop/cart", func(req) {
  let cid = cart_get_or_create(req, 0);
  return cart_summary(cid);
};

// 改数量（qty<=0 视为移除）
post "/api/shop/cart/update", func(req) {
  let body = json(req.body);
  if (body == null) { return { "ok": false, "err": "invalid_json" }; }
  let iid = int(get(body, "item_id", 0));
  let qty = int(get(body, "qty", 0));
  let cid = cart_get_or_create(req, 1);
  if (qty <= 0) {
    sql_write(db.dsn(), "DELETE FROM \"cart_item\" WHERE \"id\" = ? AND \"cart_id\" = ?", [iid, cid]);
  } else {
    sql_write(db.dsn(), "UPDATE \"cart_item\" SET \"qty\" = ? WHERE \"id\" = ? AND \"cart_id\" = ?", [qty, iid, cid]);
  }
  return cart_summary(cid);
};

// 移除单项
post "/api/shop/cart/remove", func(req) {
  let body = json(req.body);
  if (body == null) { return { "ok": false, "err": "invalid_json" }; }
  let iid = int(get(body, "item_id", 0));
  let cid = cart_get_or_create(req, 1);
  sql_write(db.dsn(), "DELETE FROM \"cart_item\" WHERE \"id\" = ? AND \"cart_id\" = ?", [iid, cid]);
  return cart_summary(cid);
};

// 结算：逐行复用单商品建单 + 库存守卫（P1-2 口径），成功行即清出购物车；
// 全部成功则购物车标记 done，否则保留未成功行供重试。返回每行订单结果。
post "/api/shop/cart/checkout", func(req) {
  let cid = cart_get_or_create(req, 0);
  if (cid == 0) { return { "ok": false, "err": "cart_empty", "msg": "购物车为空" }; }
  let items = sql_query(db.dsn(), "SELECT * FROM \"cart_item\" WHERE \"cart_id\" = ?", [cid]);
  if (len(items) == 0) { return { "ok": false, "err": "cart_empty", "msg": "购物车为空" }; }
  let orders = [];
  let done_ids = [];
  let i = 0;
  while (i < len(items)) {
    let it = items[i];
    let pid = int(get(it, "product_id", 0));
    let qty = int(get(it, "qty", 0));
    let prows = sql_query(db.dsn(), "SELECT * FROM \"{{pm}}\" WHERE \"id\" = ?", [pid]);
    if (len(prows) == 0) { push(orders, { "product_id": pid, "ok": false, "err": "product_gone" }); i = i + 1; continue; }
    let p = prows[0];
    let unit = int(get(it, "price_cents", 0));
    let amt = unit * qty;
    let ono = "CART-" + str(cid) + "-" + str(pid) + "-" + str(now());
{{#if has_pref}}
    sql_write(db.dsn(), "INSERT INTO \"{{om}}\" (\"{{onf}}\", \"{{amf}}\", \"{{prdf}}\"{{#if has_name}}, \"{{pnmf}}\"{{/if}}, \"{{stf}}\") VALUES (?, ?, ?{{#if has_name}}, ?{{/if}}, 'pending')", [
      ono, amt, pid{{#if has_name}}, str(get(p, "{{nf}}", "")){{/if}}
    ]);
{{else}}
    sql_write(db.dsn(), "INSERT INTO \"{{om}}\" (\"{{onf}}\", \"{{amf}}\", \"{{stf}}\") VALUES (?, ?, 'pending')", [ono, amt]);
{{/if}}
{{#if has_stock}}
    // 库存守卫：在 stock >= qty 内原子扣减；0 行=售罄/并发被抢 -> 补偿删单
    let n = sql_write(db.dsn(), "UPDATE \"{{pm}}\" SET \"{{skf}}\" = \"{{skf}}\" - ? WHERE \"id\" = ? AND \"{{skf}}\" >= ?", [qty, pid, qty]);
    if (n == 0) {
      sql_write(db.dsn(), "DELETE FROM \"{{om}}\" WHERE \"{{onf}}\" = ? AND \"{{stf}}\" = 'pending'", [ono]);
      push(orders, { "product_id": pid, "ok": false, "err": "sold_out" });
      i = i + 1; continue;
    }
{{/if}}
    push(orders, { "product_id": pid, "order_no": ono, "amount_cents": amt, "qty": qty, "ok": true });
    push(done_ids, int(get(it, "id", 0)));
    i = i + 1;
  }
  let d = 0;
  while (d < len(done_ids)) {
    sql_write(db.dsn(), "DELETE FROM \"cart_item\" WHERE \"id\" = ?", [get(done_ids, d, 0)]);
    d = d + 1;
  }
  let remain = sql_query(db.dsn(), "SELECT \"id\" FROM \"cart_item\" WHERE \"cart_id\" = ?", [cid]);
  if (len(remain) == 0) { sql_write(db.dsn(), "UPDATE \"cart\" SET \"status\" = 'done' WHERE \"id\" = ?", [cid]); }
  return { "ok": true, "orders": orders, "currency_symbol": "{{csym}}" };
};
