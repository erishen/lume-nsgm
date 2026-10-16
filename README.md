# lume-nsgm

**AI-friendly 的确定性 CRUD 生成层**：输入模块字段定义（JSON schema），输出一套**以 lume 为底**的全栈 CRUD 工程（SQLite 存储 + SSR 页面 + REST API + React 前端），`lume-core` 单二进制一条命令运行。

> 定位：lume 替代的是 **nsgm 的生成器与 CLI 层**，产物形态从 Next.js/Express + GraphQL + Antd 演进为 **lume-core 应用**（`server`/`route`/`run` + `sql_query`/`sql_write` 内建 + docroot 静态 + `:name` 动态路由，core ≥ 0.7.0），零 Node 依赖；生成器侧同样用 lume-core 解释执行。

## 为什么 AI 时代还需要它

让 AI 直接生成整个应用，问题在于**输出空间无限大**：每一行代码都是新的幻觉面，每次生成都要重新验证。lume-nsgm 把问题切成两半——

```
AI 只产出 schema（受控、小、可校验的 JSON）
   ↓
nsgm 确定性生成（注入防护 / 转义 / 分页边界 / UI 规范，修一次处处对，
   质量由 tests/t1-t5 套件与端到端探针固化）
   ↓
AI 再对 lume 代码做增量修改（小语言、语法面小，AI 的上下文负担极小）
```

- **AI 做决策，模板做执行**：schema 本身就是给 AI 的接口。生成器保证的是「无论谁写 schema，产物质量一致」。
- **验证一次，永久复用**：模板产出的 CRUD 行为（31 项底座探针 + 生成器套件 + UI 截图）已验证；AI 手写代码则每个项目都要重走一遍验证。
- **对 lume 生态**：lume-nsgm 是 lume 的第一个真实业务级消费者——动态路由、SQLite 内建、`json()`、三元运算符等语言特性都是它逼出来的。它是 lume-core 从玩具走向可用运行时的试金石。

一句话：它不是「替你打字的脚手架」，而是 **AI 编码时代的幻觉降噪器**——AI 写代码跑在受限运行时 + 已验证模板里，比裸生成靠谱得多。

### schema 校验（AI-friendly 报错层）

`lib/validate.lume` 在生成前对 config 做**一次性全量校验**（不是改一个报一个），每条错误带精确路径与修复提示，AI 一轮即可修完：

```
$ lume-core main.lume bad.json
schema validation failed (2 error(s)) in "bad.json":
  1. modules[0].fields[0]: unknown type "bogus_type" (supported: varchar/text/integer/decimal/boolean/date/datetime/timestamp)
  2. modules[0].fields[1]: "name" must match [a-z][a-z0-9_]* (got "2bad")
fix the config and re-run. ...
```

校验项：JSON 合法性、`modules` 非空、模块/字段 `name` 必须匹配 `[a-z][a-z0-9_]*`（**该名直接拼进 SQL DDL 与路由，白名单同时封死注入面**——曾实测 `"evil\"; DROP TABLE x--"` 可穿过无校验的生成器）、类型白名单、模块/字段重名（路由冲突）、空 `fields`。校验失败退出码 1，生成被完全跳过（此前缺 name 的模块会被静默跳过并谎报成功）。回归测试见 `tests/t6.lume`（16 断言）。

## 目录

