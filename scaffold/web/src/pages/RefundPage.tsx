// src/pages/RefundPage.tsx — 退款（路由 #/shop/refund/:ono）
import { useEffect, useState } from "react";
import { apiShopRefundGet, apiShopRefundPost, money, type RefundConfirm, type ResultData } from "../api";

export default function RefundPage({ ono }: { ono: string }) {
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
      setLoading(false);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ono]);

  async function onRefund() {
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
      setErr(r.msg || r.err || "退款失败");
      return;
    }
    setDone(r);
  }

  const sym = info?.currency_symbol || "$";

  if (loading) {
    return (
      <div className="panel">
        <h1>退款</h1>
        <div className="empty"><div className="ico">⏳</div><p>加载中…</p></div>
      </div>
    );
  }

  if (done?.ok) {
    return (
      <div className="panel">
        <h1>退款</h1>
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
        <h1>退款</h1>
        <div className="flash err">{info?.msg || info?.err || "订单不存在"}</div>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  if (info.status === "refunded") {
    return (
      <div className="panel">
        <h1>退款</h1>
        <div className="flash ok">该订单已退款。</div>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  if (info.status !== "paid") {
    return (
      <div className="panel">
        <h1>退款</h1>
        <div className="flash err">仅已支付订单可退款（当前状态：{info.status}）。</div>
        <p><a className="btn ghost" href={"#/shop/result/" + encodeURIComponent(ono)}>查看订单</a></p>
      </div>
    );
  }

  const needRecover = info.need_recover === 1;

  return (
    <div className="panel">
      <h1>申请退款</h1>
      {err && <div className="flash err">{err}</div>}
      <p>
        订单号 <code>{info.order_no}</code>
      </p>
      <p>
        退款金额 <strong>{money(info.amount_cents, sym)}</strong>
      </p>

      {needRecover && (
        <div className="flash err" style={{ marginBottom: 14 }}>
          未找到 PayPal 关联记录，需先补全关联 ID 才能发起退款。
          <br />
          <a className="btn ghost" href={"#/shop/recover/" + encodeURIComponent(ono)} style={{ marginTop: 8 }}>
            去恢复页填入关联 ID
          </a>
        </div>
      )}

      <form className="stack" style={{ marginTop: 8 }} onSubmit={(e) => { e.preventDefault(); onRefund(); }}>
        <label>
          PayPal 订单号（可选）
          <input value={ppid} onChange={(e) => setPpid(e.target.value)} placeholder="缺关联记录时填入" />
        </label>
        <label>
          捕获 ID / 交易号（可选）
          <input value={capid} onChange={(e) => setCapid(e.target.value)} placeholder="PayPal 后台的 Transaction ID" />
        </label>
        <label style={{ display: "flex", gap: 8, alignItems: "center" }}>
          <input
            type="checkbox"
            checked={manual}
            onChange={(e) => setManual(e.target.checked)}
            style={{ width: "auto", marginTop: 0 }}
          />
          <span>已在 PayPal 后台手动退款，仅本地标记（不调 PayPal API）</span>
        </label>
        <span className="muted" style={{ display: "block", fontSize: 12, marginTop: -6 }}>
          也适用于「订单未扣款需关单」的场景：PayPal 侧没有可退款项时，勾选后仅把本地订单置为已退款。
        </span>
        <div className="form-actions">
          <button type="submit" className="btn primary" disabled={busy}>
            {busy ? "处理中…" : manual ? "标记退款" : "确认退款"}
          </button>
          <a className="btn ghost" href={"#/shop/result/" + encodeURIComponent(ono)}>
            取消
          </a>
        </div>
      </form>
    </div>
  );
}
