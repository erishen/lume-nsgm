# lume-nsgm 架构文档

[English](README.md) · [简体中文](README.zh.md) · 架构文档（本文）

> 本文讲清两件事：**生成期**（本仓库的生成器如何把 JSON schema 变成工程）与**运行期**（生成的工程如何被 lume-core 跑起来）。阅读本文不需要先读源码，但接口/路由/行为细节以代码与测试为准。

## 1. 总览：两个阶段，两个世界

lume-nsgm 的全部工作分成两个互不重叠的阶段，由同一个 `lume-core` 二进制驱动：

```
┌─────────────────────────── 生成期（本仓库） ───────────────────────────┐
│                                                                        │
│   example-config.json / create / init                                  │
│          │  JSON schema（模块 + 字段定义）                              │
│          ▼                                                             │
│   main.lume ──► validate.lume ──► model.lume ──► 模板渲染 ──► scaffold  │
│   （CLI 入口）  （一次性全量校验）  （类型映射单一源）  （tpl/modlume/   │
│                                                reactgen）   （落盘）    │
│          │                                                             │
│          ▼                                                             │
│   gen/  ← 一套可运行工程（app.lume + modules + lib + web + www + sql）  │
└────────────────────────────────────────────────────────────────────────┘
                                   │
                                   ▼
┌─────────────────────────── 运行期（生成物） ───────────────────────────┐
│                                                                        │
│   lume-core gen/app.lume   单进程，同时是：                             │
│     · SSR 页面服务器（列表/新建/编辑/删除，表单 GET 提交，无 JS 依赖）  │
│     · REST API（/api/<module>，POST + JSON body）                       │
│     · 静态文件服务（docroot：SPA 构建产物 + www/ 回退资源）             │
│     · 支付对接端（/shop/* + /api/pay/*，PayPal Express Checkout）       │
│        │                                                               │
│        ▼                                                               │
│   SQLite（data/app.db，自动建表 + 自动补列迁移）                        │
└────────────────────────────────────────────────────────────────────────┘
```

设计上最关键的一条边界：**生成器的输出空间是封闭的**。AI（或人）只需要写 JSON schema，之后的一切——DDL、路由、页面、API、转义、分页——都由模板确定性产出。「AI 决定 schema，模板负责正确性」，这是整个项目存在的理由（详见 README 的 "Why it still matters in the AI era"）。

## 2. 生成期架构

### 2.1 CLI 入口（main.lume）

三种用法，按 `argv()` 分发：

| 命令 | 形态 | 用途 |
|---|---|---|
| `create` | `create <module> [db] [out]` | 命令行单模块生成（默认 `db=crm_demo`，`out=./gen`） |
| `init` | `init <module> [db] [out]` | 交互式字段录入（stdin 逐行读字段定义）后生成 |
| `batch` | `main.lume <config.json>` | **主用法**：读批量配置（多模块 + 全局设置），`make run` 即此模式 |

### 2.2 生成流水线

```
config.json
   │
   ▼
validate.lume ── 一次性全量校验，失败即退出（exit 1），不生成
   │   · JSON 合法性 / modules 非空 / 字段非空
   │   · 模块名、字段名匹配 [a-z][a-z0-9_]*   ← 名字会插进 DDL 和路由，
   │     白名单在此关闭注入面（"evil"; DROP TABLE x--" 类输入被拒）
   │   · 类型白名单（varchar/text/integer/decimal/boolean/date/datetime/timestamp）
   │   · 重名检测（路由冲突）
   ▼
model.lume ── 字段模型 + 类型映射的单一数据源
   │   · JSON 类型 → SQL 类型 → 表单控件 → 列表展示方式
   │   · 主键/自增/系统字段（create_date 等）的统一注入规则
   ▼
模板渲染（tpl.lume 驱动三个模板族）
   ├── mod.tpl          → 每模块：DDL + 数据驱动字段表 + 路由 + SSR 页面
   ├── sql.tpl          → CREATE TABLE DDL 导出（gen/sql/）
   └── react_page.tpl   → 每模块一个 <Module>Page.tsx（SPA 页面）
   ▼
scaffold.lume ── 文件树写入：静态基座（scaffold/）+ 生成内容组装成 gen/
```

### 2.3 各模块职责

