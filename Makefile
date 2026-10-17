# lume-nsgm — 用 lume 实现的 nsgm 生成器引擎（TS 全栈 CRUD 生成器）

-include .env
LUME := $(or $(LUME_CORE_BIN),lume-core)
# 生成项目运行时：lume-core（0.7.0+ 自带 server/route/run、sql_query/sql_write、
# docroot 静态与 :name 动态路由，单二进制即可跑生成物）；.env 可配 LUME_BIN / LUME_CORE_BIN 覆盖
LUME_RUN := $(or $(LUME_BIN),$(LUME_CORE_BIN),lume-core)
TARGET = main.lume

.PHONY: run base dev create init check check-privacy test serve web-install clean \
        docker-build docker-up docker-down docker-logs docker-ps docker-clean \
        test-e2e

# Docker 相关变量（可用 make ... DOCKER_PORT=19090 覆盖宿主端口）
DOCKER_PORT  ?= 18081
DOCKER_IMAGE ?= lume-nsgm-app:latest
DOCKER_NAME  ?= lume-nsgm-app

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
	$(LUME) --check tests/t6.lume
	$(LUME) --check tests/t7.lume

# 发布前隐私自检：扫描 git 跟踪文件里的本机路径 / 私有工作区名 / 凭据形态
# （有意例外需在 scripts/check-privacy.py 的 ALLOW 里登记并写理由）。
# make test 已内含本检查（前置闸）。
check-privacy:
	python3 scripts/check-privacy.py

# 运行型测试：t3 为模板引擎冒烟；t1/t2/t4/t5 为断言型回归（sql_default、模块生成器
# 数据层/路由层、React 前端生成器），t6 为 schema 校验回归，t7 为支付接线回归
# （pay.lume 已知向量 + validate_pay + 字段级 default），各自 main() 返回失败计数即
# 退出码，断言失败则 make test 非零退出。前置隐私自检（check-privacy）先跑。
test: check-privacy
	@fail=0; \
	for f in tests/t1.lume tests/t2.lume tests/t3.lume tests/t4.lume tests/t5.lume tests/t6.lume tests/t7.lume; do \
		echo "=== running $$f ==="; \
		if ! $(LUME) $$f; then echo "FAILED: $$f"; fail=1; fi; \
	done; \
	if [ $$fail -ne 0 ]; then echo "make test: $$fail suite(s) failed"; exit 1; fi; \
	echo "make test: all suites passed"

clean:
	rm -rf gen

# ---------------------------------------------------------------------------
# Docker — 容器化运行生成的全栈应用（构建上下文 = work/lume 父目录）
#
#   make docker-build   # 构建镜像（编译 lume-core + 重新生成 + 构建前端），宿主端口默认 18081
#   make docker-up      # 后台启动（首次自动 --build），端口 ${DOCKER_PORT}:18081
#   make docker-logs    # 跟踪容器日志
#   make docker-ps      # 查看容器状态
#   make docker-down    # 停止并移除容器（数据卷 nsgm-data 保留）
#   make docker-clean   # 停止并删除容器 + 数据卷（会清空数据，谨慎）
#
# 说明：容器内始终监听 18081（>10000，避开常用低位端口）；宿主端口默认 18081，
# 可用 make docker-up DOCKER_PORT=19090 覆盖。OrbStack 下 buildx 活动追踪偶发
# “operation not permitted”，统一用 DOCKER_BUILDKIT=0（legacy builder）规避。
# ---------------------------------------------------------------------------

# 构建镜像（构建上下文为父目录 work/lume，因为 Dockerfile 需同时拿到
# lume-core 源码与生成器源码）。
docker-build:
	DOCKER_BUILDKIT=0 docker build -f Dockerfile -t $(DOCKER_IMAGE) ..

# 后台启动（端口 DOCKER_PORT -> 容器 18081，数据卷持久化）。
docker-up:
	DOCKER_BUILDKIT=0 DOCKER_PORT=$(DOCKER_PORT) docker compose up -d --build

# 跟踪日志。
docker-logs:
	docker compose logs -f

# 容器状态。
docker-ps:
	docker compose ps

# 停止并移除容器（数据卷 nsgm-data 保留，数据不丢）。
docker-down:
	docker compose down

# 停止并删除容器 + 数据卷（会清空数据，谨慎使用）。
docker-clean:
	docker compose down -v

# ---------------------------------------------------------------------------
# 端到端测试 — 起生成工程 + curl 跑 SSR / 静态 / CRUD / 搜索 / 分页，固化底座行为为回归套件。
# 不依赖 pnpm / 前端构建（只测 lume 后端）。可用 E2E_PORT / E2E_DB / LUME 覆盖。
# ---------------------------------------------------------------------------
test-e2e:
	LUME="$(LUME)" ./scripts/e2e.sh
