# lume-nsgm

[English](README.md) · [简体中文](README.zh.md)

**An AI-friendly, deterministic CRUD generation layer**: feed it module field definitions (JSON schema) and it emits a full-stack CRUD project built on lume (SQLite storage + SSR pages + REST API + React frontend), run by a single `lume-core` binary.

> Positioning: lume-nsgm replaces **[nsgm](https://github.com/erishen/nsgm)'s generator and CLI layer** — [nsgm](https://github.com/erishen/nsgm) is the original full-stack framework (Next.js + Express + GraphQL + MySQL, published on npm as `nsgm-cli`); this project ports its generator layer onto [lume-core](https://github.com/erishen/lume-core), with zero Node dependencies. The output shape evolves from Next.js/Express + GraphQL + Antd into a **lume-core application** (`server`/`route`/`run` + built-in `sql_query`/`sql_write` + docroot static serving + `:name` dynamic routes, core ≥ 0.7.0); the generator itself is likewise interpreted by lume-core.

## Why it still matters in the AI era

Letting an AI generate an entire application directly fails because the **output space is unbounded**: every line of code is a new hallucination surface, and every generation has to be verified again from scratch. lume-nsgm splits the problem in half —

```
The AI emits only the schema (controlled, small, verifiable JSON)
   ↓
nsgm generates deterministically (injection guards / escaping / pagination
   boundaries / UI conventions — fixed once, correct everywhere; quality
   locked in by the tests/t1-t5 suites and the e2e probes)
   ↓
The AI then makes incremental edits to the lume code (small language,
   small grammar surface, minimal context burden for the AI)
```

- **AI decides, templates execute**: the schema itself is the interface handed to the AI. What the generator guarantees is "no matter who writes the schema, the output quality is identical".
- **Verify once, reuse forever**: the CRUD behavior of template output (31 baseline probes + the generator suites + UI snapshots) is already verified; hand-written AI code has to redo that whole verification cycle for every single project.
- **For the lume ecosystem**: lume-nsgm is lume's first real business-grade consumer — dynamic routes, SQLite built-ins, `json()`, and the ternary operator were all forced into existence by it. It is the touchstone that takes lume-core from toy to usable runtime.

In one line: it is not a scaffold that types for you, but a **hallucination noise filter for the AI coding era** — AI-written code running on a constrained runtime with verified templates is far more dependable than raw generation.

### Schema validation (the AI-friendly error layer)

`lib/validate.lume` runs a **one-shot full validation** of the config before generation (not one error at a time); every error carries a precise path and a fix hint, so the AI can fix everything in a single round:

```
$ lume-core main.lume bad.json
schema validation failed (2 error(s)) in "bad.json":
  1. modules[0].fields[0]: unknown type "bogus_type" (supported: varchar/text/integer/decimal/boolean/date/datetime/timestamp)
  2. modules[0].fields[1]: "name" must match [a-z][a-z0-9_]* (got "2bad")
fix the config and re-run. ...
```

Validation covers: JSON well-formedness, non-empty `modules`, module/field names matching `[a-z][a-z0-9_]*` (**the name is interpolated straight into SQL DDL and routes, so the whitelist closes the injection surface at the same time** — `"evil\"; DROP TABLE x--"` was empirically shown to slip through an unvalidated generator), a type whitelist, duplicate module/field names (route conflicts), and empty `fields`. A failed validation exits with code 1 and generation is skipped entirely (previously, a module missing a name was silently skipped while still reporting success). Regression tests: `tests/t6.lume` (16 assertions).

## Layout

```
lume-nsgm/
├── main.lume            # CLI entry (create / init / batch from config)
├── example-config.json  # batch generation config (user + order)
├── templates/           # render templates (mod / sql / react_page)
│   ├── mod.tpl          # module file template (DDL + data-driven field tables + routes + SSR pages)
│   ├── sql.tpl          # CREATE TABLE DDL export template
│   └── react_page.tpl   # per-module React page template (<Ctrl>Page.tsx)
├── lib/
│   ├── model.lume       # field model + type mapping (sql types, index filters)
│   ├── tpl.lume         # minimal template engine ({{var}} / {{#each}} / {{#if}})
│   ├── sql.lume         # SQL DDL generator (template rendering)
│   ├── modlume.lume     # module generator: data-driven field tables + routes + SSR pages
│   ├── reactgen.lume    # React frontend generator (web/: Vite + React + TS SPA)
│   ├── scaffold.lume    # file-tree writer (emits the gen/ full-stack project)
│   ├── validate.lume    # one-shot schema validation (injection guards / type whitelist / duplicates)
│   ├── assert.lume      # test assertion helpers (ok/eq/fail; main() returns the failure count as exit code)
│   └── base.lume        # runtime builtin helper references (SQL / JSON / route constants)
├── scaffold/            # static project base templates (copied into gen/)
│   ├── lib/db.lume      # SQLite access helpers (dsn / init / pagination / counts)
│   ├── lib/pay.lume     # payment library (PayPal Express Checkout): OAuth2 token / create / capture / get order / get capture / webhook verification / refund (copied into gen/)
│   ├── web/             # Vite + React + TS static shell (package.json / vite / tsconfig / main / api)
│   └── www/             # SSR static styles + fallback JS (app.css / app.js)
├── tests/
│   ├── t1.lume          # model / sql generator verification (13 assertions)
│   ├── t2.lume          # modlume / reactgen module and frontend generator verification
│   ├── t3.lume          # template engine verification (each / if / variable substitution)
│   ├── t4.lume          # sql_default() regression assertions
│   ├── t5.lume          # React frontend generator regression assertions
│   ├── t6.lume          # schema validation regression assertions (16 assertions, validate.lume)
│   └── t7.lume          # payment regression assertions (signature vectors / validate_pay / field defaults)
├── scripts/
│   ├── mock_pay_gateway.py  # mock PayPal gateway (OAuth2/create/capture/get order/get capture/refund — an independent implementation cross-checked against the lume side)
│   ├── check-privacy.py     # pre-publish privacy self-check (local paths / private workspace names / credential forms in tracked files)
│   └── e2e.sh          # e2e probes: boot the generated project + curl through SSR/CRUD/search/pagination/migration/payment
├── Dockerfile / docker-compose.yml / docker-build.sh   # containerized deployment (see "Docker deployment")
├── example-paypal.json # PayPal payment variant generation config (the plain variant is example-config.json above)
├── Makefile            # task entry: create / init / run / serve / dev / check / test / test-e2e / check-privacy / docker-* / clean
├── .gitignore          # ignore scope: .env / gen/ (default output) / gen-paypal/ (e2e scratch output)
├── TODO.md             # roadmap and known boundaries
├── ARCHITECTURE.zh.md  # architecture deep-dive (Chinese): generation pipeline, runtime routing, payment subsystem
├── SECURITY.md         # vulnerability reporting policy
├── LICENSE             # MIT
└── .env.example        # .env template (LUME_CORE_BIN path; the .env file itself is git-ignored)
```

## Prerequisites: install lume-core

lume-nsgm itself is nothing but `.lume` scripts and templates — **running it requires a lume-core runtime** (the compiler / CLI binary). lume-core is a self-built single-file C11 project that depends on nothing beyond libc (plus libLLVM when `llvm-config` is detected); no node / pnpm / SQLite required.

### Option 1: one-line install (recommended)

Download the prebuilt tarball for your platform; the binary lands in `~/.local/bin/lume-core` (examples + docs land in `~/.local/share/lume-core`):

```bash
curl -sSfL https://raw.githubusercontent.com/erishen/lume-core/main/install.sh | sh
```

Overridable environment variables (`export` them before the piped command):

| Variable | Default | Meaning |
|---|---|---|
| `LUME_CORE_VERSION` | `latest` | version tag to install |
| `LUME_CORE_PREFIX`  | `$HOME/.local` | install root (`$PREFIX/bin`) |
| `LUME_CORE_SHA256`  | — | expected sha256 of the tarball (verified only when set) |
| `LUME_CORE_REPO`    | `erishen/lume-core` | GitHub repo used for the download |

### Option 2: build from source

Dependencies: a C11 compiler (`cc`); for the native compilation capability `--compile-llvm`, `llvm-config` must be on `PATH` (on macOS, brew's install under `/opt/homebrew/opt/llvm` is auto-detected). **You can still build `bin/lume-core` without LLVM** — only `--compile-llvm` becomes unavailable.

```bash
git clone <lume-core repo> lume-core && cd lume-core
make           # -> bin/lume-core
make check     # self-check: all built-in examples pass type checking
# optional: sudo cp bin/lume-core /usr/local/bin/lume-core
```

Windows (**MSYS2's MINGW64 shell**, not MSVC):

```bash
pacman -S base-devel mingw-w64-x86_64-toolchain mingw-w64-x86_64-clang
make           # -> bin/lume-core.exe
```

> On Windows, `--watch` and the outbound HTTP builtins (`http_get` etc.) are not yet available, but lume-nsgm only uses the interpreter + file I/O + `read_stdin`, so it is unaffected.

### Pointing lume-nsgm at the runtime

Pick one of two ways:

1. Put `lume-core` on `PATH` (option 1 installs to `~/.local/bin` by default — add it to `PATH` yourself), then just run `make run`;
2. Create a `.env` in the lume-nsgm root with an absolute path (on Windows, `lume-core.exe`):

   ```bash
   # lume-nsgm/.env
   LUME_CORE_BIN=/Users/you/.local/bin/lume-core        # macOS / Linux
   # LUME_CORE_BIN=E:/Workspace/lume-core/bin/lume-core.exe   # Windows
   ```

   The Makefile already resolves this via `-include .env` + `$(or $(LUME_CORE_BIN),lume-core)`: with a `.env`, its absolute path wins; without one, it falls back to `lume-core` on PATH.

  > `.env` is the only file read here — nothing in this repo loads `.env.local` (a Vite convention); putting the path there would silently do nothing.

## Usage

```bash
# Batch: read example-config.json and generate the user + order modules
make run

# Single module: template fields from the command line
make dev

# Interactive field entry, then generate (stdin, one field per line: name type [required] [searchable], blank line ends)
echo "name varchar required searchable" | make init MODULE=product

# Syntax check (includes template engine t3)
make check

# Pre-publish privacy self-check (local paths / private workspace names / credential forms in tracked files; also part of make test)
make check-privacy

# Generator assertion suite (t1-t6)
make test

# E2E probes: boot the generated project + curl through SSR/static/CRUD/search/pagination/migration (scripts/e2e.sh)
make test-e2e

# Clean the generated directory
make clean
```

You can also call it directly:

```bash
# Direct invocation, bypassing make (requires lume-core on PATH, or point LUME_CORE_BIN in .env at it)
lume-core main.lume example-config.json
lume-core main.lume create order
lume-core main.lume init product
# Windows: replace lume-core with lume-core.exe (or set LUME_CORE_BIN in .env)
```

Output lands in `./gen/` (**a runnable project built on lume**: lume-core serving the backend + React frontend):

```
gen/
├── app.lume               # entry: server block + module assembly (import registers routes) + table creation + run()
├── lib/
│   ├── ui.lume            # SSR component library (nav injected from the module list)
│   └── db.lume            # SQLite access helpers (dsn/init/pagination/counts)
├── modules/{module}.lume  # per module: DDL + data-driven field tables + routes + SSR pages
├── sql/{module}.sql       # CREATE TABLE DDL export (identical to the in-module copy, for manual review)
├── web/                   # React frontend (Vite + React + TS, managed with pnpm)
│   ├── package.json / vite.config.ts / tsconfig.json / index.html
│   └── src/
│       ├── main.tsx / App.tsx    # entry + hash router + module nav
│       ├── api.ts                # JSON API client
│       ├── pages/{Ctrl}Page.tsx  # per-module page (list/controlled form/pagination/delete confirm)
│       └── ui.css                # styles (same source as the SSR app.css)
├── www/app.css            # SSR static styles (served by the server docroot)
└── data/app.db            # SQLite database (created at runtime)
```

## Running the generated project

What `make run` (or `make base`) emits is **a runnable project built on lume**; the runtime needs only the lume-core binary ≥ 0.7.0 (the generated lume modules use the ternary operator introduced in 0.7.0 — 0.6.0 fails to parse it; it ships `server`/`route`/`run`, built-in `sql_query`/`sql_write`, docroot static serving and `:name` dynamic routes):

```bash
cd gen

# lume-core binary (built from the lume-core repo with make -> bin/lume-core)
lume-core app.lume

# React frontend (the main UI): make run already runs pnpm install for gen/web;
# only re-install manually if you change web dependencies; dev/build work as-is
cd web
pnpm dev            # http://localhost:5173, /api proxied by Vite to lume :8081
```

- Tables are created automatically on first start (`CREATE TABLE IF NOT EXISTS`, SQLite file `data/app.db`; override the file with `env NSGM_DB`; SQLite is the only built-in backend)
- **Automatic schema-evolution migration**: after changing fields and regenerating, tables that already exist in the old database automatically get the missing columns added via `ALTER TABLE ADD COLUMN` (bare types; existing rows read as NULL) — no data loss, no `no such column` on startup; auto-increment primary key columns are excluded
- The server block reads `PORT` / `HOST` / `WORKERS` from the environment (defaults when unset: `8081` / `127.0.0.1` / `4`; the interpreter backend is required — the Docker build forces `HAVE_LLVM=0`), e.g. `PORT=9000 lume-core app.lume`
- **React frontend (the main UI)**: `pnpm dev` serves on :5173 with a generated `<Ctrl>Page.tsx` per module (search/pagination/controlled form/delete confirm/`fmtTime` localized time columns), hash-router navigation; `pnpm build && pnpm preview` gives a production preview (same /api proxy, no CORS)
- SSR fallback pages: http://localhost:8081/ → per-module list pages (search/create/edit/delete are all SSR forms, no JS needed)
- JSON API: `GET /api/{module}?page=0&pageSize=20&q=keyword`, `GET /api/{module}/:id`, `POST /api/{module}` (JSON body insert), `POST /api/{module}/update/:id`, `POST /api/{module}/delete/:id` (this is exactly the API the React frontend consumes)
- From the lume-nsgm root you can also `make serve` (reads `LUME_BIN` from `.env`, defaulting to `lume-core`)

> Note: SSR forms are designed for GET submission (`req.query_params` is already URL-decoded and can be read directly); programmatic writes go through POST + JSON body (`json()` parsing). `%` / `_` in search input are escaped literally (`LIKE ? ESCAPE "\"`) and never treated as wildcards. API behavior is locked in by `make test-e2e` (SSR/static/CRUD/dynamic routes/search/wildcard escaping/pagination/qs_int fallback/legacy-database migration).

## Docker deployment

Package **the generated full-stack application** (lume-core backend + React frontend + SQLite) into a single image; `docker compose up --build` brings it up on `:18081` (container port 18081, >10000, clear of common low ports). At build time the image:

1. Compiles the `lume-core` binary from `lume-core` source (with the SQLite backend, auto-enabled when `libsqlite3` is detected);
2. Runs the generator `main.lume example-config.json` with that binary to **deterministically regenerate** `gen/`;
3. Builds the React frontend with `pnpm` (output mounted at `/spa/` with a relative base), served as static files by lume-core's docroot.

> The build context must be `work/lume` (the parent directory of `lume-core` and `lume-nsgm`), because the Dockerfile needs both the lume-core source and the generator source. Companion files are provided: `Dockerfile` / `docker-compose.yml` / `docker-build.sh`, plus the Makefile's `docker-*` commands.

```bash
# Option 1: Makefile (recommended — handles build context, ports and the data volume automatically)
make docker-build     # build the image (compile lume-core + regenerate + build the frontend)
make docker-up        # start in the background (--build on first run), host port defaults to 18081
make docker-logs      # follow the logs
make docker-ps        # show container status
make docker-down      # stop and remove the container (the nsgm-data volume is kept)
make docker-clean     # stop and remove the container + volume (wipes data — careful)

# Override the host port (the container always listens on 18081):
make docker-up DOCKER_PORT=19090

# Option 2: compose directly
cd lume-nsgm
docker compose up --build          # first build (compile lume-core + regenerate + build the frontend)
docker compose up -d              # run in the background
docker compose down               # stop and remove the container (the nsgm-data volume is kept)

# Option 3: script (locates the parent directory as the build context automatically)
./docker-build.sh                 # produces the image lume-nsgm-app:latest
docker run --rm -p 18081:18081 -v lume-nsgm-data:/app/data lume-nsgm-app:latest
```

Access (port defaults to 18081; override the host port with `DOCKER_PORT`):

- Home / SSR pages: `http://localhost:18081/`
- React SPA (the main UI): `http://localhost:18081/spa/` (hash router, same-origin `/api`)
- REST API: `http://localhost:18081/api/<module>`

In-container configuration (the compose `environment` section; the generated project reads these from env, container port fixed at 18081):

| Variable | In-container value | Meaning |
|---|---|---|
| `PORT` | `18081` | listen port (>10000, clear of common low ports) |
| `HOST` | `0.0.0.0` | bind address (lume-core defaults to `127.0.0.1`; containers must open up) |
| `WORKERS` | `1` | prefork worker count (multiple workers occasionally hit init inconsistencies on Linux) |
| `NSGM_DB` | `/app/data/app.db` | SQLite data file path |

- **Health check**: compose ships a `healthcheck` (probes `GET /` every 30s; both build configurations have that route, so `docker compose ps` shows `healthy`)
- **Schema evolution**: after changing fields, re-run `make docker-build`; on container restart the missing columns are added automatically via `ALTER TABLE ADD COLUMN` and old data in the volume is preserved
- **Payment variant build**: `docker build --build-arg NSGM_CONFIG=example-paypal.json -t lume-nsgm-app:paypal .` (same `work/lume` build context) — the image runs the generated project with PayPal payment routes; sensitive items such as client_secret are still injected via environment variables (`PAYPAL_KEY` etc.) and never baked into the image layer

Data persistence: the SQLite file lives at `/app/data/app.db` inside the container, mounted as the named volume `nsgm-data` (override the path with the `NSGM_DB` environment variable).

## Payment (PayPal Express Checkout, full sandbox-mock chain)

On top of the plain CRUD generation, nsgm can generate **e-commerce projects with a closed payment loop**: place an order → redirect to approve → callback capture → order status transitions. The usage is to swap in a config with a `pay` section (`example-paypal.json`):

```bash
lume-core main.lume example-paypal.json
PAYPAL_KEY=<sandbox secret> lume-core gen/app.lume
python3 scripts/mock_pay_gateway.py --port 18097
```

> Default mock gateway credentials (the app side and the gateway side must match, or authentication fails): `MOCK_PAYPAL_CLIENT_ID=AUmock_client_id_sandbox_001` / `MOCK_PAYPAL_CLIENT_SECRET=e2e-mock-key` (corresponding to the config's `client_id` and `PAYPAL_KEY`). Changing values requires changing both sides.

The `pay` section of the config (fully validated by `validate_pay` in `lib/validate.lume`):

| Key | Meaning |
|---|---|
| `client_id` | public identifier (sandbox `AU...`); safe to commit; goes into the `Authorization` header |
| `secret_env` | **the environment variable name holding client_secret** (e.g. `PAYPAL_KEY`) — generated code reads it via `env("<name>")`, so the secret never enters the config or the output |
| `mode` | `sandbox` / `live` (selects `api-m.sandbox.paypal.com` vs `api-m.paypal.com`) |
| `order_module` / `order_no_field` / `amount_field` / `status_field` | order table and field bindings (all four names must already be defined) |
| `webhook_path` | optional async event route (not generated by default; when configured, a `post "<webhook_path>"` route is generated) |
| `currency` / `currency_symbol` / `brand` | optional; default `USD` / `$` / `lume-nsgm`; `currency_symbol` drives the amount symbol on the storefront / admin / cashier / return pages (now config-driven instead of the previously hardcoded `$`) |

> ⚠️ **Naming pitfall for `secret_env`**: lume-core's `env()` **masks** variables whose names contain the substrings `API_KEY` / `SECRET` / `PASSWORD` / `PASSWD` / `TOKEN` / `CREDENTIAL` (case-insensitive) — reading them yields null, indistinguishable from unset (`env_is_sensitive` in `src/builtins_fs.c`, a guard against scripts leaking credentials). Hence PayPal uses `PAYPAL_KEY`; **do not** call it `PAYPAL_CLIENT_SECRET` (a PayPal e2e run once 401'd because an empty secret failed Basic auth).

A generated payment project has four extra routes plus a `lib/pay.lume`:

- `POST /api/pay/create`: read the order → `pay.paypal_token` (OAuth2 `client_credentials` for a Bearer token, module-level cache ~8h) → `pay.paypal_create` (`POST /v2/checkout/orders`, intent=CAPTURE) → return JSON `{ ok, approve_url, paypal_order_id }` (the frontend redirects accordingly)
- `GET /api/pay/return`: read `token` and `order_no` from `req.query_params` → `pay.paypal_capture` (`POST .../capture`) → set `status` to `paid` (idempotent; already-paid returns the success page directly; backfills `paypal_order_id` + `capture_id` on capture success)
- `GET /api/pay/cancel`: user cancelled; returns the cancel page
- `POST /api/pay/webhook` (optional): `pay.paypal_verify_webhook` simplified HMAC verification

Pure functions exported by `lib/pay.lume` (locked in as known-answer vectors by `tests/t7.lume`):

```lume
pay.paypal_base_url(mode)              // sandbox/live → base URL
pay.paypal_basic_auth(id, secret)     // "Basic " + base64(id:secret) (RFC7617)
pay.paypal_fmt_cents(cents)           // integer cents → "x.xx" (no floats)
pay.fmt_cents(cents)                  // amount display alias (storefront/admin shared)
pay.paypal_token(cfg)                 // OAuth2 client_credentials → { ok, token }
pay.paypal_create(cfg, token, no, cents, desc, ret, cancel) // → { ok, approve_url, paypal_order_id }
pay.paypal_approve_url(cfg, ppid)     // rebuild the approve URL from the order ID (cashier reuse)
pay.paypal_capture(cfg, token, pp_order_id)                   // → { ok, status, capture_id }
pay.paypal_get_order(cfg, token, pp_order_id)                 // get order (refund capture_id fallback)
pay.paypal_get_capture(cfg, token, capture_id)                // get capture (fallback after an order GET 404: related_ids.order_id reverses the order number)
pay.paypal_refund(cfg, token, capture_id, cents, note)        // refund (capture-level)
pay.paypal_verify_webhook(secret, id, ts, body, sign_hex)    // HMAC(id\n+ts\n+body\n)
```

Known boundaries (details in TODO.md S7):

- **Simplified webhook verification**: real PayPal webhook signatures include `crc32(body)` (core has no crc32 builtin yet); this library's `paypal_verify_webhook` is a pure-HMAC sandbox-equivalent implementation; the three verification elements (`verify_id` / `verify_ts` / `verify_sign`) travel with the body
- **return via query_params**: PayPal redirects back with `?token=...`, and `req.query_params` is already URL-decoded and directly readable (same convention as SSR forms); at creation time the local `order_no` is encoded into the `return_url` itself, avoiding a server-side PayPal-order-ID → local-order-number mapping table
- **OAuth2 is easier to inline than SHA256-RSA**: PayPal's HTTP Basic credentials only need the `base64_encode` builtin — the reason PayPal was chosen as the payment channel
- **No random source**: business order numbers are derived by the generator (`order_no + now()`), sufficient for the sandbox
- **The 422 issue code for duplicate refunds is not unique** (empirically confirmed against the real sandbox on 2026-10-17): refunding an already fully refunded capture returns `CAPTURE_FULLY_REFUNDED` (the `ALREADY_REFUNDED` written in the docs and the old mock never appears); `paypal_refund` reconciles `ALREADY_REFUNDED` / `CAPTURE_FULLY_REFUNDED` / `REFUND_ALREADY_EXISTS` / `DUPLICATE` as success alike, so "already refunded" never shows up as a false failure
- **Order number ≠ transaction number**: the "Transaction ID" in the PayPal dashboard is the **capture ID**; entering it as the order number makes `GET /v2/checkout/orders/{id}` return 404 `RESOURCE_NOT_FOUND`/`INVALID_RESOURCE_ID` (empirically confirmed against the real sandbox on 2026-10-17) — after an order reverse-lookup 404, the refund route automatically retries against `GET /v2/payments/captures/{id}`, reverses the real order number via `supplementary_data.related_ids.order_id`, and backfills both columns with the correct values

Regression: `make test` includes t7 (PayPal known-answer vectors / validate_pay / field defaults); `make test-e2e` locks in the full PayPal sandbox chain — create → approve_url → return capture → `status:"paid"` → idempotent repeat return → webhook verification → cashier reuse against orphan orders → refund and stock restock → **early-order recovery with both association IDs empty** (`need_recover` hint → the `/shop/recover/:ono` form's `capid` direct route / `ppid` reverse lookup / `manual` local marking / **transaction number (capture ID) typed into the order-number field, auto-retried against the capture endpoint** — all four paths end with `refunded` persisted) → **product catalog example seeding and clear-and-reload** (empty table auto-seeds → `?act=clear` clears without touching orders → no auto-resurrection → `?act=seed` manual reload → non-empty guard).

### Storefront (the shop section, customer-facing e-commerce UI)

`pay` solves "collect the money", `shop` solves "sell the goods": with a `shop` section configured (alongside `pay`), the generated project gains a customer-facing SSR storefront (the nav gets a "Shop" entry):

| Route | Behavior |
|---|---|
| `get /shop` | Product card list (name / price / description / stock); **one-time demo seeding on an empty table** (with `stock_field` configured, seeds 10/5/0 so the sold-out state is demonstrated directly), manageable via the admin `<product_module>`. The page carries a **"Clear products"** button (after confirm, `?act=clear` deletes row by row with parameters — the `sql_write` guard forbids DELETE without WHERE; order records are unaffected); after clearing, a "seeded" marker is left in the `_nsgm_shop_meta` meta table so it **never auto-resurrects**, and the empty state offers "Load example products" (`?act=seed`, seeds only when the table is empty). Clear/reload returns to this route without consuming extra route slots: the lume-core interpreter's route table caps at 32 entries (`MAX_AL_ROUTES`), and the PayPal variant was already close |
| `get /shop/buy/:id?ik=` | Place an order and deduct stock (compensation mode, see below) → redirect to the cashier; `ik` is the idempotency key against duplicate orders |
| `get /shop/pay/:ono` | Cashier: **reuses** the order's stored `paypal_order_id` to rebuild the approve URL — repeated renders never create duplicate orders (no orphans) |
| `get /shop/result/:ono` | Payment result page (paid → success with the amount; pending → continue payment) |
| `get /shop/refund/:ono` | Refund: confirmation page, `?confirm=1` executes; only `paid` is refundable, duplicate refunds are idempotent; **stock is restored +1 after a successful gateway refund**. Association IDs are normalized (`paypal_order_id`/`capture_id` SQL NULL reads as lume null and is normalized first); when an old order lacks `capture_id`, `pay.paypal_get_order` reverse-lookup serves as fallback — an order GET 404 (i.e. a transaction/capture ID was entered) automatically retries `pay.paypal_get_capture`, reverses the real order number, and proceeds with the refund |
| `get /shop/recover/:ono` | **Recover association IDs for early orders** (early orders whose `paypal_order_id` and `capture_id` are both NULL because they predate the migration columns): enter the PayPal order number **or the transaction number (capture ID, auto-detected)** in the order-number field to reverse-lookup the capture record, or enter the capture ID directly (straight to refund), or mark "already refunded manually in the PayPal dashboard" to persist locally (no API call). On refund success the association IDs are backfilled (the reversed real order number + the capture ID), keeping subsequent operations consistent |

Configuration (`example-paypal.json`):

```json
"shop": {
  "product_module": "product",
  "order_module": "order",
  "name_field": "name",
  "price_field": "price_cents",
  "stock_field": "stock",
  "product_field": "product_id",
  "product_name_field": "product_name"
}
```

`validate_shop` (lib/validate.lume) checks: product_module must be defined; name/price fields must actually exist; `stock_field` depends on `product_field` (restocking stock needs the order row to locate the product row); `product_field` / `product_name_field` must be defined on `pay.order_module` and well-shaped. Storefront orders write to the same order table bound by the `pay` section, and callbacks reuse the payment wiring's verification/idempotency/persistence logic — **the storefront and the payment flow share one status-transition pipeline**.

**Order-time stock deduction (compensation mode, TODO P1-2)**: without transactions (S2), the sequence is
① INSERT the order (with the `product_id` / `product_name` product snapshot, when the fields are configured)
② `UPDATE product SET stock = stock - 1 WHERE id = ? AND stock >= 1` (a single atomic statement doubles as the stock guard; `sql_write` returns the affected row count, 0 = sold out / lost a race)
③ on 0 rows, compensate by DELETEing the pending order and returning a "sold out" page (the button is also greyed out and unclickable).
INSERT-first rather than deduct-then-create: the guard UPDATE is the atomic stock operation, and it avoids the dangling state of "stock deducted but no order". With `product_field` configured, a duplicate order with the same `ik` reuses the most recent pending order (no unique index required).

**PayPal cashier reuse (no orphan orders)**: on every render of `/shop/pay/:ono`, if the order already has a `paypal_order_id`, the approve URL is rebuilt directly from the order ID (mock gateway: `{gateway}/mock/paypal/approve?token=<order ID>`; real: `https://{www|www.sandbox}.paypal.com/checkoutnow?token=<order ID>`) without calling the create-order endpoint; on create-order success the `paypal_order_id` is backfilled onto the order row (that column is added by the automatic migration).

**Migration note**: after upgrading an old database, the `product.stock` column is SQL NULL — on the lume side `str(null)` is the literal string `"null"` rather than an empty string (storefront product cards / admin lists / form prefills all normalize this, so `null` never renders), but **demo products need their stock filled in from the admin**, or purchases will be rejected by the guard UPDATE with 0 rows.

## Field definitions (example-config.json)

```json
{
  "db": "crm_demo",
  "out": "./gen",
  "modules": [
    {
      "name": "user",
      "fields": [
        { "name": "id", "type": "integer", "required": true, "primary": true, "auto": true,
          "system": true, "showInList": true, "showInForm": false, "searchable": false, "comment": "ID" },
        { "name": "name", "type": "varchar", "length": 255, "required": true,
          "showInList": true, "showInForm": true, "searchable": true, "comment": "Name" }
      ]
    }
  ]
}
```

Supported types: `varchar` / `text` / `integer` / `decimal` / `boolean` / `date` / `datetime` / `timestamp`.
Field attributes: `required` / `primary` / `auto` / `system` / `showInList` / `showInForm` / `searchable` / `comment` / `length`.

## M2 status

Completed (M1's six core generators + M2's two gaps):
- **lume-core `read_stdin()` builtin**: `read_stdin()` reads one line (newline stripped), `read_stdin("all")` reads everything, EOF/empty input returns `""` — paving the way for the interactive init command
- **Template rendering engine `lib/tpl.lume`**: syntax `{{var}}` (dot paths), `{{#each list as it}}...{{/each}}` (supports inlining per-line templates via directives), `{{#if path}}...{{else}}...{{/if}}` (line-level if, nestable); the generator migrated from string concatenation to `templates/*.tpl` template rendering
- **Interactive init command**: field entry via stdin, one per line, then generate (`make init MODULE=product`)

Not included yet (future iterations): file upload, CSV export, full i18n integration, field-level custom validators (validation currently lives at the schema layer in `validate.lume`; generated artifacts only enforce required / basic type checks).

## Relationship with lume-core

lume-nsgm is lume's **first real business-grade application** (in the generator space), and it drives lume-core to add builtins in return:
- P0: `json` decoding, `argv()`, recursive `files()`
- P4a: string builtins `upper/lower/capitalize/trim/contains/split/join/substr`
- M1 fixes: `join()` passes string elements through verbatim (no JSON quoting); join of an empty list returns `""` instead of `null`
- M2: `read_stdin()` builtin (interactive stdin input); template engine pitfalls: `split("}}")` cuts through `{{else}}`/`{{/if}}` and needs reassembly, `head` is a reserved word, `fbool` must accept both bool true and the number 1
- Base switch (core ≥ 0.7.0): self-contained SQLite builtins (`sql_query`/`sql_write`), bidirectional `json()`, docroot static serving, `:name` dynamic routes
- Language feature (core 0.7.0): **the ternary operator** (lazy evaluation, adjacency disambiguation) — the direct driver behind UI conditional rendering like `q != "" ? ... : ...` in generated templates
