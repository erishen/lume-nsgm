// src/pages/PayReturnPage.tsx — PayPal 回跳处理（路由 #/pay/return 与 #/pay/cancel）
// 后端把 PayPal 的 302 改成指向 /spa/#/pay/return?order_no=&token=&PayerID= 的 hash 路由，
// 本页解析 hash 查询参数后直接调 /api/pay/return 做捕获（与后端无关 fallback）。
import { useEffect, useState } from "react";
import { apiPayReturn, apiPayCancel, money, type PayReturnResult } from "../api";

function hashQuery(): Record<string, string> {
  const h = window.location.hash || "";
  const qi = h.indexOf("?");
  if (qi < 0) return {};
  const sp = new URLSearchParams(h.slice(qi + 1));
  const out: Record<string, string> = {};
  sp.forEach((v, k) => { out[k] = v; });
  return out;
}

export default function PayReturnPage({ mode }: { mode: "return" | "cancel" }) {
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<PayReturnResult | null>(null);
  const [err, setErr] = useState("");

  useEffect(() => {
    const q = hashQuery();
    const orderNo = q["order_no"] || "";

    async function run() {
      if (mode === "cancel") {
        await apiPayCancel(orderNo);
        setLoading(false);
        return;
      }
      if (!orderNo || !q["token"]) {
        setErr("缺少订单号或 token 参数，无法完成支付。");
        setLoading(false);
        return;
      }
      const r = await apiPayReturn(orderNo, q["token"]);
      if (!r.ok) {
        setErr(r.msg || r.detail || r.err || "支付确认失败");
      }
      setData(r);
      setLoading(false);
    }

    run();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [mode]);

  if (loading) {
    return (
      <div className="panel">
        <h1>{mode === "cancel" ? "已取消支付" : "正在确认支付…"}</h1>
        <div className="empty"><div className="ico">⏳</div><p>处理中…</p></div>
      </div>
    );
  }

  if (mode === "cancel") {
    return (
      <div className="panel">
        <h1>已取消支付</h1>
        <div className="flash ok">你已取消本次 PayPal 支付，订单仍未支付。</div>
        <p><a className="btn primary" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  if (err) {
    return (
      <div className="panel">
        <h1>支付确认</h1>
        <div className="flash err">{err}</div>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  const sym = data?.currency_symbol || "$";
  return (
    <div className="panel">
      <h1>支付成功</h1>
      <div className="flash ok">支付已确认。</div>
      <p>
        订单号 <code>{data?.order_no}</code>
      </p>
      <p>
        金额 <strong>{money(data?.amount_cents || 0, sym)}</strong>
      </p>
      <p>
        <a className="btn primary" href={"#/shop/result/" + encodeURIComponent(data?.order_no || "")}>
          查看订单
        </a>
      </p>
    </div>
  );
}
