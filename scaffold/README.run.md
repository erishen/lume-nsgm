# 运行 lume-nsgm 生成的项目

`lume-nsgm` 通过 `make run`（读 `example-config.json`）生成一套**以 lume 为底**
的全栈工程，落在 `./gen`：**React 前端（web/）** + SSR 回退页面 + REST API +
SQLite 存储。服务端运行时只需 lume 宿主二进制；前端开发/构建用 pnpm（Vite + React）。

## 1. 准备 lume 宿主

生成代码使用 lume 宿主的服务端能力（`server`/`route`/`run` 与
`sql_query`/`sql_write` 内建），**lume-core（纯解释器）跑不了它**。

从 lume 仓库构建（或用已装好的 `lume`）：

```bash
git clone <lume 仓库> lume && cd lume
make            # -> bin/lume
```

## 2. 启动

### 2a. React 前端（主 UI，Vite + React + TS）

```bash
cd gen/web
pnpm install                 # packageManager 已钉 pnpm@12.11.2，corepack 自动接管
pnpm dev                     # http://localhost:5173，/api 由 Vite 代理到 lume :8081
```

另开终端启动 lume 服务端（API + SSR 回退）：

```bash
cd gen
../lume/bin/lume app.lume    # 或 lume 在 PATH 上：lume app.lume
```

- 每模块生成 `web/src/pages/<Ctrl>Page.tsx`：列表（搜索/分页/删除 confirm）+
  新增/编辑受控表单 + 时间列本地化（`fmtTime`）
- `web/src/App.tsx`：hash 路由 + 模块导航（由模块清单注入）
- `web/src/api.ts`：`apiList/apiGet/apiAdd/apiUpdate/apiDelete`，始终同源
  （Vite dev/preview 均代理 `/api` → `127.0.0.1:8081`，可用 `LUME_API` 覆盖）
- 生产构建：`pnpm build`（tsc + vite build）→ `pnpm preview`（同样带 /api 代理）

### 2b. SSR 回退页面（免 JS，零 Node）

```bash
cd gen
../lume/bin/lume app.lume       # 或 lume 在 PATH 上：lume app.lume
```

- 首次启动自动建表（`CREATE TABLE IF NOT EXISTS`，SQLite 文件 `data/app.db`）
- 页面： http://localhost:8081/ → 导航进入各模块列表页
  （搜索、新增、编辑、删除均为 SSR 表单/链接，无需 JS）
- JSON API： `GET /api/<module>?page=0&pageSize=20&q=关键字`、
  `GET /api/<module>/:id`、`POST /api/<module>`（JSON body 新增）、
  `POST /api/<module>/update/:id`、`POST /api/<module>/delete/:id`
  （React 前端消费的正是这套 API）

## 3. 配置（可选）

| 环境变量 | 默认 | 含义 |
|---|---|---|
| `NSGM_DB` | `data/app.db` | SQLite 文件路径；`postgres://` / `mysql://` DSN 需宿主编译对应后端 |
| `PORT`（写死在 app.lume 的 server 块） | `8081` | 监听端口，直接改 `app.lume` |

## 4. 目录结构（生成后）

```
gen/
├── app.lume               # 入口：server 块 + 模块装配 + 建表 + run()
├── lib/
│   ├── ui.lume            # SSR 组件库（导航由模块清单注入）
│   └── db.lume            # SQLite 存取辅助（dsn/init/分页/计数）
├── modules/
│   └── <module>.lume      # 每模块：DDL + 数据驱动字段表 + 路由 + SSR 页面
├── sql/<module>.sql       # 建表 DDL 导出（与模块内嵌一致，供人工核查）
├── web/                   # React 前端（Vite + React + TS，pnpm 管理）
│   ├── package.json / vite.config.ts / tsconfig.json / index.html
│   └── src/
│       ├── main.tsx / App.tsx    # 入口 + hash 路由 + 模块导航
│       ├── api.ts                # JSON API 客户端（apiList/Get/Add/Update/Delete）
│       ├── pages/<Ctrl>Page.tsx  # 每模块页面（列表/表单/分页/删除确认）
│       └── ui.css                # 样式（与 SSR 的 app.css 同源）
├── www/app.css            # SSR 静态样式（server docroot 服务）
└── data/app.db            # SQLite 库（运行后生成）
```

> 说明：SSR 表单按 lume 宿主"GET 走 master 快速路径"的并发模型设计为
> GET 提交（与 examples/demo.lume 的 GET-only 状态路由一致）；程序化写操作
> 走 POST + JSON body（`json()` 解析，无需 URL 解码）。
