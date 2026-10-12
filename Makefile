# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

-include .env
LUME := $(or $(LUME_CORE_BIN),lume-core)
TARGET = main.lume

.PHONY: run dev init check test clean

run:
	$(LUME) $(TARGET) example-config.json

dev:
	$(LUME) $(TARGET) create user

# 交互式字段录入后生成：echo "name varchar required searchable" | make init MODULE=product
init:
	$(LUME) $(TARGET) init $(MODULE)

check:
	$(LUME) --check $(TARGET)
	$(LUME) --check lib/tpl.lume
	$(LUME) --check tests/t3.lume
	$(LUME) --check tests/t4.lume

# 运行型测试：t1/t2/t3 仅打印（冒烟，确保不崩）；t4 为 sql_default() 回归断言，
# 其 main() 返回失败计数即退出码，断言失败则 make test 非零退出。
test:
	@for f in tests/t1.lume tests/t2.lume tests/t3.lume; do \
		echo "=== running $$f ==="; \
		$(LUME) $$f >/dev/null || exit 1; \
	done; \
	echo "=== running tests/t4.lume (sql_default regression) ==="; \
	$(LUME) tests/t4.lume

clean:
	rm -rf gen