```
lume-nsgm/
├── main.lume            # CLI 入口（create / init / 读 config 批量）
├── example-config.json  # 批量生成配置（user + order）
├── templates/           # 渲染模板（mod / sql / react_page）
│   ├── mod.tpl          # 模块文件模板（DDL + 数据驱动字段表 + 路由 + SSR 页面）
│   ├── sql.tpl          # 建表 DDL 导出模板
│   └── react_page.tpl   # 每模块 React 页面模板（<Ctrl>Page.tsx）
├── lib/
│   ├── model.lume       # 字段模型 + 类型映射（sql 类型、下标过滤）
│   ├── tpl.lume         # 极简模板引擎（{{var}} / {{#each}} / {{#if}}）
│   ├── sql.lume         # SQL DDL 生成器（模板渲染）
│   ├── modlume.lume     # 模块生成器：数据驱动字段表 + 路由 + SSR 页面
│   ├── reactgen.lume    # React 前端生成器（web/：Vite + React + TS SPA）
│   ├── scaffold.lume    # 文件树写入（输出 gen/ 全栈工程）
│   ├── validate.lume    # schema 一次性全量校验（注入防护 / 类型白名单 / 重名）
│   ├── assert.lume      # 测试断言辅助（ok/eq/fail，main() 返回失败计数即退出码）
│   └── base.lume        # 运行时内建辅助引用（SQL / JSON / 路由常量）
├── scaffold/            # 工程基座静态模板（复制进 gen/）
│   ├── lib/db.lume      # SQLite 存取辅助（dsn / init / 分页 / 计数）
│   ├── lib/pay.lume     # 支付库（provider: wechat|paypal）：v3 签名/下单/回调验签/跳转 + PayPal OAuth2 建单/捕获/webhook 验签（复制进 gen/）
│   ├── web/             # Vite + React + TS 静态壳（package.json / vite / tsconfig / main / api）
│   └── www/             # SSR 静态样式 + 回退 JS（app.css / app.js）
└── tests/
    ├── t1.lume          # model / sql 生成器验证（13 断言）
    ├── t2.lume          # modlume / reactgen 模块与前端生成器验证
    ├── t3.lume          # 模板引擎验证（each / if / 变量替换）
    ├── t4.lume          # sql_default() 回归断言
    ├── t5.lume          # React 前端生成器回归断言
    ├── t6.lume          # schema 校验回归断言（16 断言，validate.lume）
    └── t7.lume          # 支付回归断言（签名向量 / validate_pay / 字段 default）
├── scripts/
│   ├── mock_pay_gateway.py  # 模拟微信支付 v3 网关（独立 HMAC 实现，交叉验证）
│   └── e2e.sh          # 端到端探针：起生成工程 + curl 跑 SSR/CRUD/搜索/分页/迁移/支付
├── Dockerfile / docker-compose.yml / docker-build.sh   # 容器化部署（见「Docker 部署」）
├── example-config.json / example-pay.json / example-paypal.json  # 批量生成配置（普通 / 微信支付 / PayPal 支付变体）
└── .env.example        # .env 模板（LUME_CORE_BIN 路径；.env 本体进 .gitignore）
```

## 前置条件：安装 lume-core

lume-nsgm 本身只是一堆 `.lume` 脚本和模板，**运行它需要一个 lume-core 运行时**（编译器 / CLI 二进制）。lume-core 是自研的单文件 C11 工程，除 libc（探测到 `llvm-config` 时再链 libLLVM）外不依赖任何东西，不需要 node / pnpm / SQLite。

### 方式一：一键安装（推荐）

按平台下载预编译 tarball，二进制落到 `~/.local/bin/lume-core`（examples + docs 落到 `~/.local/share/lume-core`）：

```bash
curl -sSfL https://raw.githubusercontent.com/erishen/lume-core/main/install.sh | sh
```

可用环境变量覆盖（在管道命令前 `export`）：

| 变量 | 默认 | 含义 |
|---|---|---|
| `LUME_CORE_VERSION` | `latest` | 要装的版本 tag |
| `LUME_CORE_PREFIX`  | `$HOME/.local` | 安装根目录（`$PREFIX/bin`） |
| `LUME_CORE_SHA256`  | — | tarball 的预期 sha256（设置后才校验） |
| `LUME_CORE_REPO`    | `erishen/lume-core` | 拉取所用的 GitHub 仓库 |

### 方式二：从源码构建

依赖：一个 C11 编译器（`cc`）；若要原生编译能力 `--compile-llvm`，`PATH` 里需有 `llvm-config`（macOS 上 brew 装在 `/opt/homebrew/opt/llvm` 会被自动探测到）。**没有 LLVM 也能编出 `bin/lume-core`**，只是 `--compile-llvm` 不可用。

```bash
git clone <lume-core 仓库> lume-core && cd lume-core
make           # -> bin/lume-core
make check     # 自检：内置示例都过类型检查
# 可选：sudo cp bin/lume-core /usr/local/bin/lume-core
```

Windows（**MSYS2 的 MINGW64 shell**，不是 MSVC）：

```bash
pacman -S base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-clang
make           # -> bin/lume-core.exe
```

> Windows 上 `--watch` 与出站 HTTP 内建（`http_get` 等）暂不可用，但 lume-nsgm 只用解释器 + 文件 I/O + `read_stdin`，不受影响。

### 让 lume-nsgm 找到运行时

两种方式二选一：

