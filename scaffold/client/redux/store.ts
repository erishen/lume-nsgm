import { combineReducers, configureStore } from '@reduxjs/toolkit'
import { useMemo } from 'react'
import reducers from './reducers'

const reducer = combineReducers({ ...reducers })

export type RootState = ReturnType<typeof reducer>

const tempStore = configureStore({
  reducer,
  middleware: (getDefaultMiddleware) => getDefaultMiddleware({ serializableCheck: false }),
})
export type AppDispatch = typeof tempStore.dispatch

let store: any

export function useStore(initialState?: any) {
  return useMemo(() => {
    if (!store) {
      store = configureStore({
        reducer,
        preloadedState: initialState,
        middleware: (getDefaultMiddleware) => getDefaultMiddleware({ serializableCheck: false }),
      })
    }
    return store
  }, [])
}
