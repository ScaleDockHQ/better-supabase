import { writeFile } from "node:fs/promises";
import { resolve } from "node:path";
/**
 * Sets one value in the Supabase project config, whatever format it is in
 * (`config.toml`, `config.json` or `config.jsonc`), keeping comments. The
 * workflows use it to narrow the seed files for a job, instead of a `sed` that
 * only understands TOML.
 *
 * Node scripts/set-config-value.ts <project-dir> <dotted.key> <json-value>
 *
 * `<json-value>` is parsed as JSON (`'["./seed.sql"]'`, `true`, `7`), and read
 * as a string when it is not JSON.
 */
import * as v from "valibot";

import type { ConfigScalar } from "../packages/better-supabase/src/cli/supabase-config.ts";

import {
  readSupabaseConfig,
  withConfigValue,
} from "../packages/better-supabase/src/cli/supabase-config.ts";

/** The value a command-line argument names. */
export function parseValue(argument: string): ConfigScalar {
  try {
    return v.parse(
      v.union([v.string(), v.number(), v.boolean(), v.array(v.string())]),
      JSON.parse(argument),
    );
  } catch {
    // Not JSON: a bare word is a string.
  }

  return argument;
}

async function main(): Promise<void> {
  const [dir, key, value] = process.argv.slice(2);

  if (dir === undefined || key === undefined || value === undefined) {
    throw new Error(
      "Usage: node scripts/set-config-value.ts <project-dir> <dotted.key> <json-value>",
    );
  }

  const config = await readSupabaseConfig(resolve(dir));

  if (config === undefined) {
    throw new Error(
      `No supabase/config.toml, config.json or config.jsonc under ${dir}.`,
    );
  }

  await writeFile(
    resolve(dir, config.path),
    withConfigValue(config, key.split("."), parseValue(value)),
  );
  console.log(`Set ${key} in ${config.path}.`);
}

if (import.meta.main) {
  await main();
}