1. 把 `lume-core` 放进 `PATH`（方式一默认装到 `~/.local/bin`，需自己加进 `PATH`），然后直接 `make run`；
2. 在 lume-nsgm 根目录新建 `.env`，写死本机绝对路径（Windows 用 `lume-core.exe`）：

   ```bash
   # lume-nsgm/.env
   LUME_CORE_BIN=/Users/you/.local/bin/lume-core        # macOS / Linux
   # LUME_CORE_BIN=E:/Workspace/lume-core/bin/lume-core.exe   # Windows
   ```

   Makefile 已用 `-include .env` + `$(or $(LUME_CORE_BIN),lume-core)` 解析：有 `.env` 优先用它的绝对路径，没有则回退到 PATH 上的 `lume-core`。

## 用法

```bash
# 批量：读 example-config.json 生成 user + order 两个模块
make run

# 单模块：命令行模板字段
make dev

# 交互式字段录入后生成（stdin 逐行输入 name type [required] [searchable]，空行结束）
echo "name varchar required searchable" | make init MODULE=product

# 语法检查（含模板引擎 t3）
make check

# 生成器断言套件（t1-t6）
make test

# 端到端探针：起生成工程 + curl 跑 SSR/静态/CRUD/搜索/分页/迁移（scripts/e2e.sh）
make test-e2e

# 清理生成目录
make clean
```

也可以直接：

```bash
# 不经过 make 的直调方式（需 lume-core 在 PATH，或用 .env 的 LUME_CORE_BIN 指路径）
lume-core main.lume example-config.json
lume-core main.lume create order
lume-core main.lume init product
# Windows：把 lume-core 换成 lume-core.exe（或写进 .env 的 LUME_CORE_BIN）
```

生成产物落在 `./gen/`（**以 lume 为底的可运行工程**：lume-core 跑服务端 + React 前端）：

```
gen/
├── app.lume               # 入口：server 块 + 模块装配（import 即注册路由）+ 建表 + run()
├── lib/
│   ├── ui.lume            # SSR 组件库（导航由模块清单注入）
│   └── db.lume            # SQLite 存取辅助（dsn/init/分页/计数）
├── modules/{module}.lume  # 每模块：DDL + 数据驱动字段表 + 路由 + SSR 页面
├── sql/{module}.sql       # 建表 DDL 导出（与模块内嵌一致，供人工核查）
├── web/                   # React 前端（Vite + React + TS，pnpm 管理）
│   ├── package.json / vite.config.ts / tsconfig.json / index.html
│   └── src/
│       ├── main.tsx / App.tsx    # 入口 + hash 路由 + 模块导航
│       ├── api.ts                # JSON API 客户端
│       ├── pages/{Ctrl}Page.tsx  # 每模块页面（列表/受控表单/分页/删除确认）
│       └── ui.css                # 样式（与 SSR app.css 同源）
├── www/app.css            # SSR 静态样式（server docroot 服务）
└── data/app.db            # SQLite 库（运行后生成）
```

## 运行生成的项目

`make run`（或 `make base`）输出的即**以 lume 为底的可运行项目**，运行时只需 lume-core 二进制 ≥ 0.7.0（生成的 lume 模块用到 0.7.0 引入的三元运算符，0.6.0 会解析失败；自带 `server`/`route`/`run`、`sql_query`/`sql_write` 内建、docroot 静态与 `:name` 动态路由）：

```bash
cd gen

# lume-core 二进制（从 lume-core 仓库 make 得 bin/lume-core）
lume-core app.lume

# React 前端（主 UI）：make run 已自动完成 gen/web 的 pnpm install，
# 只有改了 web 依赖才需要手动重装；dev/build 直接可用
cd web
pnpm dev            # http://localhost:5173，/api 由 Vite 代理到 lume :8081
```

