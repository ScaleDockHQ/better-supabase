import type { ResolvedConfig } from "../../config/index.ts";
import type { CreateDesign } from "../../preset/index.ts";
import type { ConfigEdit } from "./config-edit.ts";

import { isRecord } from "../guards.ts";
import { setPathInConfig, setPathInJson } from "./config-edit.ts";

/** The `extraColumns` a block already has in the config, as plain strings. */
function currentExtraColumns(
  config: ResolvedConfig | undefined,
  module: string,
): Readonly<Record<string, string>> {
  const value: unknown = config?.blocks[module]?.options?.["extraColumns"];

  if (!isRecord(value)) {
    return {};
  }

  return Object.fromEntries(
    Object.entries(value).flatMap(([name, type]) =>
      typeof type === "string" ? [[name, type]] : [],
    ),
  );
}

/**
 * `source` with a `/create` design written into it: each block's
 * `options.extraColumns` (merged over the columns `config` already gives it).
 * The design's tables are SQL files, written by `appTablePlan`, and positions
 * only matter to the canvas, so neither goes into the config.
 */
export function writeDesign(
  file: string,
  source: string,
  design: CreateDesign,
  config?: ResolvedConfig,
): ConfigEdit {
  const set = file.endsWith(".json") ? setPathInJson : setPathInConfig;
  let text = source;

  const apply = (
    path: readonly [string, ...string[]],
    value: unknown,
  ): string | undefined => {
    const edit = set(text, path, value);

    if (!edit.ok) {
      return `${path.join(".")} can't be set: ${edit.reason}`;
    }

    text = edit.text;

    return undefined;
  };

  for (const [module, columns] of Object.entries(design.extraColumns ?? {})) {
    const problem = apply(["blocks", module, "options", "extraColumns"], {
      ...currentExtraColumns(config, module),
      ...columns,
    });

    if (problem !== undefined) {
      return { ok: false, reason: problem };
    }
  }

  for (const [key, value] of [
    ["variants", design.seeds?.variants],
    ["locale", design.seeds?.locale],
  ] as const) {
    if (value === undefined) {
      continue;
    }

    const problem = apply(["database", "seed", "defaults", key], value);

    if (problem !== undefined) {
      return { ok: false, reason: problem };
    }
  }

  return { ok: true, text };
}
