/**
 * Renders `schemas/design-v1.json` from the design's valibot schema
 * (`configSchemas().design`), which reuses the config's `appTables` schema.
 * `scripts/gen-config-schema.ts` writes it; `design-json-schema.test.ts`
 * fails when the file is stale.
 */
import { toJsonSchema } from "@valibot/to-json-schema";

import { configSchemas } from "../../src/cli/config-schema.ts";
import { DESIGN_FORMAT } from "../../src/preset/index.ts";
import { tidy } from "./config-json-schema.ts";

export const DESIGN_SCHEMA: URL = new URL(
  "../../schemas/design-v1.json",
  import.meta.url,
);

/** `design-v1.json`, rendered. */
export function renderDesignSchema(): string {
  const rendered = tidy(
    toJsonSchema(configSchemas().design, { target: "draft-2020-12" }),
  );

  if (typeof rendered !== "object" || rendered === null) {
    throw new TypeError("toJsonSchema returned no object");
  }

  const schema = {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    $id: "https://unpkg.com/better-supabase/schemas/design-v1.json",
    title: "better-supabase design",
    description: `A design from app.bettersupabase.com/create: app tables, extra columns on block tables and canvas positions, up to format ${String(DESIGN_FORMAT)}. This schema checks the shape; designSchema and parseDesign in better-supabase/preset also check names, defaults and limits.`,
    ...rendered,
  };

  return `${JSON.stringify(schema, null, 2)}\n`;
}
