// src/api.ts — lume JSON API 客户端（lume-nsgm 生成）
// 开发/预览环境由 Vite 把 /api 代理到 lume 宿主（见 vite.config.ts），始终同源。

export type Row = Record<string, unknown>;

export interface ListResult {
  total: number;
  items: Row[];
}

function qs(params: Record<string, string | number | undefined>): string {
  const parts: string[] = [];
  for (const k of Object.keys(params)) {
    const v = params[k];
    if (v !== undefined && v !== "") {
      parts.push(encodeURIComponent(k) + "=" + encodeURIComponent(String(v)));
    }
  }
  return parts.length ? parts.join("&") : "";
}

async function handle(res: Response): Promise<Response> {
  if (!res.ok) {
    throw new Error("API error " + res.status);
  }
  return res;
}

export async function apiList(
  ctrl: string,
  params: { q?: string; page?: number; pageSize?: number }
): Promise<ListResult> {
  const res = await handle(
    await fetch(`/api/${ctrl}?${qs(params as Record<string, string | number | undefined>)}`)
  );
  return res.json();
}

export async function apiGet(ctrl: string, id: number): Promise<Row> {
  const res = await handle(await fetch(`/api/${ctrl}/${id}`));
  return res.json();
}

async function postJSON<T = Row>(url: string, data: Row): Promise<T> {
  const res = await handle(
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data)
    })
  );
  return res.json() as T;
}

export function apiAdd(ctrl: string, data: Row): Promise<Row> {
  return postJSON(`/api/${ctrl}`, data);
}

export function apiUpdate(ctrl: string, id: number, data: Row): Promise<Row> {
  return postJSON(`/api/${ctrl}/update/${id}`, data);
}

export function apiDelete(ctrl: string, id: number): Promise<Row> {
  return postJSON(`/api/${ctrl}/delete/${id}`, {});
}

// ---------- 店面 / 收银台 / 支付 / 退款（全量 SPA：统一走 /api 前缀，dev 代理免 CORS） ----------
// 这些接口的错误响应也带 JSON 体（{ ok:false, err, msg }），故不抛异常，
// 直接回传已解析的 body，由调用方按 .ok 判定（与 CRUD 的 handle 抛错不同）。
async function rawJSON<T = Row>(res: Response): Promise<T> {
  try {
    return (await res.json()) as T;
  } catch {
    return { ok: false, err: "bad_json" } as T;
  }
}

export interface ShopItem {
  id: number;
  name: string;
  price_cents: number;
  detail?: string;
  thumb: string;
  stock?: number;
}
export interface ShopProductsResult {
  ok: boolean;
  items: ShopItem[];
  currency_symbol: string;
  seeded: number;
  empty: number;
  flash?: string;
}
export async function apiShopProducts(act?: "clear" | "seed"): Promise<ShopProductsResult> {
  const res = await fetch(`/api/shop/products${act ? "?act=" + act : ""}`);
  return rawJSON<ShopProductsResult>(res);
}

export interface CashierResult {
  ok: boolean;
  order_no: string;
  status: string;
  amount_cents: number;
  currency_symbol: string;
  approve_url?: string;
  msg?: string;
  err?: string;
}
// 收银台：下单（无 ik 时复用该商品最近 pending 单）或按订单号取（支付后回跳/手动进入）
export async function apiShopBuy(productId: number): Promise<CashierResult> {
  return postJSON<CashierResult>(`/api/shop/buy`, { product_id: productId });
}
export async function apiShopCashier(ono: string): Promise<CashierResult> {
  const res = await fetch(`/api/shop/cashier/${encodeURIComponent(ono)}`);
  return rawJSON<CashierResult>(res);
}

export interface ResultData {
  ok: boolean;
  status: string;
  order_no: string;
  amount_cents: number;
  currency_symbol: string;
  manual?: boolean;
  msg?: string;
  err?: string;
}
export async function apiShopResult(ono: string): Promise<ResultData> {
  const res = await fetch(`/api/shop/result/${encodeURIComponent(ono)}`);
  return rawJSON<ResultData>(res);
}

export interface RefundConfirm {
  ok: boolean;
  order_no: string;
  status: string;
  amount_cents: number;
  currency_symbol: string;
  need_recover?: number;
  ppid?: string;
  cap_id?: string;
  msg?: string;
  err?: string;
}
export async function apiShopRefundGet(ono: string): Promise<RefundConfirm> {
  const res = await fetch(`/api/shop/refund/${encodeURIComponent(ono)}`);
  return rawJSON<RefundConfirm>(res);
}
export async function apiShopRefundPost(
  ono: string,
  data: { confirm?: string; ppid?: string; capid?: string; manual?: string }
): Promise<ResultData> {
  return postJSON<ResultData>(`/api/shop/refund/${encodeURIComponent(ono)}`, data);
}

export interface PayReturnResult {
  ok: boolean;
  status?: string;
  order_no?: string;
  amount_cents?: number;
  currency_symbol?: string;
  msg?: string;
  err?: string;
  detail?: string;
}
export async function apiPayReturn(orderNo: string, token: string): Promise<PayReturnResult> {
  const res = await fetch(
    `/api/pay/return?order_no=${encodeURIComponent(orderNo)}&token=${encodeURIComponent(token)}`
  );
  return rawJSON<PayReturnResult>(res);
}
export async function apiPayCancel(
  orderNo: string
): Promise<{ ok: boolean; cancelled: boolean; order_no: string }> {
  const res = await fetch(`/api/pay/cancel?order_no=${encodeURIComponent(orderNo)}`);
  return rawJSON<{ ok: boolean; cancelled: boolean; order_no: string }>(res);
}

// SQLite CURRENT_TIMESTAMP 为 UTC "YYYY-MM-DD HH:MM:SS"，转本地短格式显示
export function fmtTime(v: unknown): string {
  const raw = String(v ?? "");
  const m = raw.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2})/);
  if (!m) {
    return raw;
  }
  const d = new Date(
    Date.UTC(Number(m[1]), Number(m[2]) - 1, Number(m[3]), Number(m[4]), Number(m[5]))
  );
  if (isNaN(d.getTime())) {
    return raw;
  }
  const p2 = (n: number) => (n < 10 ? "0" + n : String(n));
  return (
    d.getFullYear() + "-" + p2(d.getMonth() + 1) + "-" + p2(d.getDate()) +
    " " + p2(d.getHours()) + ":" + p2(d.getMinutes())
  );
}
