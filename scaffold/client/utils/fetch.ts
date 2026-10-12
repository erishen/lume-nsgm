// GraphQL 客户端封装（最小版，替代 nsgm 的 CSRF/axios 实现）
// 生成的 service 期望 getLocalGraphql(query, variables) 返回 GraphQL 信封 { data, errors }

export const getLocalGraphql = async (query: string, variables: any = {}) => {
  const endpoint = process.env.NEXT_PUBLIC_GRAPHQL_URL || 'http://localhost:4000/graphql'
  const res = await fetch(endpoint, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ query, variables }),
  })
  return await res.json()
}