- 首次启动自动建表（`CREATE TABLE IF NOT EXISTS`，SQLite 文件 `data/app.db`；`env NSGM_DB` 可换库文件；内建仅支持 SQLite）
- **schema 演进自动迁移**：改字段后重新生成，旧库中已存在的表会自动 `ALTER TABLE ADD COLUMN` 补齐缺失列（裸类型、旧行读作 NULL），旧数据不丢、启动不报 `no such column`；自增主键列不参与补齐
- server 块从环境变量读取 `PORT` / `HOST` / `WORKERS`（未设置时默认 `8081` / `127.0.0.1` / `4`；需默认解释器后端，Docker 构建已强制 `HAVE_LLVM=0`），例如 `PORT=9000 lume-core app.lume`
- **React 前端（主 UI）**： `pnpm dev` 起在 :5173，每模块生成 `<Ctrl>Page.tsx`（搜索/分页/受控表单/删除 confirm/时间列 `fmtTime` 本地化），hash 路由导航；`pnpm build && pnpm preview` 即生产预览（同样带 /api 代理，免 CORS）
- SSR 回退页面： http://localhost:8081/ → 各模块列表页（搜索/新增/编辑/删除均为 SSR 表单，无需 JS）
- JSON API： `GET /api/{module}?page=0&pageSize=20&q=关键字`、`GET /api/{module}/:id`、`POST /api/{module}`（JSON body 新增）、`POST /api/{module}/update/:id`、`POST /api/{module}/delete/:id`（React 前端消费的正是这套 API）
- 在 lume-nsgm 根目录可 `make serve`（读 `.env` 的 `LUME_BIN`，默认 `lume-core`）

> 说明：SSR 表单设计为 GET 提交（`req.query_params` 已 URL 解码，可直接读）；
> 程序化写操作走 POST + JSON body（`json()` 解析）。搜索输入中的 `%` / `_`
> 按字面转义（`LIKE ? ESCAPE "\"`），不会被当作通配符。API 行为由
> `make test-e2e` 固化回归（SSR/静态/CRUD/动态路由/搜索/通配符转义/分页/
> qs_int 兜底/旧库迁移）。

## Docker 部署

把**生成的全栈应用**（lume-core 后端 + React 前端 + SQLite）打成一个镜像，
`docker compose up --build` 即可在 `:18081` 跑起来（容器端口 18081，>10000，避开常用低位端口）。镜像在构建期做的事：

1. 从 `lume-core` 源码编译 `lume-core` 二进制（含 SQLite 后端，探测 `libsqlite3` 自动编入）；
2. 用该二进制跑生成器 `main.lume example-config.json` **确定性重新生成** `gen/`；
3. `pnpm` 构建 React 前端（产物以相对 `base` 挂到 `/spa/`），由 lume-core 的 docroot 静态托管。

> 构建上下文必须是 `work/lume`（`lume-core` 与 `lume-nsgm` 的父目录），
> 因为 Dockerfile 要同时拿到 lume-core 源码与生成器源码。配套文件已备好：
> `Dockerfile` / `docker-compose.yml` / `docker-build.sh`，以及 Makefile 的 `docker-*` 命令。

```bash
# 方式一：Makefile（推荐，自动处理构建上下文、端口与数据卷）
make docker-build     # 构建镜像（编译 lume-core + 重新生成 + 构建前端）
make docker-up        # 后台启动（首次自动 --build），宿主端口默认 18081
make docker-logs      # 跟踪日志
make docker-ps        # 查看容器状态
make docker-down      # 停止并移除容器（数据卷 nsgm-data 保留）
make docker-clean     # 停止并删除容器 + 数据卷（清空数据，谨慎）

# 宿主端口可覆盖（容器内始终监听 18081）：
make docker-up DOCKER_PORT=19090

# 方式二：compose 直调
cd lume-nsgm
docker compose up --build          # 首次构建（编译 lume-core + 重新生成 + 构建前端）
docker compose up -d              # 后台运行
docker compose down               # 停止并移除容器（数据卷 nsgm-data 保留）

# 方式三：脚本（自动定位父目录作为构建上下文）
./docker-build.sh                 # 产出镜像 lume-nsgm-app:latest
docker run --rm -p 18081:18081 -v lume-nsgm-data:/app/data lume-nsgm-app:latest
```

访问（端口默认 18081，可用 `DOCKER_PORT` 覆盖宿主端口）：

- 首页 / SSR 页面： `http://localhost:18081/`
- React SPA（主 UI）： `http://localhost:18081/spa/`（hash 路由，API 走同源 `/api`）
- REST API： `http://localhost:18081/api/<module>`

容器内配置（compose 的 `environment` 段，生成工程从 env 读取，容器端口固定 18081）：

| 变量 | 容器内值 | 含义 |
|---|---|---|
| `PORT` | `18081` | 服务监听端口（>10000，避开常用低位端口） |
| `HOST` | `0.0.0.0` | 绑定地址（lume-core 默认 `127.0.0.1`，容器内必须放通） |
| `WORKERS` | `1` | prefork worker 数（Linux 下多 worker 偶发初始化不一致） |
| `NSGM_DB` | `/app/data/app.db` | SQLite 数据文件路径 |