| 文件 | 职责 | 要点 |
|---|---|---|
| `main.lume` | CLI 入口与命令分发 | create / init / batch 三模式 |
| `lib/validate.lume` | schema 一次性全量校验 | 注入防护 + 类型白名单 + 重名；错误带路径与修复提示（AI 可一轮修完） |
| `lib/model.lume` | 字段模型与类型映射 | **单一数据源**：SQL 类型、索引/搜索标记、表单控件都从这里出 |
| `lib/tpl.lume` | 极简模板引擎 | `{{var}}` / `{{#each}}` / `{{#if}}`，无求值能力——故意保持弱，避免第二门语言 |
| `lib/sql.lume` | SQL DDL 生成 | 模板渲染的消费者 |
| `lib/modlume.lume` | 模块生成器 | 数据驱动字段表 + 路由 + SSR 页面（普通 CRUD）与商城/订单/支付块（`pay` 配置存在时） |
| `lib/base.lume` | 运行时基座生成 | 生成 `app.lume`（server/route/run）、`lib/ui.lume`；支付变体时生成商城与支付路由块 |
| `lib/reactgen.lume` | React 前端生成器 | 每模块 SPA 页面 + api 客户端 |
| `lib/scaffold.lume` | 文件树写入 | mkdir / write_file 原语；静态基座复制进 gen/ |
| `lib/assert.lume` | 断言辅助 | ok/eq/fail；`main()` 返回失败计数即退出码 |

### 2.4 测试体系（生成期）

| 层 | 内容 |
|---|---|
| `tests/t1.lume` | model / sql 生成器（13 断言） |
| `tests/t2.lume` | modlume / reactgen 模块与前端生成器 |
| `tests/t3.lume` | 模板引擎（each / if / 变量替换） |
| `tests/t4.lume` | `sql_default()` 回归 |
| `tests/t5.lume` | React 前端生成器回归 |
| `tests/t6.lume` | schema 校验回归（16 断言） |
| `tests/t7.lume` | 支付回归（签名向量 / validate_pay / 字段 default） |
| `scripts/e2e.sh` | 起生成工程 + curl 跑 SSR/CRUD/搜索/分页/迁移/支付全链路 |
| `make check-privacy` | 发布前隐私自检（挂 `make test` 前置闸） |

## 3. 运行期架构（生成物 gen/）

### 3.1 目录结构

```
gen/
├── app.lume        # 入口：server(:port) + 全部 route 注册 + run
├── modules/        # 每模块一个 .lume（DDL + CRUD 实现）
├── lib/
│   ├── db.lume     # SQLite 存取（dsn / init / 分页 / 计数）
│   ├── ui.lume     # 页面骨架 + HTML 转义（ui.esc）+ 导航
│   └── pay.lume    # 支付库（仅支付变体；OAuth2/建单/捕获/查单/查捕获/退款/验签）
├── sql/            # 导出的 CREATE TABLE DDL（查阅/手工建库用）
├── web/            # Vite + React + TS SPA（主 UI，make run 自动 pnpm install）
├── www/            # SSR 静态样式 + 回退 JS（app.css / app.js）
├── data/           # SQLite 数据文件（app.db，env NSGM_DB 可覆盖）
└── README.run.md   # 生成工程的运行说明（随工程一起产出）
```

### 3.2 路由分层

单进程注册三类路由（lume-core 路由表上限 128，够用到单应用约 40 条业务路由 + 每模块 10 条）：

**（a）每模块 CRUD 路由（mod.tpl 生成，`/{ctrl}` 为模块名）**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/{ctrl}` | 列表页（SSR；搜索 + 分页 + 排序） |
| GET | `/{ctrl}/new` | 新建表单 |
| GET | `/{ctrl}/edit/:id` | 编辑表单 |
| GET | `/{ctrl}/save` | 表单提交落库（GET 提交，query_params 已解码） |
| GET | `/{ctrl}/del/:id` | 删除（确认后跳回列表） |
| GET/POST | `/api/{ctrl}` | REST 列表 / 创建 |
| GET | `/api/{ctrl}/:id` | REST 读单条 |
| POST | `/api/{ctrl}/update/:id` | REST 更新 |
| POST | `/api/{ctrl}/delete/:id` | REST 删除 |

**（b）商城与支付路由（base.lume 生成，仅支付变体）**

| 方法 | 路径 | 用途 |
|---|---|---|
| GET | `/shop`（`?act=seed` / `?act=clear`） | 店面（空目录一键载入示例 / 清空；`_nsgm_shop_meta` 记住是否已 seed） |
| GET | `/shop/buy/:id?ik=` | 下单页（INSERT-first + 补偿扣库存，售罄走售罄页） |
| GET | `/shop/pay/:ono` | 收银台（复用已建单：有 `paypal_order_id` 直接重建 approve 链接，不重复建单） |
| GET | `/api/pay/return?order_no=&token=` | PayPal 回跳：捕获 → 订单转 paid → 回填 `paypal_order_id` + `capture_id` |
| GET | `/api/pay/cancel?order_no=` | 用户取消支付 |
| POST | `/api/pay/create` | 程序化建单（SPA/API 调用方） |
| GET | `/shop/result/:ono` | 支付结果查询（轮询友好） |
| GET | `/shop/refund/:ono?confirm=1` | 退款（仅 paid；重复退幂等；成功后回补库存 +1） |
| GET | `/shop/recover/:ono` | 关联 ID 恢复（订单号/交易号自动识别，早期单补录回填） |

**（c）静态与 SPA**：docroot 同时服务 `web/` 构建产物（`/spa/`，hash 路由、同源 `/api`）与 `www/`（SSR 页面样式与回退 JS）。SSR 页面零 JS 依赖；SPA 是增强而非前提。

### 3.3 两条请求路径

```
浏览器 ──SSR 表单（GET 提交）──► route handler ──► sql_query/sql_write ──► SQLite
       ◄── HTML 页面（ui.page）──┘                      ▲
                                                       │
