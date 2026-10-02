import { defineConfig } from "tsdown";

export default defineConfig({
  entry: { index: "src/index.ts", bin: "src/bin.ts" },
  platform: "node",
  fixedExtension: false,
  format: "esm",
  dts: true,
  clean: true,
  exports: false,
  deps: {
    neverBundle: [/^@supabase\//, /^better-supabase(\/|$)/, /^node:/, "pg"],
  },
});