- **健康检查**：compose 带 `healthcheck`（每 30s 探 `GET /`，两种构建配置的工程都有该路由，`docker compose ps` 可见 `healthy`）
- **schema 演进**：改字段后重新 `make docker-build`，容器重启时自动 `ALTER TABLE ADD COLUMN` 补齐缺失列，数据卷里的旧数据不丢
- **支付变体构建**：`docker build --build-arg NSGM_CONFIG=example-pay.json -t lume-nsgm-app:pay .`（微信）或 `NSGM_CONFIG=example-paypal.json -t lume-nsgm-app:paypal .`（PayPal），构建上下文同 `work/lume`）——镜像内跑的是带支付路由的生成工程，商户密钥等敏感项仍走环境变量注入（`PAY_KEY` / `PAYPAL_KEY` 等），不进镜像层

数据持久化：SQLite 文件落在容器内 `/app/data/app.db`，已挂为命名卷 `nsgm-data`
（可用环境变量 `NSGM_DB` 覆盖路径）。

## 支付（provider: wechat | paypal，沙箱 mock 全链路）

在普通 CRUD 生成能力之上，nsgm 可生成**带支付闭环的电商工程**：下单签名 →
扫码/跳转 → 回调验签 → 订单状态流转。`pay` 段用 `provider` 选择支付通道，
目前支持**微信支付 v3**（`provider: wechat`，默认）与 **PayPal Express Checkout**
（`provider: paypal`）。用法是换一份带 `pay` 段的配置：

```bash
# 微信（默认）：example-pay.json —— order 模块 + pay 段
lume-core main.lume example-pay.json
PAY_KEY=<商户密钥> lume-core gen/app.lume
python3 scripts/mock_pay_gateway.py --port 18097

# PayPal：example-paypal.json —— order 模块 + pay 段（provider: paypal）
# （示例配置默认都产出到 gen/；要两变体并存可复制配置改 out，e2e 即这么做的）
lume-core main.lume example-paypal.json
PAYPAL_KEY=<沙箱密钥> lume-core gen/app.lume
python3 scripts/mock_pay_gateway.py --paypal --port 18097
```

> mock 网关默认凭证（应用侧与网关侧必须对齐，否则验签/认证失败）：微信
> `MOCK_PAY_SECRET=mock-secret`（对应 `PAY_KEY`）；PayPal
> `MOCK_PAYPAL_CLIENT_ID=AUmock_client_id_sandbox_001` /
> `MOCK_PAYPAL_CLIENT_SECRET=e2e-mock-key`（对应配置 `client_id` 与
> `PAYPAL_KEY`）。换值需两边同时改。

配置的 `pay` 段（`lib/validate.lume` 的 `validate_pay` 全量校验，`provider` 决定走哪条校验分支）：

**微信（`provider: wechat`，默认）**

| 键 | 含义 |
|---|---|
| `gateway` | 网关地址（`http://127.0.0.1:18097` 打 mock；真实环境填微信域名） |
| `appid` / `mchid` / `serial_no` | 应用 ID / 商户号 / 证书序列号 |
| `secret_env` | **商户密钥的环境变量名**（如 `PAY_KEY`）——生成代码 `env("<name>")` 读取，密钥不写进配置与产物 |
| `order_module` / `order_no_field` / `amount_field` / `status_field` | 订单表与字段绑定（四个名字必须已定义） |
| `notify_path` | 回调路由（默认 `/api/pay/notify`） |

**PayPal（`provider: paypal`）**

| 键 | 含义 |
|---|---|
| `client_id` | 公开标识（沙箱 `AU...`），写进配置无妨；进 `Authorization` 头 |
| `secret_env` | **client_secret 的环境变量名**（如 `PAYPAL_KEY`）——生成代码 `env("<name>")` 读取，密钥不写进配置与产物 |
| `mode` | `sandbox` / `live`（决定 `api-m.sandbox.paypal.com` 还是 `api-m.paypal.com`） |
| `order_module` / `order_no_field` / `amount_field` / `status_field` | 订单表与字段绑定（四个名字必须已定义） |
| `webhook_path` | 可选，异步事件路由（默认不生成；配置后生成 `post "<webhook_path>"`） |
| `currency` / `brand` | 可选，默认 `USD` / `lume-nsgm` |

