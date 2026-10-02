import type { ResolvedConfig } from "better-supabase/config";

import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ParsedArgs } from "../args.ts";
import type { CommandResult } from "../io.ts";

import { flagBool, flagString } from "../args.ts";
import { importExport } from "../config.ts";
import { display, writeIfChanged } from "../io.ts";

export const OPENAPI_HELP = `Usage: better-supabase openapi emit [--check] [--entry src/lib/openapi.ts] [--out openapi.json]

Writes the document your createOpenApi() module exports, so it can be
reviewed, published, and checked for drift in CI.

Options
  --check          Fail when the file differs from the document
  --entry <file>   Defaults to openapi.entry. Exports \`openapi\` or default: a document or a function returning one
  --out <file>     Defaults to openapi.output`;

export async function runOpenApi(
  config: ResolvedConfig,
  args: ParsedArgs,
): Promise<CommandResult> {
  const [action] = args.rest;
  if (action !== "emit") {
    return {
      code: 2,
      error: action
        ? `Unknown openapi action "${action}".\n\n${OPENAPI_HELP}`
        : OPENAPI_HELP,
    };
  }
  const entry = flagString(args.flags, "entry") ?? config.openapi.entry;
  const out = flagString(args.flags, "out") ?? config.openapi.output;
  const exported = await importExport(resolve(config.root, entry), "openapi");
  // SAFETY: an exported openapi function takes no arguments and returns the document.
  const document: unknown =
    typeof exported === "function"
      ? await (exported as () => unknown)()
      : exported;
  if (
    typeof document !== "object" ||
    document === null ||
    !("openapi" in document)
  ) {
    return {
      code: 1,
      error: `${display(config.root, entry)} must export an OpenAPI document (createOpenApi(...)) as \`openapi\` or default.`,
    };
  }
  const contents = `${JSON.stringify(document, null, 2)}\n`;
  const path = resolve(config.root, out);
  if (flagBool(args.flags, "check")) {
    const current = existsSync(path) ? await readFile(path, "utf8") : undefined;
    return current === contents
      ? { code: 0, output: `${display(config.root, out)} is up to date.` }
      : {
          code: 1,
          error: `${display(config.root, out)} is out of date. Run \`better-supabase openapi emit\`.`,
        };
  }
  const wrote = await writeIfChanged(path, contents);
  return {
    code: 0,
    output: `${wrote ? "Wrote" : "Unchanged"} ${display(config.root, out)}`,
  };
}
