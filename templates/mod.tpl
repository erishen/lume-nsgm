// modules/{{ctrl}}.lume — {{ctrl}} 模块（lume-nsgm 生成，勿手改）
import "../lib/ui.lume" as ui;
import "../lib/db.lume" as db;

export let DDL = "{{ddl}}";

let TBL = "{{ctrl}}";
// 数据驱动字段表：form=入表单 search=可搜索 required=必填 list=列表列
let FIELDS = [
{{#each fields as f}}  { "name": "{{f.name}}", "label": "{{f.label}}", "form": {{f.form}}, "search": {{f.search}}, "required": {{f.required}}, "list": {{f.list}}, "type": "{{f.type}}" },
{{/each}}
];

// 生成期拼好的列固定 SQL（值一律 ? 绑定，由 handler 追加）
let INSERT_SQL = "{{insert_sql}}";
let UPDATE_SQL = "{{update_sql}}"; // ... WHERE id = ?（id 由 handler 追加）

// 搜索条件（数据驱动：对所有 search 字段做 OR LIKE）
func where_for(qp) {
  let q = str(get(qp, "q", ""));
  if (q == "") { return { "where": "", "params": [] }; }
  let conds = "";
  let params = [];
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "search", 0) == 1) {
      if (conds != "") { conds = conds + " OR "; }
      conds = conds + "\"" + get(f, "name", "") + "\" LIKE ?";
      push(params, "%" + q + "%");
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
  let rows = sql_query(db.dsn(), "SELECT * FROM \"" + TBL + "\"" + where + " ORDER BY id DESC LIMIT ? OFFSET ?", args);
  let cnt = sql_query(db.dsn(), "SELECT COUNT(*) AS counts FROM \"" + TBL + "\"" + where, get(w, "params", []));
  return { "total": db.count_of(cnt), "items": rows };
}

func get_row(id: int) {
  let rows = sql_query(db.dsn(), "SELECT * FROM \"" + TBL + "\" WHERE id = ?", [id]);
  if (len(rows) == 0) { return null; }
  return rows[0];
}

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

  body = body + "<div class=\"table-wrap\"><table class=\"grid\"><thead><tr>";
  let ncols = 1;
  let i = 0;
  while (i < len(FIELDS)) {
    let f = FIELDS[i];
    if (get(f, "list", 0) == 1) { body = body + "<th>" + ui.esc(get(f, "label", "")) + "</th>"; ncols = ncols + 1; }
    i = i + 1;
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
    while (j < len(FIELDS)) {
      let f = FIELDS[j];
      if (get(f, "list", 0) == 1) {
        let v = str(get(r, get(f, "name", ""), ""));
        // 时间列暴露原始值（data-ts），由 app.js 转本地友好格式
        let ts_attr = "";
        let ft = get(f, "type", "");
        if (ft == "timestamp" || ft == "date") { ts_attr = " data-ts=\"" + ui.esc(v) + "\""; }
        body = body + "<td" + ts_attr + ">" + ui.esc(v) + "</td>";
      }
      j = j + 1;
    }
    let rid = str(get(r, "id", 0));
    body = body + "<td class=\"op\"><a href=\"/{{ctrl}}/edit/" + rid + "\">编辑</a> "
      + "<a class=\"del\" href=\"/{{ctrl}}/del/" + rid + "\">删除</a></td></tr>\n";
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
  let body = "";
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
      body = body + "  <label>" + ui.esc(get(f, "label", ""))
        + (req ? "<span class=\"req\"> *</span>" : "") + "\n"
        + "    <input name=\"" + get(f, "name", "") + "\" value=\""
        + ui.esc(str(get(vals, get(f, "name", ""), ""))) + "\""
        + (req ? " required" : "") + ">\n  </label>\n";
    }
    i = i + 1;
  }
  body = body + "  <div class=\"form-actions\"><button>保存</button>"
    + "<a class=\"btn ghost\" href=\"/{{ctrl}}\">返回</a></div>\n</form>\n";
  return ui.page("{{ctrl}}", "{{ctrl}}", body);
}

func flash_page(msg: string, kind: string, back_path: string): string {
  let body = "<div class=\"flash " + kind + "\">" + ui.esc(msg) + "</div>\n"
    + "<p><a href=\"" + back_path + "\">返回列表</a></p>\n"
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
  if (r == null) { return { "status": 404, "body": { "err": "not found" } }; }
  return r;
};

post "/api/{{ctrl}}", func(req) {
  if (req.body == null) { return { "status": 400, "body": { "err": "empty body" } }; }
  let data = json(req.body);
  if (data == null) { return { "status": 400, "body": { "err": "invalid json body" } }; }
  let vals = [];
  if (collect(data, vals) != "") { return { "status": 400, "body": { "err": "missing required field" } }; }
  sql_write(db.dsn(), INSERT_SQL, vals);
  return { "status": 200, "body": { "ok": true } };
};

post "/api/{{ctrl}}/update/:id", func(req) {
  if (req.body == null) { return { "status": 400, "body": { "err": "empty body" } }; }
  let id = db.qs_int(req.params, "id", 0);
  let data = json(req.body);
  if (data == null) { return { "status": 400, "body": { "err": "invalid json body" } }; }
  let vals = [];
  if (collect(data, vals) != "") { return { "status": 400, "body": { "err": "missing required field" } }; }
  let args = db.push_all([], vals);
  push(args, id);
  sql_write(db.dsn(), UPDATE_SQL, args);
  return { "status": 200, "body": { "ok": true } };
};

post "/api/{{ctrl}}/delete/:id", func(req) {
  let id = db.qs_int(req.params, "id", 0);
  sql_write(db.dsn(), "DELETE FROM \"" + TBL + "\" WHERE id = ?", [id]);
  return { "status": 200, "body": { "ok": true } };
};
