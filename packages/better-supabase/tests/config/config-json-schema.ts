/**
 * Renders the `blocks` part of `schemas/config-v1.json` from the options
 * schema of every SQL module (`BLOCK_OPTION_SCHEMAS`), so the JSON Schema
 * and the `BlocksConfig` type come from one source.
 * `scripts/gen-config-schema.ts` writes it; `config-json-schema.test.ts`
 * fails when the file is stale.
 */
import { readFile } from "node:fs/promises";

import { BLOCK_OPTION_SCHEMAS } from "../../src/blocks/options-registry.ts";
import { optionsJsonSchema } from "../../src/blocks/options.ts";

export const CONFIG_SCHEMA: URL = new URL(
  "../../schemas/config-v1.json",
  import.meta.url,
);

type Json = Record<string, unknown>;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** `config-v1.json` with `blocks` and the `$defs/blocks` entries rendered. */
export async function renderConfigSchema(): Promise<string> {
  const schema: unknown = JSON.parse(await readFile(CONFIG_SCHEMA, "utf-8"));
  if (!isJson(schema)) throw new TypeError("config-v1.json is not an object");
  const { properties, $defs } = schema;
  if (!isJson(properties) || !isJson($defs)) {
    throw new TypeError("config-v1.json has no properties or $defs");
  }
  const { blocks } = properties;
  const { moduleConfig, accessBlock } = $defs;
  if (!isJson(blocks) || !isJson(moduleConfig) || !isJson(accessBlock)) {
    throw new TypeError("config-v1.json has no blocks or module $defs");
  }
  const modules = Object.keys(BLOCK_OPTION_SCHEMAS).sort((a, b) =>
    a.localeCompare(b),
  );
  const perModule = Object.fromEntries(
    modules.map((module) => {
      const options = Object.entries(BLOCK_OPTION_SCHEMAS).find(
        ([name]) => name === module,
      )?.[1];
      return [
        module,
        {
          $ref: `#/$defs/${module === "access" ? "accessBlock" : "moduleConfig"}`,
          type: "object",
          properties: {
            options:
              options === undefined
                ? { type: "object" }
                : optionsJsonSchema(options),
          },
        },
      ];
    }),
  );
  const rendered = {
    ...schema,
    properties: {
      ...properties,
      blocks: {
        description: blocks["description"],
        oneOf: [
          { type: "array", items: { enum: modules } },
          {
            type: "object",
            additionalProperties: false,
            properties: Object.fromEntries(
              modules.map((module) => [
                module,
                { $ref: `#/$defs/blocks/${module}` },
              ]),
            ),
          },
        ],
      },
    },
    $defs: { ...$defs, blocks: perModule },
  };
  return `${JSON.stringify(rendered, null, 2)}\n`;
}