> ⚠️ **`secret_env` 取名避坑（两通道通用）**：lume-core 的 `env()` 会**掩码**名字含
> `API_KEY` / `SECRET` / `PASSWORD` / `PASSWD` / `TOKEN` / `CREDENTIAL` 子串（大小写
> 不敏感）的变量——读到的是 null，与未设置同形（`src/builtins_fs.c` 的
> `env_is_sensitive`，防止脚本外泄凭证）。所以微信用 `PAY_KEY`、PayPal 用
> `PAYPAL_KEY`；**不要**叫 `PAYPAL_CLIENT_SECRET`（PayPal e2e 曾因此 401：
> 空 secret 过 Basic 校验失败）。

生成工程比普通工程多两条路由 + 一个 `lib/pay.lume`：

- `POST /api/pay/create`：读订单 → `pay.create_native`（`hmac_sha256` 签名调
  `POST {gateway}/v3/pay/native`）→ 返回 `code_url`（Native 下单标准返回）
- `POST /api/pay/notify`：验签 → `status` 仅允许 `pending → paid` 流转（幂等，
  重复回调返回 SUCCESS 但不重复落库）

`lib/pay.lume` 导出的纯函数（`tests/t7.lume` 用 RFC 4231 已知向量固化）：

```lume
pay.canonical(method, path, ts, nonce, body)   // 请求串：method\npath\nts\nnonce\nbody\n
pay.sign(secret, method, path, ts, nonce, body) // HMAC-SHA256 hex
pay.auth_header(mchid, serial, ts, nonce, hex)  // Authorization 头
pay.verify_notify(secret, ts, nonce, body, hex) // 回调验签（timestamp\nnonce\nbody\n）
pay.redirect_html(action, fields, title)        // 自动提交表单（302 变通，见 S3）
```

已知边界（详见 TODO.md「已知边界」）：

- **S3 响应无 302/头控制** ⇒ 跳转走自动提交表单（恰好是 Native 支付标准姿势）
- **S7 回调无请求头**：`req` 对象不带 headers，验签三要素（timestamp / nonce /
  signature）由网关放进 body 的 `verify_ts` / `verify_nonce` / `verify_sign` 字段
- **S8 无随机源**：nonce 派生为 `order_no + "-" + str(now())`；真实微信要求
  SHA256-**RSA** 签名（需平台证书），当前 `hmac_sha256` 方案面向 mock/自建网关，
  上生产前要么补 RSA 内建、要么外挂本地签名 sidecar（`http_post` 带
  `allow_private: true` 打本地服务）

回归：`make test` 含 t7（签名向量 / validate_pay / 字段 default）；`make test-e2e`
固化沙箱全链路——建单 → 签名下单 → code_url → 篡改签名拒 → 正确回调 →
`status:"paid"` → 重复回调幂等。

### PayPal Express Checkout（provider: paypal）

流程与微信不同——是**浏览器跳转**而非扫码：下单拿 `approve_url` → 前端
`window.location` 跳转 → 用户在 PayPal approve → PayPal 跳回
`return_url?token=<paypal_order_id>&order_no=<本地单号>` → 服务端 `capture` 捕获 →
改本单状态。生成工程比微信多四条路由 + `lib/pay.lume` 的 PayPal 适配器：

- `POST /api/pay/create`：读订单 → `pay.paypal_token`（OAuth2 `client_credentials`
  取 Bearer，模块级缓存约 8h）→ `pay.paypal_create`（`POST /v2/checkout/orders`，
  intent=CAPTURE）→ 返回 JSON `{ ok, approve_url, paypal_order_id }`（前端据此跳转）
- `GET /api/pay/return`：从 `req.query_params` 取 `token` 与 `order_no` → `pay.paypal_capture`
  （`POST .../capture`）→ 改 `status` 为 `paid`（幂等，已 paid 直接回成功页）
- `GET /api/pay/cancel`：用户取消，返回取消页
- `POST /api/pay/webhook`（可选）：`pay.paypal_verify_webhook` 简化 HMAC 验签

`lib/pay.lume` 导出的 PayPal 纯函数（`tests/t7.lume` 已知向量固化）：

