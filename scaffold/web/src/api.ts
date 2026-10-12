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

async function postJSON(url: string, data: Row): Promise<Row> {
  const res = await handle(
    await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(data)
    })
  );
  return res.json();
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
