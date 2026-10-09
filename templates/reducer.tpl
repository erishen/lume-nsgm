import { createSlice, createAsyncThunk } from '@reduxjs/toolkit'
import {
  search{{C}}Service,
  add{{C}}Service,
  update{{C}}Service,
  delete{{C}}Service,
} from '@/service/{{ctrl}}'

const initialState = {
  totalCounts: 0,
  items: [],
  loading: false,
}

export const fetch{{C}}List = createAsyncThunk('{{ctrl}}/fetchList', async (params: any) => {
  const res = await search{{C}}Service(params.page, params.pageSize, params.data)
  return res.data
})

export const create{{C}} = createAsyncThunk('{{ctrl}}/create', async (data: any) => {
  await add{{C}}Service(data)
  return true
})

export const update{{C}} = createAsyncThunk('{{ctrl}}/update', async ({ id, data }: { id: number; data: any }) => {
  await update{{C}}Service(id, data)
  return true
})

export const remove{{C}} = createAsyncThunk('{{ctrl}}/remove', async (id: number) => {
  await delete{{C}}Service(id)
  return id
})

const {{ctrl}}Slice = createSlice({
  name: '{{ctrl}}',
  initialState,
  reducers: {},
  extraReducers: (builder) => {
    builder
      .addCase(fetch{{C}}List.pending, (state) => { state.loading = true })
      .addCase(fetch{{C}}List.fulfilled, (state, action) => {
        state.loading = false
        state.totalCounts = action.payload.totalCounts
        state.items = action.payload.items
      })
      .addCase(fetch{{C}}List.rejected, (state) => { state.loading = false })
  },
})

export default {{ctrl}}Slice.reducer