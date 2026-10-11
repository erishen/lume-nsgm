# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

include .env
LUME ?= $(LUME_CORE_BIN)
TARGET = main.lume

.PHONY: run dev init check clean

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

clean:
	rm -rf gen
