# 安全政策（Security Policy）

## 适用范围

lume-nsgm 是一个**本地代码生成器**：它脚手架出一个自包含的电商工程
（SSR 页面 + 后台 + 订单 + 支付适配器），由使用者自行运行与运维。
本仓库自身不部署任何服务端组件。

## 报告漏洞

请通过 GitHub 的**私密漏洞报告**（仓库页 → Security → Report a vulnerability）
提交安全问题，**不要**开公开 issue。

有帮助的信息：

- 受影响文件 / 生成代码路径（如 `scaffold/lib/pay.lume`）
- 影响面（如生成 SQL 的注入面、凭据暴露）
- 复现步骤

## 密钥处理约定

- 支付凭据一律**运行时经环境变量注入**（PayPal：`PAYPAL_CLIENT_ID` /
  `PAYPAL_KEY`；微信：`PAY_APPID` / `PAY_MCHID` / `PAY_KEY` / `PAY_SERIAL` /
  `PAY_NOTIFY_URL`），不烤进生成工程或本仓库。
- `.env` 已被 `.gitignore` 忽略；`.env.example` 只含占位符。
- `make check-privacy` 对仓库做路径/凭据形态扫描，并作为 `make test` 的前置闸。

## 受支持版本

仅支持 `main` 上的最新提交。生成工程请用最新 scaffold 重新生成，
而不是原地手改生成代码。

---

## Reporting a Vulnerability (English)

Use GitHub's private vulnerability reporting (Security → Report a
vulnerability). Please do not open public issues for security findings.
Only the latest `main` commit is supported; regenerate your project with
the newest scaffold instead of patching generated code in place.
