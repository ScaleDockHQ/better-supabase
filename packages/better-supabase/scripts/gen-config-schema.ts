/**
 * Renders `schemas/config-v1.json` from the config schema and the options
 * schema of every block, and `schemas/design-v1.json` from the design
 * schema, then formats them with Oxfmt.
 */
import { execFileSync } from "node:child_process";
import { writeFile } from "node:fs/promises";
import { fileURLToPath } from "node:url";

import {
  CONFIG_SCHEMA,
  renderConfigSchema,
} from "../tests/config/config-json-schema.ts";
import {
  DESIGN_SCHEMA,
  renderDesignSchema,
} from "../tests/config/design-json-schema.ts";

await writeFile(CONFIG_SCHEMA, renderConfigSchema());

await writeFile(DESIGN_SCHEMA, renderDesignSchema());

execFileSync(
  "pnpm",
  ["exec", "oxfmt", fileURLToPath(CONFIG_SCHEMA), fileURLToPath(DESIGN_SCHEMA)],
  { stdio: "inherit" },
);

console.log("wrote schemas/config-v1.json and schemas/design-v1.json");
