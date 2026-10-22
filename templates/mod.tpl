// modules/{{ctrl}}.lume — {{ctrl}} 模块（lume-nsgm 生成，勿手改）
import "../lib/ui.lume" as ui;
import "../lib/db.lume" as db;

export let DDL = "{{ddl}}";

export let TBL = "{{ctrl}}";
// 数据驱动字段表：form=入表单 search=可搜索 required=必填 list=列表列
let FIELDS = [
{{#each fields as f}}  { "name": "{{f.name}}", "label": "{{f.label}}", "form": {{f.form}}, "search": {{f.search}}, "required": {{f.required}}, "list": {{f.list}}, "type": "{{f.type}}", "fmt": "{{f.fmt}}" },
{{/each}}
];

// 列元数据（迁移用）：name/type_sql/default 与 DDL 一致；auto 列不参与补齐
export let COLS = [
{{#each fields as f}}  { "name": "{{f.name}}", "type_sql": "{{f.type_sql}}", "not_null": {{f.not_null}}, "auto": {{f.auto}}, "default": "{{f.default}}" },
{{/each}}
];

// P2-1：引用字段下拉——从目标模块取 id + 显示列（约定 name），渲染 <select>；
// selected 为当前存储的 id（字符串），命中即标 selected。列表/编辑表单共用。
func ref_select(target: string, dispcol: string, name: string, selected: string): string {
  let rows = sql_query(db.dsn(), "SELECT \"id\", \"" + dispcol + "\" FROM \"" + target + "\" ORDER BY id", []);
  let h = "<select name=\"" + name + "\">";
  let i = 0;
  while (i < len(rows)) {
    let r = rows[i];
    let idv = str(get(r, "id", 0));
    let lbl = str(get(r, dispcol, ""));
    let sel = (idv == selected ? " selected" : "");
    h = h + "<option value=\"" + ui.esc(idv) + "\"" + sel + ">" + ui.esc(lbl) + "</option>";
    i = i + 1;
  }
  return h + "</select>";
}

// P2-3：枚举选项 <option> 串（values_json 为 ["a","b"] 形式的 JSON 字符串）；
// selected 命中即标 selected（编辑页回显）。取值由校验期收窄，ui.esc 防注入。
func enum_opts_html(values_json: string, selected: string): string {
  let vals = json(values_json);
  let h = "";
  let i = 0;
  while (i < len(vals)) {
    let vv = str(get(vals, i, ""));
    let sel = (vv == selected ? " selected" : "");
    h = h + "<option value=\"" + ui.esc(vv) + "\"" + sel + ">" + ui.esc(vv) + "</option>";
    i = i + 1;
  }
  return h;
}

// 生成期拼好的列固定 SQL（值一律 ? 绑定，由 handler 追加）
let INSERT_SQL = "{{insert_sql}}";
let UPDATE_SQL = "{{update_sql}}"; // ... WHERE id = ?（id 由 handler 追加）

// 搜索条件（数据驱动：对所有 search 字段做 OR LIKE）
func where_for(qp) {
  let q = str(get(qp, "q", ""));
  if (q == "") { return { "where": "", "params": [] }; }
  // 转义 LIKE 通配符，避免用户输入 %/_ 命中全部记录
  let qe = replace(replace(q, "%", "\\%"), "_", "\\_");
  let conds = "";
  let params = [];
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "search", 0) == 1) {
      if (conds != "") { conds = conds + " OR "; }
      conds = conds + "\"" + get(f, "name", "") + "\" LIKE ? ESCAPE \"\\\"";
      push(params, "%" + qe + "%");
    }
    i = i + 1;
  }
  if (conds == "") { return { "where": "", "params": [] }; }
  return { "where": " WHERE (" + conds + ")", "params": params };
}

func list_rows(page: int, pageSize: int, qp) {
  let w = where_for(qp);
  let where = get(w, "where", "");
  let args = db.push_all([], get(w, "params", []));
  push(args, pageSize);
  push(args, page * pageSize);
  // P2-2：列表走 JOIN 视图（{{list_head}} 已由生成器拼好 SELECT/FROM/JOIN，ref 字段投影为 <field>_name）
  let rows = sql_query(db.dsn(), {{list_head}} + where + " ORDER BY \"t\".id DESC LIMIT ? OFFSET ?", args);
  let cnt = sql_query(db.dsn(), {{list_count}} + where, get(w, "params", []));
  return { "total": db.count_of(cnt), "items": rows };
}

func get_row(id: int) {
  let rows = sql_query(db.dsn(), "SELECT * FROM \"" + TBL + "\" WHERE id = ?", [id]);
  if (len(rows) == 0) { return null; }
  return rows[0];
}
{{#if refund_on}}
// 对账保护：paid/refunded 的店面订单已被支付网关引用（退款按行金额、关联 ID
// 已回填），后台改单/删单会破坏对账 —— 一律拒绝；pending 单照常可编辑
func row_locked(r): int {
  if (r == null) { return 0; }
  let st = str(get(r, "{{refund_st_f}}", ""));
  if (st == "paid" || st == "refunded") { return 1; }
  return 0;
}
{{/if}}

// 从表单/JSON 数据按序收集 form 字段值（写入 out_vals）；
// 返回 "" 表示齐全，否则为缺失的必填字段 label
func collect(data, out_vals): string {
  let missing = "";
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "form", 0) == 1) {
      let v = str(get(data, get(f, "name", ""), ""));
      if (get(f, "required", 0) == 1 && v == "") { missing = get(f, "label", ""); }
      push(out_vals, v);
    }
    i = i + 1;
  }
  return missing;
}

