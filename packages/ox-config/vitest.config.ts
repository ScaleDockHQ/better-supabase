import { defineConfig } from "vitest/config";

// RuleTester registers its cases through the global `describe` and `it`.
export default defineConfig({ test: { globals: true } });
