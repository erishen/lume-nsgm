# lume-nsgm

用 **lume**（自研语言，lume-core 运行时）实现的 **nsgm** 生成器引擎复刻版：输入模块字段定义（JSON），输出一套 TS 全栈 CRUD 工程骨架（SQL / GraphQL schema / resolver / service / page / redux / styled / i18n）。

> 定位：lume 替代的是 **nsgm 的生成器与 CLI 层**；生成产物仍是 Next.js/Express + GraphQL + Antd 的 TS 全栈项目（即 nsgm 的输出风格），不替代任何运行时。

## 目录

```
lume-nsgm/
├── main.lume            # CLI 入口（create / 读 config 批量）
├── example-config.json  # 批量生成配置（user + order）
├── lib/
│   ├── model.lume       # 字段模型 + 类型映射（gql/sql 类型、下标过滤）
│   ├── sql.lume         # SQL 生成器（建库建表）
│   ├── schema.lume      # GraphQL schema 生成器
│   ├── service.lume     # GraphQL 客户端 service 生成器
│   ├── resolver.lume    # GraphQL resolver 生成器
│   ├── page.lume        # Antd 页面生成器（Table + Modal 表单）
│   └── scaffold.lume    # 文件树写入 + redux/styled/i18n 生成
└── tests/
    ├── t1.lume          # model/sql/schema 验证
    └── t2.lume          # service/resolver/page 验证
```

## 用法

```powershell
# 批量：读 example-config.json 生成 user + order 两个模块
make run

# 单模块：命令行模板字段
make dev

# 语法检查
make check

# 清理生成目录
make clean
```

也可以直接：

```powershell
E:/Workspace/lume-core/bin/lume-core main.lume example-config.json
E:/Workspace/lume-core/bin/lume-core main.lume create order
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

## M1 状态

已完成（对照 nsgm 8 个生成器中的 6 个核心）：model / sql / schema / service / resolver / page / scaffold（redux/styled/i18n 简版）。
暂不含（后续迭代）：i18n 多语言完整集成、上传/CSV 导出、DataLoader 批量、字段级校验函数、stdin 交互初始化。

## 与 lume-core 的关系

lume-nsgm 是 lume 语言的**第一个真实业务级应用**（生成器领域），同时反向驱动 lume-core 补内建：
- P0：`json` 解码、`argv()`、递归 `files()`
- P4a：字符串内建 `upper/lower/capitalize/trim/contains/split/join/substr`
- M1 修复：`join()` 字符串元素 verbatim（无 JSON 引号）、空列表 join 返回 `""` 而非 `null`
