/**
 * Renders `schemas/config-v1.json` from the config's valibot schema
 * (`configSchemas()`), the options schema of every block
 * (`BLOCK_OPTION_SCHEMAS`) and the descriptions in `config-annotations.ts`,
 * so the JSON Schema, the CLI's config check and the `BetterSupabaseConfig`
 * type come from one source. `scripts/gen-config-schema.ts` writes it;
 * `config-json-schema.test.ts` fails when the file is stale.
 */
import { toJsonSchema } from "@valibot/to-json-schema";

import { BLOCK_OPTION_SCHEMAS } from "../../src/blocks/options-registry.ts";
import { optionsJsonSchema } from "../../src/blocks/options.ts";
import { configSchemas } from "../../src/cli/config-schema.ts";
import { PRESET_NAMES } from "../../src/preset/index.ts";
import { type Annotation, CONFIG_ANNOTATIONS } from "./config-annotations.ts";

export const CONFIG_SCHEMA: URL = new URL(
  "../../schemas/config-v1.json",
  import.meta.url,
);

type Json = Record<string, unknown>;

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function child(node: Json, key: string): Json | undefined {
  const value = node[key];

  return isJson(value) ? value : undefined;
}

/** The nodes a config path step leads to, through union members. */
function step(node: Json, segment: string): Json[] {
  const members = [node["anyOf"], node["oneOf"]]
    .filter(Array.isArray)
    .flat()
    .filter(isJson);

  if (members.length > 0) {
    return members.flatMap((member) => step(member, segment));
  }

  if (segment === "*") {
    const rest = child(node, "additionalProperties");

    return rest === undefined ? [] : [rest];
  }

  if (segment === "[]") {
    const items = child(node, "items");

    return items === undefined ? [] : [items];
  }

  const property = child(node, "properties")?.[segment];

  return isJson(property) ? [property] : [];
}

const SEGMENT = /\[\]|[^.[\]]+/g;

function annotate(root: Json, path: string, annotation: Annotation): void {
  const segments = path.match(SEGMENT) ?? [];

  const start =
    segments[0] === "$defs"
      ? child(child(root, "$defs") ?? {}, segments[1] ?? "")
      : root;

  const rest = segments[0] === "$defs" ? segments.slice(2) : segments;

  const nodes = rest.reduce<Json[]>(
    (current, segment) => current.flatMap((node) => step(node, segment)),
    start === undefined ? [] : [start],
  );

  if (nodes.length === 0) {
    throw new Error(`config-annotations.ts: no ${path} in the config schema`);
  }

  for (const node of nodes) {
    Object.assign(node, annotation);
  }
}

function blocksSchema(description: unknown): {
  readonly blocks: Json;
  readonly perModule: Json;
} {
  const modules = Object.keys(BLOCK_OPTION_SCHEMAS).sort((a, b) =>
    a.localeCompare(b),
  );

  const options = new Map(Object.entries(BLOCK_OPTION_SCHEMAS));

  const perModule = Object.fromEntries(
    modules.map((module) => {
      const schema = options.get(module);

      return [
        module,
        {
          $ref: `#/$defs/${module === "access" ? "accessBlock" : "moduleConfig"}`,
          type: "object",
          properties: {
            options:
              schema === undefined
                ? { type: "object" }
                : optionsJsonSchema(schema),
          },
        },
      ];
    }),
  );

  return {
    blocks: {
      description,
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
    perModule,
  };
}

/** Drops what toJsonSchema writes that says nothing: `required: []` and string `propertyNames`. */
export function tidy(node: unknown): unknown {
  if (Array.isArray(node)) {
    return node.map(tidy);
  }

  if (!isJson(node)) {
    return node;
  }

  return Object.fromEntries(
    Object.entries(node)
      .filter(
        ([key, value]) =>
          !(key === "required" && Array.isArray(value) && value.length === 0) &&
          !(
            key === "propertyNames" &&
            JSON.stringify(value) === JSON.stringify({ type: "string" })
          ),
      )
      .map(([key, value]) => [key, tidy(value)]),
  );
}

/** `config-v1.json`, rendered. */
export function renderConfigSchema(): string {
  const {
    config,
    environment,
    moduleConfig,
    accessBlock,
    privilege,
    triggerValue,
    generator,
  } = configSchemas();

  const rendered: unknown = tidy(
    toJsonSchema(config, {
      target: "draft-2020-12",
      definitions: {
        environment,
        moduleConfig,
        accessBlock,
        privilege,
        triggerValue,
      },
      // `rawCheck` runs the authorization scope checks, which have no JSON
      // Schema keyword.
      ignoreActions: ["raw_check"],
      overrideSchema: ({ valibotSchema }) => {
        if (valibotSchema === generator) {
          return { type: "object" };
        }

        if (
          "getter" in valibotSchema &&
          typeof valibotSchema.getter === "function" &&
          valibotSchema.getter(undefined) === triggerValue
        ) {
          return { $ref: "#/$defs/triggerValue" };
        }

        // `blocks` is a list or an object, rendered from the block manifests.
        return valibotSchema.type === "lazy" ? {} : undefined;
      },
    }),
  );

  if (!isJson(rendered)) {
    throw new TypeError("toJsonSchema returned no object");
  }

  const properties = child(rendered, "properties") ?? {};

  // The `blocks` lazy schema leaves numbered definitions nothing references.
  const $defs = Object.fromEntries(
    Object.entries(child(rendered, "$defs") ?? {}).filter(
      ([name]) => !/^\d+$/.test(name),
    ),
  );

  const entries = Object.keys(
    child(child($defs, "environment") ?? {}, "properties") ?? {},
  );

  const { blocks, perModule } = blocksSchema(
    CONFIG_ANNOTATIONS["blocks"]?.description,
  );

  const schema: Json = {
    $schema: "https://json-schema.org/draft/2020-12/schema",
    $id: "https://unpkg.com/better-supabase/schemas/config-v1.json",
    title: "better-supabase config",
    description: "Configuration for better-supabase.config.ts (or .json).",
    ...rendered,
    properties: {
      ...properties,
      preset: {
        ...child(properties, "preset"),
        description: `A named preset (${PRESET_NAMES.join(", ")}), a code from app.bettersupabase.com/create, or its URL. defineConfig expands it into blocks and its conventions, and the keys you set win.`,
      },
      blocks,
    },
    $defs: {
      ...$defs,
      environment: {
        type: "object",
        additionalProperties: false,
        properties: Object.fromEntries(
          entries.map((key) => [key, { $ref: `#/properties/${key}` }]),
        ),
      },
      blocks: perModule,
    },
  };

  for (const [path, annotation] of Object.entries(CONFIG_ANNOTATIONS)) {
    if (path !== "blocks") {
      annotate(schema, path, annotation);
    }
  }

  return `${JSON.stringify(schema, null, 2)}\n`;
}
