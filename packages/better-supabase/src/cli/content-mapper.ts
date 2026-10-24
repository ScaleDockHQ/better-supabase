import { parseJSONC } from "confbox/jsonc";
import { createHash } from "node:crypto";
import { resolve } from "node:path";

import type { PlannedFile } from "./core/files.ts";

import { readIfExists } from "./core/io.ts";
import { CACHE_DIR } from "./introspect/cache.ts";

/** The file extension the content mapper handles. */
export const MAPPER_EXTENSION = ".bsb";

/** The `contentMappers` entry `init --content-mapper` adds to `tsconfig.json`. */
export const CONTENT_MAPPER_ENTRY: {
  readonly package: "better-supabase";
  readonly extensions: readonly [".bsb"];
} = { package: "better-supabase", extensions: [MAPPER_EXTENSION] };

/** The flag `tsc` needs before it runs a content mapper. */
export const RUN_EXTERNAL_CODE = "--runExternalCode";

/**
 * The file `gen` rewrites when the schema types change in mapper mode. The
 * mapper lists it in `watchedFiles`, so an editor reloads `schema.bsb` after
 * `gen` or `gen --watch` reads a new schema.
 */
export function schemaStampPath(root: string, output: string): string {
  const id = createHash("sha256").update(output).digest("hex").slice(0, 16);

  return resolve(root, CACHE_DIR, `schema-${id}.stamp`);
}

const isObject = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** Whether a parsed tsconfig lists the better-supabase content mapper. */
export function hasContentMapper(tsconfig: unknown): boolean {
  if (!isObject(tsconfig) || !Array.isArray(tsconfig["contentMappers"])) {
    return false;
  }

  return tsconfig["contentMappers"].some(
    (entry: unknown) =>
      isObject(entry) &&
      entry["package"] === CONTENT_MAPPER_ENTRY.package &&
      Array.isArray(entry["extensions"]) &&
      entry["extensions"].includes(MAPPER_EXTENSION),
  );
}

/** The indent of the first indented line, or two spaces. */
function indentOf(text: string): string {
  return /^([ \t]+)\S/m.exec(text)?.[1] ?? "  ";
}

function parseJson(text: string): unknown {
  try {
    return JSON.parse(text);
  } catch {
    return undefined;
  }
}

export type JsonEdit =
  | { readonly kind: "unchanged" }
  | { readonly kind: "edited"; readonly contents: string }
  | { readonly kind: "manual"; readonly reason: string };

/**
 * Adds the content mapper entry to a `tsconfig.json`. A file with comments or
 * trailing commas is left alone (rewriting it would drop them), so the caller
 * prints the entry instead.
 */
export function addContentMapper(text: string): JsonEdit {
  let parsed: unknown;

  try {
    parsed = parseJSONC(text, { allowTrailingComma: true });
  } catch {
    return { kind: "manual", reason: "it does not parse" };
  }

  if (hasContentMapper(parsed)) {
    return { kind: "unchanged" };
  }

  const json = parseJson(text);

  if (!isObject(json)) {
    return { kind: "manual", reason: "it holds comments" };
  }

  const mappers: readonly unknown[] = Array.isArray(json["contentMappers"])
    ? json["contentMappers"]
    : [];

  return {
    kind: "edited",
    contents: `${JSON.stringify(
      { ...json, contentMappers: [...mappers, CONTENT_MAPPER_ENTRY] },
      null,
      indentOf(text),
    )}\n`,
  };
}

/**
 * Adds `--runExternalCode` to the `typecheck` script of a `package.json` when
 * that script runs `tsc` without it.
 */
export function addRunExternalCode(text: string): JsonEdit {
  const json = parseJson(text);

  if (!isObject(json)) {
    return { kind: "manual", reason: "it does not parse" };
  }

  const scripts = isObject(json["scripts"]) ? json["scripts"] : {};
  const script = scripts["typecheck"];

  if (typeof script !== "string" || !/\btsc\b/.test(script)) {
    return {
      kind: "manual",
      reason: "it has no typecheck script that runs tsc",
    };
  }

  if (script.includes(RUN_EXTERNAL_CODE)) {
    return { kind: "unchanged" };
  }

  return {
    kind: "edited",
    contents: `${JSON.stringify(
      {
        ...json,
        scripts: {
          ...scripts,
          typecheck: script.replace(/\btsc\b/, `tsc ${RUN_EXTERNAL_CODE}`),
        },
      },
      null,
      indentOf(text),
    )}\n`,
  };
}

const MISSING: JsonEdit = { kind: "manual", reason: "it does not exist" };

/** The snippet a note prints when `init` can't edit `tsconfig.json` itself. */
const TSCONFIG_SNIPPET = `"contentMappers": [${JSON.stringify(CONTENT_MAPPER_ENTRY)}]`;

const EDITS = [
  {
    path: "tsconfig.json",
    edit: addContentMapper,
    note: (reason: string) =>
      `Add ${TSCONFIG_SNIPPET} to tsconfig.json, next to compilerOptions (init left the file alone: ${reason})`,
  },
  {
    path: "package.json",
    edit: addRunExternalCode,
    note: (reason: string) =>
      `Run tsc with ${RUN_EXTERNAL_CODE} (TypeScript 7.1 or later), or it can't load the content mapper (init left package.json alone: ${reason})`,
  },
] as const;

/**
 * The `tsconfig.json` and `package.json` edits that turn the content mapper on,
 * and a note for each file it can't edit.
 */
export async function contentMapperFiles(
  root: string,
): Promise<{
  readonly files: readonly PlannedFile[];
  readonly notes: readonly string[];
}> {
  const files: PlannedFile[] = [];
  const notes: string[] = [];

  for (const { path, edit, note } of EDITS) {
    const text = await readIfExists(resolve(root, path));
    const result = text === undefined ? MISSING : edit(text);

    switch (result.kind) {
      case "unchanged": {
        break;
      }

      case "edited": {
        files.push({ path, contents: result.contents, policy: "edit" });
        break;
      }

      case "manual": {
        notes.push(note(result.reason));
        break;
      }

      default: {
        const never: never = result;
        throw new Error(`Unhandled edit: ${JSON.stringify(never)}`);
      }
    }
  }

  return { files, notes };
}
