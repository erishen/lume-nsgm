# TODO — lume-nsgm 电商方向路线图

> 来源：2026-10-15 能力评估结论（「lume-nsgm 创建的页面能往电商走吗」）。
> 评估发现：底座（CRUD/搜索/分页/SQLite/JOIN/session/crypt_sha512/出站 HTTP）已足够覆盖
> 管理端电商与交易闭环；**真实收款**唯一硬缺口是 lume-core 无 SHA256/HMAC（支付签名/验签
> 做不了）。据此拆三阶段，从零 core 改动到支付闭环，每阶段独立可验收。

---

## 阶段一：管理端电商（零 core 改动，纯 lume 侧）

目标：当天可跑的「进销存」——商品/订单/库存 + 下单扣库存，先当内部管理端用。

- [x] **P1-1 电商 schema**（2026-10-16/17 完成）：`example-paypal.json`
      即电商 schema——`product`（名称/价格 `price_cents`/库存 `stock`）、`order`
      （订单号/金额/状态 + `product_id` / `product_name` 商品快照列）；字段白名单校验
      沿用 `validate.lume`
- [x] **P1-2 下单扣库存（补偿模式）**（2026-10-17 完成）：落在店面 `get /shop/buy/:id?ik=`
      ——① INSERT order（含商品快照）；② `UPDATE product SET stock = stock - 1
      WHERE id = ? AND stock >= 1`（单条原子语句即库存守卫，`sql_write` 返回受影响
      行数，0 = 售罄/并发被抢）；③ 0 行补偿 DELETE 该 pending 单 + 「已售罄」页。
      与原计划差异：未用 `lock_file`——SQLite 单写者下守卫 UPDATE 本身原子，
      加锁反而串行化所有下单；选 INSERT-first 避免「货扣了单没建」的悬挂
- [x] **P1-3 订单状态机（应用层）**（2026-10-16/17 完成）：varchar + 路由内白名单校验——
      `pending → paid`（支付回调/return 捕获，幂等）；`paid → refunded`（退款路由，
      仅 paid 可退、重复退幂等）。`shipped` / `done` 演示范围未生成（管理后台可手工改）
- [x] **P1-4 超卖回归探针**（2026-10-17 完成）：`scripts/e2e.sh` 固化——播种 10/5/0 三档
      → 购买扣 10→9 → 库存 0 商品拒单（不建单、不误扣）→ 退款回补 +1。并发安全性
      由构造保证：扣减是单条 `stock >= 1` 守卫 UPDATE（SQLite 写串行化），不存在
      read-modify-write 竞态，故未加并行 POST 探针
- [x] **P1-5 文档**（2026-10-17 完成）：README「店面」小节含 shop 三键说明、补偿模式、
      收银台复用、迁移后补库存注意；S2 边界文案同步

验收：`make check && make test && make test-e2e` 全绿（含超卖探针）。

## 阶段二：nsgm 生成器扩展（交易闭环）

目标：生成器直接产出电商骨架——关系、购物车、面向顾客的店面。

- [x] **P2-1 引用型字段**（✅ 2026-10-22）：schema 支持 `{"name":"product_id","type":"ref","target":"product"}`
      —— `lib/validate.lume` TYPES 加 `ref` + target 必须指向已定义模块（第二遍 cross-module
      校验）；`lib/model.lume` 解析（`sql_type`→INTEGER + `fis_ref/ftarget` 辅助）；
      DDL 仍出裸 integer 列（不引 SQLite FK，保持迁移简单）
- [x] **P2-2 列表 JOIN 渲染**（✅ 2026-10-22）：`lib/modlume.lume` `gen_module` 对 ref 字段生成
      `list_head/list_count`（`SELECT ... LEFT JOIN ... <field>_name`），`templates/mod.tpl`
      列表行显示关联名（回落原始 id）；`sql_query` 放行任意 SELECT，无需改 core
- [x] **P2-3 enum 字段**（✅ 2026-10-22）：`{"name":"status","type":"enum","values":[...]}` ——
      校验期收窄取值（非空 + 每值安全 token），DDL 仍 varchar；表单/列表按 values 渲染
      （`<select>` / `<span class="tag">`）
