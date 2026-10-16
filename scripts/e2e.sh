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
PAY_DB="${E2E_PAY_DB:-/tmp/nsgm-e2e-pay.db}"
PAYPAL_DB="${E2E_PAYPAL_DB:-/tmp/nsgm-e2e-paypal.db}"
B="http://$HOST:$PORT"
PID=""
MOCK_PID=""
PP_MOCK_PID=""

cleanup() {
  [ -n "$PID" ] && kill "$PID" 2>/dev/null || true
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null || true
  [ -n "$PP_MOCK_PID" ] && kill "$PP_MOCK_PID" 2>/dev/null || true
  wait "$PID" "$MOCK_PID" "$PP_MOCK_PID" 2>/dev/null || true
  rm -f "$DB" "$MIG_DB" "$PAY_DB" "$PAYPAL_DB"
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
  echo "ok   迁移：旧库自动补列，旧行保留，新写正常，SSR 可渲染"
else
  echo "SKIP 迁移阶段: 无 python3"
fi

# ---- 支付阶段：mock 网关全链路（建单 -> 签名下单 -> code_url -> 回调验签 -> 状态落库 -> 幂等 -> 篡改拒）----
# 场景：example-pay.json 生成带 pay 接线的工程（order 模块 + pay.lume），mock 网关
# （scripts/mock_pay_gateway.py，Python 侧独立实现同一套 HMAC-SHA256）验签后返回
# code_url，并代网关投递签名回调；应用验签通过才把订单 pending -> paid。
if command -v python3 >/dev/null 2>&1; then
  echo "==> 支付阶段：生成 example-pay.json 工程 + 起 mock 网关 ..."
  kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
  PAY_APP_PORT="${E2E_PAY_PORT:-18095}"
  MOCK_PORT="${E2E_MOCK_PORT:-18097}"
  PAY_KEY="${E2E_PAY_KEY:-e2e-mock-key}"
  PB="http://127.0.0.1:$PAY_APP_PORT"
  MB="http://127.0.0.1:$MOCK_PORT"
  rm -rf gen-pay
  rm -f "$PAY_DB"
  # 统一改写一份临时配置：输出到 gen-pay（不污染 CRUD 演示的 gen/），
  # gateway 端口与 MOCK_PORT 对齐（默认都是 18097，见 example-pay.json）
  python3 - "$MOCK_PORT" <<'PY' || { echo "E2E FAIL: 改写支付配置失败"; exit 1; }
import json, sys
cfg = json.load(open('example-pay.json'))
cfg['out'] = './gen-pay'
cfg['pay']['gateway'] = f"http://127.0.0.1:{sys.argv[1]}"
json.dump(cfg, open('/tmp/nsgm-e2e-pay-config.json', 'w'))
PY
  rm -rf gen-pay
  rm -f "$PAY_DB"
  "$LUME" main.lume /tmp/nsgm-e2e-pay-config.json >/dev/null 2>&1 \
    || { echo "E2E FAIL: example-pay.json 生成失败"; exit 1; }

  # mock 网关（与应用同密钥；Python 侧独立实现签名=跨语言一致性验证）
  MOCK_PAY_PORT="$MOCK_PORT" MOCK_PAY_SECRET="$PAY_KEY" \
    python3 scripts/mock_pay_gateway.py >/tmp/nsgm-mock-gw.log 2>&1 &
  MOCK_PID=$!
  # 应用（no_proxy 必须带上：lume 出站 HTTP 只认 NO_PROXY 系列变量，
  # 否则 http_proxy 会把打往 127.0.0.1 的网关请求接走）。
  # 密钥变量名 PAY_KEY：部分执行环境会按名过滤含 SECRET/TOKEN/PASSWORD 的变量，
  # PAY_KEY 不被过滤；名字可在 config.pay.secret_env 自定。
  ( cd gen-pay && PORT="$PAY_APP_PORT" HOST=127.0.0.1 WORKERS=1 \
      NSGM_DB="$PAY_DB" PAY_KEY="$PAY_KEY" \
      PAY_NOTIFY_URL="$PB/api/pay/notify" \
      no_proxy="127.0.0.1,localhost" NO_PROXY="127.0.0.1,localhost" \
      exec "$LUME" app.lume ) >/tmp/nsgm-e2e-pay.log 2>&1 &
  PID=$!

  for _ in $(seq 1 30); do
    curl -s --noproxy '*' -o /dev/null "$MB/health" 2>/dev/null && break
    sleep 0.5
  done
  curl -s --noproxy '*' -o /dev/null "$MB/health" 2>/dev/null \
    || { echo "E2E FAIL: mock 网关未就绪"; tail -5 /tmp/nsgm-mock-gw.log; exit 1; }
  for _ in $(seq 1 30); do
    curl -s --noproxy '*' -o /dev/null "$PB/api/order" 2>/dev/null && break
    sleep 0.5
  done
  curl -s --noproxy '*' -o /dev/null "$PB/api/order" 2>/dev/null \
    || { echo "E2E FAIL: 支付应用未就绪"; tail -5 /tmp/nsgm-e2e-pay.log; exit 1; }

  ONO="E2E-$(date +%s)"
  # 1) 建单：order_no 自选；status 不入表单，走 DDL 默认 'pending'
  [ "$(code -X POST "$PB/api/order" -H 'Content-Type: application/json' \
       -d "{\"order_no\":\"$ONO\",\"amount_cents\":9900}")" = "200" ] \
    || fail "POST /api/order 非 200"
  curl -s --noproxy '*' "$PB/api/order?q=$ONO" | grep -q '"status":"pending"' \
    || fail "建单后 status 应为 pending（DDL 默认值）"
  # 2) 下单：应用 HMAC 签名调网关；签名不过则网关 401、应用回 502 探针失败
  CREATE_RESP="$(curl -s --noproxy '*' -X POST "$PB/api/pay/create" \
    -H 'Content-Type: application/json' -d "{\"order_no\":\"$ONO\"}")"
  if ! echo "$CREATE_RESP" | grep -q "\"code_url\": *\"weixin://wxpay/bizpayurl?pr=MOCK$ONO\""; then
    if echo "$CREATE_RESP" | grep -q 'signature mismatch'; then
      echo "E2E FAIL: 网关判定签名不匹配。常见根因：密钥未到达应用进程——"
      echo "  部分执行环境会按环境变量名过滤密钥类变量（含 SECRET/TOKEN/PASSWORD/CREDENTIAL"
      echo "  的名字会被洗成空），应用以空密钥签名。本脚本用 PAY_KEY（不被过滤）；"
      echo "  若你改了 secret_env，请确认该名字在执行环境里能原样到达子进程。"
    fi
    fail "pay/create 未返回预期 code_url: $CREATE_RESP"
  fi
  # 3) 网关侧负例：坏 Authorization 签名必须 401（证明网关真在验签）
  [ "$(code -X POST "$MB/v3/pay/transactions/native" \
       -H 'Authorization: WECHATPAY2-SHA256-HMAC mchid="x",serial_no="y",nonce_str="n",timestamp="1",signature="deadbeef"' \
       -H 'Content-Type: application/json' -d '{}')" = "401" ] \
    || fail "mock 网关应拒坏签名(401)"
  # 4) 未知订单：create 走 404 分支（注意：core 无响应状态码控制，
  #    {status,body} 只是 payload 约定，HTTP 恒 200——断 body 不断状态码）
  CREATE404="$(curl -s --noproxy '*' -X POST "$PB/api/pay/create" \
    -H 'Content-Type: application/json' -d '{"order_no":"NOPE-1"}')"
  echo "$CREATE404" | grep -q '"err":"order not found"' \
    || fail "未知订单应回 order not found: $CREATE404"
  # 5) 回调负例：坏签名 -> FAIL，订单状态不动
  BAD_NOTIFY="$(curl -s --noproxy '*' -X POST "$PB/api/pay/notify" \
    -H 'Content-Type: application/json' \
    -d '{"verify_ts":"1","verify_nonce":"x","verify_sign":"deadbeef","payload":"{\"out_trade_no\":\"'$ONO'\"}"}')"
  echo "$BAD_NOTIFY" | grep -q '"code":"FAIL"' \
    || fail "坏签名回调应 FAIL: $BAD_NOTIFY"
  curl -s --noproxy '*' "$PB/api/order?q=$ONO" | grep -q '"status":"pending"' \
    || fail "坏签名回调不应改动订单状态"
  # 6) 正常回调：mock 代网关投递（Python 侧签名）-> 应用验签通过 -> SUCCESS + 落库
  NOTIFY_RESP="$(curl -s --noproxy '*' -X POST "$MB/mock/notify" \
    -H 'Content-Type: application/json' \
    -d "{\"notify_url\":\"$PB/api/pay/notify\",\"order_no\":\"$ONO\",\"amount_cents\":9900}")"
  echo "$NOTIFY_RESP" | grep -q 'SUCCESS' \
    || fail "回调未成功送达/应用未验签通过: $NOTIFY_RESP"
  curl -s --noproxy '*' "$PB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "回调后 status 应为 paid（状态落库）"
  # 7) 幂等：重复回调仍 SUCCESS，不产生新行、状态不变
  NOTIFY2="$(curl -s --noproxy '*' -X POST "$MB/mock/notify" \
    -H 'Content-Type: application/json' \
    -d "{\"notify_url\":\"$PB/api/pay/notify\",\"order_no\":\"$ONO\",\"amount_cents\":9900}")"
  echo "$NOTIFY2" | grep -q 'SUCCESS' || fail "重复回调应仍 SUCCESS: $NOTIFY2"
  [ "$(total_of "$PB/api/order")" = "1" ] || fail "重复回调不应产生新行"
  curl -s --noproxy '*' "$PB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "重复回调后 status 仍应为 paid"
  echo "ok   支付：建单 -> HMAC 签名下单 -> code_url -> 回调验签 -> pending->paid -> 幂等 -> 篡改拒"

  # ---- 店面（shop）：商品列表 -> 购买下单 -> 收银台 -> 模拟支付 -> 结果页 ----
  # 场景：example-pay.json 现含 product 模块 + shop 段，gen_shop_block 生成店面路由。
  # /shop 首访自动播种 3 个演示商品；mock-pay 由应用请求 mock 网关 /mock/notify
  # 代投递签名回调（demo 专用，真实环境由微信服务器打 notify）。
  echo "==> 店面阶段：商品列表 -> 购买 -> 收银台 -> 支付落库 ..."
  SHOP_HTML="$(curl -s --noproxy '*' "$PB/shop")"
  echo "$SHOP_HTML" | grep -q '机械键盘' || fail "店面应播种演示商品: $(echo "$SHOP_HTML" | head -5)"
  echo "$SHOP_HTML" | grep -q '¥399.00' || fail "店面价格应格式化为元（分->x.xx）"
  curl -s --noproxy '*' -o /dev/null "$PB/shop/buy/1" || fail "购买请求失败"
  SONO="$(curl -s --noproxy '*' "$PB/api/order" | grep -oE '"order_no":"SHOP-[^"]*"' | head -1 | sed 's/"order_no":"//;s/"$//')"
  [ -n "$SONO" ] || fail "购买应产生 SHOP-* 订单"
  PAY_HTML="$(curl -s --noproxy '*' "$PB/shop/pay/$SONO")"
  echo "$PAY_HTML" | grep -q 'weixin://wxpay/bizpayurl' || fail "收银台应展示 code_url: $(echo "$PAY_HTML" | head -8)"
  curl -s --noproxy '*' -o /dev/null "$PB/shop/mock-pay/$SONO" || fail "模拟支付请求失败"
  curl -s --noproxy '*' "$PB/shop/result/$SONO" | grep -q '支付成功' || fail "模拟支付后结果页应为支付成功"
  curl -s --noproxy '*' "$PB/api/order?q=$SONO" | grep -q '"status":"paid"' || fail "店面支付后订单应落库 paid"
  # ---- 幂等（ik）：同 ik 重复点击/刷新复用同一笔 pending 单；已支付则开新单（重买）----
  # 用户明确诉求：避免重复下单。商品列表「购买」链接带 ik（幂等 Key）= id-now()，
  # 下单 GET /shop/buy/:id?ik= 复用同一笔 pending 单；已支付后再点同 ik 开新单（SHOP-<ik>-r<ts>）。
  echo "==> 幂等（ik）阶段：重复下单复用同一笔 pending 单，已支付开新单 ..."
  IK="IDEM-$(date +%s%N)"
  [ "$(code "$PB/shop/buy/1?ik=$IK")" = "200" ] || fail "幂等首购应 200"
  IDEM_ONO="SHOP-$IK"
  curl -s --noproxy '*' "$PB/api/order?q=$IDEM_ONO" | grep -q "\"order_no\":\"$IDEM_ONO\"" \
    || fail "幂等：应已创建 $IDEM_ONO"
  curl -s --noproxy '*' "$PB/api/order?q=$IDEM_ONO" | grep -q '"status":"pending"' \
    || fail "幂等：首单应 pending"
  # 刷新 / 重复点击（同一 ik）-> 复用同一笔，不产生新行
  [ "$(code "$PB/shop/buy/1?ik=$IK")" = "200" ] || fail "幂等重复点击应 200"
  [ "$(total_of "$PB/api/order?q=$IDEM_ONO")" = "1" ] \
    || fail "幂等：同一 ik 重复下单不应产生新订单行（total 应为 1）"
  # 模拟支付 -> paid
  curl -s --noproxy '*' -o /dev/null "$PB/shop/mock-pay/$IDEM_ONO" || fail "幂等模拟支付请求失败"
  curl -s --noproxy '*' "$PB/api/order?q=$IDEM_ONO" | grep -q '"status":"paid"' \
    || fail "幂等：模拟支付后应为 paid"
  # 已支付后再次同 ik -> 开新单（重买），订单号带 -r 后缀、状态 pending
  curl -s --noproxy '*' -o /dev/null "$PB/shop/buy/1?ik=$IK" || fail "幂等已支付后重买请求失败"
  REBUY="$(curl -s --noproxy '*' "$PB/api/order" | grep -oE "SHOP-$IK-r[0-9]+" | head -1)"
  [ -n "$REBUY" ] || fail "幂等：已支付后同 ik 应开新单（SHOP-$IK-r<ts>）"
  curl -s --noproxy '*' "$PB/api/order?q=$REBUY" | grep -q '"status":"pending"' \
    || fail "幂等：重买新单应 pending"
  echo "ok   幂等（ik）：首单 pending -> 同 ik 复用 -> 支付 -> 同 ik 重买开新单（SHOP-<ik>-r<ts>）"
  echo "ok   店面：商品列表 -> 购买下单 -> code_url 收银台 -> mock 支付 -> paid 落库"
else
  echo "SKIP 支付阶段: 无 python3"
fi

# ---- 支付阶段（PayPal）：建单 -> OAuth2 建单 -> approve_url -> return 捕获 -> 状态落库 -> 幂等 -> webhook ----
# 场景：example-paypal.json 生成带 pay 接线的工程（provider: paypal），复用微信阶段
# 已起的 mock 网关（mock_pay_gateway.py 同时支持 PayPal 端点）。OAuth2 的 Basic 凭证
# 用 Python 侧独立 base64 实现交叉验证；approve_url 指向 mock 收银台，curl -L 模拟
# 浏览器 approve 后 302 跳回应用的 /api/pay/return（带 token），应用捕获并改状态。
if command -v python3 >/dev/null 2>&1; then
  echo "==> 支付阶段(PayPal)：生成 example-paypal.json 工程 ..."
  kill "$PID" 2>/dev/null; wait "$PID" 2>/dev/null; PID=""
  PP_APP_PORT="${E2E_PP_PORT:-18096}"
  PP_MOCK_PORT="${E2E_PP_MOCK_PORT:-18098}"   # 独立端口起 PayPal mock（避免与微信阶段 mock/旧孤儿冲突）
  PP_SECRET="${E2E_PAYPAL_SECRET:-e2e-mock-key}"
  PP_CLIENT_ID="AUmock_client_id_sandbox_001"
  PPB="http://127.0.0.1:$PP_APP_PORT"
  PMB="http://127.0.0.1:$PP_MOCK_PORT"
  # 改写配置：out=gen-paypal，gateway=mock base，client_id/secret_env/webhook_path 对齐
  python3 - "$PP_CLIENT_ID" <<'PY' || { echo "E2E FAIL: 改写 PayPal 配置失败"; exit 1; }
import json, sys
cfg = json.load(open('example-paypal.json'))
cfg['out'] = './gen-paypal'
cfg['pay']['client_id'] = sys.argv[1]
cfg['pay']['secret_env'] = 'PAYPAL_KEY'
cfg['pay']['mode'] = 'sandbox'
cfg['pay']['webhook_path'] = '/api/pay/webhook'
json.dump(cfg, open('/tmp/nsgm-e2e-paypal-config.json', 'w'))
PY
  rm -rf gen-paypal
  rm -f "$PAYPAL_DB"
  "$LUME" main.lume /tmp/nsgm-e2e-paypal-config.json >/dev/null 2>&1 \
    || { echo "E2E FAIL: example-paypal.json 生成失败"; exit 1; }
  # PayPal mock：独立端口，显式传 client_id/secret（与生成配置一致），避免旧孤儿干扰
  MOCK_PAY_PORT="$PP_MOCK_PORT" MOCK_PAY_SECRET="$PP_SECRET" \
    MOCK_PAYPAL_CLIENT_ID="$PP_CLIENT_ID" MOCK_PAYPAL_CLIENT_SECRET="$PP_SECRET" \
    python3 scripts/mock_pay_gateway.py >/tmp/nsgm-mock-gw-pp.log 2>&1 &
  PP_MOCK_PID=$!
  # 应用：PAY_GATEWAY 指向本阶段独立起的 PayPal mock；client_secret 走
  # PAYPAL_KEY（避开部分环境对含 SECRET/TOKEN 的变量名过滤，同微信用 PAY_KEY）
  ( cd gen-paypal && PORT="$PP_APP_PORT" HOST=127.0.0.1 WORKERS=1 \
      NSGM_DB="$PAYPAL_DB" PAYPAL_KEY="$PP_SECRET" \
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
  # 3) 模拟浏览器 approve：跟 302 跳回 app /api/pay/return?token=...&order_no=... -> 捕获 -> paid
  RT="$(curl -s --noproxy '*' -L -o /dev/null -w '%{http_code}' "$APPROVE_URL")"
  [ "$RT" = "200" ] || fail "approve 跳转后 return 应 200 (got $RT)"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "PayPal 捕获后 status 应为 paid"
  # 4) 幂等：重复 approve（同 token）-> 仍 paid，不产生新行
  RT2="$(curl -s --noproxy '*' -L -o /dev/null -w '%{http_code}' "$APPROVE_URL")"
  [ "$RT2" = "200" ] || fail "重复 approve 应仍 200"
  [ "$(total_of "$PPB/api/order")" = "1" ] || fail "重复 approve 不应产生新行"
  curl -s --noproxy '*' "$PPB/api/order?q=$ONO" | grep -q '"status":"paid"' \
    || fail "重复 approve 后 status 仍应为 paid"
  # 5) webhook 负例：坏签名 -> 401
  BAD_WH="$(curl -s --noproxy '*' -X POST "$PPB/api/pay/webhook" \
    -H 'Content-Type: application/json' \
    -d '{"verify_id":"x","verify_ts":"1","verify_sign":"deadbeef","payload":"{}"}')"
  echo "$BAD_WH" | grep -q 'signature mismatch' || fail "PayPal webhook 坏签名应拒: $BAD_WH"
  echo "ok   支付(PayPal)：建单 -> OAuth2 建单 -> approve_url -> return 捕获 -> pending->paid -> 幂等 -> webhook 验签"
else
  echo "SKIP 支付阶段(PayPal): 无 python3"
fi

echo "E2E PASS: 全部探针通过 (SSR / 静态 / CRUD / 搜索 / 通配符转义 / 分页 / qs_int 兜底 / 迁移 / 微信支付全链路 / PayPal 全链路)"
exit 0
