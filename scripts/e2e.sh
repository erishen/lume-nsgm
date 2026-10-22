#!/usr/bin/env bash
#
# 端到端探针：重新生成 gen/，起 lume-core 服务，curl 跑 SSR / 静态 / CRUD / 搜索 / 分页 /
# 迁移 / 支付全链路，把此前手工验证的行为固化成回归套件。不依赖 pnpm/前端构建（只测 lume 后端）。
#
# 用法：
#   ./scripts/e2e.sh                 # 用 PATH 上的 lume-core
#   LUME=/path/to/lume-core ./scripts/e2e.sh
#   E2E_PORT=18099 E2E_DB=/tmp/x.db ./scripts/e2e.sh
#
# 支付阶段需要 python3（mock 网关 scripts/mock_pay_gateway.py）；缺失则 SKIP。

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

LUME="${LUME:-lume-core}"
PORT="${E2E_PORT:-18099}"
HOST="127.0.0.1"
DB="${E2E_DB:-/tmp/nsgm-e2e.db}"
MIG_DB="${E2E_MIG_DB:-/tmp/nsgm-e2e-mig.db}"
PAYPAL_DB="${E2E_PAYPAL_DB:-/tmp/nsgm-e2e-paypal.db}"
B="http://$HOST:$PORT"
PID=""
PP_MOCK_PID=""

cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ -n "$PP_MOCK_PID" ] && kill "$PP_MOCK_PID" 2>/dev/null || true
  wait "$PID" "$PP_MOCK_PID" 2>/dev/null || true
  rm -f "$DB" "$MIG_DB" "$PAYPAL_DB"
}
trap cleanup EXIT

command -v curl >/dev/null 2>&1 || { echo "E2E FAIL: 需要 curl"; exit 1; }

echo "==> 重新生成 gen/ ..."
"$LUME" main.lume example-config.json >/dev/null 2>&1 || { echo "E2E FAIL: 生成失败"; exit 1; }

rm -f "$DB"
echo "==> 启动 lume-core (PORT=$PORT HOST=$HOST) ..."
# docroot ./www 相对 CWD 解析：必须 cd gen 再起（与 make dev/serve、Docker 的
# WORKDIR /app 同口径），否则静态文件全 404
( cd gen && PORT="$PORT" HOST="$HOST" WORKERS=1 NSGM_DB="$DB" exec "$LUME" app.lume ) >/tmp/nsgm-e2e.log 2>&1 &
PID=$!

# 等待端口就绪（最多 15s）
for _ in $(seq 1 30); do
  curl -s --noproxy '*' -o /dev/null "$B/api/user" 2>/dev/null && break
  sleep 0.5
done
curl -s --noproxy '*' -o /dev/null "$B/api/user" 2>/dev/null || { echo "E2E FAIL: server 在 $PORT 未就绪"; tail -5 /tmp/nsgm-e2e.log; exit 1; }

code() { curl -s --noproxy '*' -o /dev/null -w "%{http_code}" "$@"; }
total_of() { curl -s --noproxy '*' "$1" | grep -o '"total":[0-9]*' | head -1 | grep -o '[0-9]*'; }
items_of() { curl -s --noproxy '*' "$1" | grep -o '"id":' | wc -l | tr -d ' '; }

fail() { echo "E2E FAIL: $1"; exit 1; }

[ "$(code "$B/")" = "200" ]           || fail "GET / 非 200"
[ "$(code "$B/app.css")" = "200" ]    || fail "GET /app.css 非 200"
[ "$(code "$B/api/user")" = "200" ]   || fail "GET /api/user 非 200"

# ---- SPA 壳探针（条件执行）：gen/www/spa 存在才验——Docker 构建期会把
# web/dist 拷到 www/spa；纯 e2e 环境不构建 SPA，跳过不判失败 ----
if [ -f "gen/www/spa/index.html" ]; then
  [ "$(code "$B/spa/")" = "200" ] || fail "GET /spa/ 非 200"
  curl -s --noproxy '*' "$B/spa/" | grep -q 'id="root"' || fail "SPA 壳缺 root 挂载点"
  SPA_JS="$(curl -s --noproxy '*' "$B/spa/" | grep -o 'assets/index-[^"]*\.js' | head -1)"
  [ -n "$SPA_JS" ] || fail "SPA 壳未引用 index js"
  [ "$(code "$B/spa/$SPA_JS")" = "200" ] || fail "SPA 主 chunk 非 200 ($SPA_JS)"
  echo "ok   SPA 壳：/spa/ 200 + root 挂载点 + 主 chunk 200"
else
  echo "skip SPA 壳探针（gen/www/spa 未构建；Docker 镜像内构建后自动生效）"
fi

# 创建
[ "$(code -X POST "$B/api/user" -H 'Content-Type: application/json' -d '{"name":"Alice","email":"alice@example.com"}')" = "200" ] \
  || fail "POST /api/user 非 200"
# 列表应含 1 条
[ "$(total_of "$B/api/user")" = "1" ] || fail "创建后 total 应为 1"
# 搜索命中
[ "$(total_of "$B/api/user?q=Ali")" = "1" ] || fail "搜索 Ali 应命中 1"
# 搜索不命中
[ "$(total_of "$B/api/user?q=zzz")" = "0" ] || fail "搜索 zzz 应为 0"
# 搜索通配符转义：输入 % 不应命中全部
[ "$(total_of "$B/api/user?q=%25")" = "0" ] || fail "搜索 % 应被转义、命中 0"
# 分页：page 越界返回空 items（total 是匹配总行数，与页无关）
[ "$(items_of "$B/api/user?page=99")" = "0" ] || fail "page=99 应返回 0 条 items"
# qs_int 兜底：page 非数字应回落默认值而非报错
[ "$(code "$B/api/user?page=abc")" = "200" ] || fail "page=abc 应回落默认值(200)"
[ "$(items_of "$B/api/user?page=abc")" = "1" ] || fail "page=abc 应回落到第 0 页(1 条)"

