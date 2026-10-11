# lume-nsgm

用 **lume**（自研语言，lume-core 运行时）实现的 **nsgm** 生成器引擎复刻版：输入模块字段定义（JSON），输出一套 TS 全栈 CRUD 工程骨架（SQL / GraphQL schema / resolver / service / page / redux / styled / i18n）。

> 定位：lume 替代的是 **nsgm 的生成器与 CLI 层**；生成产物仍是 Next.js/Express + GraphQL + Antd 的 TS 全栈项目（即 nsgm 的输出风格），不替代任何运行时。

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
│   └── scaffold.lume    # 文件树写入 + redux/styled/i18n 生成（模板渲染）
└── tests/
    ├── t1.lume          # model/sql/schema 验证
    ├── t2.lume          # service/resolver/page 验证
    └── t3.lume          # 模板引擎验证（each/if/变量替换）
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

生成产物落在 `./gen/`：

```
gen/
├── sql/{module}.sql            # 建库建表 SQL
├── schema/{module}.ts          # GraphQL schema（query/mutation/type）
├── resolver/{module}.js        # resolver（分页/Get/Search/Add/Update/Delete）
├── service/{module}.ts         # GraphQL 客户端 service
├── page/{module}/index.tsx     # Antd 列表页（搜索 + Modal 表单）
├── redux/{module}/actions.ts
├── redux/{module}/reducer.ts
├── styled/{module}.ts
└── i18n/zh-CN/{module}.ts
```

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