```lume
pay.paypal_base_url(mode)              // sandbox/live → base URL
pay.paypal_basic_auth(id, secret)     // "Basic " + base64(id:secret)（RFC7617）
pay.paypal_fmt_cents(cents)           // 整数分 → "x.xx"（无浮点）
pay.paypal_token(cfg)                 // OAuth2 client_credentials → { ok, token }
pay.paypal_create(cfg, token, no, cents, desc, ret, cancel) // → { ok, approve_url, paypal_order_id }
pay.paypal_capture(cfg, token, pp_order_id)                   // → { ok, status, capture_id }
pay.paypal_verify_webhook(secret, id, ts, body, sign_hex)    // HMAC(id\n+ts\n+body\n)
```

PayPal 专属边界（详见 TODO.md P3-8）：

- **webhook 验签简化**：真实 PayPal webhook 签名含 `crc32(body)`（core 暂无 crc32
  内建），本库 `paypal_verify_webhook` 为纯 HMAC 沙箱等价实现；验签三要素
  （`verify_id` / `verify_ts` / `verify_sign`）随 body 传递，共用 S7 边界
- **return 走 query_params**：PayPal 跳回带 `?token=...`，`req.query_params` 已
  URL 解码可直接读（同 SSR 表单约定）；创建时把本地 `order_no` 编码进 `return_url`
  本身，避免服务端存 PayPal 订单 ID → 本地单号映射
- **OAuth2 比 SHA256-RSA 易内嵌**：PayPal 的 HTTP Basic 凭证只需 `base64_encode`
  （P3-1 内建），无需 RSA 内建，这是选 PayPal 作为第二通道的动因

回归：`make test` 含 t7（PayPal 已知向量 / validate_pay paypal 分支 / 字段 default）；
`make test-e2e` 固化 PayPal 沙箱全链路——建单 → approve_url → return 捕获 →
`status:"paid"` → 重复 return 幂等。

## 字段定义（example-config.json）

```json
{
  "db": "crm_demo",
  "out": "./gen",
  "modules": [
    {
      "name": "user",
      "fields": [
        { "name": "id", "type": "integer", "required": true, "primary": true, "auto": true,
          "system": true, "showInList": true, "showInForm": false, "searchable": false, "comment": "ID" },
        { "name": "name", "type": "varchar", "length": 255, "required": true,
          "showInList": true, "showInForm": true, "searchable": true, "comment": "姓名" }
      ]
    }
  ]
}
```

支持类型：`varchar` / `text` / `integer` / `decimal` / `boolean` / `date` / `datetime` / `timestamp`。
字段属性：`required` / `primary` / `auto` / `system` / `showInList` / `showInForm` / `searchable` / `comment` / `length`。

## M2 状态

已完成（M1 6 个核心生成器 + M2 两项缺口）：
- **lume-core `read_stdin()` 内建**：`read_stdin()` 读一行（去换行）、`read_stdin("all")` 读全部，EOF/空输入返回 `""`，为 init 交互命令铺路
- **模板渲染引擎 `lib/tpl.lume`**：语法 `{{var}}`（点路径）、`{{#each list as it}}...{{/each}}`（支持指令行内联每行模板）、`{{#if path}}...{{else}}...{{/if}}`（行内 if，可嵌套）；生成器从字符串拼接迁移到 `templates/*.tpl` 模板渲染
- **init 交互命令**：stdin 逐行录入字段后生成（`make init MODULE=product`）

暂不含（后续迭代）：文件上传、CSV 导出、i18n 多语言完整集成、字段级自定义校验函数（当前校验集中在 schema 层 `validate.lume`，生成物内只做必填 / 类型基础校验）。

## 与 lume-core 的关系

lume-nsgm 是 lume 语言的**第一个真实业务级应用**（生成器领域），同时反向驱动 lume-core 补内建：
- P0：`json` 解码、`argv()`、递归 `files()`
- P4a：字符串内建 `upper/lower/capitalize/trim/contains/split/join/substr`
- M1 修复：`join()` 字符串元素 verbatim（无 JSON 引号）、空列表 join 返回 `""` 而非 `null`
- M2：`read_stdin()` 内建（stdin 交互输入）；模板引擎踩坑：`split("}}")` 会切开 `{{else}}`/`{{/if}}` 需重组、`head` 是保留字、`fbool` 需同时兼容 bool true 与数字 1
- 基座切换（core ≥ 0.7.0）：自包含 SQLite 内建（`sql_query`/`sql_write`）、`json()` 双向、docroot 静态服务、`:name` 动态路由
- 语言特性（core 0.7.0）：**三元运算符**（惰性求值、贴邻消歧）——生成模板中 `q != "" ? ... : ...` 这类 UI 条件渲染的直接驱动力
