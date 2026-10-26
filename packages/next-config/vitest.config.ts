import type { ViteUserConfig } from "vitest/config";

import { defineConfig } from "vitest/config";

const config: ViteUserConfig = defineConfig({
  test: { include: ["tests/**/*.test.ts"] },
});

export default config;
