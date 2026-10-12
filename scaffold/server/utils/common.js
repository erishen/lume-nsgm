// 桥接到 server/index.js 导出的 serverDB（复刻 nsgm server/utils/common.js 结构）
const { serverDB } = require('../../index')

const { getConnection, executeQuery, executePaginatedQuery } = serverDB

module.exports = {
  getConnection, // 兼容旧版本
  executeQuery, // 新的查询方法
  executePaginatedQuery, // 新的分页查询方法
}
