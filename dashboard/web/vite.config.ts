/// <reference types="vitest/config" />
import { resolve } from "node:path"
import tailwindcss from "@tailwindcss/vite"
import react from "@vitejs/plugin-react"
import { defineConfig } from "vite"

export default defineConfig(({ command }) => ({
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: {
      "@": resolve(import.meta.dirname, "./src"),
    },
  },
  // The build has no public folder at all, so the MSW worker never reaches dist/ (brief D3).
  publicDir: command === "serve" ? "dev-public" : false,
  server:
    process.env.VITE_MOCK === "off"
      ? {
          proxy: {
            "/api": `http://127.0.0.1:${process.env.STAR_DASHBOARD_PORT ?? "4767"}`,
          },
        }
      : undefined,
  test: {
    environment: "jsdom",
    setupFiles: ["./src/test/setup.ts"],
    include: ["src/**/*.test.{ts,tsx}"],
    exclude: ["e2e/**"],
    css: false,
  },
}))