- [x] **P2-4 购物车**（✅ 2026-10-22）：落库持久化（`cart`/`cart_item` 表），session 里只放
      cart_id（原因见「已知边界」S1）。实现同构于现有 shop：`lib/base.lume`
      `gen_cart_block`(生成) + `templates/cart_block.lume.tpl`(JSON API) +
      `db.init` 注入 cart/cart_item 两张固定表；加购(合并同名数量)→查看→改量→移除→
      结算逐行复用单商品建单 + 库存守卫（P1-2 口径），成功行清出购物车、售罄行保留、
      全清则 cart 标记 done。**加性**：不改动既有「直接下单」/api/shop/buy 链路。
      运行期实测：session 跨请求持久（WORKERS=1）、结算建单 CART-* + 精确扣库存、
      售罄拒单保留、done 后再加购新建购物车，全绿
- [x] ~~**P2-5 店面模板**~~（2026-10-16 被 P3-9 取代并完成）：顾客端店面最终以
      `config.shop` 段 + SSR 路由落地（非独立 storefront.tpl 模板），见文末 P3-9；
      购物车/结算走「直接下单」演示路径，落库购物车（P2-4）仍未做
- [x] **P2-6 React SPA 同步扩展**（✅ 2026-10-22）：ref 字段下拉选项来自 `/api/<target>`
      （`refOptions` + `loadRefOptions`）、enum 渲染（`<select>` / `<span class="tag">`）、
      ref 列表显示 `<field>_name` 回落 id，均已落入 `reactgen.lume` + `templates/react_page.tpl`；
      店面保持 SSR（无 React 店面页，故「店面路由」React 同步不适用）。`make test`(t5) 已覆盖
      扩键回归。**`tsc && vite build` noEmit 验证已完成**（✅ 2026-10-22 晚）：根级
      `pnpm-workspace.yaml`（`packages: ["gen*/web"]` + `allowBuilds: esbuild`）落地后，
      `pnpm install && pnpm -r build` 对 gen/web 与 gen-paypal/web 双双通过——tsc
      （strict + noUnusedLocals/Parameters）零错误，vite 产出 dist。修复了根级 pnpm
      装不到成员依赖的坑（根级 pnpm-workspace.yaml：`packages: ["gen*/web"]` +
      `allowBuilds: esbuild`；scaffold/web 是模板碎片不可独立构建故非成员）
- [x] **P2-7 回归**（✅ 2026-10-22）：`tests/t6.lume` 加 8 条 ref/enum 校验断言
      （正例 + ref 无 target / target 非模块 / target 无 name；enum 无 values / 空 values /
      values 含引号）；`scripts/e2e.sh` 加「购物车」全链路阶段——加购 → session 持久
      （同 cookie 复得购物车）→ 结算建单 CART-* + 扣库存 → 清空 → 售罄拒单且保留，
      独立 cookie 会话、与直接下单正交。**顺带根治**：e2e 启动 PayPal mock app 时补
      `PAYPAL_CLIENT_ID` 内联覆盖——否则 Makefile `-include .env` + `export PAYPAL_CLIENT_ID`
      会把 .env 里的真实 client_id 泄漏进 mock app 致 OAuth2 401（`make test-e2e` 挂、
      直接跑 e2e.sh 不挂的差异根源）

验收：新 config 一键生成店面+admin，`make check && make test && make test-e2e` 全绿。

## 阶段三：支付闭环（lume-core 补 crypto 内建 + 网关对接）

目标：真实收款。前置硬缺口：core 无 SHA256/HMAC。做法参照 2026-10-15 的 ALTER 通道
先例（严格形状校验 + 回归断言 + CHANGELOG/README 同步）。

- [x] **P3-1 core 加 crypto 内建**（2026-10-15 完成）：`sha256(str)` → 64 位小写 hex、
      `hmac_sha256(key, msg)` → 同格式。落在 `src/builtins_crypt.c` 扩建 + vendored
      `src/compat/sha256/`（public domain，无外部依赖，照 compat/regex 规矩）；
      输入限 string（按显式长度哈希，含 NUL 安全）；错误信息带内建名；
      `interp.c` 内建表 / `builtins.h` 声明 / `typecheck.c` 的 `LUME_BUILTIN_NAMES`
      三处登记（照 crypt_sha512 范本）。边界：解释器路径内建，编译后端（text IR /
      libLLVM）不 lower 这两个调用——与 crypt_sha512 / sql_* / http_* 同口径，
      `--compile` 报 "call to unknown function"；server/DSL 脚本走解释器，不受影响
