# syntax=docker/dockerfile:1
#
# lume-nsgm 生成工程的容器化构建。
#
# 构建上下文必须是 work/lume（lume-core 与 lume-nsgm 的父目录），
# 因为本 Dockerfile 需要同时拿到 lume-core 源码与生成器源码：
#
#   cd work/lume
#   docker build -f lume-nsgm/Dockerfile -t lume-nsgm-app .
#
# 或直接使用仓库内的 docker-build.sh / docker-compose.yml。
#
# 多阶段：
#   1) core-build : 从源码编 lume-core 二进制（含 SQLite 后端，依赖 libsqlite3）
#   2) app-build  : 用 lume-core 确定性重新生成 gen/，再用 pnpm 构建 React 前端
#   3) runtime    : 最小运行镜像，起 `lume-core app.lume`（监听 :18081）

# ---------------------------------------------------------------------------
# Stage 1 — 编译 lume-core
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS core-build

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        make \
        pkg-config \
        libsqlite3-dev \
        libcrypt-dev \
        libssl-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /core

# core 构建只需 src/ 与 Makefile；版本号在 Makefile 写死为 0.7.0，不依赖 git。
# SQLite 通过探测 libsqlite3-dev 自动编入（builtins_sql.c），否则会编出
# “built without libsqlite3” 的运行时 stub，所以上面必须装 libsqlite3-dev。
COPY lume-core/src ./src
COPY lume-core/Makefile ./Makefile

# 强制纯文本后端（HAVE_LLVM=0）：与本地可用的 478KB 二进制一致、可移植；
# LLVM 后端（1.8MB）在 Linux 容器内与 prefork(workers>1) 配合偶发不稳。
RUN make bin/lume-core HAVE_LLVM=0 \
    && ./bin/lume-core --version \
    && ls -l bin/lume-core

# ---------------------------------------------------------------------------
# Stage 2 — 生成应用 + 构建前端
# ---------------------------------------------------------------------------
FROM node:20-bookworm-slim AS app-build

# 国内网络友好：pnpm 与依赖都走 npmmirror
ENV COREPACK_NPM_REGISTRY=https://registry.npmmirror.com
ENV PNPM_REGISTRY=https://registry.npmmirror.com

RUN corepack enable \
    && corepack prepare pnpm@12.11.2 --activate \
    && pnpm config set registry https://registry.npmmirror.com

# lume-core 动态链 libsqlite3 / libcrypt / libssl，node 基础镜像不带其运行时 .so，
# 必须先装，否则 COPY 进来的二进制运行时会 “not found”(127) / libssl.so.3 缺失。
RUN apt-get update && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        libcrypt1 \
        libssl3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# lume-core 二进制（来自 Stage 1）
COPY --from=core-build /core/bin/lume-core /usr/local/bin/lume-core
RUN lume-core --version

# 生成器源码（不含生成产物 gen/，运行时由下面这一步确定性生成）
COPY lume-nsgm/main.lume ./main.lume
COPY lume-nsgm/lib ./lib
COPY lume-nsgm/templates ./templates
COPY lume-nsgm/scaffold ./scaffold
COPY lume-nsgm/example-config.json ./example-config.json
COPY lume-nsgm/example-pay.json ./example-pay.json
COPY lume-nsgm/example-paypal.json ./example-paypal.json

# 构建配置：默认 example-config.json（CRUD 演示）；传
#   --build-arg NSGM_CONFIG=example-pay.json       微信支付变体
#   --build-arg NSGM_CONFIG=example-paypal.json    PayPal 变体
# 可打出带支付接线的镜像（order 模块 + pay 路由，密钥运行时由 env 注入）。
ARG NSGM_CONFIG=example-config.json

# 确定性重新生成 gen/（同 schema -> 同产物）
RUN lume-core main.lume "$NSGM_CONFIG"

# 端口/host/workers 现由 gen/app.lume 从环境变量读取（PORT/HOST/WORKERS），
# 由 docker-compose.yml 的 environment 注入（容器内固定 18081/0.0.0.0/1），
# 不再需要 sed 补丁。这里仅打印生成的 server 块做构建期核对。
RUN echo "--- server block (env-driven) ---" && grep -A6 "^server {" gen/app.lume

# 构建 React 前端。
# 用 `--base ./`（相对路径）让产物可挂在任意子路径下（本镜像挂在 /spa/），
# 与 lume-core docroot 对目录请求自动回 index.html 的行为配合。
WORKDIR /src/gen/web
RUN pnpm install \
    && pnpm exec vite build --base ./

# 把前端静态产物放进 www/spa/，由 lume-core 的 docroot 静态托管。
RUN mkdir -p /src/gen/www/spa \
    && cp -r /src/gen/web/dist/* /src/gen/www/spa/

# ---------------------------------------------------------------------------
# Stage 3 — 运行镜像
# ---------------------------------------------------------------------------
FROM debian:bookworm-slim AS runtime

# 运行时仅需 SQLite / crypt / openssl 的共享库（构建期已动态链入，运行期要 .so）；
# ca-certificates 提供根证书，否则出站 https 会因 SSL_CTX_set_default_verify_paths
# 找不到 CA 而 TLS handshake failed。
RUN apt-get update && apt-get install -y --no-install-recommends \
        libsqlite3-0 \
        libcrypt1 \
        libssl3 \
        ca-certificates \
        curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=core-build /core/bin/lume-core /usr/local/bin/lume-core

# 拷贝生成工程（只留运行所需：入口 / lib / modules / sql / www 静态）
COPY --from=app-build /src/gen/app.lume ./app.lume
COPY --from=app-build /src/gen/lib ./lib
COPY --from=app-build /src/gen/modules ./modules
COPY --from=app-build /src/gen/sql ./sql
COPY --from=app-build /src/gen/www ./www

# SQLite 数据目录（生成工程默认 data/app.db，可用 NSGM_DB 覆盖）
RUN mkdir -p /app/data
ENV NSGM_DB=/app/data/app.db

# server 配置由生成工程从 env 读（PORT/HOST/WORKERS）；容器场景给固定默认值，
# 裸 docker run 即可用（此前只靠 compose 注入，裸 run 会落到 127.0.0.1:8081）。
# compose 的 environment 段与这里同值，保持显式。
ENV PORT=18081 HOST=0.0.0.0 WORKERS=1

EXPOSE 18081

# 数据持久化：把 /app/data 挂成卷
VOLUME ["/app/data"]

CMD ["lume-core", "app.lume"]
