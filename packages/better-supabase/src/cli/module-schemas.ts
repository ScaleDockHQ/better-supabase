import { resolve } from "node:path";

import type { JsonSchemaSource, ResolvedConfig } from "../config/index.ts";

import { CliError } from "./core/errors.ts";
import { importFresh } from "./fresh-import.ts";
import { isRecord } from "./guards.ts";

/**
 * Where each loaded schema came from, as the `"./path.ts#name"` it was named
 * by.
 */
const references = new WeakMap<object, string>();

/** The module reference a schema was loaded from, when the config named one. */
export function moduleRefOf(value: unknown): string | undefined {
  return typeof value === "object" && value !== null
    ? references.get(value)
    : undefined;
}

const isReference = (value: unknown): value is string =>
  typeof value === "string" && /^\.{1,2}\/[^#]+#[\w$]+$/u.test(value);

/** Loads the export a `"./path.ts#name"` reference names. */
async function load(
  root: string,
  reference: string,
  where: string,
): Promise<JsonSchemaSource> {
  const [path = "", name = ""] = reference.split("#");
  let loaded: Record<string, unknown>;

  try {
    loaded = await importFresh(resolve(root, path));
  } catch (error) {
    throw new CliError(
      "config_invalid",
      `${where}: cannot load ${path} (${error instanceof Error ? error.message : String(error)})`,
    );
  }

  const value = loaded[name];

  if (typeof value !== "object" || value === null) {
    throw new CliError(
      "config_invalid",
      `${where}: ${path} does not export a schema named ${name}`,
    );
  }

  references.set(value, reference);

  // SAFETY: a schema export is a Standard Schema object; resolveJsonSchema
  // reports one that implements no Standard JSON Schema.
  return value as JsonSchemaSource;
}

type Schemas = Readonly<Record<string, unknown>>;

async function getMap(
  root: string,
  map: Schemas,
  where: string,
): Promise<Schemas> {
  const entries = await Promise.all(
    Object.entries(map).map(
      async ([key, entry]): Promise<[string, unknown]> => {
        if (isReference(entry)) {
          return [key, await load(root, entry, `${where}.${key}`)];
        }

        if (isRecord(entry) && isReference(entry["schema"])) {
          return [
            key,
            {
              ...entry,
              schema: await load(
                root,
                entry["schema"],
                `${where}.${key}.schema`,
              ),
            },
          ];
        }

        return [key, entry];
      },
    ),
  );

  return Object.fromEntries(entries);
}

async function getSettings(
  root: string,
  options: Readonly<Record<string, unknown>> | undefined,
  where: string,
): Promise<Readonly<Record<string, unknown>> | undefined> {
  const schemas = options?.["schemas"];

  if (options === undefined || !isRecord(schemas) || "schemas" in schemas) {
    return options;
  }

  const next = { ...schemas };

  for (const scope of ["user", "organization", "platform"]) {
    const map = schemas[scope];

    if (isRecord(map)) {
      next[scope] = await getMap(root, map, `${where}.schemas.${scope}`);
    }
  }

  return { ...options, schemas: next };
}

/**
 * `config` with every module reference (`"./schemas.ts#name"`) in
 * `gen.json.<column>.schema` and `blocks.settings.options.schemas` replaced by
 * the exported schema, so the SQL modules read its JSON Schema and the
 * generator types the column from it. An inline JSON Schema or a schema value
 * stays as it is.
 */
export async function withModuleSchemas(
  config: ResolvedConfig,
): Promise<ResolvedConfig> {
  const json = Object.fromEntries(
    await Promise.all(
      Object.entries(config.json).map(async ([key, entry]) => {
        const source: unknown = entry.schema;

        return [
          key,
          isReference(source)
            ? {
                ...entry,
                schema: await load(
                  config.root,
                  source,
                  `gen.json["${key}"].schema`,
                ),
              }
            : entry,
        ] as const;
      }),
    ),
  );

  const settings = config.blocks["settings"];

  const options = await getSettings(
    config.root,
    settings?.options,
    "blocks.settings.options",
  );

  const instances = Object.fromEntries(
    await Promise.all(
      Object.entries(config.instances).map(async ([key, instance]) => {
        if (instance.block !== "settings") {
          return [key, instance] as const;
        }

        const own = await getSettings(
          config.root,
          instance.config.options,
          `blocks.${key}.options`,
        );

        return [
          key,
          own === undefined
            ? instance
            : { ...instance, config: { ...instance.config, options: own } },
        ] as const;
      }),
    ),
  );

  return {
    ...config,
    // SAFETY: a loaded schema takes the place of the module reference string, a
    // value the resolved config's `json` type allows next to import and type.
    json: json as ResolvedConfig["json"],
    instances,
    blocks:
      settings === undefined || options === undefined
        ? config.blocks
        : { ...config.blocks, settings: { ...settings, options } },
  };
}