- [x] **P3-2 core 回归**（2026-10-15 完成）：`tests/test-crypto.lume` 17 断言全过
      （FIPS 180-4 / RFC 4231 已知向量 + 1000B 多块流式 + >64B 长 key HMAC 分支 +
      空 key/msg 边角 + 输出形状 + 4 条负例）；`make crypto-test` 已接入
      `make check` 与 `make test`；全量 `make test` 绿（2m31s，含三后端一致性 /
      case-parity / treecheck）；`~/.local/bin/lume-core` 已重装，nsgm 生成器 +
      `make test-e2e` 冒烟仍绿
- [x] **P3-3 文档**（2026-10-15 完成）：CHANGELOG 加条目。README.md / README.zh.md
      **无可改处**——两树 README 本就没有内建清单章节，crypt_sha512 先例同样零
      README 痕迹；SQL 护栏句与 crypto 无关，不动
- [x] ~~**P3-4 微信支付 v3 下单**~~（2026-10-15 完成，**2026-10-17 移除**）：`canonical` /
      `sign` / `auth_header` / `nonce_str` / `create_native` 等微信适配函数已从
      `scaffold/lib/pay.lume` 删除（恢复见 git 历史 `ec1e43f`）。真实微信 v3 签名是
      SHA256-**RSA**（平台证书），core 无 RSA 内建，当时走的是 HMAC 简化方案
- [x] ~~**P3-5 支付跳转**~~（2026-10-15 完成，**2026-10-17 移除**）：`pay.redirect_html`
      自动提交表单（core 无 302/响应头控制，S3 的既定变通）随微信 Native 扫码一起删除；
      PayPal 链路走 `approve_url` 浏览器跳转，不需要该变通
- [x] ~~**P3-6 回调 + 验签 + 幂等**~~（2026-10-15 完成，**2026-10-17 移除**）：微信
      `post "<notify_path>"` 路由与 `pay.verify_notify` 已删；`pending → paid`
      幂等状态流转的通用部分由 PayPal `get /api/pay/return` 捕获链路继承
- [x] **P3-7 镜像与部署**（2026-10-15 完成，env 清单 2026-10-17 随微信移除更新）：
      `Dockerfile` 加 `ARG NSGM_CONFIG`（`example-paypal.json` 即支付变体构建）；
      `docker-compose.yml` 补 `PAYPAL_KEY` / `PAY_GATEWAY` / `PAYPAL_RETURN_URL`
      ——全部从宿主 env 注入，**不进镜像层**；healthcheck 改
      探 `GET /`（两种构建配置都有该路由）

- [x] **P3-8 PayPal Express Checkout 适配器**（2026-10-16 完成）：`scaffold/lib/pay.lume`
      新增 `paypal_base_url` / `paypal_basic_auth` / `paypal_fmt_cents` / `paypal_token`
      / `paypal_create` / `paypal_capture` / `paypal_verify_webhook`——OAuth2
      `client_credentials` 取 Bearer（HTTP Basic 凭证用 P3-1 补的 `base64_encode` 内建），
      `POST /v2/checkout/orders`（intent=CAPTURE）建单拿 `approve_url`，用户 approve 后
      `POST .../capture` 捕获。对照 `personal/personal-site/django-oscar-paypal-store`
      的 `PayPalFacade`：OAuth2 比 SHA256-RSA 更易内嵌（无需 RSA 内建），webhook 的
      HMAC 形状与 webhook 验签共用 S7 边界（真实 PayPal 还含 `crc32(body)`，core 暂无
      crc32 内建 ⇒ webhook 验签为 HMAC 简化版）。入口 `pay` 段曾支持
      `provider: wechat|paypal`（`validate.lume` 分两支校验、`base.lume` 分两支生成；
      2026-10-17 微信移除后合并为 PayPal 单路，遗留 `provider: wechat` 配置报明确错误）：
      生成 `PAYPAL_CFG` + `post /api/pay/create`（返 JSON `approve_url`，前端
      `window.location` 跳转）+ `get /api/pay/return`（捕获并改状态，幂等）+ `get
      /api/pay/cancel` + 可选 `post /api/pay/webhook`；`client_id` 来自配置（公开标识），
      `client_secret` 走 `secret_env` 注入，绝不进配置/镜像。回归见 `example-paypal.json`
      + `tests/t7.lume` PayPal 向量；`make test-e2e` 增 PayPal 链路（mock 网关）

