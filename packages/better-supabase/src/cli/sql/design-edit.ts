import type { CreateDesign } from "../../preset/index.ts";
import type { ConfigEdit } from "./config-edit.ts";

import { setPathInConfig, setPathInJson } from "./config-edit.ts";

/**
 * `source` with a `/create` design written into it: its seeds. The design's
 * tables are SQL files, written by `appTablePlan`, and positions only matter to
 * the canvas, so neither goes into the config.
 */
export function writeDesign(
  file: string,
  source: string,
  design: CreateDesign,
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

  for (const [path, value] of [
    [["database", "seed", "defaults", "variants"], design.seeds?.variants],
    [["database", "seed", "defaults", "locale"], design.seeds?.locale],
    [["database", "seed", "sample", "size"], design.seeds?.sample?.size],
    [["database", "seed", "sample", "seed"], design.seeds?.sample?.seed],
  ] as const) {
    if (value === undefined) {
      continue;
    }

    const problem = apply(path, value);

    if (problem !== undefined) {
      return { ok: false, reason: problem };
    }
  }

  return { ok: true, text };
}
