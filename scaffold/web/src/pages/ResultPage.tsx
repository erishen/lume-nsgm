// src/pages/ResultPage.tsx — 支付结果（路由 #/shop/result/:ono）
import { useEffect, useState } from "react";
import { apiShopResult, money, statusBadge, type ResultData } from "../api";

export default function ResultPage({ ono }: { ono: string }) {
  const [data, setData] = useState<ResultData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    setLoading(true);
    apiShopResult(ono).then((r) => {
      setData(r);
      setLoading(false);
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ono]);

  if (loading) {
    return (
      <div className="panel">
        <h1>支付结果</h1>
        <div className="empty"><div className="ico">⏳</div><p>加载中…</p></div>
      </div>
    );
  }

  if (!data?.ok) {
    return (
      <div className="panel">
        <h1>支付结果</h1>
        <div className="flash err">{data?.msg || data?.err || "订单不存在"}</div>
        <p><a className="btn ghost" href="#/shop">返回商城</a></p>
      </div>
    );
  }

  const sym = data.currency_symbol || "$";
  const b = statusBadge(data.status);

  return (
    <div className="panel">
      <h1>支付结果</h1>
      <div className={"flash " + (data.status === "paid" ? "ok" : data.status === "refunded" ? "ok" : "")}>
        <span className={b.cls}>{b.label}</span>
      </div>
      <p>
        订单号 <code>{data.order_no}</code>
      </p>
      <p>
        金额 <strong>{money(data.amount_cents, sym)}</strong>
      </p>
      <div className="form-actions" style={{ marginTop: 16 }}>
        {data.status === "pending" && (
          <a className="btn primary" href={"#/shop/pay/" + encodeURIComponent(data.order_no)}>
            去支付
          </a>
        )}
        {data.status === "paid" && (
          <a className="btn ghost" href={"#/shop/refund/" + encodeURIComponent(data.order_no)}>
            申请退款
          </a>
        )}
        <a className="btn ghost" href="#/shop">返回商城</a>
      </div>
    </div>
  );
}
