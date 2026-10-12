# lume-nsgm

**AI-friendly 的确定性 CRUD 生成层**：输入模块字段定义（JSON schema），输出一套**以 lume 为底**的全栈 CRUD 工程（SQLite 存储 + SSR 页面 + REST API + React 前端），`lume-core` 单二进制一条命令运行。

> 定位：lume 替代的是 **nsgm 的生成器与 CLI 层**，产物形态从 Next.js/Express + GraphQL + Antd 演进为 **lume-core 应用**（`server`/`route`/`run` + `sql_query`/`sql_write` 内建 + docroot 静态 + `:name` 动态路由，core ≥ 0.6.0），零 Node 依赖；生成器侧同样用 lume-core 解释执行。

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
├── templates/           # 渲染模板（sql/schema/service/resolver/page/actions/reducer/styled/i18n）
├── lib/
│   ├── model.lume       # 字段模型 + 类型映射（gql/sql 类型、下标过滤）
│   ├── tpl.lume         # 极简模板引擎（{{var}} / {{#each}} / {{#if}}）
│   ├── sql.lume         # SQL 生成器（模板渲染）
│   ├── schema.lume      # GraphQL schema 生成器（模板渲染）
│   ├── service.lume     # GraphQL 客户端 service 生成器（模板渲染）
│   ├── resolver.lume    # GraphQL resolver 生成器（模板渲染）
│   ├── page.lume        # Antd 页面生成器（模板渲染）
│   ├── scaffold.lume    # 文件树写入 + redux/styled/i18n 生成（模板渲染）
│   └── base.lume        # 可运行工程基座：复制 scaffold/ 静态壳 + reducers.ts + pages 路由
├── scaffold/            # 工程基座静态模板（package.json / server / client / pages 壳）
└── tests/
    ├── t1.lume          # model/sql/schema 验证
    ├── t2.lume          # service/resolver/page 验证
    ├── t3.lume          # 模板引擎验证（each/if/变量替换）
    └── t4.lume          # sql_default() 回归断言（main() 返回失败数即退出码）
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

`make run`（或 `make base`）输出的即**以 lume 为底的可运行项目**，运行时只需 lume-core 二进制 ≥ 0.6.0（自带 `server`/`route`/`run`、`sql_query`/`sql_write` 内建、docroot 静态与 `:name` 动态路由）：

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
- **React 前端（主 UI）**： `pnpm dev` 起在 :5173，每模块生成 `<Ctrl>Page.tsx`（搜索/分页/受控表单/删除 confirm/时间列 `fmtTime` 本地化），hash 路由导航；`pnpm build && pnpm preview` 即生产预览（同样带 /api 代理，免 CORS）
- SSR 回退页面： http://localhost:8081/ → 各模块列表页（搜索/新增/编辑/删除均为 SSR 表单，无需 JS）
- JSON API： `GET /api/{module}?page=0&pageSize=20&q=关键字`、`GET /api/{module}/:id`、`POST /api/{module}`（JSON body 新增）、`POST /api/{module}/update/:id`、`POST /api/{module}/delete/:id`（React 前端消费的正是这套 API）
- 在 lume-nsgm 根目录可 `make serve`（读 `.env` 的 `LUME_BIN`，默认 `lume-core`）

> 说明：SSR 表单设计为 GET 提交（`req.query_params` 已 URL 解码，可直接读）；
> 程序化写操作走 POST + JSON body（`json()` 解析）。API 行为已 curl 实测
> （lume-core 底座 31 项探针全过：SSR/静态/CRUD/动态路由/搜索/decimal/校验）。

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

暂不含（后续迭代）：i18n 多语言完整集成、上传/CSV 导出、DataLoader 批量、字段级校验函数。

## 与 lume-core 的关系

lume-nsgm 是 lume 语言的**第一个真实业务级应用**（生成器领域），同时反向驱动 lume-core 补内建：
- P0：`json` 解码、`argv()`、递归 `files()`
- P4a：字符串内建 `upper/lower/capitalize/trim/contains/split/join/substr`
- M1 修复：`join()` 字符串元素 verbatim（无 JSON 引号）、空列表 join 返回 `""` 而非 `null`
- M2：`read_stdin()` 内建（stdin 交互输入）；模板引擎踩坑：`split("}}")` 会切开 `{{else}}`/`{{/if}}` 需重组、`head` 是保留字、`fbool` 需同时兼容 bool true 与数字 1
- 基座切换（core ≥ 0.6.0）：自包含 SQLite 内建（`sql_query`/`sql_write`）、`json()` 双向、docroot 静态服务、`:name` 动态路由
- 语言特性（core 0.7.0）：**三元运算符**（惰性求值、贴邻消歧）——生成模板中 `q != "" ? ... : ...` 这类 UI 条件渲染的直接驱动力