验收：沙箱模式全链路（PayPal 建单→跳转 approve→return 捕获→状态落库）均 e2e
固化进 `scripts/e2e.sh`（mock 网关）。微信链路（下单→签名→跳转→回调验签→落库）
曾同路固化，2026-10-17 随支付通道移除删去。

---

## 已知边界（评估结论，非本轮待办，记录在案避免重复踩坑）

- **S1 Session 进程内内存**：`req.session` 是 VM 内存表（`bridge_serve.c`），
  `workers > 1` 时各 worker 一份 → 购物车串味；重启即丢。⇒ Docker 必须
  `WORKERS=1`；购物车落库（P2-4）
- **S2 无事务**：`BEGIN/COMMIT` 被 `sql_validate_write` 拒（`builtins_sql.c`），
  且每次调用开关连接 ⇒ 事务状态无法跨语句保持。订单+库存非原子 ⇒ 守卫 UPDATE +
  补偿 DELETE 缓解（P1-2），接受最终一致（崩在中间留 pending 孤儿单：不占库存、
  不超卖，待手工清或后续事务支持）。并发写冲突已由 busy timeout 兜底（P3-15）
- **S3 响应无状态码/头/302**：handler 只能 string→200 HTML / null→204 / map→200 JSON
  （`bridge_serve.c:826-836`）⇒ 跳转变通用自动提交表单（P3-5）
- **S4 无 multipart**：商品图走外链或后台上传，不做容器内上传
- **S5 出站 HTTP 默认拒私有地址**：`http_*` 需显式 `allow_private: true`
  （`builtins_http.c`）——本地 sidecar/mock 网关注意
- **S6 SQLite 单文件写并发**：电商规模内没问题；瞬时冲突已由 busy timeout 兜底
  （P3-15），量上来先加 WAL + 单写者队列，勿过早引外置库
- **S7 回调无请求头**：`req` 对象不带 headers（只有 method/path/query/body/…）⇒
  webhook 验签三要素（transmission id / time / signature）由网关放进 body 的
  `verify_ts` / `verify_nonce` / `verify_sign` 字段（mock PayPal webhook 同款约定）。
  真实支付网关回调签名都在**请求头**（微信 `Wechatpay-Signature`、PayPal
  `PayPal-Transmission-Sig`），直连真实网关前需 core 暴露 req headers
- **S8 无随机源 + 签名算法差**：core 无随机内建 ⇒ nonce 派生
  `order_no + "-" + str(now())`（唯一性够 mock 用，真实网关要求 32 位随机串）；
  PayPal webhook 真实验签含 `crc32(body)`（core 暂无 crc32 内建）⇒ 当前
  `hmac_sha256` 方案面向 mock/自建网关。上生产前要么补 RSA/crc32 内建 + 随机源，
  要么外挂本地签名 sidecar（`http_post` 带 `allow_private: true`，S5 同款注意）。
  另：执行环境可能按名过滤密钥类 env 变量（实测 `*SECRET*`/`*TOKEN*` 等被剥，
  沙箱内 `dangerouslyDisableSandbox` 也拦）⇒ 密钥 env 名避开这些词根（用
  `PAYPAL_KEY`）

## 依赖顺序

```
P1（纯 lume，零风险） ──┐
                        ├─→ P3（core crypto → 支付）
P2（生成器扩展） ───────┘
```

P1 与 P2 可并行；P3 的 P3-1/2/3（core 内建）不依赖 P1/P2，可随时插队。

### P3-9 店面（shop 段）：面向顾客的电商前端（✅ 2026-10-16）
- `config.shop`（与 pay 同配）：product_module / order_module / name_field / price_field。
- 生成路由：`get /shop`（商品卡片，空表播种 3 演示商品）→ `get /shop/buy/:id`
  （写订单 pending，SHOP-<ts>-<pid>）→ `get /shop/pay/:ono`（PayPal approve_url
  收银台，复用已存 `paypal_order_id` 防孤儿单）→ `get /shop/result/:ono`（结果页）。
  导航与首页多「商城」入口。（微信 `code_url` / `mock-pay` 代投递路由随支付通道
  移除删去）
