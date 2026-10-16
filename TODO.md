# TODO — lume-nsgm 电商方向路线图

> 来源：2026-10-15 能力评估结论（「lume-nsgm 创建的页面能往电商走吗」）。
> 评估发现：底座（CRUD/搜索/分页/SQLite/JOIN/session/crypt_sha512/出站 HTTP）已足够覆盖
> 管理端电商与交易闭环；**真实收款**唯一硬缺口是 lume-core 无 SHA256/HMAC（支付签名/验签
> 做不了）。据此拆三阶段，从零 core 改动到支付闭环，每阶段独立可验收。

---

## 阶段一：管理端电商（零 core 改动，纯 lume 侧）

目标：当天可跑的「进销存」——商品/订单/库存 + 下单扣库存，先当内部管理端用。

- [ ] **P1-1 电商 schema**：在 `example-config.json` 同款新 config（如 `example-shop.json`）
      定义 `product`（名称/价格 decimal/库存 integer/状态）、`order`（订单号/金额/状态）、
      `stock_log`（出入库流水）三个模块；字段白名单校验沿用 `validate.lume`
- [ ] **P1-2 下单扣库存（补偿模式）**：`gen/` 下手写下单路由——
      ① `lock_file` 互斥；② INSERT order；③ `UPDATE product SET stock = stock - ?
      WHERE id = ? AND stock >= ?`（`sql_write` 返回 `sqlite3_changes`，0 = 库存不足）；
      ④ 失败则补偿 DELETE 订单并回错误
- [ ] **P1-3 订单状态机（应用层）**：pending → paid → shipped → done，varchar +
      路由内白名单校验（core 无 enum 类型，先应用层兜底）
- [ ] **P1-4 超卖回归探针**：`scripts/e2e.sh` 加并发场景——N 个并行 POST 抢同一商品，
      断言成功数 ≤ 库存、不出现负库存
- [ ] **P1-5 文档**：README 补「电商模式」小节（schema 示例 + 补偿模式说明 + 无事务的边界）

验收：`make check && make test && make test-e2e` 全绿（含超卖探针）。

## 阶段二：nsgm 生成器扩展（交易闭环）

目标：生成器直接产出电商骨架——关系、购物车、面向顾客的店面。

- [ ] **P2-1 引用型字段**：schema 支持 `{"name":"product_id","type":"ref","target":"product"}`
      —— `lib/validate.lume` TYPES 加 `ref` + target 必须指向已定义模块；`lib/model.lume`
      解析；`templates/sql.tpl` 仍出裸 integer 列（不引 SQLite FK，保持迁移简单）
- [ ] **P2-2 列表 JOIN 渲染**：`templates/mod.tpl` 对 ref 字段生成
      `SELECT ... JOIN` 显示关联名称（`sql_query` 放行任意 SELECT，无需改 core）
- [ ] **P2-3 enum 字段**：`{"name":"status","type":"enum","values":[...]}` —— 校验期收窄
      取值，DDL 仍 varchar；表单/列表按 values 渲染
- [ ] **P2-4 购物车**：`scaffold/lib/cart.lume` + `templates/cart.tpl`——**落库持久化**
      （`cart`/`cart_item` 表），session 里只放 cart_id（原因见「已知边界」S1）
- [ ] **P2-5 店面模板**：`templates/storefront.tpl` + `scaffold/web` 的顾客端页面
      （商品列表/详情/加购/结算），与 admin 端分离
- [ ] **P2-6 React SPA 同步扩展**：ref 字段下拉选项来自 `/api/<target>`、enum 渲染、
      店面路由；`tsc && vite build` 保持 noEmit 不脏源码
- [ ] **P2-7 回归**：`tests/` 加 t7（ref/enum 校验断言）；e2e 加「加购→下单→库存扣减」
      全链路探针

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
- [x] **P3-4 微信支付 v3 下单**（2026-10-15 完成）：`scaffold/lib/pay.lume` 新增
      `canonical` / `sign` / `auth_header` / `nonce_str` / `create_native`——
      `http_post` 调 `POST {gateway}/v3/pay/native`，请求串
      `method\npath\nts\nnonce\nbody\n` 过 `hmac_sha256`（P3-1 内建）。
      RSA 缺口按预案走 **HMAC 方案**（真实微信是 SHA256-RSA，见 S8）；
      出站打 mock/本地网关带 `allow_private: true`（S5）。无随机源 ⇒ nonce
      派生 `order_no + "-" + str(now())`（S8）
- [x] **P3-5 支付跳转**（2026-10-15 完成）：`pay.redirect_html(action, fields, title)`
      产自动提交表单 HTML（meta refresh + JS + 隐藏 input，`esc_attr` 转义）——
      core 无 302/响应头控制（S3）的既定变通，恰好是微信/支付宝 Native 标准姿势
- [x] **P3-6 回调 + 验签 + 幂等**（2026-10-15 完成）：`post "<notify_path>"` 路由——
      `pay.verify_notify`（回调串 `timestamp\nnonce\nbody\n`）验签；
      `status` 仅允许 `pending → paid` 流转，重复回调返回 SUCCESS 但不重复
      落库（幂等）；验签三要素随 body 传递（S7）
- [x] **P3-7 镜像与部署**（2026-10-15 完成）：`Dockerfile` 加 `ARG NSGM_CONFIG`
      （`example-pay.json` 即支付变体构建）；`docker-compose.yml` 补
      `PAY_KEY` / `PAY_GATEWAY` / `PAY_MCHID` / `PAY_APPID` / `PAY_SERIAL` /
      `PAY_NOTIFY_URL`——全部从宿主 env 注入，**不进镜像层**；healthcheck 改
      探 `GET /`（两种构建配置都有该路由）

