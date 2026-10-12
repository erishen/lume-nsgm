# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

-include .env
LUME := $(or $(LUME_CORE_BIN),lume-core)
# 生成项目运行时：lume-core（0.6.0 起自带 server/route/run、sql_query/sql_write、
# docroot 静态与 :name 动态路由，单二进制即可跑生成物）；.env 可配 LUME_BIN 覆盖
LUME_RUN := $(or $(LUME_BIN),lume-core)
TARGET = main.lume

.PHONY: run base dev create init check test serve web-install clean

# 源比产物新（或产物缺失）则判定过期：main.lume / 配置 / lib / scaffold / templates 任一文件
# （*.md 是纯文档，排除）
GEN_STAMP := $(wildcard gen/app.lume)
STALE := $(if $(GEN_STAMP),$(shell find main.lume example-config.json lib scaffold templates -type f -newer $(GEN_STAMP) ! -name '*.md' 2>/dev/null | head -1),yes)

run:
	$(LUME) $(TARGET) example-config.json
	@$(MAKE) --no-print-directory web-install

# run 的别名：产物为以 lume 为底的可运行工程（app.lume + modules + SQLite）
base: run

# 开发模式：产物缺失或源有更新时先重新生成（含 web 依赖幂等安装），
# 然后前台启动 lume-core 服务（Ctrl-C 退出）
dev:
ifeq ($(STALE),)
	@echo "==> 产物已是最新，直接启动"
else
	@echo "==> 产物缺失或源有更新，先重新生成..."
	@$(MAKE) --no-print-directory run
endif
	cd gen && $(LUME_RUN) app.lume

# gen/web 依赖安装（run 生成后自动触发，也可单独调用）：
# - 幂等：node_modules/.pnpm 比 package.json 新（或同刻）则跳过；
# - pnpm 缺失时降级为 corepack pnpm；都没有则提示手动，不报错——
#   依赖安装失败不影响已生成的工程本体。
web-install:
	@if [ ! -d gen/web ]; then exit 0; fi; \
	if [ gen/web/node_modules/.pnpm -nt gen/web/package.json ] 2>/dev/null; then \
	  echo "==> gen/web 依赖已就绪，跳过 pnpm install"; exit 0; fi; \
	if command -v pnpm >/dev/null 2>&1; then PM="pnpm"; \
	elif command -v corepack >/dev/null 2>&1; then PM="corepack pnpm"; \
	else echo "==> 未找到 pnpm/corepack，请手动安装: cd gen/web && pnpm install"; exit 0; fi; \
	echo "==> gen/web 依赖安装 ($$PM)..."; \
	(cd gen/web && $$PM install --silent) \
	  && echo "==> gen/web 依赖就绪" \
	  || echo "==> pnpm install 失败（不影响生成物），可稍后手动: cd gen/web && pnpm install"

# 用 lume-core 运行生成项目（需先 make run；二进制路径可写 .env 的 LUME_BIN）
serve:
	cd gen && $(LUME_RUN) app.lume

# 交互式新建模块（生成后需 make dev / make run 重新产出工程）
create:
	$(LUME) $(TARGET) create $(MODULE)

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
	@for f in tests/t1.lume tests/t2.lume tests/t3.lume tests/t4.lume tests/t5.lume tests/t6.lume; do \
		echo "=== running $$f ==="; \
		$(LUME) $$f >/dev/null || exit 1; \
	done

clean:
	rm -rf gen
