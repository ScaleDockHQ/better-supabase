import type { ResolvedConfig } from "../../config/index.ts";

import { isRecord } from "../guards.ts";

/**
 * The `json` option of every `standardSchema()` generator: `table.column` to
 * `./path.ts#schemaName`, the project's Standard Schema setup. Later generators
 * win over earlier ones.
 */
export function standardSchemaJson(
  generators: ResolvedConfig["generators"],
): ReadonlyMap<string, string> {
  const found = new Map<string, string>();

  for (const generator of generators) {
    const options = generator.options;

    if (generator.name !== "standard-schema" || !isRecord(options)) {
      continue;
    }

    const json = options["json"];

    if (!isRecord(json)) {
      continue;
    }

    for (const [key, spec] of Object.entries(json)) {
      if (typeof spec === "string") {
        found.set(key, spec);
      }
    }
  }

  return found;
}
