// src/pages/RecoverPage.tsx — 恢复关联 ID 并退款（路由 #/shop/recover/:ono）
// 早期订单缺 paypal_order_id/capture_id 时，凭用户提供的关联 ID 反查或直接标记退款。
import { useEffect, useState } from "react";
import { apiShopRefundGet, apiShopRefundPost, money, type RefundConfirm, type ResultData } from "../api";

export default function RecoverPage({ ono }: { ono: string }) {
  const [info, setInfo] = useState<RefundConfirm | null>(null);
  const [loading, setLoading] = useState(true);
  const [ppid, setPpid] = useState("");
  const [capid, setCapid] = useState("");
  const [manual, setManual] = useState(false);
  const [busy, setBusy] = useState(false);
  const [done, setDone] = useState<ResultData | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    setLoading(true);
    apiShopRefundGet(ono).then((r) => {
      setInfo(r);
      setPpid(r.ppid || "");
      setCapid(r.cap_id || "");
      setLoading(false);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ono]);

  async function onSubmit() {
    if (!ppid && !capid && !manual) {
      setErr("请至少填入一个关联 ID，或勾选「仅本地标记退款」。");
      return;
    }
    setBusy(true);
    setErr("");
    const r = await apiShopRefundPost(ono, {
      confirm: "1",
      ppid: ppid || undefined,
      capid: capid || undefined,
      manual: manual ? "1" : undefined
    });
    setBusy(false);
    if (!r.ok) {
      setErr(r.msg || r.err || "恢复失败");
      return;
    }
    setDone(r);
  }

  const sym = info?.currency_symbol || "$";

  if (loading) {
    return (
      <div className="panel">
        <h1>恢复关联 ID</h1>
        <div className="empty"><div className="ico">⏳</div><p>加载中…</p></div>
      </div>
    );
  }

  if (done?.ok) {
    return (
      <div className="panel">
        <h1>恢复关联 ID</h1>
        <div className="flash ok">退款成功。{done.manual ? "（仅本地标记）" : ""}</div>
        <p>
          订单号 <code>{done.order_no}</code> · 金额 <strong>{money(done.amount_cents, sym)}</strong>
        </p>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  if (!info?.ok) {
    return (
      <div className="panel">
        <h1>恢复关联 ID</h1>
        <div className="flash err">{info?.msg || info?.err || "订单不存在"}</div>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  return (
    <div className="panel">
      <h1>恢复关联 ID</h1>
      {err && <div className="flash err">{err}</div>}
      <p>
        订单号 <code>{info.order_no}</code> · 金额 <strong>{money(info.amount_cents, sym)}</strong>
      </p>
      <p className="muted" style={{ fontSize: 13 }}>
        早期订单缺失 PayPal 关联记录时，可在 PayPal 后台「交易」页找到订单号或交易号（Transaction ID = 捕获 ID）填入。
        系统会用捕获 ID 直接退款；若填入的是订单号，会自动反查捕获记录。
      </p>
      <form className="stack" style={{ marginTop: 8 }} onSubmit={(e) => { e.preventDefault(); onSubmit(); }}>
        <label>
          PayPal 订单号（可选）
          <input value={ppid} onChange={(e) => setPpid(e.target.value)} placeholder="如 5XX...R" />
        </label>
        <label>
          捕获 ID / 交易号（可选）
          <input value={capid} onChange={(e) => setCapid(e.target.value)} placeholder="PayPal 后台 Transaction ID" />
        </label>
        <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <input
            type="checkbox"
            checked={manual}
            onChange={(e) => setManual(e.target.checked)}
            style={{ width: "auto", marginTop: 0 }}
          />
          已在 PayPal 后台手动退款，仅本地标记（不调 PayPal API）
        </label>
        <div className="form-actions">
          <button type="submit" className="btn primary" disabled={busy}>
            {busy ? "处理中…" : "恢复并退款"}
          </button>
          <a className="btn ghost" href={"#/shop/refund/" + encodeURIComponent(ono)}>
            返回退款页
          </a>
        </div>
      </form>
    </div>
  );
}
