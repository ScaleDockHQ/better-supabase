import { dirname } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { sourceFiles } from "./doctor/inputs.ts";

const WORD = /[a-z_][a-z0-9_]*/gi;

/**
 * The names `gen.api.expose: "used"` keeps a wrapper for: every word in the
 * workspace sources outside the generated folder, plus `exposeAlso`. A source
 * that calls `supabase.rpc("flag_definitions")` or
 * `db.$rpc("flag_definitions")` names the function, and the generated types
 * name all of them, so they are left out. `undefined` for `expose: "all"`, the
 * default.
 */
export async function apiUsedNames(
  config: ResolvedConfig,
): Promise<readonly string[] | undefined> {
  const api = config.gen.api;

  if (api?.expose !== "used") {
    return undefined;
  }

  const generated = dirname(config.output);
  const used = new Set<string>(api.exposeAlso);

  for (const file of await sourceFiles(config)) {
    if (file.path.startsWith(`${generated}/`) || file.path.endsWith(".d.ts")) {
      continue;
    }

    for (const word of file.text.match(WORD) ?? []) {
      used.add(word);
    }
  }

  return [...used];
}
