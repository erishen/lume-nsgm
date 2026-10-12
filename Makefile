# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

-include .env
LUME := $(or $(LUME_CORE_BIN),lume-core)
# lume 宿主（带 server/route/run 与 sql 内建）；运行生成项目用，.env 可配 LUME_BIN
LUME_HOST := $(or $(LUME_BIN),lume)
TARGET = main.lume

.PHONY: run base dev init check test serve clean

run:
	$(LUME) $(TARGET) example-config.json

# run 的别名：产物为以 lume 为底的可运行工程（app.lume + modules + SQLite）
base: run

# 用 lume 宿主运行生成项目（需先 make run；宿主二进制路径写 .env 的 LUME_BIN）
serve:
	cd gen && $(LUME_HOST) app.lume

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