// ---------- SSR 页面 ----------

func list_body(qp) {
  let page = db.qs_int(qp, "page", 0);
  let pageSize = db.qs_int(qp, "pageSize", 20);
  let res = list_rows(page, pageSize, qp);
  let total = get(res, "total", 0);
  let items = get(res, "items", []);
  let q = str(get(qp, "q", ""));

  let body = "<h1>{{ctrl}} 列表 <span class=\"muted\">(" + str(total) + ")</span></h1>\n";
  body = body + "<form class=\"toolbar\" method=\"get\" action=\"/{{ctrl}}\">"
    + "<input name=\"q\" value=\"" + ui.esc(q) + "\" placeholder=\"搜索\">"
    + "<input type=\"hidden\" name=\"page\" value=\"0\">"
    + "<button class=\"ghost\">搜索</button>"
    + (q != "" ? "<a class=\"clear\" href=\"/{{ctrl}}\">清除</a>" : "")
    + "<a class=\"btn primary push\" href=\"/{{ctrl}}/new\">+ 新增</a>"
    + "</form>\n";

  // 计算需显示的列表列：list==1 且当前页至少一行有值；全空列（如未走店面的
  // product_id / product_name / paypal_order_id）不渲染，避免无意义空白占宽。
  // 无行时展示全部表头，保证空态表格整齐。
  let vis = [];
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "list", 0) == 1) {
      let any_val = 0;
      if (len(items) == 0) { any_val = 1; }
      else {
        let k = 0;
        while (k < len(items)) {
          let rv = str(get(items[k], get(f, "name", ""), ""));
          if (rv != "" && rv != "null") { any_val = 1; break; }
          k = k + 1;
        }
      }
      if (any_val == 1) { push(vis, i); }
    }
    i = i + 1;
  }
  let ncols = len(vis) + 1;

  body = body + "<div class=\"table-wrap\"><table class=\"grid\"><thead><tr>";
  let vi = 0;
  while (vi < len(vis)) {
    let f = FIELDS[vis[vi]];
    body = body + "<th>" + ui.esc(get(f, "label", "")) + "</th>";
    vi = vi + 1;
  }
  body = body + "<th class=\"op\">操作</th></tr></thead><tbody>\n";

  i = 0;
  if (len(items) == 0) {
    if (q != "") {
      body = body + "<tr><td colspan=\"" + str(ncols) + "\"><div class=\"empty\">"
        + "<div class=\"ico\">🔍</div><p>无匹配结果</p>"
        + "<a class=\"btn primary\" href=\"/{{ctrl}}\">清除搜索</a>"
        + "</div></td></tr>\n";
    } else {
      body = body + "<tr><td colspan=\"" + str(ncols) + "\"><div class=\"empty\">"
        + "<div class=\"ico\">📭</div><p>暂无数据</p>"
        + "<a class=\"btn primary\" href=\"/{{ctrl}}/new\">新增第一条</a>"
        + "</div></td></tr>\n";
    }
  }
  while (i < len(items)) {
    let r = items[i];
    body = body + "<tr>";
    let j = 0;
    while (j < len(vis)) {
      let f = FIELDS[vis[j]];
      let v = str(get(r, get(f, "name", ""), ""));
      // 迁移补列（ALTER ADD COLUMN 无默认值）的旧行读出是 SQL NULL -> lume null，
      // str(null) 得字面量 "null"——非空串，会骗过 == "" 守卫渲染出 "null"，先归一
      if (v == "null") { v = ""; }
      let ffmt = str(get(f, "fmt", ""));
      if (ffmt == "money" && v != "" && v != "null") {
        // *_cents 字段：分 -> 元（tabular-nums 对齐，货币符号随店面 provider）
        let c = int(v);
        let tail = str(c % 100);
        if (c % 100 < 10) { tail = "0" + tail; }
        body = body + "<td class=\"money\">{{cur_sym}}" + str(int(c / 100)) + "." + tail + "</td>";
      } else if (ffmt == "st") {
        // status 字段：paid=绿 pending=黄 refunded=灰（未知值=蓝）
        let sc = "st-info";
        if (v == "paid") { sc = "st-ok"; }
        if (v == "pending") { sc = "st-warn"; }
        if (v == "refunded") { sc = "st-mut"; }
        body = body + "<td><span class=\"st " + sc + "\">" + ui.esc(v) + "</span></td>";
      } else if (get(f, "enum", 0) == 1) {
        // P2-3：枚举字段渲染为彩色 tag（取值由校验期收窄，无注入面）
        body = body + "<td><span class=\"tag\">" + ui.esc(v) + "</span></td>";
      } else if (get(f, "ref", 0) == 1) {
        // P2-2：引用字段显示关联名（列表 JOIN 投影的 <field>_name 列），无则回落原始 id
        let rv = str(get(r, get(f, "name", "") + "_name", ""));
        if (rv != "" && rv != "null") { v = rv; }
        body = body + "<td>" + ui.esc(v) + "</td>";
      } else {
      // 时间列暴露原始值（data-ts），由 app.js 转本地友好格式
      let ts_attr = "";
      let ft = get(f, "type", "");
      if (ft == "timestamp" || ft == "date") { ts_attr = " data-ts=\"" + ui.esc(v) + "\""; }
      body = body + "<td" + ts_attr + ">" + ui.esc(v) + "</td>";
      }
      j = j + 1;
    }
    let rid = str(get(r, "id", 0));
    body = body + "<td class=\"op\">";
    // 对账锁定（refund 模块）：paid 行只留退款入口、refunded 行无后台操作，
    // 与 save/del handler 的状态守卫一致；普通模块恒出编辑/删除
    let lck = 0;
{{#if refund_on}}
    if (str(get(r, "{{refund_st_f}}", "")) == "paid") { lck = 1; }
    if (str(get(r, "{{refund_st_f}}", "")) == "refunded") { lck = 1; }
{{/if}}
    if (lck == 0) {
      body = body + "<a href=\"/{{ctrl}}/edit/" + rid + "\">编辑</a> "
        + "<a class=\"del\" href=\"/{{ctrl}}/del/" + rid + "\">删除</a>";
    }
{{#if refund_on}}
    if (str(get(r, "{{refund_st_f}}", "")) == "paid") {
      body = body + "<a class=\"refund\" href=\"/shop/refund/" + ui.esc(str(get(r, "{{refund_no_f}}", ""))) + "\">退款</a>";
    }
{{/if}}
    body = body + "</td></tr>\n";
    i = i + 1;
  }
  body = body + "</tbody></table></div>\n";

  // 分页：总条数 + 页码恒显，上/下页按钮在越界侧置灰
  // lume 的 / 是浮点除，整除 ceil 须用 % 余数判断
  let pages = int(total / pageSize) + (total % pageSize > 0 ? 1 : 0);
  if (pages < 1) { pages = 1; }
  body = body + "<div class=\"pager\">";
  body = body + "<span class=\"info\">共 " + str(total) + " 条 · 第 " + str(page + 1) + " / " + str(pages) + " 页</span>";
  if (page > 0) {
    body = body + "<a href=\"/{{ctrl}}?page=" + str(page - 1) + "&q=" + ui.esc(q) + "\">‹ 上一页</a>";
  } else {
    body = body + "<span class=\"pg disabled\">‹ 上一页</span>";
  }
  if ((page + 1) * pageSize < total) {
    body = body + "<a href=\"/{{ctrl}}?page=" + str(page + 1) + "&q=" + ui.esc(q) + "\">下一页 ›</a>";
  } else {
    body = body + "<span class=\"pg disabled\">下一页 ›</span>";
  }
  body = body + "</div>\n";
  return body;
}

// 表单页：新增（id=0）与编辑共用；vals 为预填 map，msg 为校验错误提示
func form_page(id: int, vals, msg: string): string {
  let body = "<div class=\"form-wrap\">\n";
  if (msg != "") { body = body + "<div class=\"flash err\">" + ui.esc(msg) + "</div>\n"; }
  if (id > 0) {
    body = body + "<h1>编辑 {{ctrl}}</h1>\n";
  } else {
    body = body + "<h1>新增 {{ctrl}}</h1>\n";
  }
  body = body + "<form class=\"stack\" method=\"get\" action=\"/{{ctrl}}/save\">\n";
  if (id > 0) { body = body + "  <input type=\"hidden\" name=\"id\" value=\"" + str(id) + "\">\n"; }
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "form", 0) == 1) {
      let req = get(f, "required", 0) == 1;
      // NULL 归一（同列表列）：编辑页预填不能把 "null" 字面量写进输入框
      let fv = str(get(vals, get(f, "name", ""), ""));
      if (fv == "null") { fv = ""; }
      let lbl = ui.esc(get(f, "label", "")) + (req ? "<span class=\"req\"> *</span>" : "");
      if (get(f, "ref", 0) == 1) {
        // P2-1：引用字段渲染关联下拉（选项来自目标模块，selected = 当前 id）
        body = body + "  <label>" + lbl + "\n    "
          + ref_select(get(f, "target", ""), get(f, "ref_disp", ""), get(f, "name", ""), fv)
          + "\n  </label>\n";
      } else if (get(f, "enum", 0) == 1) {
        // P2-3：枚举字段渲染固定选项下拉（selected = 当前值）
        body = body + "  <label>" + lbl + "\n    <select name=\""
          + get(f, "name", "") + "\">" + enum_opts_html(get(f, "values_json", ""), fv)
          + "</select>\n  </label>\n";
      } else {
        // 普通字段：文本/数值输入框
        body = body + "  <label>" + lbl + "\n    <input name=\"" + get(f, "name", "")
          + "\" value=\"" + ui.esc(fv) + "\""
          + (req ? " required" : "") + ">\n  </label>\n";
      }
    }
    i = i + 1;
  }
  body = body + "  <div class=\"form-actions\"><button>保存</button>"
    + "<a class=\"btn ghost\" href=\"/{{ctrl}}\">返回</a></div>\n</form>\n</div>\n";
  return ui.page("{{ctrl}}", "{{ctrl}}", body);
}

