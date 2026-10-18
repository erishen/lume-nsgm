// src/pages/ShopPage.tsx — 商城商品列表（lume-nsgm 生成：静态页面，路由 #/shop）
import { useEffect, useState } from "react";
import { apiShopProducts, apiShopBuy, type ShopItem, type ShopProductsResult } from "../api";

function money(cents: number, sym: string): string {
  return sym + (cents / 100).toFixed(2);
}

export default function ShopPage() {
  const [data, setData] = useState<ShopProductsResult | null>(null);
  const [loading, setLoading] = useState(true);
  const [buying, setBuying] = useState<number | null>(null);
  const [err, setErr] = useState("");

  async function load() {
    setLoading(true);
    setErr("");
    const r = await apiShopProducts();
    setData(r);
    setLoading(false);
  }

  useEffect(() => {
    load();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function onBuy(it: ShopItem) {
    setBuying(it.id);
    setErr("");
    const r = await apiShopBuy(it.id);
    setBuying(null);
    if (!r.ok || !r.order_no) {
      setErr(r.msg || r.err || "下单失败");
      return;
    }
    window.location.hash = "#/shop/pay/" + encodeURIComponent(r.order_no);
  }

  async function onSeed() {
    setErr("");
    const r = await apiShopProducts("seed");
    setData(r);
  }
  async function onClear() {
    if (!window.confirm("确定清空全部商品目录？（订单记录不受影响）")) return;
    setErr("");
    const r = await apiShopProducts("clear");
    setData(r);
  }

  const sym = data?.currency_symbol || "$";

  return (
    <div>
      <h1>
        商城 <span className="badge">PayPal</span>
      </h1>

      <form className="toolbar">
        <button type="button" className="ghost" onClick={onSeed}>
          重新载入示例
        </button>
        <a className="clear" href="#" onClick={(e) => { e.preventDefault(); onClear(); }}>
          清空目录
        </a>
      </form>

      {data?.flash && <div className="flash ok">{data.flash}</div>}
      {err && <div className="flash err">{err}</div>}

      {loading ? (
        <div className="empty"><div className="ico">⏳</div><p>加载中…</p></div>
      ) : data && data.items.length === 0 ? (
        <div className="empty">
          <div className="ico">🛒</div>
          <p>商品目录为空。</p>
          <a className="btn primary" href="#" onClick={(e) => { e.preventDefault(); onSeed(); }}>
            载入示例商品
          </a>
        </div>
      ) : (
        <div className="shop-grid">
          {(data?.items || []).map((it) => {
            const soldOut = it.stock !== undefined && it.stock <= 0;
            return (
              <div className="card" key={it.id}>
                <div className="thumb">{it.thumb}</div>
                <h3>{it.name}</h3>
                <p className="price">{money(it.price_cents, sym)}</p>
                {it.stock !== undefined && (
                  <span className={"st " + (soldOut ? "st-mut" : "st-info")}>
                    {soldOut ? "已售罄" : "库存 " + it.stock}
                  </span>
                )}
                <button
                  className={"btn primary" + (soldOut ? " disabled" : "")}
                  disabled={soldOut || buying === it.id}
                  onClick={() => onBuy(it)}
                >
                  {buying === it.id ? "下单中…" : soldOut ? "已售罄" : "购买"}
                </button>
              </div>
            );
          })}
        </div>
      )}
    </div>
  );
}
