import type {
  GeneratedFile,
  Generator,
  GeneratorInput,
} from "../config/index.ts";

import { VERSION } from "../core/version.ts";
import { HEADER, siblingPath } from "./kit.ts";

export interface TagsGeneratorOptions {
  /** Output path relative to the project root. Defaults to `<output>.tags.ts`. */
  readonly output?: string;
  /**
   * The table keys to write tag functions for (`tasks`, `customerTags`).
   * Defaults to every table, block tables included under their final names.
   */
  readonly tables?: readonly string[];
}

/**
 * One tag function per table, written with `defineTags`: `tags.customers(org)`
 * is the tag a read lists in `bsb.tenant(..., { tags })` and an action lists in
 * `tags: ({ tenant }) => [...]`, so both name the same cache entry.
 */
export function tags(options: TagsGeneratorOptions = {}): Generator {
  return {
    apiVersion: 2,
    version: VERSION,
    options,
    pure: true,
    workerSafe: true,
    module: { specifier: "better-supabase/generators/tags", export: "tags" },
    name: "tags",
    generate(input: GeneratorInput): GeneratedFile[] {
      const path =
        options.output ?? siblingPath(input.config.output, "tags.ts");

      const wanted =
        options.tables === undefined ? undefined : new Set(options.tables);

      const keys = input.model.tables
        .map((table) => table.key)
        .filter((key) => wanted === undefined || wanted.has(key))
        .toSorted((a, b) => (a < b ? -1 : a > b ? 1 : 0));

      const missing = [...(wanted ?? [])].filter((key) => !keys.includes(key));

      if (missing.length > 0) {
        throw new Error(
          `tags(): no table named ${missing.map((key) => `"${key}"`).join(", ")}`,
        );
      }

      const contents = [
        HEADER,
        'import { defineTags } from "better-supabase/next";',
        "",
        "/** A cache tag per table as a function of the tenant, shared by reads and actions. */",
        `export const tags = defineTags([${keys.map((key) => JSON.stringify(key)).join(", ")}] as const);`,
        "",
      ].join("\n");

      return [{ path, contents }];
    },
  };
}
