import { resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { CliError } from "./core/errors.ts";
import { importFresh } from "./fresh-import.ts";

/**
 * The `settings` option of every `standardSchema()` generator; the last one
 * wins.
 */
function settingsSpec(config: ResolvedConfig): string | undefined {
  let found: string | undefined;

  for (const generator of config.generators) {
    const options = generator.options;

    if (
      generator.name === "standard-schema" &&
      typeof options === "object" &&
      options !== null &&
      "settings" in options &&
      typeof options.settings === "string"
    ) {
      found = options.settings;
    }
  }

  return found;
}

function hasSchemas(entry: { readonly options?: unknown }): boolean {
  const options = entry.options;

  return (
    typeof options === "object" &&
    options !== null &&
    "schemas" in options &&
    options.schemas !== undefined
  );
}

/**
 * `config` with the settings schemas that `standardSchema({ settings })` names
 * ("./path.ts#export", the `defineSettings()` result) as the `schemas` option
 * of every `settings` instance that sets none, so one line of config no longer
 * repeats an export the project already has (ADR 0394). A `schemas` option the
 * config sets wins.
 */
export async function withSettingsSchemas(
  config: ResolvedConfig,
): Promise<ResolvedConfig> {
  const spec = settingsSpec(config);

  const targets = Object.values(config.instances).filter(
    (instance) => instance.block === "settings" && !hasSchemas(instance.config),
  );

  if (spec === undefined || targets.length === 0) {
    return config;
  }

  const [path, name] = spec.split("#");

  if (path === undefined || name === undefined || name === "") {
    throw new CliError(
      "config_invalid",
      `standardSchema({ settings }) must look like "./path.ts#settings", got "${spec}"`,
    );
  }

  const loaded = await importFresh(resolve(config.root, path));
  const definition = loaded[name];

  if (
    typeof definition !== "object" ||
    definition === null ||
    !("schemas" in definition)
  ) {
    throw new CliError(
      "config_invalid",
      `${spec} must export the defineSettings() result`,
    );
  }

  const withOptions = <T extends { readonly options?: unknown }>(
    entry: T,
  ): T => ({
    ...entry,
    options: {
      ...(typeof entry.options === "object" && entry.options !== null
        ? entry.options
        : {}),
      schemas: definition,
    },
  });

  const names = new Set(targets.map((instance) => instance.name));

  return {
    ...config,
    instances: Object.fromEntries(
      Object.entries(config.instances).map(([key, instance]) => [
        key,
        names.has(key)
          ? { ...instance, config: withOptions(instance.config) }
          : instance,
      ]),
    ),
    blocks: {
      ...config.blocks,
      settings: withOptions(config.blocks["settings"] ?? {}),
    },
  };
}