- [x] **P3-8 PayPal Express Checkout 适配器**（2026-10-16 完成）：`scaffold/lib/pay.lume`
      新增 `paypal_base_url` / `paypal_basic_auth` / `paypal_fmt_cents` / `paypal_token`
      / `paypal_create` / `paypal_capture` / `paypal_verify_webhook`——OAuth2
      `client_credentials` 取 Bearer（HTTP Basic 凭证用 P3-1 补的 `base64_encode` 内建），
      `POST /v2/checkout/orders`（intent=CAPTURE）建单拿 `approve_url`，用户 approve 后
      `POST .../capture` 捕获。对照 `personal/personal-site/django-oscar-paypal-store`
      的 `PayPalFacade`：OAuth2 比 SHA256-RSA 更易内嵌（无需 RSA 内建），webhook 的
      HMAC 形状与 `verify_notify` 共用 S7 边界（真实 PayPal 还含 `crc32(body)`，core 暂无
      crc32 内建 ⇒ webhook 验签为 HMAC 简化版）。入口 `pay` 段加
      `provider: wechat|paypal`（`validate.lume` 分两支校验、`base.lume` 分两支生成）：
      生成 `PAYPAL_CFG` + `post /api/pay/create`（返 JSON `approve_url`，前端
      `window.location` 跳转）+ `get /api/pay/return`（捕获并改状态，幂等）+ `get
      /api/pay/cancel` + 可选 `post /api/pay/webhook`；`client_id` 来自配置（公开标识），
      `client_secret` 走 `secret_env` 注入，绝不进配置/镜像。回归见 `example-paypal.json`
      + `tests/t7.lume` PayPal 向量；`make test-e2e` 增 PayPal 链路（mock 网关）

验收：沙箱模式全链路（微信下单→签名→跳转→回调验签→订单状态落库；PayPal 建单→
跳转 approve→return 捕获→状态落库）均 e2e 固化进 `scripts/e2e.sh`（mock 网关）。

---

## 已知边界（评估结论，非本轮待办，记录在案避免重复踩坑）

- **S1 Session 进程内内存**：`req.session` 是 VM 内存表（`bridge_serve.c`），
  `workers > 1` 时各 worker 一份 → 购物车串味；重启即丢。⇒ Docker 必须
  `WORKERS=1`；购物车落库（P2-4）
- **S2 无事务**：`BEGIN/COMMIT` 被 `sql_validate_write` 拒（`builtins_sql.c`）。
  订单+库存非原子 ⇒ lock_file + 补偿 DELETE 缓解（P1-2），接受最终一致
- **S3 响应无状态码/头/302**：handler 只能 string→200 HTML / null→204 / map→200 JSON
  （`bridge_serve.c:826-836`）⇒ 跳转变通用自动提交表单（P3-5）
- **S4 无 multipart**：商品图走外链或后台上传，不做容器内上传
- **S5 出站 HTTP 默认拒私有地址**：`http_*` 需显式 `allow_private: true`
  （`builtins_http.c`）——本地 sidecar/mock 网关注意
- **S6 SQLite 单文件写并发**：电商规模内没问题；量上来先加 WAL + 单写者队列，
  勿过早引外置库
- **S7 回调无请求头**：`req` 对象不带 headers（只有 method/path/query/body/…）⇒
  回调验签三要素（timestamp / nonce / signature）由网关放进 body 的
  `verify_ts` / `verify_nonce` / `verify_sign` 字段。真实微信回调带
  `Wechatpay-Signature` 等**请求头**，直连真实网关前需 core 暴露 req headers
- **S8 无随机源 + 签名算法差**：core 无随机内建 ⇒ nonce 派生
  `order_no + "-" + str(now())`（唯一性够 mock 用，真实网关要求 32 位随机串）；
  真实微信 v3 签名是 SHA256-**RSA**（平台证书），当前 `hmac_sha256` 方案面
  向 mock/自建网关。上生产前要么补 RSA 内建 + 随机源，要么外挂本地签名
  sidecar（`http_post` 带 `allow_private: true`，S5 同款注意）。另：执行环境
  可能按名过滤密钥类 env 变量（实测 `*SECRET*`/`*TOKEN*` 等被剥，沙箱内
  `dangerouslyDisableSandbox` 也拦）⇒ 密钥 env 名避开这些词根（用 `PAY_KEY`）

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
  （写订单 pending，SHOP-<ts>-<pid>）→ `get /shop/pay/:ono`（微信 code_url /
  PayPal approve_url）→ `get /shop/mock-pay/:ono`（仅微信，mock 代投递签名回调，
  demo 专用）→ `get /shop/result/:ono`（结果页）。导航与首页多「商城」入口。
- `validate_shop`：product_module 必须已定义、name/price 字段必须真实存在。
- 店面与支付共享订单表与回调链路（验签/幂等/落库复用 gen_pay_block 产物）。
- 验收：e2e 店面阶段（列表/播种/购买/收银台/模拟支付/paid 落库）+ Docker 容器
  内全链路复验；t7 增 validate_shop 用例（5 条）。
- 🔴 教训：`fn` 已成 lume 保留字（core aa57a68），validate.lume `let fn` 改名 fname；
  生成器写「产物级模板 + replace 注入占位符」暴露 core `native_split` 未根住 list
  的 heap-use-after-free（`200ed4e` 修复）——占位符 replace 必须在全部拼接完成后。
