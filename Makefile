# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

-include .env
LUME := $(or $(LUME_CORE_BIN),lume-core)
# 生成项目运行时：lume-core（0.6.0 起自带 server/route/run、sql_query/sql_write、
# docroot 静态与 :name 动态路由，单二进制即可跑生成物）；.env 可配 LUME_BIN 覆盖
LUME_RUN := $(or $(LUME_BIN),lume-core)
TARGET = main.lume

.PHONY: run base dev init check test serve clean

run:
	$(LUME) $(TARGET) example-config.json

# run 的别名：产物为以 lume 为底的可运行工程（app.lume + modules + SQLite）
base: run

# 用 lume-core 运行生成项目（需先 make run；二进制路径可写 .env 的 LUME_BIN）
serve:
	cd gen && $(LUME_RUN) app.lume

dev:
	$(LUME) $(TARGET) create user

# 交互式字段录入后生成：echo "name varchar required searchable" | make init MODULE=product
init:
	$(LUME) $(TARGET) init $(MODULE)

check:
	$(LUME) --check $(TARGET)
	$(LUME) --check lib/tpl.lume
	$(LUME) --check tests/t1.lume
	$(LUME) --check tests/t2.lume
	$(LUME) --check tests/t3.lume
	$(LUME) --check tests/t4.lume
	$(LUME) --check tests/t5.lume

# 运行型测试：t3 为模板引擎冒烟；t1/t2/t4/t5 为断言型回归（sql_default、模块生成器
# 数据层/路由层、React 前端生成器），各自 main() 返回失败计数即退出码，
# 断言失败则 make test 非零退出。
test:
	@for f in tests/t1.lume tests/t2.lume tests/t3.lume tests/t4.lume tests/t5.lume; do \
		echo "=== running $$f ==="; \
		$(LUME) $$f >/dev/null || exit 1; \
	done

clean:
	rm -rf gen
