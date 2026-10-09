# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

LUME = E:/Workspace/lume-core/bin/lume-core
TARGET = main.lume

.PHONY: run dev check clean

run:
	$(LUME) $(TARGET) example-config.json

dev:
	$(LUME) $(TARGET) create user

check:
	$(LUME) --check $(TARGET)
	$(LUME) --check tests/t1.lume
	$(LUME) --check tests/t2.lume

clean:
	rmdir /s /q gen 2>nul || (rd /s /q gen 2>nul & exit 0)
