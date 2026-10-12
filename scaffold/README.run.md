# 运行 lume-nsgm 生成的项目

`lume-nsgm` 通过 `make run`（读 `example-config.json`）生成一套**可独立运行**的
Next.js + GraphQL(Yoga) + MySQL 全栈工程，落在 `./gen`。

## 1. 准备数据库

在 MySQL 里建库并执行生成的建表 SQL：

```bash
mysql -u root -p -e "CREATE DATABASE crm_demo CHARACTER SET utf8mb4;"
mysql -u root -p crm_demo < gen/server/sql/user.sql
mysql -u root -p crm_demo < gen/server/sql/order.sql
```

## 2. 配置环境变量

```bash
cd gen
cp .env.example .env
# 编辑 .env，填入你的 MySQL 账号/密码/库名
```

## 3. 安装依赖并启动

```bash
pnpm install         # 首次运行需有 pnpm（corepack enable 或 npm i -g pnpm）
pnpm dev             # 同时启动 GraphQL(:4000) 与 Next(:3000)
```

- GraphQL 端点： http://localhost:4000/graphql （自带 Yoga IDE，可直接试查询）
- 前端页面： http://localhost:3000 → 点 `/user`、`/order` 进入 CRUD 列表

## 4. 目录结构（生成后）

```
gen/
├── package.json / tsconfig.json / next.config.js / .env.example
├── server/
│   ├── index.js              # Express + mysql2 连接池 + Yoga GraphQL
│   ├── graphql/index.js      # 聚合 apis + schema 构建可执行 schema
│   ├── utils/{common,validation}.js
│   ├── apis/<module>.js      # 生成的 resolver 映射
│   ├── schema/<module>.js    # 生成的 SDL 片段（CommonJS）
│   └── sql/<module>.sql      # 生成的建表 SQL
├── client/
│   ├── _app.tsx / utils/fetch.ts / redux/store.ts
│   ├── components/<module>/index.tsx   # 生成的 Antd 列表页
│   ├── redux/<module>/{actions,reducer}.ts
│   ├── service/<module>.ts / styled/<module>.ts
│   └── i18n/zh-CN/<module>.ts
└── pages/
    ├── _app.tsx / index.tsx
    └── <module>.tsx          # 薄壳，转发到 client/components/<module>
```

> 说明：为保持最小可运行，客户端壳**精简掉了** nsgm 原生的 SSO 登录、完整 i18n、
> Apollo Client（改用自写 `fetch` 封装）。需要时可按需补回。