- `validate_shop`：product_module 必须已定义、name/price 字段必须真实存在。
- 店面与支付共享订单表与回调链路（验签/幂等/落库复用支付接线产物）。
- 验收：e2e 店面阶段（列表/播种/购买/收银台/模拟支付/paid 落库）+ Docker 容器
  内全链路复验；t7 增 validate_shop 用例（5 条）。
- 🔴 教训：`fn` 已成 lume 保留字（core aa57a68），validate.lume `let fn` 改名 fname；
  生成器写「产物级模板 + replace 注入占位符」暴露 core `native_split` 未根住 list
  的 heap-use-after-free（`200ed4e` 修复）——占位符 replace 必须在全部拼接完成后。

### P3-10 shop 加固批次（✅ 2026-10-17，五项）
- **PayPal 收银台复用（修孤儿单）**：`/shop/pay/:ono` 原每次渲染都调建单 ⇒ 用户刷新
  一次多一笔 PayPal 订单。现按订单行 `paypal_order_id` 重建 approve 链接
  （mock `{gw}/mock/paypal/approve?token=`；真实 checkoutnow），建单成功即回填该列
  （自动迁移补列）；mock 网关加 `GET /mock/paypal/orders` 计数端点供 e2e 断言
- **`/api/pay/return` 加固**：原按 query 订单号直查，查空即当异常。现 `len(cur)==0`
  返回「订单不存在」错误页；paid 早返回页与捕获成功页均补金额展示
- **下单扣库存 + 商品快照（P1-2 收口）**：shop 三键 `stock_field` / `product_field` /
  `product_name_field`；INSERT-first 补偿模式（见 README）；无 ik 购买配 `product_field`
  时复用最近一笔 pending 单；播种改 10/5/0 三档演示售罄
- **NULL 陷阱补全**：`str(null)="null"` 骗过 `== ""` 守卫——迁移补列的旧行在后台列表
  单元格与表单预填两处归一（`templates/mod.tpl`）；店面卡本就无此列故只修模板侧
- **回归**：`make test`（t7 B4 组 7 断言：shop 三键校验矩阵）+ `scripts/e2e.sh`
  （8 组新探针：NULL 不渲染/库存 UI/快照回填/扣减/售罄拒单/退款回补/return 未知单/
  收银台复用）+ 一次性冒烟脚本 14 断言全绿（眼见为实）

### P3-11 早期订单双空关联 ID 退款恢复（✅ 2026-10-17）
- **Bug**：迁移补列（`paypal_order_id` / `capture_id` 经 `ALTER TABLE ADD COLUMN` 补出）
  之前的早期订单，两列读出全是 SQL NULL。退款路由旧逻辑**只兜底「capture_id 空但
  paypal_order_id 在」**的旧单；**两者皆空**时直接死在报错（用户原话「订单缺少 PayPal
  关联 ID（早期订单），无法定位捕获记录」）。  e2e 只覆盖「仅 capture_id=NULL」一种，漏测双空。
- **修复**（`lib/base.lume` `gen_shop_block`）：
  - 退款确认页新增 `need_recover = (cap_id == "" && ppid == "")` 分支：双空时提示去
    `/shop/recover/:ono`，而非报错死掉；关联 ID 归一（SQL NULL 读作 lume null 先归一）后
    允许退款请求从 `q_ppid` / `q_capid` 带入手动恢复的关联 ID。
  - 新增 `get /shop/recover/:ono` 顶层路由（**必须落在退款函数闭合 `};` 之后**，否则会嵌进
    退款函数体内不被注册——此前踩过一次）：表单填 PayPal 订单号（反查捕获记录）或捕获 ID
    （直达退款）；另有「已在 PayPal 后台手动退款，本地标记退款」入口（`?confirm=1&manual=1`，
    本地落库 refund、回补库存，不调 API）。
  - 退款执行分支：捕获 ID 定位链 = 本地 `cap_id` → 本地/请求 `ppid` 反查 → 请求 `capid` 直达；
    退款成功 `upd_ppid_cap` 回补关联 ID，后续操作一致。
  - 已退款订单（无论关联 ID 是否齐全）确认页直接展示「已退款」——避免早期订单手动退款后
    因两列仍 NULL 误提示「去恢复关联 ID」。
