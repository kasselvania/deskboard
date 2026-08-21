import { fileURLToPath, URL } from "node:url";

import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "@deskboard/contracts": fileURLToPath(
        new URL("./packages/contracts/src/index.ts", import.meta.url),
      ),
    },
  },
  test: {
    environment: "node",
    environmentOptions: {
      jsdom: {
        url: "http://localhost/board",
      },
    },
    include: [
      "packages/**/*.test.ts",
      "apps/**/*.test.ts",
      "apps/**/*.test.tsx",
    ],
    setupFiles: ["./apps/web/test/setup.ts"],
    restoreMocks: true,
  },
});
