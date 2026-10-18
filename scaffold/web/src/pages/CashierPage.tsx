// src/pages/CashierPage.tsx — 收银台（路由 #/shop/pay/:ono）
import { useEffect, useState } from "react";
import { apiShopCashier, money, type CashierResult } from "../api";

export default function CashierPage({ ono }: { ono: string }) {
  const [data, setData] = useState<CashierResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [err, setErr] = useState("");

  useEffect(() => {
    setLoading(true);
    setErr("");
    apiShopCashier(ono).then((r) => {
      setData(r);
      setLoading(false);
      if (!r.ok) setErr(r.msg || r.err || "加载收银台失败");
    });
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [ono]);

  if (loading) {
    return (
      <div className="panel">
        <h1>收银台</h1>
        <div className="empty"><div className="ico">⏳</div><p>加载中…</p></div>
      </div>
    );
  }

  const sym = data?.currency_symbol || "$";

  // 已支付：直接引导到结果页
  if (data?.ok && data.status === "paid") {
    return (
      <div className="panel">
        <h1>收银台</h1>
        <div className="flash ok">该订单已支付。</div>
        <p>
          订单号 <code>{data.order_no}</code> · 金额 <strong>{money(data.amount_cents, sym)}</strong>
        </p>
        <a className="btn primary" href={"#/shop/result/" + encodeURIComponent(data.order_no)}>
          查看支付结果
        </a>
      </div>
    );
  }

  return (
    <div className="panel">
      <h1>收银台</h1>
      {err && <div className="flash err">{err}</div>}
      <p>
        订单号 <code>{data?.order_no}</code>
      </p>
      <p>
        应付金额 <strong style={{ fontSize: 22 }}>{money(data?.amount_cents || 0, sym)}</strong>
      </p>
      {data?.ok && data.approve_url ? (
        <a className="btn primary" href={data.approve_url}>
          前往 PayPal 支付
        </a>
      ) : (
        <div className="flash err">暂无法生成 PayPal 支付链接，请稍后重试。</div>
      )}
      <p style={{ marginTop: 16 }}>
        <a className="btn ghost" href={"#/shop/result/" + encodeURIComponent(ono)}>
          查看支付状态
        </a>
      </p>
    </div>
  );
}