func flash_page(msg: string, kind: string, back_path: string): string {
  let body = "<div class=\"form-wrap\"><div class=\"flash " + kind + "\">" + ui.esc(msg) + "</div>\n"
    + "<p><a href=\"" + back_path + "\">返回列表</a></p></div>\n"
    + "<script>setTimeout(function(){ location.href = '" + back_path + "'; }, 1200);</script>\n";
  return ui.page("{{ctrl}}", "{{ctrl}}", body);
}

// ---------- 页面路由 ----------

get "/{{ctrl}}", func(req) {
  return ui.page("{{ctrl}}", "{{ctrl}}", list_body(db.qparams(req)));
};

get "/{{ctrl}}/new", func(req) {
  return form_page(0, {}, "");
};

get "/{{ctrl}}/edit/:id", func(req) {
  let id = db.qs_int(req.params, "id", 0);
  let r = get_row(id);
  if (r == null) { return flash_page("记录不存在", "err", "/{{ctrl}}"); }
  return form_page(id, r, "");
};

get "/{{ctrl}}/save", func(req) {
  let qp = db.qparams(req);
  let id = db.qs_int(qp, "id", 0);
{{#if refund_on}}
  if (id > 0 && row_locked(get_row(id)) == 1) {
    return flash_page("已支付/已退款订单受对账保护，禁止编辑", "err", "/{{ctrl}}");
  }
{{/if}}
  let vals = [];
  let missing = collect(qp, vals);
  if (missing != "") {
    return form_page(id, qp, "必填项缺失: " + missing);
  }
  if (id > 0) {
    let args = db.push_all([], vals);
    push(args, id);
    sql_write(db.dsn(), UPDATE_SQL, args);
  } else {
    sql_write(db.dsn(), INSERT_SQL, vals);
  }
  return flash_page("已保存", "ok", "/{{ctrl}}");
};

get "/{{ctrl}}/del/:id", func(req) {
  let id = db.qs_int(req.params, "id", 0);
{{#if refund_on}}
  if (id > 0 && row_locked(get_row(id)) == 1) {
    return flash_page("已支付/已退款订单受对账保护，禁止删除", "err", "/{{ctrl}}");
  }
{{/if}}
  if (id > 0) {
    sql_write(db.dsn(), "DELETE FROM \"" + TBL + "\" WHERE id = ?", [id]);
  }
  return flash_page("已删除", "ok", "/{{ctrl}}");
};

// ---------- JSON API ----------

get "/api/{{ctrl}}", func(req) {
  let qp = db.qparams(req);
  let res = list_rows(db.qs_int(qp, "page", 0), db.qs_int(qp, "pageSize", 20), qp);
  return res; // 裸 map -> JSON
};

get "/api/{{ctrl}}/:id", func(req) {
  let id = db.qs_int(req.params, "id", 0);
  let r = get_row(id);
  if (r == null) { return { "err": "not found" }; }
  return r;
};

post "/api/{{ctrl}}", func(req) {
  if (req.body == null) { return { "err": "empty body" }; }
  let data = json(req.body);
  if (data == null) { return { "err": "invalid json body" }; }
  let vals = [];
  if (collect(data, vals) != "") { return { "err": "missing required field" }; }
  sql_write(db.dsn(), INSERT_SQL, vals);
  return { "ok": true };
};

post "/api/{{ctrl}}/update/:id", func(req) {
  if (req.body == null) { return { "err": "empty body" }; }
  let id = db.qs_int(req.params, "id", 0);
  let data = json(req.body);
  if (data == null) { return { "err": "invalid json body" }; }
{{#if refund_on}}
  if (row_locked(get_row(id)) == 1) {
    return { "ok": false, "err": "order_locked", "msg": "已支付/已退款订单受对账保护，禁止编辑" };
  }
{{/if}}
  let vals = [];
  if (collect(data, vals) != "") { return { "err": "missing required field" }; }
  let args = db.push_all([], vals);
  push(args, id);
  sql_write(db.dsn(), UPDATE_SQL, args);
  return { "ok": true };
};

post "/api/{{ctrl}}/delete/:id", func(req) {
  let id = db.qs_int(req.params, "id", 0);
{{#if refund_on}}
  if (row_locked(get_row(id)) == 1) {
    return { "ok": false, "err": "order_locked", "msg": "已支付/已退款订单受对账保护，禁止删除" };
  }
{{/if}}
  sql_write(db.dsn(), "DELETE FROM \"" + TBL + "\" WHERE id = ?", [id]);
  return { "ok": true };
};
