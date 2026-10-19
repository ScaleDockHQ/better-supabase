/**
 * Renders `schemas/config-v1.json` from the config schema and the options
 * schema of every block, then formats it with Oxfmt.
 */
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import {
  CONFIG_SCHEMA,
  renderConfigSchema,
} from "../tests/config/config-json-schema.ts";

await writeFile(CONFIG_SCHEMA, renderConfigSchema());

execFileSync("pnpm", ["exec", "oxfmt", fileURLToPath(CONFIG_SCHEMA)], {
  stdio: "inherit",
});

console.log("wrote schemas/config-v1.json");