SPA（fetch） ──POST /api/<module>（JSON body）──► json() 解析 ──┘
```

- SSR 走 query_params（lume-core 已 URL 解码），**GET 提交**即可完成增删改——无需 CSRF token、无需前端 JS；
- 程序化写入走 POST + JSON body；
- 搜索词中的 `%` / `_` 按字面转义（`LIKE ? ESCAPE "\"`），永不当通配符。

### 3.4 数据层

| 关注点 | 实现 |
|---|---|
| 存储 | SQLite 唯一内建后端（lume-core `sql_query` / `sql_write` 内建） |
| 建表 | 首次启动 `CREATE TABLE IF NOT EXISTS` |
| 迁移 | 自动补列（新增字段生成 `ALTER TABLE ... ADD COLUMN` 迁移语句） |
| 写安全 | `sql_write` 的 WHERE 护栏：UPDATE/DELETE 无 WHERE 一律拒绝（防全表误操作） |
| 分页/计数 | db.lume 统一助手（page/page_size/qs_int 回退） |
| NULL 陷阱 | SQL NULL 读出为 lume null，`str(null)` 得字面量 `"null"` —— 列表与表单回显前先归一化 |
| 金额 | 整数分存储，`fmt_cents` 转 `"x.xx"`（无浮点误差） |
| bool 陷阱 | lume 运行时 `bool == int` 恒 false —— 一律用 `!= true` 比较（pay.lume 通篇遵守） |

## 4. 支付子系统（支付变体）

配置里出现 `pay` 段时，生成器在 `gen/` 里追加商城 + 支付块，并复制 `scaffold/lib/pay.lume` 为 `gen/lib/pay.lume`。

### 4.1 pay.lume 函数面

| 函数 | 职责 |
|---|---|
| `paypal_token(cfg)` | OAuth2 client_credentials 取 Bearer token；**进程内缓存**（有效期约 9h，保守 30000s 阈值），避免每次建单握手 |
| `paypal_create_order(cfg, ...)` | POST `/v2/checkout/orders`（intent=CAPTURE），返回 approve_url + paypal_order_id |
| `paypal_approve_url(cfg, id)` | 由订单 ID **重建** approve 链接（mock: `{gw}/mock/paypal/approve?token=`；真实: `checkoutnow?token=`） |
| `paypal_capture(cfg, id)` | POST `/v2/checkout/orders/{id}/capture`，返回 capture_id |
| `paypal_get_order(cfg, id)` | GET `/v2/checkout/orders/{id}`，从 purchase_units 反查捕获 ID（退款兜底） |
| `paypal_get_capture(cfg, id)` | GET `/v2/payments/captures/{id}`，用 `related_ids.order_id` **反解订单号**（用户填交易号当订单号的兜底） |
| `paypal_refund(cfg, capture_id)` | POST `/v2/payments/captures/{id}/refund`，默认全额退 |
| `paypal_verify_webhook(...)` | 简化 HMAC-SHA256 验签（沙箱等价实现，见 4.3 边界） |

### 4.2 订单状态机

```
pending ──捕获成功──► paid ──退款成功──► refunded
   │                    ▲
   └──用户取消──► canceled（本地单；PayPal 侧订单未 approve 前可反复支付）
```

- `pending`：本地已建单、未捕获；此状态下收银台可复用（重建 approve 链接）；
- `paid`：捕获成功，回填 `paypal_order_id` + `capture_id` 两列；
- `refunded`：网关退款成功（或用户在 PayPal 后台手动退款后本地标记）。

### 4.3 关键设计决策（含踩过的坑）