# ---- 迁移阶段：旧库（缺列）启动后自动补齐，旧行不丢 ----
# 场景：schema 加了字段后重新生成，旧 data/app.db 的表没有新列 —— db.init 的
# migrate_cols 应 ALTER TABLE ADD COLUMN 补齐（lume-core 0.7.0+ 放行该严格形状）。
echo "==> 迁移阶段：预置旧 schema 库 ..."
kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
if command -v python3 >/dev/null 2>&1; then
  rm -f "$MIG_DB"
  python3 - "$MIG_DB" <<'PY' || { echo "E2E FAIL: 预置旧库失败"; exit 1; }
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
# 旧版生成器产出的 user 表：只有 id + name（缺 email / create_date 两列）
con.execute('CREATE TABLE "user" ("id" INTEGER PRIMARY KEY AUTOINCREMENT, "name" TEXT NOT NULL)')
con.execute('INSERT INTO "user" ("name") VALUES (?)', ("Legacy Guy",))
con.commit(); con.close()
PY
  ( cd gen && PORT="$PORT" HOST="$HOST" WORKERS=1 NSGM_DB="$MIG_DB" exec "$LUME" app.lume ) >/tmp/nsgm-e2e-mig.log 2>&1 &
  PID=$!
  for _ in $(seq 1 30); do
    curl -s --noproxy '*' -o /dev/null "$B/api/user" 2>/dev/null && break
    sleep 0.5
  done
  curl -s --noproxy '*' -o /dev/null "$B/api/user" 2>/dev/null \
    || { echo "E2E FAIL: 迁移库启动未就绪"; tail -5 /tmp/nsgm-e2e-mig.log; exit 1; }
  [ "$(total_of "$B/api/user")" = "1" ] || fail "迁移后旧行应保留 (total=1)"
  curl -s --noproxy '*' "$B/api/user" | grep -q '"name":"Legacy Guy"' || fail "迁移后旧行 name 应可读"
  curl -s --noproxy '*' "$B/api/user" | grep -q '"email":null' || fail "迁移应补齐 email 列（旧行为 NULL）"
  [ "$(code -X POST "$B/api/user" -H 'Content-Type: application/json' -d '{"name":"New Guy","email":"new@example.com"}')" = "200" ] \
    || fail "迁移后 POST 应成功"
  [ "$(total_of "$B/api/user")" = "2" ] || fail "迁移后新增一行 total 应为 2"
  [ "$(code "$B/user")" = "200" ] || fail "迁移后 SSR /user 应 200（旧行新列 NULL 可渲染）"
  # NULL 归一（str(null)="null" 陷阱）：旧行新列是 SQL NULL，SSR 列表不能把
  # 字面量 "null" 渲染进单元格（mod.tpl 列表列/表单预填均已归一）
  curl -s --noproxy '*' "$B/user" | grep -q '>null<' \
    && fail "迁移旧行的 NULL 列不应渲染成 null 单元格" || true
  echo "ok   迁移：旧库自动补列，旧行保留，新写正常，SSR 可渲染"
else
  echo "SKIP 迁移阶段: 无 python3"
fi

# ---- 支付阶段（PayPal）：建单 -> OAuth2 建单 -> approve_url -> return 捕获 -> 状态落库 -> 幂等 -> webhook ----
# 场景：example-paypal.json 生成带 pay 接线的工程，独立端口起 PayPal mock 网关。
# OAuth2 的 Basic 凭证用 Python 侧独立 base64 实现交叉验证；approve_url 指向 mock
# 收银台。全量 SPA 后回跳走 /spa/#/pay/return hash 路由、由前端调 /api/pay/return
# 捕获 —— e2e 从 approve_url 提取 token 后直接调 /api/pay/return（与 SPA 行为一致；
# curl -L 跟 302 只会拿到 SPA 壳，不会触发捕获）。
if command -v python3 >/dev/null 2>&1; then
  echo "==> 支付阶段(PayPal)：生成 example-paypal.json 工程 ..."
  kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
  PP_APP_PORT="${E2E_PP_PORT:-18096}"
  PP_MOCK_PORT="${E2E_PP_MOCK_PORT:-18098}"   # 独立端口起 PayPal mock
  PP_SECRET="${E2E_PAYPAL_SECRET:-e2e-mock-key}"
  PP_CLIENT_ID="AUmock_client_id_sandbox_001"
  PPB="http://127.0.0.1:$PP_APP_PORT"
  PMB="http://127.0.0.1:$PP_MOCK_PORT"
  # 改写配置：out=gen-paypal，gateway=mock base，client_id/secret_env/webhook_path 对齐
  python3 - "$PP_CLIENT_ID" <<'PY' || { echo "E2E FAIL: 改写 PayPal 配置失败"; exit 1; }
