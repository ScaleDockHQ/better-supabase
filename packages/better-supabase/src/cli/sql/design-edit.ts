import type { ResolvedConfig } from "../../config/index.ts";
import type { CreateDesign } from "../../preset/index.ts";

import { isRecord } from "../guards.ts";
import {
  type ConfigEdit,
  setPathInConfig,
  setPathInJson,
} from "./config-edit.ts";

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
 * `options.extraColumns` (merged over the columns `config` already gives it)
 * and each table in `appTables`, replacing a table of the same name and keeping
 * the others. Positions only matter to the canvas and stay out.
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

  for (const [name, table] of Object.entries(design.appTables ?? {})) {
    const problem = apply(["appTables", name], table);

    if (problem !== undefined) {
      return { ok: false, reason: problem };
    }
  }

  return { ok: true, text };
}