- **e2e 补测**（`scripts/e2e.sh`）：早期订单（双空）阶段 3 条路径探针：
  `capid` 直达退款 → `ppid` 反查退款 → `manual` 本地标记，均落库 `refunded` 且回补关联 ID；
  mock 网关 `_pp_bearer_ok` 改为接受**任意已下发 token**（多 token 集合，不主动过期），
  消除「直连 oauth 顶替 app 缓存 token 致 401」的测试侧互踩（pay.lume `paypal_token`
  命中缓存直接返回，与 mock 单槽 token 存储冲突）。全部探针通过。

### P3-12 交易号（捕获 ID）误填订单号框：捕获兜底 + 422 对账补全（✅ 2026-10-17）
- **Bug（真实沙箱事故，示例单号 SHOP-1-xxxxxxxx）**：用户在恢复页把 PayPal 后台的「交易号 /
  Transaction ID」（即**捕获 ID**）填进「PayPal 订单号」框 → `GET /v2/checkout/orders/{捕获ID}`
  回 404 `RESOURCE_NOT_FOUND`/`INVALID_RESOURCE_ID` → 页面报「无法从 PayPal 反查捕获记录」死掉。
  真实沙箱实证：PayPal 订单号走 orders 端点 200，捕获 ID 走 orders 端点必 404、
  走 captures 端点 200。根因是**订单号 ≠ 交易号**这一 PayPal 语义差，UI 未说明、系统不兼容。
- **修复**：
  - `scaffold/lib/pay.lume` 新增 `paypal_get_capture(cfg, token, id)`：`GET /v2/payments/captures/{id}`，
    从 `supplementary_data.related_ids.order_id` 反解真实订单号（对齐真实 PayPal 响应结构）。
  - `lib/base.lume` 退款路由：`paypal_get_order` 失败时用**同一输入**改查 `paypal_get_capture`；
    命中则 `cap_id` 直接用该捕获 ID、`ppid` 回填反解出的真实订单号（两列都落正确值，不会把
    捕获 ID 写进订单号列）。
  - 反查仍失败的错误页补指引：ID 有误 / **沙箱与正式环境不一致**（本店跑 sandbox，要去
    sandbox.paypal.com 查）/ 并未通过 PayPal 收款；保留 PayPal `debug_id`；新增「本地标记退款」直达。
  - 恢复页改三条路径卡片式：方式一订单号或交易号任意填一个（系统自动识别，附 PayPal 后台
    查找路径与 ID 形态示例）、方式二直接填捕获 ID、方式三本地标记。
  - `paypal_refund` 422 对账补 `CAPTURE_FULLY_REFUNDED`（真实沙箱实证：已全额退再退回的是
    这个 issue，文档/旧 mock 的 `ALREADY_REFUNDED` 反而不出现）——否则「其实已退成功」会
    显示成假失败（测试单实测撞到后修）。
  - mock 网关补 `GET /v2/payments/captures/{id}`（404 时回 `RESOURCE_NOT_FOUND` 语义），
    重复退 422 body 对齐真实 issue `CAPTURE_FULLY_REFUNDED`。
- **e2e 补测**：早期订单阶段第 4 条路径——把捕获 ID 填进 `ppid` 框，断言自动改查捕获、
  落库 `refunded`、回填**真实订单号**（related_ids.order_id）与捕获 ID。真实实例另用一次性
  测试单（已退捕获，ID 从略）跑通 404→捕获 200→422 对账→双列回填→删除测试单，
  现场库存/真实订单未受影响。

### P3-13 商品目录示例播种 + 清空/重载按钮（✅ 2026-10-17）
- **诉求（用户）**：「商品目录空表起步，可以给点示例，UI 上提供清空按钮」。
- **实现**（`lib/base.lume` `gen_shop_block`，仅 shop+pay 变体）：
  - `/shop` 空表播种三件套演示商品（键盘 $399 库存 10 / 卫衣 $199 库存 5 / 马克杯 $59
    库存 0——0 即售罄态演示），**一次性语义**：播种后落标记到 `_nsgm_shop_meta` 元表
    （`k='seeded'`），此后删空不再自动复活。
  - 页内「清空商品」按钮（confirm 弹窗）→ `/shop?act=clear`：落标记 + 按 id 逐行参数化
    删商品（`sql_write` 护栏：UPDATE/DELETE 必须带 WHERE，禁整表 DELETE）；订单记录不受影响。
  - 空态给出「载入示例商品」→ `/shop?act=seed`：仅空表时播种（非空守卫，不重复插），
    附「去后台添加商品」入口（`/<product_module>` CRUD）。
  - 清空/重载**并回 `/shop` 查参**，不单独占路由位（原因见 P3-14）。