| 决策 | 理由 |
|---|---|
| **收银台复用**：`/shop/pay/:ono` 有 `paypal_order_id` 就重建 approve 链接，不重新建单 | 否则用户刷新一次收银台就产生一个孤儿 PayPal 订单 |
| **INSERT-first + 补偿扣库存**：先插单（带商品快照），再 `UPDATE ... stock = stock - 1 WHERE id=? AND stock>=1`，0 行则删单 + 售罄页 | 并发下不会超卖；失败有明确页面而非 500 |
| **订单号/交易号互认**：退款与恢复页接受订单号或捕获 ID（交易号），订单端点 404 自动改查捕获端点 | 真实事故：用户把 PayPal 后台「交易号」填进「订单号」框，`orders/{捕获ID}` 必回 404 `RESOURCE_NOT_FOUND` |
| **重复退款幂等**：422 的 `CAPTURE_FULLY_REFUNDED` / `ALREADY_REFUNDED` / `REFUND_ALREADY_EXISTS` / `DUPLICATE` 一律按成功对账 | 都说明上次已退成功，按失败报会给用户假失败（真实沙箱实证：已全额退再退是 `CAPTURE_FULLY_REFUNDED`，文档写的 `ALREADY_REFUNDED` 反而不出现） |
| **出站重试只重传传输失败**：`http_post` 的 `ok=false` 仅表示 connect/TLS/超时；4xx/5xx 仍 `ok=true` | 按 ok 重试不会重放已被服务端拒绝的请求；core 无 sleep 内建，立即重试（单次超时本身即等待） |
| **密钥 env 注入**：`client_secret` 走 `PAYPAL_KEY` 等环境变量，从不进镜像层、不进生成物 | 镜像 `docker history` 干净；env 名不能含 `SECRET` 子串（lume `env()` 掩码会读出 null，见 README） |

**已知边界**（与 TODO S7 对齐）：
- webhook 验签是纯 HMAC 简化版——真实 PayPal 签名含 `crc32(body)`，lume-core 暂无 crc32 内建，验签材料随 JSON body 传递（沙箱约定）；
- 无随机源 ⇒ 业务单号由生成器侧派生（`order_no` + `now()`），沙箱够用；
- 微信支付 v3 为 HMAC-SHA256 适配（真 RSA 是已知边界）；
- 金额/币种配置驱动（`currency` / `currency_symbol` / `brand`）。

### 4.4 mock 网关与交叉验证

`scripts/mock_pay_gateway.py` 是**独立实现**的 PayPal 网关模拟器（OAuth2/建单/捕获/查单/查捕获/退款），与 lume 侧 `pay.lume` 不共享代码——两边对同一组已知向量（建单响应结构、捕获响应结构、404 语义、重复退款 422 的 issue 编码）必须给出一致答案。`scripts/e2e.sh` 第 4 条探针路径专门固化「交易号填进订单号」的恢复链路。

## 5. 横切关注点

### 5.1 安全面

| 层 | 机制 |
|---|---|
| 输入 | `validate.lume`：名字白名单（关闭 DDL/路由注入面）、类型白名单、重名检测 |
| 输出 | `ui.esc()` 全量转义；SQL 一律参数化（`LIKE ? ESCAPE`） |
| 写入 | `sql_write` WHERE 护栏（无 WHERE 的 UPDATE/DELETE 拒绝执行） |
| 密钥 | env 运行时注入；`.env` 进 `.gitignore`；`make check-privacy` 扫描跟踪文件 |
| 支付 | 托管收银台（应用不碰卡号）；webhook 验签；退款幂等对账 |

### 5.2 确定性保证

生成器侧无随机源、无时间依赖（除业务单号派生）、无网络调用——同一份 schema 在任何机器上产出逐字节相同的工程。这是「验证一次，处处正确」的前提：`tests/t1-t7` + e2e 探针锁定的行为，不随生成次数漂移。

### 5.3 部署形态

| 形态 | 说明 |
|---|---|
| 本地 | `make run`（生成）→ `make dev` / `make serve`（跑）；或 `lume-core gen/app.lume` |
| Docker | 镜像内 `RUN lume-core main.lume "$NSGM_CONFIG"` **从源码重新生成** gen/（不拷贝宿主产物）；`NSGM_CONFIG` 选普通/支付变体；数据落命名卷；密钥 env 注入 |
| Windows | lume-core 完整支持（解释器 + 文件 I/O 路径）；生成器本身只用解释器，不受 `--watch`/出站 HTTP 限制影响 |

## 6. 相关文档

- [README.md](README.md) / [README.zh.md](README.zh.md)：项目介绍与使用
- [TODO.md](TODO.md)：路线图与已知边界
- [SECURITY.md](SECURITY.md)：漏洞报告政策
- 上游项目：[nsgm](https://github.com/erishen/nsgm)（原版 Next.js + Express + GraphQL + MySQL 全栈框架，本项目的生成器层由其移植而来）；运行时：[lume-core](https://github.com/erishen/lume-core)
