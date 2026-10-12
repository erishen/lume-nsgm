import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// 开发（pnpm dev）与生产预览（pnpm preview）都把 /api 代理到 lume 宿主，
// 浏览器始终同源，免 CORS 配置。
const apiTarget = process.env.LUME_API || "http://127.0.0.1:8081";

export default defineConfig({
  plugins: [react()],
  server: {
    proxy: { "/api": apiTarget }
  },
  preview: {
    proxy: { "/api": apiTarget }
  }
});
