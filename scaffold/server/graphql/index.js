// 聚合 server/apis/*.js（resolver 映射）与 server/schema/*.js（SDL 片段），构建可执行 schema
const fs = require('fs')
const path = require('path')
const { createSchema } = require('graphql-yoga')

const SCHEMA_DIR = path.join(__dirname, '..', 'schema')
const APIS_DIR = path.join(__dirname, '..', 'apis')

function readFieldNames(sdlText) {
  // 从 SDL 片段中提取顶层字段名：形如 `name(...): Type`
  const names = new Set()
  const re = /(\w+)\s*\(/g
  let m
  while ((m = re.exec(sdlText)) !== null) {
    names.add(m[1])
  }
  return names
}

function build() {
  const queryNames = new Set()
  const mutationNames = new Set()
  const typeBlocks = []
  let queryBlock = ''
  let mutationBlock = ''

  fs.readdirSync(SCHEMA_DIR).forEach((file) => {
    if (!file.endsWith('.js')) return
    const mod = require(path.join(SCHEMA_DIR, file))
    if (mod.query) {
      queryBlock += mod.query + '\n'
      readFieldNames(mod.query).forEach((n) => queryNames.add(n))
    }
    if (mod.mutation) {
      mutationBlock += mod.mutation + '\n'
      readFieldNames(mod.mutation).forEach((n) => mutationNames.add(n))
    }
    if (mod.type) typeBlocks.push(mod.type)
    if (mod.subscription) {
      typeBlocks.push('type Subscription {\n' + mod.subscription + '\n}')
    }
  })

  const typeDefs = [
    'type Query {',
    queryBlock,
    '}',
    'type Mutation {',
    mutationBlock,
    '}',
    ...typeBlocks,
  ].join('\n')

  const resolvers = { Query: {}, Mutation: {} }
  fs.readdirSync(APIS_DIR).forEach((file) => {
    if (!file.endsWith('.js')) return
    const mod = require(path.join(APIS_DIR, file))
    Object.keys(mod).forEach((fnName) => {
      if (typeof mod[fnName] !== 'function') return
      if (queryNames.has(fnName)) resolvers.Query[fnName] = mod[fnName]
      else if (mutationNames.has(fnName)) resolvers.Mutation[fnName] = mod[fnName]
      else resolvers.Query[fnName] = mod[fnName] // 兜底
    })
  })

  return createSchema({ typeDefs, resolvers })
}

module.exports = { schema: build() }
