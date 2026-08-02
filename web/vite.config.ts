/// <reference types="vitest/config" />
import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    proxy: {
      // 开发期将 /api 代理到 P01 服务端（对齐 P01 API 契约）
      '/api': {
        target: 'http://127.0.0.1:8080',
        changeOrigin: true,
      },
    },
  },
  test: {
    environment: 'jsdom',
    globals: true, // 启用 RTL 自动清理（@testing-library/react 依赖全局 afterEach）
    setupFiles: './src/test/setup.ts',
  },
})
