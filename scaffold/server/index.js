// lume-nsgm 生成项目的 GraphQL + MySQL 服务入口
// 复刻 nsgm serverDB 契约：getConnection / executeQuery / executePaginatedQuery / closePool
require('dotenv').config()
const express = require('express')
const { createYoga } = require('graphql-yoga')
const mysql = require('mysql2/promise')

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '3306', 10),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || '',
  database: process.env.DB_DATABASE || 'crm_demo',
  connectionLimit: 10,
  waitForConnections: true,
  supportBigNumbers: true,
  bigNumberStrings: true,
})

async function executeQuery(sql, values = []) {
  const [rows] = await pool.query(sql, values)
  return rows
}

async function executePaginatedQuery(sql, countSql, values = [], countValues = []) {
  const [results, countResults] = await Promise.all([
    executeQuery(sql, values),
    executeQuery(countSql, countValues),
  ])
  return {
    totalCounts: countResults[0] ? countResults[0].counts : 0,
    items: results,
  }
}

async function closePool() {
  await pool.end()
}

const serverDB = {
  getConnection: () => pool.getConnection(),
  executeQuery,
  executePaginatedQuery,
  closePool,
}

// 必须先导出 serverDB，再加载 graphql（其依赖 apis -> utils/common -> 本模块），
// 否则循环初始化时 common.js 拿到的 serverDB 为 undefined。
module.exports = { serverDB }

const app = express()
app.get('/health', (req, res) => res.json({ ok: true }))

const { schema } = require('./graphql')
const yoga = createYoga({
  schema,
  cors: { origin: '*', credentials: false },
})
app.use('/graphql', yoga)

const PORT = parseInt(process.env.GRAPHQL_PORT || '4000', 10)
app.listen(PORT, () => {
  console.log(`GraphQL endpoint: http://localhost:${PORT}/graphql`)
})
