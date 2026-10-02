import { defineConfig } from "oxlint";

import {
  core,
  ignorePatterns,
  library,
  node,
  test,
} from "@better-supabase/ox-config/oxlint";

export default defineConfig({
  extends: [core, node, library, test],
  ignorePatterns: [...ignorePatterns],
  overrides: [
    {
      // Oxlint loads JS plugins from the module's default export.
      files: ["src/anti-slop/index.ts"],
      rules: { "import/no-default-export": "off" },
    },
    {
      // The rule against "shape" in names is itself named after the word.
      files: [
        "src/anti-slop/index.ts",
        "src/anti-slop/rules/no-shape-in-symbol-names.ts",
        "tests/anti-slop/rules/no-shape-in-symbol-names.test.ts",
      ],
      rules: { "anti-slop/no-shape-in-symbol-names": "off" },
    },
  ],
});
