/**
 * 通用验证工具（复刻 nsgm server/utils/validation.js）
 */

const validateInteger = (value, fieldName = 'value', options = {}) => {
  const { min = Number.MIN_SAFE_INTEGER, max = Number.MAX_SAFE_INTEGER, required = false } = options

  if (value === undefined || value === null || value === '') {
    if (required) {
      throw new Error(`${fieldName}是必填字段`)
    }
    return undefined
  }

  let numericValue = value

  if (typeof value === 'string') {
    numericValue = parseInt(value.trim(), 10)
    if (isNaN(numericValue)) {
      throw new Error(`${fieldName}必须是数字，收到的值: "${value}"`)
    }
  }

  if (!Number.isInteger(numericValue)) {
    throw new Error(`${fieldName}必须是整数，收到的值: ${value}`)
  }

  if (numericValue < min || numericValue > max) {
    throw new Error(`${fieldName}必须在${min}-${max}之间，收到的值: ${value}`)
  }

  return numericValue
}

const validatePagination = (page, pageSize) => {
  const validPage = validateInteger(page, 'page', { min: 0, max: 999999 }) || 0
  const validPageSize = validateInteger(pageSize, 'pageSize', { min: 1, max: 100 }) || 10

  return { page: validPage, pageSize: validPageSize }
}

const validateId = (id, fieldName = 'ID') => {
  return validateInteger(id, fieldName, { min: 1, required: true })
}

module.exports = {
  validateInteger,
  validatePagination,
  validateId,
}
