import { Provider } from 'react-redux'
import { ConfigProvider } from 'antd'
import { useStore } from '@/redux/store'
import 'antd/dist/reset.css'

export default function App({ Component, pageProps }: any) {
  const store = useStore(pageProps.initialReduxState)
  return (
    <ConfigProvider>
      <Provider store={store}>
        <Component {...pageProps} />
      </Provider>
    </ConfigProvider>
  )
}
