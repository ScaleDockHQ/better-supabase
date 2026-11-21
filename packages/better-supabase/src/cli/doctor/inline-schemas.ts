import { resolve } from "node:path";

import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { resolveJsonSchema } from "../../config/index.ts";
import { importFresh } from "../fresh-import.ts";
import { isRecord } from "../guards.ts";

/** A JSON Schema as text with its keys in order, to compare two documents. */
function canonical(value: unknown): string {
  if (Array.isArray(value)) {
    return `[${value.map((item) => canonical(item)).join(",")}]`;
  }

  if (isRecord(value)) {
    return `{${Object.keys(value)
      .toSorted()
      .map((key) => `${JSON.stringify(key)}:${canonical(value[key])}`)
      .join(",")}}`;
  }

  return JSON.stringify(value);
}

const isStandard = (value: unknown): boolean =>
  isRecord(value) && "~standard" in value;

/** The module paths the standardSchema generators already name. */
function modulesOf(context: DoctorContext): string[] {
  const paths = new Set<string>();

  for (const generator of context.config.generators) {
    const options = generator.options;

    if (generator.name !== "standard-schema" || !isRecord(options)) {
      continue;
    }

    const specs = [
      options["settings"],
      ...(isRecord(options["json"]) ? Object.values(options["json"]) : []),
    ];

    for (const spec of specs) {
      if (typeof spec === "string" && spec.includes("#")) {
        paths.add(spec.split("#")[0] ?? "");
      }
    }
  }

  return [...paths].filter((path) => path !== "");
}

/** Every exported Standard Schema with a JSON Schema, by its canonical text. */
async function exportedSchemas(
  context: DoctorContext,
): Promise<Map<string, string>> {
  const found = new Map<string, string>();

  for (const path of modulesOf(context)) {
    let loaded: Record<string, unknown>;

    try {
      loaded = await importFresh(resolve(context.config.root, path));
    } catch {
      continue;
    }

    for (const [name, value] of Object.entries(loaded)) {
      if (!isStandard(value)) {
        continue;
      }

      try {
        // SAFETY: isStandard saw ~standard; resolveJsonSchema throws for a
        // library without Standard JSON Schema, which is skipped below.
        const document = resolveJsonSchema(
          value as Parameters<typeof resolveJsonSchema>[0],
        );

        found.set(canonical(document), `${path}#${name}`);
      } catch {
        continue;
      }
    }
  }

  return found;
}

/**
 * Inline JSON Schemas in `gen.json` and `blocks.settings.options.schemas` whose
 * document an exported Standard Schema already produces (BS704).
 */
export async function inlineSchemasAnExportHolds(
  context: DoctorContext,
): Promise<FindingInput[]> {
  const inline: { where: string; document: unknown }[] = [];

  for (const [key, entry] of Object.entries(context.config.json)) {
    const schema: unknown = entry.schema;

    if (isRecord(schema) && !isStandard(schema)) {
      inline.push({ where: `gen.json["${key}"].schema`, document: schema });
    }
  }

  const options = context.config.blocks["settings"]?.options?.["schemas"];

  if (isRecord(options) && !("schemas" in options)) {
    for (const scope of ["user", "organization", "platform"]) {
      const map = options[scope];

      for (const [key, entry] of isRecord(map) ? Object.entries(map) : []) {
        if (isRecord(entry) && !isStandard(entry) && !("schema" in entry)) {
          inline.push({
            where: `blocks.settings.options.schemas.${scope}.${key}`,
            document: entry,
          });
        }
      }
    }
  }

  if (inline.length === 0) {
    return [];
  }

  const exported = await exportedSchemas(context);

  return inline.flatMap(({ where, document }) => {
    const reference = exported.get(canonical(document));

    return reference === undefined
      ? []
      : [
          {
            message: `${where} repeats the JSON Schema that ${reference} produces. Name it as "${reference}" so the column and the database check share one schema.`,
            target: where,
          },
        ];
  });
}

export const INLINE_SCHEMA_RULES: readonly Rule[] = [
  {
    code: "BS704",
    severity: "info",
    title: "Inline JSON Schema repeats an exported schema",
    description:
      'A `gen.json` column or a `blocks.settings.options.schemas` entry holds a JSON Schema that an exported Standard Schema (in a module the `standardSchema()` generator names) already produces. Pass `"./schemas.ts#name"` instead: the CLI loads the export for the pg_jsonschema check and types the column from it. The inline schema still works.',
    check: inlineSchemasAnExportHolds,
  },
];
