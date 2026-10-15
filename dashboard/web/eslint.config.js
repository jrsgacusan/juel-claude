import js from "@eslint/js"
import globals from "globals"
import reactHooks from "eslint-plugin-react-hooks"
import reactRefresh from "eslint-plugin-react-refresh"
import tseslint from "typescript-eslint"
import { defineConfig, globalIgnores } from "eslint/config"

export default defineConfig([
  // shadcn's generated files are not linted (spec D14): use-mobile.ts fails
  // react-hooks/set-state-in-effect as generated, and `shadcn add --overwrite` must stay clean.
  globalIgnores([
    "dist",
    "dev-public",
    "playwright-report",
    "test-results",
    "src/components/ui",
    "src/hooks/use-mobile.ts",
  ]),
  {
    files: ["**/*.{ts,tsx}"],
    extends: [
      js.configs.recommended,
      tseslint.configs.recommended,
      reactHooks.configs.flat.recommended,
      reactRefresh.configs.vite,
    ],
    languageOptions: {
      globals: globals.browser,
    },
    rules: {
      "react-refresh/only-export-components": "off",
    },
  },
])