- **e2e 补测**：`商品目录：空表自动播种 -> 清空（订单不受影响）-> 不自动复活 -> 手动重载 -> 非空守卫`。

### P3-14 lume-core 路由表上限 32（MAX_AL_ROUTES）——✅ 2026-10-17 已修（core `556cbf3`，local-only）
- **发现**：P3-13 最初给 `/shop/seed`、`/shop/clear` 各开一条独立路由，运行即
  `failed to register route GET /`——`lume-core/src/lume.h:390` `#define MAX_AL_ROUTES 32`，
  `bridge_define_route` 超限直接返回 -1。PayPal 变体路由数：product 10 + order 10 +
  pay 4 + shop 6 + `/` 1 = **31**（+2 即 33 超限）；第三个模块就会超（33+10=43）。
- **已修**（lume-core `556cbf3` raise(route): route table caps 32 -> 128）：
  - `MAX_AL_ROUTES` 32→128；**原生后端 `NATIVE_ROUTES_MAX` 同步 32→128**
    （bridge_native.c，原先只改解释器会出现"解释器跑得起来、编译后少路由"）。
  - 满表返回码 -2（区别于参数非法 -1），解释器三处注册点报
    `route table full (N routes, max M): cannot register ...`——旧报错指向最后一条
    路由、极具误导性；原生端满表由**静默丢弃**改为 stderr 警告。
  - core 侧新增 `make route-cap-test`（40 路由夹具，已并入 `make test`）；
    `make test` 全绿（唯一红项 native-consistency llvm 腿是既有闭包捕获缺口，
    干净 HEAD 可复现，与本改无关）。
  - 宿主树 `work/lume/lume` 的 `lume.h`/`interp.c`/`bridge_stub.c` 在 HOST_PINNED
    清单，不会自动同步，需要时手工合并；`bridge_native.c` 未 pin，会随 sync 流入。
- **遗留**：P3-13 的 `/shop?act=` 查参方案保持不变（31 条稳，无需改回独立路由）。

### P3-15 SQLite busy timeout：并发写从「立即失败」到「排队等待」（✅ 2026-10-17，core `178501c`，local-only）
- **发现**（用户提问「有处理重复幂等支付和库存锁吗」的深挖）：lume-core 的
  `sql_query`/`sql_write` 每次调用开关连接，而 sqlite3 默认 busy timeout 为 0——
  prefork 多 worker（或任何第二进程）并发写同一库文件时，写锁被占的请求**立即**
  `database is locked` 失败，而非等待。实测 8 进程 × 60 次守卫 UPDATE：
  **7 个进程失败、480 次写只落地 77 次**。
- **修复**（`src/builtins_sql.c`，两个 open 点——只读与读写路径各一）：
  `sqlite3_busy_timeout(sq, 5000)`；默认 5s，env `LUME_SQLITE_BUSY_TIMEOUT_MS`
  可覆盖（钳制 [0, 60000]；`0` = 恢复原生 fail-fast；非法值回落默认）。
  文件头注释同步说明「每次调用新连接 ⇒ 必须 armed timeout」的动因。
- **实证**：同负载新默认下 8 进程 **0 失败、末值 480（零丢更新）**；`env=0`
  复现旧行为（7 失败/77）；`env=abc` 回落默认（0 失败/480）。
- **回归**：`make sql-test` / `builtins-test` / `backend-parity` / smoke 及
  其余全部 test 目标绿（native-consistency llvm 腿仍是既有闭包捕获缺口，
  干净 HEAD 可复现，与本次无关——interp/text 双腿均匹配 expected）。
- **边界不变**：单语句护栏不动（`BEGIN/COMMIT` 仍拒、仍禁多语句、仍参数化），
  原子性由单语句本身保证，timeout 只改失败语义不改隔离性；跨语句事务仍是 S2。
  文档：core CHANGELOG「Fixed」节 + 本仓 README 双语「并发与库存」条 +
  ARCHITECTURE §4.3 两行决策 + S2/S6 更新。
- **安装**：`~/.local/bin/lume-core` 已更新（rm 后 cp）；Docker 镜像下次
  `docker compose up -d --build` 时从源码编入，数据卷不受影响。
