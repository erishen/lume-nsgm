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
};

const CTRL = "{{ctrl}}";

const FIELDS: Field[] = [
{{#each fields as f}}  { name: "{{f.name}}", label: "{{f.label}}", form: {{f.form}}, search: {{f.search}}, required: {{f.required}}, list: {{f.list}}, input_type: "{{f.input_type}}", is_ts: {{f.is_ts}} },
{{/each}}
];

const LIST_FIELDS = FIELDS.filter((f) => f.list === 1);
const FORM_FIELDS = FIELDS.filter((f) => f.form === 1);
const HAS_SEARCH = FIELDS.some((f) => f.search === 1);
const PAGE_SIZE = 20;

export default function {{Ctrl}}Page() {
  const [rows, setRows] = useState<Row[]>([]);
  const [total, setTotal] = useState(0);
  const [page, setPage] = useState(0);
  const [q, setQ] = useState("");
  const [editing, setEditing] = useState<Row | null>(null);
  const [msg, setMsg] = useState("");
  const [err, setErr] = useState("");

  async function load(p: number, query: string) {
    try {
      const res = await apiList(CTRL, { q: query, page: p, pageSize: PAGE_SIZE });
      setRows(res.items || []);
      setTotal(res.total || 0);
    } catch (e) {
      setErr(String(e));
    }
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
    setEditing({});
  }

  function openEdit(row: Row, e: MouseEvent) {
    e.preventDefault();
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
      if (editing.id) {
        await apiUpdate(CTRL, Number(editing.id), data);
      } else {
        await apiAdd(CTRL, data);
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
    await apiDelete(CTRL, id);
    flash("已删除");
    load(page, q);
  }

  function gotoPage(p: number, e: MouseEvent) {
    e.preventDefault();
    setPage(p);
  }

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
              <input
                name={f.name}
                type={f.input_type}
                required={f.required === 1}
                value={String(editing[f.name] ?? "")}
                onChange={(e) => setEditing({ ...editing, [f.name]: e.target.value })}
              />
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
                <th key={f.name}>{f.label}</th>
              ))}
              <th className="op">操作</th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 ? (
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
              rows.map((row) => (
                <tr key={String(row.id)}>
                  {LIST_FIELDS.map((f) => (
                    <td key={f.name}>
                      {f.is_ts === 1 ? fmtTime(row[f.name]) : String(row[f.name] ?? "")}
                    </td>
                  ))}
                  <td className="op">
{{#if refund_ono}}
                    {String(row["{{refund_status}}"]) === "paid" ? (
                      <a className="refund" href={"#/shop/refund/" + encodeURIComponent(String(row["{{refund_ono}}"] ?? ""))}>
                        退款
                      </a>
                    ) : null}
{{/if}}
                    <a href={"#/" + CTRL} onClick={(e) => openEdit(row, e)}>
                      编辑
                    </a>
                    <a className="del" href={"#/" + CTRL} onClick={(e) => removeRow(Number(row.id), e)}>
                      删除
                    </a>
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