import json, sys
cfg = json.load(open('example-paypal.json'))
cfg['pay']['client_id'] = sys.argv[1]
cfg['pay']['secret_env'] = 'PAYPAL_KEY'
cfg['pay']['mode'] = 'sandbox'
cfg['pay']['webhook_path'] = '/api/pay/webhook'
json.dump(cfg, open('/tmp/nsgm-e2e-paypal-config.json', 'w'))
PY
  rm -rf gen-paypal
  rm -f "$PAYPAL_DB"
  # 输出目录走 CLI 覆盖 out=./gen-paypal（免去改写配置副本），与 make run-paypal 同口径
  "$LUME" main.lume /tmp/nsgm-e2e-paypal-config.json out=./gen-paypal >/dev/null 2>&1 \
    || { echo "E2E FAIL: example-paypal.json 生成失败"; exit 1; }
  # PayPal mock：独立端口，显式传 client_id/secret（与生成配置一致），避免旧孤儿干扰
  MOCK_PAY_PORT="$PP_MOCK_PORT" \
    MOCK_PAYPAL_CLIENT_ID="$PP_CLIENT_ID" MOCK_PAYPAL_CLIENT_SECRET="$PP_SECRET" \
    python3 scripts/mock_pay_gateway.py >/tmp/nsgm-mock-gw-pp.log 2>&1 &
  PP_MOCK_PID=$!
  # 应用：PAY_GATEWAY 指向本阶段独立起的 PayPal mock；client_secret 走
  # PAYPAL_KEY（避开部分环境对含 SECRET/TOKEN 的变量名过滤）。
  # PAYPAL_CLIENT_ID 必须显式内联覆盖：Makefile `-include .env` + `export
  # PAYPAL_CLIENT_ID` 会把 .env 里的真实 client_id 泄漏进本进程（直接跑
  # e2e.sh 不经 make 则无此问题）；不覆盖的话 app 用真实 id、mock 期望
  # AUmock… → OAuth2 401。故四个凭证/网关变量全部内联钉死为 mock 值。
  ( cd gen-paypal && PORT="$PP_APP_PORT" HOST=127.0.0.1 WORKERS=1 \
      NSGM_DB="$PAYPAL_DB" PAYPAL_KEY="$PP_SECRET" PAYPAL_CLIENT_ID="$PP_CLIENT_ID" \
      PAY_GATEWAY="$PMB" PAYPAL_RETURN_URL="$PPB" \
      no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost" \
      exec "$LUME" app.lume ) >/tmp/nsgm-e2e-paypal.log 2>&1 &
  PID=$!
  for _ in $(seq 1 30); do
    curl -s --noproxy '*' -o /dev/null "$PMB/health" 2>/dev/null && break
    sleep 0.5
  done
  curl -s --noproxy '*' -o /dev/null "$PMB/health" 2>/dev/null \
    || { echo "E2E FAIL: PayPal mock 网关未就绪"; tail -5 /tmp/nsgm-mock-gw-pp.log; exit 1; }
  for _ in $(seq 1 30); do
    curl -s --noproxy '*' -o /dev/null "$PPB/api/order" 2>/dev/null && break
    sleep 0.5
  done
  curl -s --noproxy '*' -o /dev/null "$PPB/api/order" 2>/dev/null \
    || { echo "E2E FAIL: PayPal 应用未就绪"; tail -5 /tmp/nsgm-e2e-paypal.log; exit 1; }

  ONO="PPE2E-$(date +%s)"
  [ "$(code -X POST "$PPB/api/order" -H 'Content-Type: application/json' \
       -d "{\"order_no\":\"$ONO\",\"amount_cents\":14900}")" = "200" ] \
    || fail "PayPal POST /api/order 非 200"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"pending"' \
    || fail "PayPal 建单后 status 应为 pending"
  # 2) 建单（pay/create）：OAuth2 Bearer 由 mock 下发并校验 -> approve_url
  CREATE_RESP="$(curl -s --noproxy '*' -X POST "$PPB/api/pay/create" \
    -H 'Content-Type: application/json' -d "{\"order_no\":\"$ONO\"}")"
  if ! echo "$CREATE_RESP" | grep -q '"approve_url":'; then
    fail "PayPal pay/create 未返回 approve_url: $CREATE_RESP"
  fi
  APPROVE_URL="$(echo "$CREATE_RESP" | grep -o '"approve_url":"[^"]*"' | head -1 | sed 's/"approve_url":"//;s/"$//')"
  echo "$APPROVE_URL" | grep -q "mock/paypal/approve" \
    || fail "approve_url 应指向 mock 收银台: $APPROVE_URL"
  # 3) 全量 SPA：PayPal 回跳走 hash 路由（/spa/#/pay/return），由前端调 /api/pay/return 捕获。
  #    e2e 等价地直接调 /api/pay/return（与 SPA 行为一致），不再跟 302 到 SPA 壳（壳不触发捕获）。
  RT_TOKEN="$(echo "$APPROVE_URL" | sed -E 's/.*[?&]token=([^&"]*).*/\1/')"
  [ -n "$RT_TOKEN" ] || fail "approve_url 应带 token（PayPal 订单号）"
  RT_RESP="$(curl -s --noproxy '*' "$PPB/api/pay/return?order_no=$ONO&token=$RT_TOKEN")"
  echo "$RT_RESP" | grep -q '"status":"paid"' || fail "PayPal 捕获后 status 应为 paid: $RT_RESP"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "PayPal 捕获后落库应为 paid"
  # 4) 幂等：重复调 return（同 token）-> 仍 paid，不产生新行
  RT_RESP2="$(curl -s --noproxy '*' "$PPB/api/pay/return?order_no=$ONO&token=$RT_TOKEN")"
  echo "$RT_RESP2" | grep -q '"status":"paid"' || fail "重复 return 应仍 paid"
  [ "$(total_of "$PPB/api/order")" = "1" ] || fail "重复 return 不应产生新行"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "重复 return 后 status 仍应为 paid"
  # 5) webhook 负例：坏签名 -> 401
  BAD_WH="$(curl -s --noproxy '*' -X POST "$PPB/api/pay/webhook" \
    -H 'Content-Type: application/json' \
    -d '{"verify_id":"x","verify_ts":"1","verify_sign":"deadbeef","payload":"{}"}')"
  echo "$BAD_WH" | grep -q 'signature_mismatch' || fail "PayPal webhook 坏签名应拒: $BAD_WH"
  # 5b) 未知订单号存在性检查：不进捕获流程，回错误（订单不存在）
  curl -s --noproxy '*' "$PPB/api/pay/return?order_no=NOPE-PP&token=MOCK-PP-ORDER-x" | grep -q '订单不存在' \
    || fail "未知订单的 return 应提示订单不存在"
  # 6) 店面（PayPal 变体）：全量 SPA 后页面由 React 渲染，后端只出 JSON —— 断言走 JSON 端点。
  PP_PROD="$(curl -s --noproxy '*' "$PPB/api/shop/products")"
  echo "$PP_PROD" | grep -q '"currency_symbol":"\$"' || fail "PayPal 店面应以 \$ 计价: $(echo "$PP_PROD" | head -c 200)"
  echo "$PP_PROD" | grep -q '"name":"Lume 机械键盘"' || fail "PayPal 店面应有示例商品"
  echo "$PP_PROD" | grep -q '"price_cents":39900' || fail "PayPal 店面键盘价格应为 39900（分）"
  echo "$PP_PROD" | grep -q '"stock":10' || fail "PayPal 店面键盘库存应为 10"
  echo "$PP_PROD" | grep -q '"stock":0' || fail "PayPal 店面马克杯库存应为 0（售罄态由前端渲染）"
  # 下单：POST /api/shop/buy -> 收银台 JSON（order_no + approve_url）
  PP_BUY="$(curl -s --noproxy '*' -X POST "$PPB/api/shop/buy" -H 'Content-Type: application/json' -d '{"product_id":1}')"
  echo "$PP_BUY" | grep -q '"order_no":"SHOP-' || fail "PayPal 店面购买应产生 SHOP-* 订单: $PP_BUY"
  PP_SONO="$(echo "$PP_BUY" | grep -o '"order_no":"SHOP-[^"]*"' | head -1 | sed 's/"order_no":"//;s/"$//')"
  [ -n "$PP_SONO" ] || fail "PayPal 店面购买应产生 SHOP-* 订单"
  # 商品快照（P1-2）：订单行回填商品 id + 下单时定格商品名（后台列表直接可见）
  curl -s --noproxy '*' "$PPB/api/order?q=$PP_SONO" | grep -q '"product_id":1' \
    || fail "店面下单应回填 product_id"
  curl -s --noproxy '*' "$PPB/api/order?q=$PP_SONO" | grep -q '"product_name":"Lume 机械键盘"' \
    || fail "店面下单应定格商品名快照"
  # 扣库存：键盘 10 -> 9（JSON 列序固定，price_cents 唯一可定位到行）
  [ "$(curl -s --noproxy '*' "$PPB/api/product" | grep -o '"price_cents":39900,"stock":[0-9]*' | head -1 | sed 's/.*://')" = "9" ] \
    || fail "下单后键盘库存应 10->9"
  # 售罄拒单（P1-2）：0 库存商品（马克杯 id=3）被守卫拒掉，不建单、不误扣
  NSO_BEFORE="$(curl -s --noproxy '*' "$PPB/api/order" | grep -oE '"order_no":"SHOP-[^"]*"' | wc -l | tr -d ' ')"
  SOLD_OUT="$(curl -s --noproxy '*' -X POST "$PPB/api/shop/buy" -H 'Content-Type: application/json' -d '{"product_id":3}')"
  echo "$SOLD_OUT" | grep -q '已售罄' || fail "0 库存商品购买应提示已售罄: $SOLD_OUT"
  NSO_AFTER="$(curl -s --noproxy '*' "$PPB/api/order" | grep -oE '"order_no":"SHOP-[^"]*"' | wc -l | tr -d ' ')"
  [ "$NSO_BEFORE" = "$NSO_AFTER" ] || fail "售罄拒单不应产生订单（$NSO_BEFORE -> $NSO_AFTER）"
  # 收银台（JSON）：含 approve_url
  PP_CASH="$(curl -s --noproxy '*' "$PPB/api/shop/cashier/$PP_SONO")"
  echo "$PP_CASH" | grep -q '"approve_url":' || fail "PayPal 收银台应返回 approve_url: $PP_CASH"
  # 收银台复用（孤儿单防护）：建单成功即回填 paypal_order_id；再渲染一次收银台
  # 凭已回填 ID 重建 approve 链接，不向 PayPal 重复建单（刷新/重试不再堆孤儿单）
  curl -s --noproxy '*' "$PPB/api/order?q=$PP_SONO" | grep -q '"paypal_order_id":"MOCK-PP-ORDER-' \
    || fail "收银台建单后应回填 paypal_order_id"
  PP_CNT1="$(curl -s --noproxy '*' "$PMB/mock/paypal/orders" | grep -o '"orders":[0-9]*' | sed 's/.*://')"
  PP_CASH2="$(curl -s --noproxy '*' "$PPB/api/shop/cashier/$PP_SONO")"
  PP_CNT2="$(curl -s --noproxy '*' "$PMB/mock/paypal/orders" | grep -o '"orders":[0-9]*' | sed 's/.*://')"
  [ "$PP_CNT1" = "$PP_CNT2" ] || fail "重复渲染收银台不应新增 PayPal 建单（$PP_CNT1 -> $PP_CNT2）"
  echo "$PP_CASH2" | grep -q '"approve_url":' || fail "复用渲染的收银台仍应返回支付入口"
  # 支付店面单（PayPal 路径）：取 approve_url 的 token -> 直接调 /api/pay/return 捕获（SPA 同行为）
  PP_SONO_APPROVE="$(echo "$PP_CASH2" | grep -o '"approve_url":"[^"]*"' | head -1 | sed 's/"approve_url":"//;s/"$//')"
  [ -n "$PP_SONO_APPROVE" ] || fail "店面收银台应给出 approve 链接"
  PP_SONO_TOKEN="$(echo "$PP_SONO_APPROVE" | sed -E 's/.*[?&]token=([^&"]*).*/\1/')"
  [ -n "$PP_SONO_TOKEN" ] || fail "店面 approve_url 应带 token"
  RT_SONO_RESP="$(curl -s --noproxy '*' "$PPB/api/pay/return?order_no=$PP_SONO&token=$PP_SONO_TOKEN")"
  echo "$RT_SONO_RESP" | grep -q '"status":"paid"' || fail "店面单支付后应落库 paid: $RT_SONO_RESP"
  # 结果页（JSON）：paid
  curl -s --noproxy '*' "$PPB/api/shop/result/$PP_SONO" | grep -q '"status":"paid"' \
    || fail "PayPal 结果页应 paid"
  curl -s --noproxy '*' "$PPB/api/shop/result/NOPE-1" | grep -q '订单不存在' \
    || fail "未知订单结果页应提示不存在"
  echo "ok   店面(PayPal)：JSON 列表 \$ 计价/库存 -> 下单回填快照 -> 售罄拒单 -> 收银台 approve_url -> 结果页 paid"

  # ---- 幂等（ik）：同 ik 重复点击/刷新复用同一笔 pending 单；已支付则开新单（重买）----
  # 用户明确诉求：避免重复下单。SPA 下单走 POST /api/shop/buy（可带 ik 幂等 Key），
  # 复用同一笔 pending 单；已支付后再点同 ik 开新单（SHOP-<ik>-r<ts>）。
  echo "==> 幂等（ik）阶段：重复下单复用同一笔 pending 单，已支付开新单 ..."
  IK="IDEM-$(date +%s%N)"
  [ "$(code -X POST "$PPB/api/shop/buy" -H 'Content-Type: application/json' -d "{\"product_id\":1,\"ik\":\"$IK\"}")" = "200" ] \
    || fail "幂等首购应 200"
  IDEM_ONO="SHOP-$IK"
  curl -s --noproxy '*' "$PPB/api/order?q=$IDEM_ONO" | grep -q "\"order_no\":\"$IDEM_ONO\"" \
    || fail "幂等：应已创建 $IDEM_ONO"
  curl -s --noproxy '*' "$PPB/api/order?q=$IDEM_ONO" | grep -q '"status":"pending"' \
    || fail "幂等：首单应 pending"
  # 刷新 / 重复点击（同一 ik）-> 复用同一笔，不产生新行
  [ "$(code -X POST "$PPB/api/shop/buy" -H 'Content-Type: application/json' -d "{\"product_id\":1,\"ik\":\"$IK\"}")" = "200" ] \
    || fail "幂等重复点击应 200"
  [ "$(total_of "$PPB/api/order?q=$IDEM_ONO")" = "1" ] \
    || fail "幂等：同一 ik 重复下单不应产生新订单行（total 应为 1）"
  # 支付（PayPal 路径）：收银台 JSON 取 approve_url -> 直接调 return 捕获 -> paid
  IK_CASH="$(curl -s --noproxy '*' "$PPB/api/shop/cashier/$IDEM_ONO")"
  IK_APPROVE="$(echo "$IK_CASH" | grep -o '"approve_url":"[^"]*"' | head -1 | sed 's/"approve_url":"//;s/"$//')"
  [ -n "$IK_APPROVE" ] || fail "幂等：收银台应给出 approve 链接: $IK_CASH"
  IK_TOKEN="$(echo "$IK_APPROVE" | sed -E 's/.*[?&]token=([^&"]*).*/\1/')"
  [ -n "$IK_TOKEN" ] || fail "幂等：approve_url 应带 token"
  RT_IK_RESP="$(curl -s --noproxy '*' "$PPB/api/pay/return?order_no=$IDEM_ONO&token=$IK_TOKEN")"
  echo "$RT_IK_RESP" | grep -q '"status":"paid"' || fail "幂等：支付后应为 paid: $RT_IK_RESP"
  # 已支付后再次同 ik -> 开新单（重买），订单号带 -r 后缀、状态 pending
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/buy" -H 'Content-Type: application/json' -d "{\"product_id\":1,\"ik\":\"$IK\"}" \
    || fail "幂等已支付后重买请求失败"
  REBUY="$(curl -s --noproxy '*' "$PPB/api/order" | grep -oE "SHOP-$IK-r[0-9]+" | head -1)"
  [ -n "$REBUY" ] || fail "幂等：已支付后同 ik 应开新单（SHOP-$IK-r<ts>）"
  curl -s --noproxy '*' "$PPB/api/order?q=$REBUY" | grep -q '"status":"pending"' \
    || fail "幂等：重买新单应 pending"
  echo "ok   幂等（ik）：首单 pending -> 同 ik 复用 -> approve 支付 -> 同 ik 重买开新单（SHOP-<ik>-r<ts>）"

  # ---- 退款（PayPal）：确认页 -> capture refund -> refunded 落库 -> 重复退幂等 ----
  # 场景：$ONO 已捕获（capture_id 由 return 处理器回填）；退款走
  # POST /v2/payments/captures/{capture_id}/refund。pending 单（店面新单未 approve）
  # 与未知订单被拒；mock 侧对同一捕获重复退回 422 ALREADY_REFUNDED（应用侧
  # paypal_refund 按成功对账，本地状态守卫为主）。
  echo "==> 退款阶段（PayPal）：确认数据(JSON) -> 退款 -> 已退款 -> 重复退幂等 ..."
  PP_RF="$(curl -s --noproxy '*' "$PPB/api/shop/refund/$ONO")"
  echo "$PP_RF" | grep -q '"status":"paid"' || fail "PayPal 退款确认数据应为 paid: $PP_RF"
  echo "$PP_RF" | grep -q '"amount_cents":14900' || fail "PayPal 退款确认数据应含订单金额"
  echo "$PP_RF" | grep -q '"currency_symbol":"\$"' || fail "PayPal 退款确认数据应以 \$ 计价"
  # pending 单不可退（幂等段重买的新单此时仍 pending）
  curl -s --noproxy '*' -X POST "$PPB/api/shop/refund/$REBUY" -H 'Content-Type: application/json' -d '{"confirm":"1"}' \
    | grep -q '仅已支付订单可退款' || fail "pending 订单应拒退"
  # 未知订单
  curl -s --noproxy '*' "$PPB/api/shop/refund/NOPE-1" | grep -q '订单不存在' \
    || fail "未知订单退款应提示不存在"
  # 订单后台（/order SSR 仍在）paid 行动作列应注入「退款」链接（用户诉求：UI 上能找到退款入口）
  curl -s --noproxy '*' "$PPB/order" | grep -q "/shop/refund/$ONO" \
    || fail "订单后台 paid 行应带退款链接"
  # 展示格式化：美元计价 + paid 绿徽标（PayPal 变体 cur=$）
  PPLIST="$(curl -s --noproxy '*' "$PPB/order")"
  echo "$PPLIST" | grep -qF 'class="money">$399.00' \
    || fail "PayPal 订单后台金额列应格式化为美元: $(echo "$PPLIST" | grep -o 'class="money">[^<]*' | head -2)"
  echo "$PPLIST" | grep -qF '<span class="st st-ok">paid</span>' \
    || fail "PayPal 订单后台 paid 行应带绿色状态徽标"
  # 正常路径：return 处理器应回填 paypal_order_id + capture_id（退款凭据）
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"capture_id":"MOCK-CAPTURE-' \
    || fail "return 处理器应回填 capture_id"
  # 早期订单场景：capture_id 列为 SQL NULL（迁移补列的旧单读出来是 lume null，
  # str(null) 得字面量 "null" 会骗过 == "" 守卫）——抹成 NULL 后退款应走
  # paypal_get_order 反查兜底而非把 "null" 当 capture_id 发给 PayPal
  python3 - "$PAYPAL_DB" "$ONO" <<'PY' || fail "预置 NULL capture_id 失败"
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('UPDATE "order" SET "capture_id" = NULL WHERE "order_no" = ?', (sys.argv[2],))
con.commit(); con.close()
PY
  # 确认退款（POST JSON；mock 受理；capture_id 走反查兜底）
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/refund/$ONO" -H 'Content-Type: application/json' -d '{"confirm":"1"}' \
    || fail "PayPal 退款请求失败"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"refunded"' \
    || fail "退款后订单应落库 refunded"
  curl -s --noproxy '*' "$PPB/api/shop/result/$ONO" | grep -q '"status":"refunded"' \
    || fail "结果页应展示已退款"
  # 重复退（幂等）：本地状态守卫，仍返回已退款
  curl -s --noproxy '*' -X POST "$PPB/api/shop/refund/$ONO" -H 'Content-Type: application/json' -d '{"confirm":"1"}' \
    | grep -q '"status":"refunded"' || fail "重复退应幂等返回已退款"
  # 已退款行不应再显示退款链接（SSR 条件渲染只认 paid）
  curl -s --noproxy '*' "$PPB/order" | grep -q "/shop/refund/$ONO" \
    && fail "refunded 行不应再带退款链接" || true
  # mock 侧直探：查单兜底（GET order 返回 captures）+ 同一捕获重复退 422
  # （放在所有应用侧调用之后：直取 token 会顶掉 mock 的 PP_ISSUED_TOKEN）
  PP_PPID="$(curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -o '"paypal_order_id":"[^"]*"' | head -1 | sed 's/"paypal_order_id":"//;s/"$//')"
  [ -n "$PP_PPID" ] || fail "return 处理器应回填 paypal_order_id"
  PP_TOK="$(curl -s --noproxy '*' -u "$PP_CLIENT_ID:$PP_SECRET" -d 'grant_type=client_credentials' \
    "$PMB/v1/oauth2/token" | grep -o '"access_token":"[^"]*"' | head -1 | sed 's/"access_token":"//;s/"$//')"
  [ -n "$PP_TOK" ] || fail "PayPal mock 应下发 access_token"
  # 查单兜底路径：捕获 ID 从 mock 侧订单详情取（应用退款时同路反查）
  PP_CAP="$(curl -s --noproxy '*' -H "Authorization: Bearer $PP_TOK" "$PMB/v2/checkout/orders/$PP_PPID" \
    | grep -o '"id":"MOCK-CAPTURE-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$PP_CAP" ] || fail "mock 查单应返回 capture_id（退款反查兜底）"
  DUP_CODE="$(curl -s --noproxy '*' -o /dev/null -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $PP_TOK" -H 'Content-Type: application/json' \
    -d '{"amount":{"value":"149.00","currency_code":"USD"}}' \
    "$PMB/v2/payments/captures/$PP_CAP/refund")"
  [ "$DUP_CODE" = "422" ] || fail "mock 对已退捕获重复退应回 422（got $DUP_CODE）"
  echo "ok   退款（PayPal）：确认页 -> capture refund -> refunded 落库 -> 重复退幂等 -> NULL 列兜底 -> 查单 -> mock 422 对账"

  # ---- 对账保护：paid/refunded 订单禁止后台改单/删单（SSR + JSON 双面守卫）----
  # 店面订单的金额/订单号已被 PayPal 侧引用（退款按行金额、关联 ID 回填），
  # 后台篡改会破坏对账 —— row_locked 守卫四处拒绝；pending 单照常可编辑。
  echo "==> 对账保护阶段：paid/refunded 拒后台改删，pending 可编辑 ..."
  PP_OID="$(curl -s --noproxy '*' "$PPB/api/order?q=$PP_SONO" | grep -o '"id":[0-9]*' | head -1 | sed 's/[^0-9]//g')"
  [ -n "$PP_OID" ] || fail "对账保护：未定位到店面订单行 id"
  UPD_LOCK="$(curl -s --noproxy '*' -X POST "$PPB/api/order/update/$PP_OID" -H 'Content-Type: application/json' -d '{"order_no":"HACK","amount_cents":1}')"
  echo "$UPD_LOCK" | grep -q '"err":"order_locked"' || fail "paid 订单应拒绝后台编辑: $UPD_LOCK"
  DEL_LOCK="$(curl -s --noproxy '*' -X POST "$PPB/api/order/delete/$PP_OID" -H 'Content-Type: application/json' -d '{}')"
  echo "$DEL_LOCK" | grep -q '"err":"order_locked"' || fail "paid 订单应拒绝后台删除: $DEL_LOCK"
  # SSR 路径同样拒（flash 提示、不落库）
  SSR_SAVE="$(curl -s --noproxy '*' "$PPB/order/save?id=$PP_OID&order_no=HACK&amount_cents=1")"
  echo "$SSR_SAVE" | grep -q '受对账保护' || fail "paid 订单 SSR 编辑应被守卫拒绝: $SSR_SAVE"
  curl -s --noproxy '*' -o /dev/null "$PPB/order/del/$PP_OID"
  curl -s --noproxy '*' "$PPB/api/order?q=$PP_SONO" | grep -q '"status":"paid"' \
    || fail "对账守卫：paid 订单不应被删除/篡改"
  # refunded（$ONO）：编辑亦拒
  ONO_ID="$(curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -o '"id":[0-9]*' | head -1 | sed 's/[^0-9]//g')"
  [ -n "$ONO_ID" ] || fail "对账保护：未定位到已退款订单行 id"
  curl -s --noproxy '*' -X POST "$PPB/api/order/update/$ONO_ID" -H 'Content-Type: application/json' -d '{"order_no":"HACK"}' \
    | grep -q '"err":"order_locked"' || fail "refunded 订单应拒绝后台编辑"
  # pending（幂等段重买单 REBUY）：仍可编辑（手工调整合法）
  REBUY_ID="$(curl -s --noproxy '*' "$PPB/api/order?q=$REBUY" | grep -o '"id":[0-9]*' | head -1 | sed 's/[^0-9]//g')"
  [ -n "$REBUY_ID" ] || fail "对账保护：未定位到重买 pending 单 id"
  curl -s --noproxy '*' -X POST "$PPB/api/order/update/$REBUY_ID" -H 'Content-Type: application/json' \
    -d "{\"order_no\":\"$REBUY\",\"amount_cents\":14900}" | grep -q '"ok":true' \
    || fail "pending 订单仍应可后台编辑（守卫只锁 paid/refunded）"
  echo "ok   对账保护：paid/refunded 编辑+删除+SSR 守卫全拒、pending 编辑放行"

  # ---- 早期订单（paypal_order_id 与 capture_id 均为 SQL NULL）退款恢复阶段 ----
  # 真实 bug：迁移补列前的早期订单两列全 NULL，退款路由旧逻辑只兜底「capture_id 空但
  # paypal_order_id 在」，两者皆空时直接死在报错。修复后：确认页提示去恢复，
  # /shop/recover/:ono 表单可填 ppid 反查 / capid 直达退款 / manual 本地标记。
  # 后续事故：用户把 PayPal 后台「交易号/Transaction ID」（即捕获 ID）填进订单号框，
  # 订单 GET 对捕获 ID 回 404 RESOURCE_NOT_FOUND——恢复页填 ppid 时增加捕获兜底
  # （改查 /v2/payments/captures/{id}，related_ids.order_id 反解订单号）。
  echo "==> 早期订单（双空关联 ID）退款恢复阶段 ..."
  # 预备：在 mock 建两张可捕获的 PayPal 订单，拿两个有效捕获 ID（互不影响，避免耦合）
  MOCK_TOK="$(curl -s --noproxy '*' -u "$PP_CLIENT_ID:$PP_SECRET" -d 'grant_type=client_credentials' \
    "$PMB/v1/oauth2/token" | grep -o '"access_token":"[^"]*"' | head -1 | sed 's/"access_token":"//;s/"$//')"
  [ -n "$MOCK_TOK" ] || fail "mock token (早期订单) 失败"
  EO_A_OID="$(curl -s --noproxy '*' -H "Authorization: Bearer $MOCK_TOK" -H 'Content-Type: application/json' \
    -d '{"application_context":{"return_url":"http://x/retA"}}' \
    "$PMB/v2/checkout/orders" | grep -o '"id":"MOCK-PP-ORDER-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_A_OID" ] || fail "mock 建单 (早期-A) 失败"
  EO_A_CAP="$(curl -s --noproxy '*' -X POST -H "Authorization: Bearer $MOCK_TOK" \
    "$PMB/v2/checkout/orders/$EO_A_OID/capture" | grep -o '"id":"MOCK-CAPTURE-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_A_CAP" ] || fail "mock 捕获 (早期-A) 失败"
  EO_B_OID="$(curl -s --noproxy '*' -H "Authorization: Bearer $MOCK_TOK" -H 'Content-Type: application/json' \
    -d '{"application_context":{"return_url":"http://x/retB"}}' \
    "$PMB/v2/checkout/orders" | grep -o '"id":"MOCK-PP-ORDER-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_B_OID" ] || fail "mock 建单 (早期-B) 失败"
  EO_B_CAP="$(curl -s --noproxy '*' -X POST -H "Authorization: Bearer $MOCK_TOK" \
    "$PMB/v2/checkout/orders/$EO_B_OID/capture" | grep -o '"id":"MOCK-CAPTURE-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_B_CAP" ] || fail "mock 捕获 (早期-B) 失败"
  EO_C_OID="$(curl -s --noproxy '*' -H "Authorization: Bearer $MOCK_TOK" -H 'Content-Type: application/json' \
    -d '{"application_context":{"return_url":"http://x/retC"}}' \
    "$PMB/v2/checkout/orders" | grep -o '"id":"MOCK-PP-ORDER-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_C_OID" ] || fail "mock 建单 (早期-C) 失败"
  EO_C_CAP="$(curl -s --noproxy '*' -X POST -H "Authorization: Bearer $MOCK_TOK" \
    "$PMB/v2/checkout/orders/$EO_C_OID/capture" | grep -o '"id":"MOCK-CAPTURE-[^"]*"' | head -1 | sed 's/"id":"//;s/"$//')"
  [ -n "$EO_C_CAP" ] || fail "mock 捕获 (早期-C) 失败"
  # 双空早期订单：两列均 NULL、paid、无商品引用（库存回补跳过）
  python3 - "$PAYPAL_DB" <<'PY' || fail "预置双空早期订单失败"
import sqlite3, sys
con = sqlite3.connect(sys.argv[1])
con.execute('INSERT INTO "order" ("order_no","amount_cents","status") VALUES (?,?,?)', ("EARLY-DIRECT", 9900, "paid"))
con.execute('INSERT INTO "order" ("order_no","amount_cents","status") VALUES (?,?,?)', ("EARLY-PPID", 8800, "paid"))
con.execute('INSERT INTO "order" ("order_no","amount_cents","status") VALUES (?,?,?)', ("EARLY-TXNID", 6600, "paid"))
con.execute('INSERT INTO "order" ("order_no","amount_cents","status") VALUES (?,?,?)', ("EARLY-MANUAL", 7700, "paid"))
con.commit(); con.close()
PY
  # 确认数据应提示缺关联 ID（need_recover=1；恢复页由 SPA hash 路由渲染，后端不再出 SSR 表单）
  EO_RF="$(curl -s --noproxy '*' "$PPB/api/shop/refund/EARLY-DIRECT")"
  echo "$EO_RF" | grep -q '"need_recover":1' \
    || fail "双空早期订单确认数据应提示缺关联 ID（need_recover=1）: $EO_RF"
  # 路径1：填捕获 ID 直达退款（POST JSON；真实 PayPal refund 走 mock，EARLY-DIRECT）
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/refund/EARLY-DIRECT" \
    -H 'Content-Type: application/json' -d "{\"confirm\":\"1\",\"capid\":\"$EO_A_CAP\"}" \
    || fail "早期订单 capid 退款请求失败"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-DIRECT" | grep -q '"status":"refunded"' \
    || fail "早期订单 capid 直达退款后应落库 refunded"
  # 回补关联 ID（capid 写回）：后续操作一致
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-DIRECT" | grep -q "\"capture_id\":\"$EO_A_CAP\"" \
    || fail "早期订单退款应回补 capture_id"
  # 路径2：填 PayPal 订单号反查捕获再退款（EARLY-PPID）
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/refund/EARLY-PPID" \
    -H 'Content-Type: application/json' -d "{\"confirm\":\"1\",\"ppid\":\"$EO_B_OID\"}" \
    || fail "早期订单 ppid 反查退款请求失败"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-PPID" | grep -q '"status":"refunded"' \
    || fail "早期订单 ppid 反查退款后应落库 refunded"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-PPID" | grep -q "\"paypal_order_id\":\"$EO_B_OID\"" \
    || fail "早期订单 ppid 反查退款应回补 paypal_order_id"
  # 路径3：已在 PayPal 后台手动退款 -> 本地标记（不调 API，EARLY-MANUAL）
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/refund/EARLY-MANUAL" \
    -H 'Content-Type: application/json' -d '{"confirm":"1","manual":"1"}' \
    || fail "早期订单手动标记退款请求失败"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-MANUAL" | grep -q '"status":"refunded"' \
    || fail "早期订单手动标记后应落库 refunded"
  curl -s --noproxy '*' "$PPB/api/shop/result/EARLY-MANUAL" | grep -q '"status":"refunded"' \
    || fail "早期订单手动标记结果数据应展示已退款"
  # 路径4：把「交易号/捕获 ID」填进订单号框——订单 GET 404 后自动改查捕获接口
  # （真实事故：早期订单恢复时用户把交易号填进订单号框，订单端点回
  # RESOURCE_NOT_FOUND/INVALID_RESOURCE_ID 直接报错；兜底后反解订单号并退款）
  curl -s --noproxy '*' -o /dev/null -X POST "$PPB/api/shop/refund/EARLY-TXNID" \
    -H 'Content-Type: application/json' -d "{\"confirm\":\"1\",\"ppid\":\"$EO_C_CAP\"}" \
    || fail "早期订单 交易号兜底退款请求失败"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-TXNID" | grep -q '"status":"refunded"' \
    || fail "交易号兜底退款后应落库 refunded"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-TXNID" | grep -q "\"paypal_order_id\":\"$EO_C_OID\"" \
    || fail "交易号兜底应回填真实订单号（related_ids.order_id）"
  curl -s --noproxy '*' "$PPB/api/order?q=EARLY-TXNID" | grep -q "\"capture_id\":\"$EO_C_CAP\"" \
    || fail "交易号兜底应回填捕获 ID"
  echo "ok   早期订单（双空关联 ID）：need_recover 提示 -> capid 直达 / ppid 反查 / manual 本地标记 / 交易号捕获兜底 四条路径均落库 refunded"

  # ---- 购物车（P2-4）：落库持久化，session 仅存 cart_id ----
  # 场景：独立 cookie 会话跑加购 -> 会话持久（同 cookie 复得购物车，S1 边界 WORKERS=1
  # 下跨请求持久）-> 结算建单(CART-*) + 扣库存 + 清空 -> 售罄商品被拒且保留在购物车。
  # 全 JSON，与既有「直接下单」/api/shop/buy 正交，不改动其链路。
  # 置于商品目录 clear 之前：本段依赖商品行（含 0 库存售罄样本）存在。
  echo "==> 购物车阶段：加购 -> session 持久 -> 结算扣库存 -> 清空 -> 售罄拒单 ..."
  CART_CJ="/tmp/nsgm-e2e-cart-cj.txt"
  rm -f "$CART_CJ"
  # 键盘库存基线（/api/product 列序固定：price_cents 紧跟 stock）
  KB0="$(curl -s --noproxy '*' "$PPB/api/product" | grep -o '"price_cents":39900,"stock":[0-9]*' | head -1 | sed 's/.*://')"
  [ -n "$KB0" ] || fail "购物车：未取到键盘库存基线"
  # 1) 加购：键盘 x2（建购物车 + 会话写回 cart_id）
  CART_ADD="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" -X POST "$PPB/api/shop/cart/add" \
    -H 'Content-Type: application/json' -d '{"product_id":1,"qty":2}')"
  echo "$CART_ADD" | grep -q '"product_id":1' || fail "购物车：加购应含商品行: $CART_ADD"
  echo "$CART_ADD" | grep -q '"total_cents":79800' || fail "购物车：键盘 x2 总价应 79800: $CART_ADD"
  # 2) session 持久：同 cookie 复得同一购物车
  CART_GET="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" "$PPB/api/shop/cart")"
  echo "$CART_GET" | grep -q '"total_cents":79800' || fail "购物车：同会话应复得购物车: $CART_GET"
  # 3) 结算：建单（CART-*）+ 扣库存（-2）+ 清空购物车
  CART_CK="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" -X POST "$PPB/api/shop/cart/checkout" \
    -H 'Content-Type: application/json' -d '{}')"
  echo "$CART_CK" | grep -q '"order_no":"CART-' || fail "购物车：结算应建 CART-* 订单: $CART_CK"
  echo "$CART_CK" | grep -q '"ok":true' || fail "购物车：结算行应 ok: $CART_CK"
  KB1="$(curl -s --noproxy '*' "$PPB/api/product" | grep -o '"price_cents":39900,"stock":[0-9]*' | head -1 | sed 's/.*://')"
  [ "$KB1" = "$((KB0 - 2))" ] || fail "购物车：结算后键盘库存应 $((KB0 - 2))（got $KB1）"
  CART_EMPTY="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" "$PPB/api/shop/cart")"
  echo "$CART_EMPTY" | grep -q '"count":0' || fail "购物车：结算后应清空: $CART_EMPTY"
  # 4) 售罄拒单：马克杯（库存 0）结算应 sold_out 且保留在购物车
  curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" -X POST "$PPB/api/shop/cart/add" \
    -H 'Content-Type: application/json' -d '{"product_id":3,"qty":1}' >/dev/null
  CART_SO="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" -X POST "$PPB/api/shop/cart/checkout" \
    -H 'Content-Type: application/json' -d '{}')"
  echo "$CART_SO" | grep -q '"err":"sold_out"' || fail "购物车：0 库存商品结算应 sold_out: $CART_SO"
  CART_KEEP="$(curl -s --noproxy '*' -c "$CART_CJ" -b "$CART_CJ" "$PPB/api/shop/cart")"
  echo "$CART_KEEP" | grep -q '"product_id":3' || fail "购物车：售罄行应保留在购物车: $CART_KEEP"
  echo "ok   购物车：加购 -> session 持久 -> 结算建单扣库存 -> 清空 -> 售罄拒单且保留"

  # ---- 商品目录：空表自动播种 -> 清空不复活 -> 手动重载（用户诉求：给示例 + 清空按钮）----
  # 新库首访 /api/shop/products 已自动播种（上方 PP_PROD 断言即依赖该行为）；
  # 本段验证清空/重载闭环（JSON 端点，SPA 前端调同一接口）。
  # 放在所有依赖商品行的探针之后：clear 会删光商品，提前会破坏后续 buy/退款断言。
  # 实现细节：清空落「已播种」标记（_nsgm_shop_meta 元表）——否则空表会被下一次
  # 访问自动播种，按钮形同虚设；sql_write 护栏禁无 WHERE 的 DELETE，按 id 逐行参数化删。
  curl -s --noproxy '*' "$PPB/api/shop/products?act=clear" | grep -q '已清空全部商品' \
    || fail "products?act=clear 应提示已清空"
  [ "$(curl -s --noproxy '*' "$PPB/api/product" | grep -o '"total":[0-9]*' | head -1 | grep -o '[0-9]*')" = "0" ] \
    || fail "clear 后商品应清零"
  curl -s --noproxy '*' "$PPB/api/shop/products" | grep -q '"empty":1' \
    || fail "clear 后再访问 products 应为空态（不自动复活）"
  curl -s --noproxy '*' "$PPB/api/shop/products?act=seed" | grep -q '示例商品已载入' \
    || fail "products?act=seed 应重载示例商品"
  curl -s --noproxy '*' "$PPB/api/shop/products" | grep -q '"price_cents":39900' \
    || fail "seed 后店面应恢复示例商品"
  curl -s --noproxy '*' "$PPB/api/shop/products?act=seed" | grep -q '商品目录非空，未重复载入' \
    || fail "非空时 act=seed 不应重复载入"
  # 订单不受清空影响（早前探针建的单仍在）
  curl -s --noproxy '*' "$PPB/api/order" | grep -q '"total":[1-9]' \
    || fail "clear 商品不应波及订单记录"
  echo "ok   商品目录：空表自动播种 -> 清空（订单不受影响）-> 不自动复活 -> 手动重载 -> 非空守卫"
else
  echo "SKIP 支付阶段(PayPal): 无 python3"
fi

echo "E2E PASS: 全部探针通过 (SSR / 静态 / CRUD / 搜索 / 通配符转义 / 分页 / qs_int 兜底 / 迁移 / NULL 归一 / PayPal 全链路(JSON) / 退款全链路(JSON) / 订单后台退款入口 / 库存扣减与售罄拒单 / 商品快照 / 退款回补 / 收银台复用防孤儿单 / ik 幂等 / 早期订单双空关联 ID 恢复 / 交易号捕获兜底 / 商品目录示例播种与清空重载 / 购物车落库加购-会话持久-结算扣库存-售罄拒单)"
exit 0
