import React, { useState, useEffect } from 'react'
import { ConfigProvider, Modal, Space, message } from 'antd'
import {
  Container,
  SearchRow,
  ModalContainer,
  StyledButton,
  StyledInput,
  StyledTable,
  ModalInput,
  GlobalStyle,
} from '@/styled/{{ctrl}}'
import { useDispatch, useSelector } from 'react-redux'
import {
  search{{C}},
  add{{C}},
  mod{{C}},
  del{{C}},
} from '@/redux/{{ctrl}}/actions'
import { get{{C}}Service } from '@/service/{{ctrl}}'
import { RootState, AppDispatch } from '@/redux/store'
import _ from 'lodash'

const pageSize = 100

const Page = ({ {{ctrl}} }) => {
  const dispatch = useDispatch<AppDispatch>()
  const [isModalVisiable, setIsModalVisible] = useState(false)
  const [modalId, setModalId] = useState(0)
{{search_hook}}  const [batchDelIds, setBatchDelIds] = useState([])

  useEffect(() => {
    dispatch(search{{C}}({ page: 0, pageSize }))
  }, [dispatch])

  const {{ctrl}}Data = useSelector((state: RootState) => state.{{ctrl}})
  const { totalCounts, items: {{ctrl}}Items } = _.cloneDeep({{ctrl}}Data)

  const dataSource = {{ctrl}}Items

  const onSearch = () => {
    dispatch(search{{C}}({ page: 0, pageSize, data: { {{search_arg}} } }))
  }

  const openAdd = () => {
    setModalId(0)
    setIsModalVisible(true)
  }

  const openEdit = (record: any) => {
    setModalId(record.id)
    setIsModalVisible(true)
  }

  const handleOk = (values: any) => {
    if (modalId) {
      dispatch(mod{{C}}({ id: modalId, data: values }))
    } else {
      dispatch(add{{C}}(values))
    }
    setIsModalVisible(false)
  }

  const onDelete = (record: any) => {
    dispatch(del{{C}}(record.id))
  }

  return (
    <ConfigProvider>
      <GlobalStyle />
      <Container>
        <SearchRow>
{{search_input}}          <StyledButton type="primary" onClick={onSearch}>搜索</StyledButton>
          <StyledButton onClick={openAdd}>新增</StyledButton>
        </SearchRow>
        <StyledTable
          rowKey="id"
          columns={columns}
          dataSource={dataSource}
          pagination={{ total: totalCounts }}
        />
      </Container>
      <Modal
        visible={isModalVisiable}
        onCancel={() => setIsModalVisible(false)}
        onOk={() => handleOk({})}
      >
        <ModalContainer>
{{modal}}        </ModalContainer>
      </Modal>
    </ConfigProvider>
  )
}

const columns = [
{{cols}}  { title: '操作', dataIndex: 'action', render: (_: any, record: any) => (
    <Space>
      <StyledButton onClick={() => openEdit(record)}>编辑</StyledButton>
      <StyledButton danger onClick={() => onDelete(record)}>删除</StyledButton>
    </Space>
  ) },
]

export default Page