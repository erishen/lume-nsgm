import { createAction } from '@reduxjs/toolkit'
import {
  search{{C}}Service,
  add{{C}}Service,
  update{{C}}Service,
  delete{{C}}Service,
} from '@/service/{{ctrl}}'

export const search{{C}} = createAction<string | object>('{{ctrl}}/search{{C}}')
export const add{{C}} = createAction<object>('{{ctrl}}/add{{C}}')
export const mod{{C}} = createAction<{ id: number; data: object }>('{{ctrl}}/mod{{C}}')
export const del{{C}} = createAction<number>('{{ctrl}}/del{{C}}')

export const set{{C}}Data = createAction<{ totalCounts: number; items: any[] }>('{{ctrl}}/setData')