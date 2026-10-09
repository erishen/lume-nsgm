import { getLocalGraphql } from '@/utils/fetch'
import _ from 'lodash'

export const get{{C}}Service = (page = 0, pageSize = 10) => {
  const get{{C}}Query = `query ($page: Int, $pageSize: Int) { {{ctrl}}(page: $page, pageSize: $pageSize) { 
        totalCounts items { 
          {{sel}}
        } 
      } 
    }`

  return getLocalGraphql(get{{C}}Query, {
    page,
    pageSize
  })
}

export const search{{C}}ByIdService = (id: number) => {
  const search{{C}}ByIdQuery = `query ($id: Int) { {{ctrl}}Get(id: $id){
      {{sel}}
    }
  }`

  return getLocalGraphql(search{{C}}ByIdQuery, {
    id
  })
}

export const search{{C}}Service = (page = 0, pageSize = 10, data: any) => {
  const { {{s_names}} } = data

  const search{{C}}Query = `query ($page: Int, $pageSize: Int, $data: {{C}}SearchInput) { 
    {{ctrl}}Search(page: $page, pageSize: $pageSize, data: $data) {
      totalCounts items { 
        {{sel}}
      } 
    }
  }`

  return getLocalGraphql(search{{C}}Query, {
    page,
    pageSize,
    data
  })
}

export const add{{C}}Service = (data: any) => {
  const { {{f_names}} } = data

  const add{{C}}Query = `mutation ($data: {{C}}AddInput) { {{ctrl}}Add(data: $data) }`

  return getLocalGraphql(add{{C}}Query, {
    data
  })
}

export const update{{C}}Service = (id: number, data: any) => {
  const { {{f_names}} } = data

  const update{{C}}Query = `mutation ($id: Int, $data: {{C}}AddInput) { {{ctrl}}Update(id: $id, data: $data) }`

  return getLocalGraphql(update{{C}}Query, {
    id,
    data
  })
}

export const delete{{C}}Service = (id: number) => {
  const delete{{C}}Query = `mutation ($id: Int) { {{ctrl}}Delete(id: $id) }`

  return getLocalGraphql(delete{{C}}Query, {
    id
  })
}