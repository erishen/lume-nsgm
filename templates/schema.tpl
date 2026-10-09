module.exports = {
    query: `
        {{ctrl}}(page: Int, pageSize: Int): {{P}}
        {{ctrl}}Get(id: Int): {{C}}
        {{ctrl}}BatchGet(ids: [Int]): [{{C}}]
        {{ctrl}}Search(page: Int, pageSize: Int, data: {{C}}SearchInput): {{P}}
    `,
    mutation: `
        {{ctrl}}Add(data: {{C}}AddInput): Int
        {{ctrl}}BatchAdd(datas: [{{C}}AddInput]): Int
        {{ctrl}}Update(id: Int, data: {{C}}AddInput): Boolean
        {{ctrl}}Delete(id: Int): Boolean
        {{ctrl}}BatchDelete(ids: [Int]): Boolean
    `,
    subscription: ``,
    type: `
        type {{C}} {
{{type_fields}}
        }

        type {{P}} {
            totalCounts: Int
            items: [{{C}}]
        }

        input {{C}}AddInput {
{{input_fields}}
        }

        input {{C}}SearchInput {
{{search_fields}}
        }
    `
};