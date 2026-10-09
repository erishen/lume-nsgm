const { executeQuery, executePaginatedQuery } = require('../../utils/common')
const { validatePagination, validateId } = require('../../utils/validation')

module.exports = {
    // 获取{{ctrl}}列表（分页）
    {{ctrl}}: async ({ page = 0, pageSize = 10 }) => {
        try {
            const { page: validPage, pageSize: validPageSize } = validatePagination(page, pageSize);

            const sql = 'SELECT {{sel}} FROM `{{ctrl}}` LIMIT ? OFFSET ?';
            const countSql = 'SELECT COUNT(*) as counts FROM `{{ctrl}}`';
            const values = [validPageSize, validPage * validPageSize];

            return await executePaginatedQuery(sql, countSql, values);
        } catch (error) {
            console.error('获取{{ctrl}}列表失败:', error.message);
            throw error;
        }
    },

    // 根据ID获取{{ctrl}}
    {{ctrl}}Get: async ({ id }) => {
        try {
            const validId = validateId(id);

            const sql = 'SELECT {{sel}} FROM `{{ctrl}}` WHERE id = ?';
            const values = [validId];

            const rows = await executeQuery(sql, values);
            if (!rows || rows.length === 0) {
                throw new Error(`ID为 ${validId} 的{{ctrl}}不存在`);
            }

            return rows[0];
        } catch (error) {
            console.error('获取{{ctrl}}失败:', error.message);
            throw error;
        }
    },

    // 搜索{{ctrl}}（分页）
    {{ctrl}}Search: async ({ page = 0, pageSize = 10, data = {} }, context) => {
        try {
            const { page: validPage, pageSize: validPageSize } = validatePagination(page, pageSize);

            const values = [];
            let whereSql = '';
{{conds}}
            const sql = 'SELECT {{sel}} FROM `{{ctrl}}` WHERE 1=1' + whereSql + ' LIMIT ? OFFSET ?';
            const countSql = 'SELECT COUNT(*) as counts FROM `{{ctrl}}` WHERE 1=1' + whereSql;

            values.push(validPageSize, validPage * validPageSize);

            return await executePaginatedQuery(sql, countSql, values);
        } catch (error) {
            console.error('搜索{{ctrl}}失败:', error.message);
            throw error;
        }
    },

    // 添加{{ctrl}}
    {{ctrl}}Add: async ({ data }) => {
        try {
            if (!data) {
                throw new Error('添加数据不能为空');
            }

            const sql = 'INSERT INTO `{{ctrl}}` ({{ins_fields}}) VALUES ({{ins_q}})';
            const values = [{{ins_vals}}];

            console.log('添加{{ctrl}}:', { sql, values });

            const results = await executeQuery(sql, values);
            return results.insertId;
        } catch (error) {
            console.error('添加{{ctrl}}失败:', error.message);
            throw error;
        }
    },

    // 更新{{ctrl}}
    {{ctrl}}Update: async ({ id, data }) => {
        try {
            const validId = validateId(id);

            if (!data) {
                throw new Error('更新数据不能为空');
            }

            const sql = 'UPDATE `{{ctrl}}` SET {{upd}} WHERE id = ?';
            const values = [{{ins_vals}}, validId];

            console.log('更新{{ctrl}}:', { sql, values });

            const results = await executeQuery(sql, values);
            if (results.affectedRows === 0) {
                throw new Error(`ID为 ${validId} 的{{ctrl}}不存在`);
            }

            return true;
        } catch (error) {
            console.error('更新{{ctrl}}失败:', error.message);
            throw error;
        }
    },

    // 删除{{ctrl}}
    {{ctrl}}Delete: async ({ id }) => {
        try {
            const validId = validateId(id);

            const sql = 'DELETE FROM `{{ctrl}}` WHERE id = ?';
            const values = [validId];

            console.log('删除{{ctrl}}:', { sql, values });

            const results = await executeQuery(sql, values);
            if (results.affectedRows === 0) {
                throw new Error(`ID为 ${validId} 的{{ctrl}}不存在`);
            }

            return true;
        } catch (error) {
            console.error('删除{{ctrl}}失败:', error.message);
            throw error;
        }
    }
};