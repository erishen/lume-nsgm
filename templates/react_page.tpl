// src/pages/{{Ctrl}}Page.tsx — {{ctrl}} 模块页面（lume-nsgm 生成，勿手改）
import { useEffect, useState, FormEvent, MouseEvent } from "react";
import { apiList, apiAdd, apiUpdate, apiDelete, fmtTime, Row } from "../api";

type Field = {
  name: string;
  label: string;
  form: number;
  search: number;
  required: number;
  list: number;
  input_type: string;
  is_ts: number;
  is_ref: number;
  target: string;
  is_enum: number;
  values_json: string[];
};

const CTRL = "{{ctrl}}";
// 货币符号（店面订单模块由生成器注入；空则 *_cents 列不做金额格式化）
const CSYM = "{{csym}}";

const FIELDS: Field[] = [
{{#each fields as f}}  { name: "{{f.name}}", label: "{{f.label}}", form: {{f.form}}, search: {{f.search}}, required: {{f.required}}, list: {{f.list}}, input_type: "{{f.input_type}}", is_ts: {{f.is_ts}}, is_ref: {{f.is_ref}}, target: "{{f.target}}", is_enum: {{f.is_enum}}, values_json: {{f.values_json}} },
{{/each}}
];

const LIST_FIELDS = FIELDS.filter((f) => f.list === 1);
const FORM_FIELDS = FIELDS.filter((f) => f.form === 1);
const HAS_SEARCH = FIELDS.some((f) => f.search === 1);
const PAGE_SIZE = 20;

function money(v: unknown): string {
  return CSYM + (Number(v || 0) / 100).toFixed(2);
}

function statusBadge(s: string): { cls: string; plain: boolean } {
  if (s === "paid") return { cls: "st st-ok", plain: false };
  if (s === "pending") return { cls: "st st-warn", plain: false };
  if (s === "refunded") return { cls: "st st-mut", plain: false };
  return { cls: "", plain: true };
}

// 列表单元格渲染：status 列出徽标、*_cents 列出等宽金额（与 SSR /order 对齐）
function cellText(f: Field, row: Row): JSX.Element {
  const raw = row[f.name];
  const s = String(raw ?? "");
  if (f.name === "status") {
    const b = statusBadge(s);
    return b.plain ? <>{s}</> : <span className={b.cls}>{s}</span>;
  }
  // P2-3：枚举字段渲染彩色 tag
  if (f.is_enum === 1) {
    return <span className="tag">{s}</span>;
  }
  // P2-2：引用字段优先显示关联名（列表 JOIN 投影的 <field>_name 列），无则回落原始 id
  if (f.is_ref === 1) {
    const refName = row[f.name + "_name"];
    return <>{String(refName ?? raw ?? "")}</>;
  }
  if (CSYM && f.name.endsWith("_cents")) {
    return <>{money(raw)}</>;
  }
  return <>{s}</>;
}

// 客户端排序：可解析为数字的按数值比，其余按字符串 localeCompare
function cmpRows(k: string, a: Row, b: Row): number {
  const av = a[k];
  const bv = b[k];
  const an = Number(av);
  const bn = Number(bv);
  if (!isNaN(an) && !isNaN(bn) && String(av ?? "").trim() !== "" && String(bv ?? "").trim() !== "") {
    return an - bn;
  }
  return String(av ?? "").localeCompare(String(bv ?? ""));
}

export default function {{Ctrl}}Page() {
  const [rows, setRows] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [q, setQ] = useState("");
  const [editing, setEditing] = useState<Row | null>(null);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");
  const [loaded, setLoaded] = useState(false);
  const [sort, setSort] = useState<{ k: string; dir: 1 | -1 } | null>(null);
  // P2-1：引用字段下拉选项（按 target 模块批量拉取；编辑/新增时填充）
  const [refOptions, setRefOptions] = useState<Record<string, { id: number; label: string }[]>>({});
  async function loadRefOptions() {
    const targets = Array.from(new Set(FORM_FIELDS.filter((f) => f.is_ref === 1).map((f) => f.target)));
    for (const t of targets) {
      try {
        const res = await apiList(t, { page: 0, pageSize: 200 });
        setRefOptions((prev) => ({
          ...prev,
          [t]: (res.items || []).map((r: Row) => ({ id: Number(r.id), label: String(r.name ?? r.id) })),
        }));
      } catch {
        /* 关联模块不可达时下拉留空，不影响其它字段 */
      }
    }
  }

  async function load(p: number, query: string) {
    try {
      const res = await apiList(CTRL, { q: query, page: p, pageSize: PAGE_SIZE });
      setRows(res.items || []);
      setTotal(res.total || 0);
    } catch (e) {
      setErr(String(e));
    }
    setLoaded(true);
  }

  useEffect(() => {
    load(page, q);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [page]);

  function flash(text: string) {
    setMsg(text);
    window.setTimeout(() => setMsg(""), 2000);
  }

  function onSearch(e: FormEvent) {
    e.preventDefault();
    setPage(0);
    load(0, q);
  }

  function openNew() {
    loadRefOptions();
    setEditing({});
  }

  function openEdit(row: Row, e: MouseEvent) {
    e.preventDefault();
    loadRefOptions();
    setEditing({ ...row });
  }

  async function saveRow(e: FormEvent) {
    e.preventDefault();
    if (!editing) {
      return;
    }
    const data: Row = {};
    for (const f of FORM_FIELDS) {
      data[f.name] = String(editing[f.name] ?? "");
    }
    try {
      const res: Row = editing.id
        ? await apiUpdate(CTRL, Number(editing.id), data)
        : await apiAdd(CTRL, data);
      // 服务端守卫拒绝（如订单对账保护）返回 { ok:false, err, msg }（HTTP 恒 200）
      if (res.ok === false) {
        setErr(String(res.msg ?? res.err ?? "保存失败"));
        return;
      }
      flash("已保存");
      setEditing(null);
      load(page, q);
    } catch (e2) {
      setErr(String(e2));
    }
  }

  async function removeRow(id: number, e: MouseEvent) {
    e.preventDefault();
    if (!window.confirm("确认删除该记录？此操作不可恢复。")) {
      return;
    }
    try {
      const res = await apiDelete(CTRL, id);
      if (res.ok === false) {
        setErr(String(res.msg ?? res.err ?? "删除失败"));
        return;
      }
      flash("已删除");
      load(page, q);
    } catch (e2) {
      setErr(String(e2));
    }
  }

  function gotoPage(p: number, e: MouseEvent) {
    e.preventDefault();
    setPage(p);
  }

  function toggleSort(k: string) {
    setSort((prev) => (prev && prev.k === k ? (prev.dir === 1 ? { k, dir: -1 } : null) : { k, dir: 1 }));
  }

  const viewRows = sort ? [...rows].sort((a, b) => cmpRows(sort.k, a, b) * sort.dir) : rows;

  return (
    <div>
      <h1>
        {{Ctrl}} <span className="muted">({total})</span>
      </h1>
      {msg ? <div className="flash ok">{msg}</div> : null}
      {err ? <div className="flash err">{err}</div> : null}

      <form className="toolbar" onSubmit={onSearch}>
        {HAS_SEARCH ? (
          <input name="q" value={q} onChange={(e) => setQ(e.target.value)} placeholder="搜索" />
        ) : null}
        {HAS_SEARCH ? <button type="submit" className="ghost">搜索</button> : null}
        {q ? (
          <a
            className="clear"
            href={"#/" + CTRL}
            onClick={(e) => {
              e.preventDefault();
              setQ("");
              setPage(0);
              load(0, "");
            }}
          >
            清除
          </a>
        ) : null}
        <button type="button" className="primary push" onClick={openNew}>
          + 新增
        </button>
      </form>

      {editing ? (
        <form className="stack" onSubmit={saveRow}>
          <h2>{editing.id ? "编辑" : "新增"} {{ctrl}}</h2>
          {FORM_FIELDS.map((f) => (
            <label key={f.name}>
              {f.label}
              {f.required === 1 ? <span className="req"> *</span> : null}
              {f.is_ref === 1 ? (
                <select
                  name={f.name}
                  required={f.required === 1}
                  value={String(editing[f.name] ?? "")}
                  onChange={(e) => setEditing({ ...editing, [f.name]: e.target.value })}
                >
                  {(refOptions[f.target] || []).map((o) => (
                    <option key={o.id} value={o.id}>
                      {o.label}
                    </option>
                  ))}
                </select>
              ) : f.is_enum === 1 ? (
                <select
                  name={f.name}
                  required={f.required === 1}
                  value={String(editing[f.name] ?? "")}
                  onChange={(e) => setEditing({ ...editing, [f.name]: e.target.value })}
                >
                  {(f.values_json as string[]).map((v) => (
                    <option key={v} value={v}>
                      {v}
                    </option>
                  ))}
                </select>
              ) : (
                <input
                  name={f.name}
                  type={f.input_type}
                  required={f.required === 1}
                  value={String(editing[f.name] ?? "")}
                  onChange={(e) => setEditing({ ...editing, [f.name]: e.target.value })}
                />
              )}
            </label>
          ))}
          <div className="form-actions">
            <button type="submit">保存</button>
            <button type="button" className="ghost" onClick={() => setEditing(null)}>
              取消
            </button>
          </div>
        </form>
      ) : null}

      <div className="table-wrap">
        <table className="grid">
          <thead>
            <tr>
              {LIST_FIELDS.map((f) => (
                <th
                  key={f.name}
                  className="sortable"
                  data-sort={sort && sort.k === f.name ? (sort.dir === 1 ? "asc" : "desc") : undefined}
                  onClick={() => toggleSort(f.name)}
                >
                  {f.label}
                </th>
              ))}
              <th className="op">操作</th>
            </tr>
          </thead>
          <tbody>
            {!loaded ? (
              <tr>
                <td colSpan={LIST_FIELDS.length + 1}>
                  <div className="empty">
                    <div className="ico">⏳</div>
                    <p>加载中…</p>
                  </div>
                </td>
              </tr>
            ) : viewRows.length === 0 ? (
              <tr>
                <td colSpan={LIST_FIELDS.length + 1}>
                  <div className="empty">
                    <div className="ico">{q ? "🔍" : "📭"}</div>
                    <p>{q ? "无匹配结果" : "暂无数据"}</p>
                    {q ? (
                      <button
                        type="button"
                        className="primary"
                        onClick={() => {
                          setQ("");
                          setPage(0);
                          load(0, "");
                        }}
                      >
                        清除搜索
                      </button>
                    ) : (
                      <button type="button" className="primary" onClick={openNew}>
                        新增第一条
                      </button>
                    )}
                  </div>
                </td>
              </tr>
            ) : (
              viewRows.map((row) => (
                <tr key={String(row.id)}>
                  {LIST_FIELDS.map((f) => (
                    <td key={f.name} className={CSYM && f.name.endsWith("_cents") ? "money" : ""}>
                      {f.is_ts === 1 ? fmtTime(row[f.name]) : cellText(f, row)}
                    </td>
                  ))}
                  <td className="op">
{{#if refund_ono}}
                    {/* 对账锁定：paid 只留退款入口、refunded 无后台操作（与服务端 row_locked 守卫一致） */}
                    {String(row["{{refund_status}}"] ?? "") === "paid" ? (
                      <a className="refund" href={"#/shop/refund/" + encodeURIComponent(String(row["{{refund_ono}}"] ?? ""))}>
                        退款
                      </a>
                    ) : String(row["{{refund_status}}"] ?? "") === "refunded" ? null : (
                      <>
                        <a href={"#/" + CTRL} onClick={(e) => openEdit(row, e)}>
                          编辑
                        </a>
                        <a className="del" href={"#/" + CTRL} onClick={(e) => removeRow(Number(row.id), e)}>
                          删除
                        </a>
                      </>
                    )}
{{else}}
                    <a href={"#/" + CTRL} onClick={(e) => openEdit(row, e)}>
                      编辑
                    </a>
                    <a className="del" href={"#/" + CTRL} onClick={(e) => removeRow(Number(row.id), e)}>
                      删除
                    </a>
{{/if}}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>
      </div>

      <div className="pager">
        <span className="info">
          共 {total} 条 · 第 {page + 1} / {Math.max(1, Math.ceil(total / PAGE_SIZE))} 页
        </span>
        {page > 0 ? (
          <a href={"#/" + CTRL} onClick={(e) => gotoPage(page - 1, e)}>
            ‹ 上一页
          </a>
        ) : (
          <span className="pg disabled">‹ 上一页</span>
        )}
        {(page + 1) * PAGE_SIZE < total ? (
          <a href={"#/" + CTRL} onClick={(e) => gotoPage(page + 1, e)}>
            下一页 ›
          </a>
        ) : (
          <span className="pg disabled">下一页 ›</span>
        )}
      </div>
    </div>
  );
}
