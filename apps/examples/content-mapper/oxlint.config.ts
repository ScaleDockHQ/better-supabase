import { defineConfig } from "oxlint";

// @boundaries-ignore the root lint and format config is repo tooling, not a package
import root, { ignorePatterns, settings } from "../../../oxlint.config.ts";

export default defineConfig({
  extends: [root],
  settings,
  ignorePatterns,
  overrides: [
    {
      // Examples read env where they create the client, the way the
      // generated templates do, so they stay copyable.
      files: ["**/*.ts"],
      rules: { "node/no-process-env": "off" },
    },
    {
      // tsgolint checks with its own TypeScript 7.0, which runs no content
      // mapper, so every type from schema.bsb is an error type and these
      // rules flag each use (1 finding today, in index.ts).
      // `tsc --runExternalCode` in typecheck checks these files instead.
      files: ["src/**/*.ts", "tests/**/*.ts"],
      rules: {
        "typescript/no-unsafe-argument": "off",
        "typescript/no-unsafe-assignment": "off",
        "typescript/no-unsafe-call": "off",
        "typescript/no-unsafe-member-access": "off",
        "typescript/no-unsafe-return": "off",
      },
    },
  ],
});
